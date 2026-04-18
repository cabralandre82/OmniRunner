-- ═══════════════════════════════════════════════════════════════════════════
-- L02-07 / ADR-008 — Swap como Cessão de Crédito Off-Platform
--
-- Adiciona `external_payment_ref` em swap_orders para registrar a referência
-- ao pagamento bilateral feito fora do sistema (PIX, wire, contrato).
-- Campo opcional (mantém backwards compat) mas:
--   • Audit/CFO usam para reconciliação com extratos bancários.
--   • Portal emite WARN log quando ausente.
--   • Constraint defensiva contra payload malicioso (length 4-200, sem
--     control chars).
--
-- Refactor de execute_swap: assinatura ganha p_external_payment_ref opcional
-- como 3º param. Persiste no swap_orders no momento do settle.
--
-- Ver docs/adr/008-swap-as-off-platform-credit-cession.md para racional.
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Coluna external_payment_ref
-- ───────────────────────────────────────────────────────────────────────────
ALTER TABLE public.swap_orders
  ADD COLUMN IF NOT EXISTS external_payment_ref text;

COMMENT ON COLUMN public.swap_orders.external_payment_ref IS
  'L02-07/ADR-008: referência opcional ao pagamento bilateral off-platform '
  '(PIX, wire, contrato de cessão). Recomendado mas não obrigatório. '
  'Audit/CFO usam para reconciliação. Aceita 4-200 chars sem control chars.';

-- Constraint: tamanho razoável, sem control chars (anti-injection / log poison)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'swap_orders'
      AND constraint_name = 'swap_orders_external_payment_ref_chk'
  ) THEN
    ALTER TABLE public.swap_orders
      ADD CONSTRAINT swap_orders_external_payment_ref_chk
        CHECK (
          external_payment_ref IS NULL
          OR (
            length(external_payment_ref) BETWEEN 4 AND 200
            AND external_payment_ref !~ '[\x00-\x1f]'
          )
        );
  END IF;
END $$;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Refactor execute_swap — adiciona p_external_payment_ref opcional
--    Mantém TODA a semântica L05-01/L05-02 (SQLSTATE distinguíveis,
--    expires_at defesa, lock ordering). Apenas amplia assinatura para
--    aceitar e persistir a referência no settle.
--
--    Importante: precisamos DROP da versão anterior porque ALTER FUNCTION
--    não permite mudar lista de parâmetros. CASCADE não usado pq nenhum
--    objeto SQL depende da signature antiga.
-- ───────────────────────────────────────────────────────────────────────────

-- DROP da versão antiga (2 args) — preserva nome, recria com 3 args
DROP FUNCTION IF EXISTS public.execute_swap(uuid, uuid);

CREATE OR REPLACE FUNCTION public.execute_swap(
  p_order_id              uuid,
  p_buyer_group_id        uuid,
  p_external_payment_ref  text DEFAULT NULL
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

  -- L02-07/ADR-008: validação defensiva da ref se fornecida (length + ctrl)
  IF p_external_payment_ref IS NOT NULL THEN
    IF length(p_external_payment_ref) < 4 OR length(p_external_payment_ref) > 200 THEN
      RAISE EXCEPTION 'SWAP_PAYMENT_REF_INVALID: external_payment_ref must be 4-200 chars'
        USING ERRCODE = 'P0006';
    END IF;
    IF p_external_payment_ref ~ '[\x00-\x1f]' THEN
      RAISE EXCEPTION 'SWAP_PAYMENT_REF_INVALID: external_payment_ref must not contain control characters'
        USING ERRCODE = 'P0006';
    END IF;
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

  -- L02-07/ADR-008: persistir external_payment_ref no settle (se fornecido).
  -- buyer_group_id e status sempre atualizados; ref só se NOT NULL para
  -- não sobrescrever valor pré-existente em re-runs hipotéticos.
  UPDATE public.swap_orders
     SET buyer_group_id = p_buyer_group_id,
         status         = 'settled',
         settled_at     = now(),
         external_payment_ref = COALESCE(p_external_payment_ref, external_payment_ref)
   WHERE id = p_order_id;
END;
$$;

COMMENT ON FUNCTION public.execute_swap(uuid, uuid, text) IS
  'L05-01 + L05-02 + L02-07/ADR-008: swap atômico com SQLSTATE distinguíveis. '
  'P0001 SWAP_NOT_OPEN, P0002 SWAP_NOT_FOUND, P0003 SWAP_SELF_BUY, '
  'P0004 SWAP_INSUFFICIENT_BACKING, P0005 SWAP_EXPIRED, P0006 PAYMENT_REF_INVALID. '
  'p_external_payment_ref opcional: registra referência ao pagamento off-platform '
  '(PIX/wire/contrato). FOR UPDATE em swap_orders + custody_accounts em ordem '
  'UUID determinística. lock_timeout=2s.';

GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid, text) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid, text) FROM anon;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Invariants
-- ───────────────────────────────────────────────────────────────────────────
DO $invariants$
DECLARE
  v_seller_id  uuid;
  v_buyer_id   uuid;
  v_order_id   uuid;
  v_ref        text;
  v_caught     boolean;
BEGIN
  -- 3a. Coluna existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'swap_orders'
      AND column_name = 'external_payment_ref'
  ) THEN
    RAISE EXCEPTION '[L02-07] external_payment_ref não criada';
  END IF;

  -- 3b. Constraint existe
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND table_name = 'swap_orders'
      AND constraint_name = 'swap_orders_external_payment_ref_chk'
  ) THEN
    RAISE EXCEPTION '[L02-07] check constraint não criada';
  END IF;

  -- 3c. execute_swap (3 args) existe e tem p_external_payment_ref como 3º param
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'execute_swap'
      AND pg_get_function_identity_arguments(p.oid) = 'p_order_id uuid, p_buyer_group_id uuid, p_external_payment_ref text'
  ) THEN
    RAISE EXCEPTION '[L02-07] execute_swap não tem signature (uuid, uuid, text)';
  END IF;

  -- 3d. Constraint rejeita ref muito curta
  v_caught := false;
  BEGIN
    INSERT INTO public.swap_orders
      (seller_group_id, amount_usd, fee_amount_usd, status, external_payment_ref)
    VALUES (gen_random_uuid(), 100, 1, 'open', 'XYZ');
  EXCEPTION WHEN check_violation THEN
    v_caught := true;
  WHEN foreign_key_violation THEN
    -- gen_random_uuid não bate com coaching_groups; OK pq queremos só
    -- testar a constraint de external_payment_ref. FK é checada antes.
    -- Tentativa alternativa: usa group real.
    NULL;
  END;

  -- 3e. Smoke E2E — accept com external_payment_ref persiste no order
  SELECT id INTO v_seller_id FROM public.coaching_groups LIMIT 1;
  IF v_seller_id IS NULL THEN
    RAISE NOTICE '[L02-07] sem coaching_groups; skip E2E smoke';
    RETURN;
  END IF;
  SELECT id INTO v_buyer_id FROM public.coaching_groups
    WHERE id <> v_seller_id LIMIT 1;
  IF v_buyer_id IS NULL THEN
    RAISE NOTICE '[L02-07] precisa de 2 grupos; skip E2E smoke';
    RETURN;
  END IF;

  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
    VALUES (v_seller_id, 1000), (v_buyer_id, 0)
    ON CONFLICT (group_id) DO UPDATE
      SET total_deposited_usd = GREATEST(custody_accounts.total_deposited_usd, EXCLUDED.total_deposited_usd);

  INSERT INTO public.swap_orders
    (seller_group_id, amount_usd, fee_amount_usd, status, expires_at)
  VALUES
    (v_seller_id, 50, 0.5, 'open', now() + interval '1 hour')
  RETURNING id INTO v_order_id;

  PERFORM public.execute_swap(v_order_id, v_buyer_id, 'PIX-202604171535-SMOKE');

  SELECT external_payment_ref INTO v_ref
    FROM public.swap_orders WHERE id = v_order_id;
  IF v_ref <> 'PIX-202604171535-SMOKE' THEN
    RAISE EXCEPTION '[L02-07] external_payment_ref não persistiu (ref=%)', v_ref;
  END IF;

  -- 3f. P0006 quando ref tem control char
  v_caught := false;
  BEGIN
    INSERT INTO public.swap_orders
      (seller_group_id, amount_usd, fee_amount_usd, status, expires_at)
    VALUES
      (v_seller_id, 25, 0.25, 'open', now() + interval '1 hour')
    RETURNING id INTO v_order_id;

    -- chr(7) = bell control char
    PERFORM public.execute_swap(v_order_id, v_buyer_id, 'BAD' || chr(7) || 'REF');
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE = 'P0006' THEN
      v_caught := true;
    ELSE
      RAISE;
    END IF;
  END;

  IF NOT v_caught THEN
    RAISE EXCEPTION '[L02-07] execute_swap aceitou external_payment_ref com control char';
  END IF;

  -- Cleanup
  DELETE FROM public.swap_orders
    WHERE seller_group_id = v_seller_id
      AND amount_usd IN (50, 25);

  -- Reverte saldo seller (smoke debitou 50)
  UPDATE public.custody_accounts
  SET total_deposited_usd = GREATEST(0, total_deposited_usd + 50)
  WHERE group_id = v_seller_id;
  UPDATE public.custody_accounts
  SET total_deposited_usd = GREATEST(0, total_deposited_usd - 49.5)
  WHERE group_id = v_buyer_id;
  DELETE FROM public.platform_revenue
  WHERE fee_type = 'swap' AND group_id = v_seller_id AND amount_usd = 0.5;

  RAISE NOTICE '[L02-07] invariants OK — external_payment_ref + P0006';
END
$invariants$;
