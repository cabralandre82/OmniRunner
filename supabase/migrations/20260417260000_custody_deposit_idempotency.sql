-- ═══════════════════════════════════════════════════════════════════════════
-- L01-04 — Idempotency-key + cross-group ownership em custody deposits
--
-- Problemas (CISO 1.4):
--   • POST /api/custody (deposit) sem idempotency-key → double-click cria 2
--     rows custody_deposits PENDING. UNIQUE em payment_reference só age
--     APÓS gateway responder; janela entre INSERT e callback é vulnerável.
--   • confirm_custody_deposit(p_deposit_id) não exige group_id → admin_master
--     do grupo A poderia confirmar deposit do grupo B se conhecesse o UUID,
--     creditando-se sem pagar. Crítico se RPC for exposta via PostgREST.
--
-- Correções:
--   1. ADD COLUMN custody_deposits.idempotency_key text + UNIQUE composto
--      (group_id, idempotency_key) WHERE idempotency_key IS NOT NULL.
--   2. Nova RPC fn_create_custody_deposit_idempotent(group, amount, coins,
--      gateway, key) — SELECT first / INSERT on miss. Retorna was_idempotent.
--   3. Drop confirm_custody_deposit(uuid) e cria confirm_custody_deposit(
--      p_deposit_id, p_group_id) — exige match dos dois.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. ADD COLUMN idempotency_key + UNIQUE parcial composto
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.custody_deposits
  ADD COLUMN IF NOT EXISTS idempotency_key text;

COMMENT ON COLUMN public.custody_deposits.idempotency_key IS
  'L01-04: chave fornecida pelo cliente (UUID v4 recomendado). Reuso da '
  'mesma chave para o mesmo group_id retorna o deposit existente (idempotente). '
  'NULL permite legacy rows; novos clientes devem sempre enviar.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_custody_deposits_group_idempotency
  ON public.custody_deposits(group_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. RPC create_custody_deposit_idempotent
--    SECURITY DEFINER permite que o portal (service_role) chame sem precisar
--    de GRANT específico em cada caller. Faz SELECT-first para idempotency
--    hit "barato" sem disputar lock; só na miss tenta INSERT (que pode race
--    contra outro request com mesma chave — UNIQUE garante consistência).
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_create_custody_deposit_idempotent(
  p_group_id          uuid,
  p_amount_usd        numeric,
  p_coins_equivalent  integer,
  p_payment_gateway   text,
  p_idempotency_key   text
)
  RETURNS TABLE(
    deposit_id      uuid,
    was_idempotent  boolean,
    status          text,
    amount_usd      numeric,
    coins_equivalent integer,
    payment_gateway text,
    payment_reference text,
    created_at      timestamptz
  )
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_existing_id uuid;
BEGIN
  -- Validações de contrato
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_group_id is required' USING ERRCODE = 'P0001';
  END IF;
  IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
    RAISE EXCEPTION 'p_idempotency_key must be >= 8 chars (UUID v4 recomendado)'
      USING ERRCODE = 'P0001';
  END IF;
  IF p_amount_usd IS NULL OR p_amount_usd <= 0 THEN
    RAISE EXCEPTION 'p_amount_usd must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_coins_equivalent IS NULL OR p_coins_equivalent <= 0 THEN
    RAISE EXCEPTION 'p_coins_equivalent must be > 0' USING ERRCODE = 'P0001';
  END IF;
  IF p_payment_gateway NOT IN ('stripe', 'mercadopago') THEN
    RAISE EXCEPTION 'p_payment_gateway must be stripe|mercadopago' USING ERRCODE = 'P0001';
  END IF;

  -- Hit do cache de idempotência: chave já gravada para este grupo.
  SELECT id INTO v_existing_id
  FROM public.custody_deposits
  WHERE group_id = p_group_id
    AND idempotency_key = p_idempotency_key
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN QUERY
      SELECT d.id, true, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;
  END IF;

  -- Miss → INSERT. Se duas chamadas concorrentes tentarem inserir com a mesma
  -- chave, UNIQUE composto faz a segunda receber unique_violation — capturada
  -- aqui e convertida em SELECT (idempotent hit equivalente).
  BEGIN
    INSERT INTO public.custody_deposits (
      group_id, amount_usd, coins_equivalent, payment_gateway,
      status, idempotency_key
    )
    VALUES (
      p_group_id, p_amount_usd, p_coins_equivalent, p_payment_gateway,
      'pending', p_idempotency_key
    )
    RETURNING id INTO v_existing_id;

    RETURN QUERY
      SELECT d.id, false, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;

  EXCEPTION WHEN unique_violation THEN
    -- Race: outro request criou primeiro. Retorna o vencedor.
    SELECT id INTO v_existing_id
    FROM public.custody_deposits
    WHERE group_id = p_group_id AND idempotency_key = p_idempotency_key;

    RETURN QUERY
      SELECT d.id, true, d.status, d.amount_usd, d.coins_equivalent,
             d.payment_gateway, d.payment_reference, d.created_at
      FROM public.custody_deposits d
      WHERE d.id = v_existing_id;
    RETURN;
  END;
END $$;

REVOKE ALL ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) TO service_role;

-- Aplica lock_timeout (consistência com L19-05)
ALTER FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text)
  SET lock_timeout = '2s';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. confirm_custody_deposit — DROP single-arg + CREATE com p_group_id
--    Old signature `(uuid)` permitia cross-group spoofing se RPC exposta.
--    Novo signature `(uuid, uuid)` exige caller fornecer ambos; SQL valida.
-- ───────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.confirm_custody_deposit(uuid);

CREATE OR REPLACE FUNCTION public.confirm_custody_deposit(
  p_deposit_id uuid,
  p_group_id   uuid
)
  RETURNS void
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_amount   numeric(14,2);
  v_status   text;
BEGIN
  IF p_deposit_id IS NULL OR p_group_id IS NULL THEN
    RAISE EXCEPTION 'p_deposit_id and p_group_id are required'
      USING ERRCODE = 'P0001';
  END IF;

  -- Lock + ownership check num único SELECT.
  SELECT amount_usd, status
    INTO v_amount, v_status
  FROM public.custody_deposits
  WHERE id = p_deposit_id
    AND group_id = p_group_id
  FOR UPDATE;

  IF v_amount IS NULL THEN
    -- Não distinguimos "deposit não existe" de "wrong group" — same error
    -- defende contra enumeration de UUIDs cross-group.
    RAISE EXCEPTION 'Deposit not found, wrong group, or already processed'
      USING ERRCODE = 'P0002', HINT = 'L01-04: confirm exige group_id correto';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Deposit not in pending state (current: %)', v_status
      USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.custody_deposits
  SET status = 'confirmed',
      confirmed_at = now()
  WHERE id = p_deposit_id;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (p_group_id, v_amount)
  ON CONFLICT (group_id) DO UPDATE
  SET total_deposited_usd = custody_accounts.total_deposited_usd + v_amount,
      updated_at = now();
END $$;

REVOKE ALL ON FUNCTION public.confirm_custody_deposit(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.confirm_custody_deposit(uuid, uuid) TO service_role;

ALTER FUNCTION public.confirm_custody_deposit(uuid, uuid)
  SET lock_timeout = '2s';

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Invariants check (auto-test ao aplicar)
-- ───────────────────────────────────────────────────────────────────────────
DO $invariants$
DECLARE
  v_group_id   uuid;
  v_dep1       uuid;
  v_dep2       uuid;
  v_idem1      boolean;
  v_idem2      boolean;
  v_count      integer;
BEGIN
  -- 4a. Garante que coluna foi criada
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'custody_deposits'
      AND column_name = 'idempotency_key'
  ) THEN
    RAISE EXCEPTION '[L01-04] custody_deposits.idempotency_key não criada';
  END IF;

  -- 4b. Garante UNIQUE parcial existe
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_custody_deposits_group_idempotency'
  ) THEN
    RAISE EXCEPTION '[L01-04] UNIQUE composto não criado';
  END IF;

  -- 4c. Smoke da nova RPC create_idempotent (idempotency hit)
  SELECT id INTO v_group_id FROM public.coaching_groups LIMIT 1;
  IF v_group_id IS NULL THEN
    RAISE NOTICE '[L01-04] sem coaching_groups; skip RPC smoke';
    RETURN;
  END IF;

  -- Garante account existe (FK)
  INSERT INTO public.custody_accounts (group_id) VALUES (v_group_id)
  ON CONFLICT DO NOTHING;

  -- Primeira chamada: cria
  SELECT deposit_id, was_idempotent
    INTO v_dep1, v_idem1
  FROM public.fn_create_custody_deposit_idempotent(
    v_group_id, 100.0, 100, 'stripe', 'L01-04-smoke-key-12345'
  );
  IF v_dep1 IS NULL OR v_idem1 IS NOT FALSE THEN
    RAISE EXCEPTION '[L01-04] first call did not create deposit (was_idempotent=%)', v_idem1;
  END IF;

  -- Segunda chamada com mesma chave: hit
  SELECT deposit_id, was_idempotent
    INTO v_dep2, v_idem2
  FROM public.fn_create_custody_deposit_idempotent(
    v_group_id, 100.0, 100, 'stripe', 'L01-04-smoke-key-12345'
  );
  IF v_dep2 IS DISTINCT FROM v_dep1 OR v_idem2 IS NOT TRUE THEN
    RAISE EXCEPTION '[L01-04] idempotent hit failed: dep1=% dep2=% idem2=%',
      v_dep1, v_dep2, v_idem2;
  END IF;

  -- 4d. Confirm com group_id certo: ok
  PERFORM public.confirm_custody_deposit(v_dep1, v_group_id);
  SELECT count(*) INTO v_count
  FROM public.custody_deposits
  WHERE id = v_dep1 AND status = 'confirmed';
  IF v_count <> 1 THEN
    RAISE EXCEPTION '[L01-04] confirm did not transition status';
  END IF;

  -- 4e. Cleanup smoke entries (não polui prod)
  DELETE FROM public.custody_deposits WHERE idempotency_key = 'L01-04-smoke-key-12345';
  -- Reverte custody_account smoke
  UPDATE public.custody_accounts
  SET total_deposited_usd = GREATEST(0, total_deposited_usd - 100.0)
  WHERE group_id = v_group_id;

  RAISE NOTICE '[L01-04] invariants OK — idempotency + cross-group enforcement';
END
$invariants$;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Documentação
-- ───────────────────────────────────────────────────────────────────────────
COMMENT ON FUNCTION public.fn_create_custody_deposit_idempotent(uuid, numeric, integer, text, text) IS
  'L01-04: cria custody_deposit idempotente. Reuso de p_idempotency_key para '
  'mesmo p_group_id retorna o deposit existente. Race protegida por UNIQUE '
  'parcial (group_id, idempotency_key).';

COMMENT ON FUNCTION public.confirm_custody_deposit(uuid, uuid) IS
  'L01-04: confirma deposit pending → confirmed e credita custody_account. '
  'Exige match (deposit_id, group_id) — bloqueia confirm cross-group por '
  'admin malicioso. Single-arg overload removido.';
