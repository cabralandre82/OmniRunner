-- ═══════════════════════════════════════════════════════════════════════════
-- L05-02 — TTL/expiração de swap_orders + cron sweep + accept reject defesa
--
-- Problema (CPO 5.2):
--   Não há `expires_at` em swap_orders. Ofertas abertas permanecem no
--   marketplace para sempre. Vendedor cria oferta de US$ 500k, esquece, e
--   meses depois um buyer aceita ao preço/fee daquela época. Além disso:
--     • `getOpenSwapOffers` polui resultado com listagens stale (anos atrás).
--     • Auditoria perde rastro: nenhum cleanup automático.
--
-- Correção:
--   1. ADD COLUMN swap_orders.expires_at timestamptz NOT NULL DEFAULT now()+7d.
--   2. Estende CHECK status para incluir 'expired'.
--   3. Index parcial (expires_at) WHERE status='open' — sweep eficiente.
--   4. Refactor execute_swap: rejeita expires_at < now() mesmo se status='open'
--      (defesa entre runs do cron). Novo P0005 SWAP_EXPIRED.
--   5. Nova RPC fn_expire_swap_orders() — UPDATE … status='expired' WHERE
--      status='open' AND expires_at < now(). RETURNS count.
--   6. pg_cron job 'swap-expire' a cada 10min.
--   7. Invariants check.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. ADD COLUMN expires_at + estende CHECK status
-- ───────────────────────────────────────────────────────────────────────────

-- Step 1a: ADD COLUMN com default de 7 dias para legacy rows.
-- Existing rows recebem expires_at = now() + 7d (migration time). Isso
-- permite ao cron processar ofertas antigas dentro de 7d, dando ao operador
-- janela para revisão. Acceitable: alternativa seria expirar tudo no primeiro
-- run (UX hostil para clientes que confiam no marketplace).
ALTER TABLE public.swap_orders
  ADD COLUMN IF NOT EXISTS expires_at timestamptz NOT NULL
    DEFAULT (now() + interval '7 days');

COMMENT ON COLUMN public.swap_orders.expires_at IS
  'L05-02: instante após o qual a oferta é elegível para expiração. '
  'Default 7d. Cron job ''swap-expire'' marca status=expired após esse '
  'horário. execute_swap também rejeita aceitar oferta expirada (defesa '
  'entre runs do cron). Cliente pode informar expires_in_days (1/7/30/90).';

-- Step 1b: Estende CHECK status para incluir 'expired'.
-- IF EXISTS guard permite re-aplicação idempotente.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'swap_orders'
      AND constraint_name = 'swap_orders_status_check'
  ) THEN
    ALTER TABLE public.swap_orders
      DROP CONSTRAINT swap_orders_status_check;
  END IF;
END $$;

ALTER TABLE public.swap_orders
  ADD CONSTRAINT swap_orders_status_check
    CHECK (status IN ('open', 'matched', 'settled', 'cancelled', 'expired'));

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Index parcial para sweep eficiente
-- ───────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_swap_orders_open_expires
  ON public.swap_orders(expires_at)
  WHERE status = 'open';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Refactor execute_swap: rejeita expirado
--    Race: cron pode rodar AGORA mesmo que valide o aceite. Defesa neste
--    SELECT FOR UPDATE garante que entre 2 runs do cron um buyer apressado
--    não pegue oferta caducada. SQLSTATE P0005 distingue "expirou" de
--    "cancelou" para UX melhor.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.execute_swap(
  p_order_id        uuid,
  p_buyer_group_id  uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '2s'
AS $$
DECLARE
  v_seller       uuid;
  v_status       text;
  v_amount       numeric(14,2);
  v_fee          numeric(14,2);
  v_expires_at   timestamptz;
  v_net          numeric(14,2);
  v_seller_avail numeric(14,2);
BEGIN
  SELECT seller_group_id, status, amount_usd, fee_amount_usd, expires_at
    INTO v_seller, v_status, v_amount, v_fee, v_expires_at
    FROM public.swap_orders
   WHERE id = p_order_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SWAP_NOT_FOUND: order % does not exist', p_order_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'SWAP_NOT_OPEN: order % is in status=% (expected=open)',
                    p_order_id, v_status
      USING ERRCODE = 'P0001',
            HINT    = v_status;
  END IF;

  -- L05-02: rejeita expired antes de qualquer write.
  -- Nota: NÃO marcamos status='expired' aqui porque RAISE EXCEPTION
  -- abaixo causaria rollback dessa UPDATE quando o caller (PL/pgSQL com
  -- BEGIN/EXCEPTION ou cliente que captura) aborta o subtransaction.
  -- Cron job 'swap-expire' marcará status dentro de ~10min. Janela de
  -- inconsistência aceitável (status='open' mas não-acceptável); o
  -- filtro `expires_at >= now()` em getOpenSwapOffers + a defesa aqui
  -- garantem que nenhum buyer consegue aceitar oferta expirada.
  IF v_expires_at IS NOT NULL AND v_expires_at < now() THEN
    RAISE EXCEPTION 'SWAP_EXPIRED: order % expired at % (now=%)',
                    p_order_id, v_expires_at, now()
      USING ERRCODE = 'P0005',
            HINT    = to_char(v_expires_at AT TIME ZONE 'UTC',
                              'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  END IF;

  IF v_seller = p_buyer_group_id THEN
    RAISE EXCEPTION 'SWAP_SELF_BUY: buyer % is the seller of order %',
                    p_buyer_group_id, p_order_id
      USING ERRCODE = 'P0003';
  END IF;

  v_net := v_amount - v_fee;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (p_buyer_group_id, 0)
  ON CONFLICT (group_id) DO NOTHING;

  IF v_seller < p_buyer_group_id THEN
    SELECT total_deposited_usd - total_committed
      INTO v_seller_avail
      FROM public.custody_accounts
     WHERE group_id = v_seller
       FOR UPDATE;
    PERFORM 1 FROM public.custody_accounts WHERE group_id = p_buyer_group_id FOR UPDATE;
  ELSE
    PERFORM 1 FROM public.custody_accounts WHERE group_id = p_buyer_group_id FOR UPDATE;
    SELECT total_deposited_usd - total_committed
      INTO v_seller_avail
      FROM public.custody_accounts
     WHERE group_id = v_seller
       FOR UPDATE;
  END IF;

  IF v_seller_avail IS NULL OR v_seller_avail < v_amount THEN
    RAISE EXCEPTION 'SWAP_INSUFFICIENT_BACKING: seller % avail=%, needed=%',
                    v_seller, COALESCE(v_seller_avail, 0), v_amount
      USING ERRCODE = 'P0004';
  END IF;

  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd - v_amount,
         updated_at          = now()
   WHERE group_id = v_seller;

  UPDATE public.custody_accounts
     SET total_deposited_usd = total_deposited_usd + v_net,
         updated_at          = now()
   WHERE group_id = p_buyer_group_id;

  IF v_fee > 0 THEN
    INSERT INTO public.platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
    VALUES ('swap', v_fee, p_order_id::text, v_seller,
            format('Swap fee: %s sells %s USD to %s', v_seller, v_amount, p_buyer_group_id));
  END IF;

  UPDATE public.swap_orders
     SET buyer_group_id = p_buyer_group_id,
         status         = 'settled',
         settled_at     = now()
   WHERE id = p_order_id;
END;
$$;

COMMENT ON FUNCTION public.execute_swap(uuid, uuid) IS
  'L05-01 + L05-02: swap atômico com SQLSTATE distinguíveis. '
  'P0001 SWAP_NOT_OPEN, P0002 SWAP_NOT_FOUND, P0003 SWAP_SELF_BUY, '
  'P0004 SWAP_INSUFFICIENT_BACKING, P0005 SWAP_EXPIRED. '
  'FOR UPDATE em swap_orders + custody_accounts em ordem UUID determinística. '
  'lock_timeout=2s. Rejeita expires_at<now() (cron sweep marca status=expired).';

GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) FROM anon;

-- ───────────────────────────────────────────────────────────────────────────
-- 4. fn_expire_swap_orders — sweep batch
--    Idempotente. Retorna count para observability. Lock por row via UPDATE
--    serializa contra execute_swap concorrente (quem chegar primeiro vence).
--    O RETURNING agrega rows expiradas para audit trail subsequente se
--    necessário.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_expire_swap_orders()
  RETURNS TABLE(
    expired_count integer,
    expired_ids   uuid[]
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '5s'
AS $$
DECLARE
  v_ids uuid[];
BEGIN
  WITH swept AS (
    UPDATE public.swap_orders
       SET status = 'expired'
     WHERE status = 'open'
       AND expires_at < now()
    RETURNING id
  )
  SELECT array_agg(id) INTO v_ids FROM swept;

  expired_count := COALESCE(array_length(v_ids, 1), 0);
  expired_ids   := COALESCE(v_ids, ARRAY[]::uuid[]);
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.fn_expire_swap_orders() IS
  'L05-02: sweep batch que marca swap_orders abertas e expiradas como '
  '''expired''. Idempotente: rodar várias vezes não muda nada após o '
  'primeiro pass (status sai de ''open''). Retorna count + array de ids '
  'para observability/audit.';

GRANT EXECUTE ON FUNCTION public.fn_expire_swap_orders() TO service_role;
REVOKE EXECUTE ON FUNCTION public.fn_expire_swap_orders() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_expire_swap_orders() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.fn_expire_swap_orders() FROM anon;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. pg_cron schedule (a cada 10 min)
--    Garante extension + faz unschedule defensivo de job homônimo (idempotência
--    em re-aplicação da migration).
-- ───────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

DO $$
BEGIN
  -- Unschedule se já existe (re-aplicação)
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'swap-expire') THEN
    PERFORM cron.unschedule('swap-expire');
  END IF;

  PERFORM cron.schedule(
    'swap-expire',
    '*/10 * * * *',
    $cron$ SELECT public.fn_expire_swap_orders(); $cron$
  );
EXCEPTION WHEN undefined_table THEN
  -- pg_cron não disponível em ambiente local sem extensão habilitada;
  -- tolerar silenciosamente para não quebrar dev. Em prod, supabase já
  -- carrega pg_cron por padrão.
  RAISE NOTICE '[L05-02] cron.job table não existe — skip schedule (dev env)';
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Invariants check
-- ───────────────────────────────────────────────────────────────────────────
DO $invariants$
DECLARE
  v_seller_id   uuid;
  v_buyer_id    uuid;
  v_order_id    uuid;
  v_count       integer;
  v_ids         uuid[];
  v_status      text;
  v_caught      boolean;
BEGIN
  -- 6a. Coluna existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'swap_orders'
      AND column_name = 'expires_at'
  ) THEN
    RAISE EXCEPTION '[L05-02] swap_orders.expires_at não criada';
  END IF;

  -- 6b. Status check inclui 'expired'
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_schema = 'public'
      AND constraint_name = 'swap_orders_status_check'
      AND check_clause LIKE '%expired%'
  ) THEN
    RAISE EXCEPTION '[L05-02] swap_orders_status_check não inclui ''expired''';
  END IF;

  -- 6c. Index parcial criado
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_swap_orders_open_expires'
  ) THEN
    RAISE EXCEPTION '[L05-02] index parcial não criado';
  END IF;

  -- 6d. fn_expire_swap_orders smoke (sem rows expiradas → 0)
  SELECT expired_count INTO v_count FROM public.fn_expire_swap_orders();
  IF v_count IS NULL OR v_count < 0 THEN
    RAISE EXCEPTION '[L05-02] fn_expire_swap_orders retornou count inválido: %', v_count;
  END IF;

  -- 6e. Smoke E2E: cria seller+buyer fictícios + order já-expirada e verifica
  --     que expire sweep marca como 'expired' E que execute_swap rejeita.
  SELECT id INTO v_seller_id FROM public.coaching_groups LIMIT 1;
  IF v_seller_id IS NULL THEN
    RAISE NOTICE '[L05-02] sem coaching_groups — skip E2E smoke';
    RETURN;
  END IF;
  SELECT id INTO v_buyer_id FROM public.coaching_groups
    WHERE id <> v_seller_id LIMIT 1;
  IF v_buyer_id IS NULL THEN
    RAISE NOTICE '[L05-02] precisa de 2 grupos — skip E2E smoke';
    RETURN;
  END IF;

  -- Garante seller tem custody account com saldo (para passar valid)
  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
    VALUES (v_seller_id, 1000)
    ON CONFLICT (group_id) DO NOTHING;

  -- Cria oferta JÁ expirada (expires_at no passado)
  INSERT INTO public.swap_orders
    (seller_group_id, amount_usd, fee_amount_usd, status, expires_at)
  VALUES
    (v_seller_id, 50, 0.5, 'open', now() - interval '1 hour')
  RETURNING id INTO v_order_id;

  -- Sweep marca como expired
  SELECT expired_count, expired_ids
    INTO v_count, v_ids
    FROM public.fn_expire_swap_orders();
  IF v_count < 1 OR NOT (v_order_id = ANY(v_ids)) THEN
    RAISE EXCEPTION '[L05-02] sweep não capturou order expirada: count=%, ids=%',
      v_count, v_ids;
  END IF;

  SELECT status INTO v_status FROM public.swap_orders WHERE id = v_order_id;
  IF v_status <> 'expired' THEN
    RAISE EXCEPTION '[L05-02] após sweep, status=% (esperado expired)', v_status;
  END IF;

  -- 6f. execute_swap em order expirada deve falhar com P0001 (já expired,
  --     status≠open). Re-execute sweep não deve incluir esta order.
  v_caught := false;
  BEGIN
    PERFORM public.execute_swap(v_order_id, v_buyer_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE IN ('P0001', 'P0005') THEN
      v_caught := true;
    ELSE
      RAISE;
    END IF;
  END;
  IF NOT v_caught THEN
    RAISE EXCEPTION '[L05-02] execute_swap deveria rejeitar order expirada';
  END IF;

  -- 6g. execute_swap em order com expires_at < now() mas status='open'
  --     (janela entre cron runs) deve raise P0005. Status fica 'open' até
  --     o próximo sweep (rollback de subtransaction não persiste UPDATE).
  INSERT INTO public.swap_orders
    (seller_group_id, amount_usd, fee_amount_usd, status, expires_at)
  VALUES
    (v_seller_id, 75, 0.75, 'open', now() - interval '1 second')
  RETURNING id INTO v_order_id;

  v_caught := false;
  BEGIN
    PERFORM public.execute_swap(v_order_id, v_buyer_id);
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0005' THEN
      v_caught := true;
    ELSE
      RAISE EXCEPTION '[L05-02] esperava P0005, recebeu SQLSTATE=%', SQLSTATE;
    END IF;
  END;
  IF NOT v_caught THEN
    RAISE EXCEPTION '[L05-02] execute_swap não levantou P0005 SWAP_EXPIRED';
  END IF;

  -- Confirma sweep marca essa order:
  PERFORM public.fn_expire_swap_orders();
  SELECT status INTO v_status FROM public.swap_orders WHERE id = v_order_id;
  IF v_status <> 'expired' THEN
    RAISE EXCEPTION '[L05-02] sweep não capturou order expirada (status=%)',
      v_status;
  END IF;

  -- Cleanup
  DELETE FROM public.swap_orders WHERE seller_group_id = v_seller_id
    AND amount_usd IN (50, 75)
    AND status = 'expired';

  RAISE NOTICE '[L05-02] invariants OK — TTL + cron sweep + execute_swap defesa';
END
$invariants$;
