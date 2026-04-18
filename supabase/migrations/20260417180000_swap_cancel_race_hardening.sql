-- ──────────────────────────────────────────────────────────────────────────
-- L05-01 — Race condition entre accept e cancel em swap_orders
--
-- Referência auditoria:
--   docs/audit/findings/L05-01-swap-race-entre-accept-e-cancel-do-dono.md
--   docs/audit/parts/05-cpo.md [5.1]
--
-- Problema:
--   1. `cancelSwapOffer` (portal/src/lib/swap.ts) executa direto UPDATE
--      `swap_orders SET status='cancelled' WHERE id=X AND status='open'`
--      sem FOR UPDATE explícito nem feedback semântico ao caller. Silencia
--      falha de concorrência (0 rows updated → caller recebe "ok").
--   2. `execute_swap` (20260228170000_custody_gaps.sql:210) RAISE EXCEPTION
--      com mensagem genérica "Swap order not found or no longer open" sem
--      SQLSTATE distinguível — impossível para portal mapear para HTTP
--      apropriado (404 vs 409 vs 422).
--   3. Sem `lock_timeout` explícito no nível da função — L19-05 cobriu
--      execute_swap mas NÃO cancel_swap_order (que não existia).
--
-- Correção:
--   (a) Nova RPC `cancel_swap_order(p_order_id, p_seller_group_id)`:
--       SECURITY DEFINER, FOR UPDATE do row, ownership check, status check.
--       SQLSTATE codes: P0001 (SWAP_NOT_OPEN), P0002 (SWAP_NOT_FOUND),
--       P0003 (SWAP_NOT_OWNER). Inclui hint com status atual.
--       lock_timeout='2s' + search_path=public,pg_temp (L19-05 + L18-03).
--   (b) Refactor `execute_swap` adicionando SQLSTATE distinguíveis: P0001
--       (já não aceita, status≠open), P0002 (não encontrada), P0003 (self
--       buy), P0004 (seller sem backing suficiente). Mantém toda a lógica
--       transacional (FOR UPDATE em swap_orders + custody_accounts em ordem
--       determinística).
--   (c) Garantia adicional: execute_swap e cancel_swap_order REVOGAM acesso
--       para `anon` (apenas service_role + authenticated via portal).
-- ──────────────────────────────────────────────────────────────────────────

-- 1. cancel_swap_order — atomic cancel with ownership + status guards
CREATE OR REPLACE FUNCTION public.cancel_swap_order(
  p_order_id        uuid,
  p_seller_group_id uuid
)
  RETURNS TABLE (
    order_id       uuid,
    previous_status text,
    new_status     text,
    cancelled_at   timestamptz
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET lock_timeout = '2s'
AS $$
DECLARE
  v_seller_actual uuid;
  v_status        text;
  v_now           timestamptz := now();
BEGIN
  -- Lock the row atomically. FOR UPDATE waits up to lock_timeout (2s).
  -- If execute_swap concurrently holds this row, one of the two wins;
  -- the other observes the committed end-state on re-check below.
  SELECT so.seller_group_id, so.status
    INTO v_seller_actual, v_status
    FROM public.swap_orders so
   WHERE so.id = p_order_id
     FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SWAP_NOT_FOUND: order % does not exist', p_order_id
      USING ERRCODE = 'P0002',
            HINT    = 'order_id does not match any swap_orders row';
  END IF;

  IF v_seller_actual <> p_seller_group_id THEN
    RAISE EXCEPTION 'SWAP_NOT_OWNER: group % is not the seller of order %',
                    p_seller_group_id, p_order_id
      USING ERRCODE = 'P0003',
            HINT    = 'Only the seller_group_id of a swap order may cancel it';
  END IF;

  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'SWAP_NOT_OPEN: order % is in status=% (expected=open)',
                    p_order_id, v_status
      USING ERRCODE = 'P0001',
            HINT    = v_status;  -- current status surfaced to caller
  END IF;

  UPDATE public.swap_orders
     SET status = 'cancelled'
   WHERE id = p_order_id;

  RETURN QUERY SELECT p_order_id, v_status, 'cancelled'::text, v_now;
END;
$$;

COMMENT ON FUNCTION public.cancel_swap_order(uuid, uuid) IS
  'L05-01: atomic cancel with FOR UPDATE + ownership + status guards. '
  'Error codes: P0001 SWAP_NOT_OPEN, P0002 SWAP_NOT_FOUND, P0003 SWAP_NOT_OWNER. '
  'lock_timeout=2s: se concorrência prolongada, falha com 55P03 (caller deve retry).';

GRANT EXECUTE ON FUNCTION public.cancel_swap_order(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_swap_order(uuid, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_swap_order(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cancel_swap_order(uuid, uuid) FROM anon;

-- 2. execute_swap — hardenizado com SQLSTATE distinguíveis
--
-- Mantém EXATAMENTE a lógica transacional original (FOR UPDATE em swap_orders,
-- locks de custody_accounts em ordem UUID determinística, update de saldos,
-- registro de platform_revenue, transição open→settled). Apenas substitui
-- RAISE EXCEPTION genéricos por códigos SQLSTATE estáveis + preserva
-- lock_timeout=2s (L19-05) e search_path=public,pg_temp (L18-03).
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
  v_net          numeric(14,2);
  v_seller_avail numeric(14,2);
BEGIN
  -- Lock row by id only so we can distinguish "not found" vs "not open".
  SELECT seller_group_id, status, amount_usd, fee_amount_usd
    INTO v_seller, v_status, v_amount, v_fee
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

  IF v_seller = p_buyer_group_id THEN
    RAISE EXCEPTION 'SWAP_SELF_BUY: buyer % is the seller of order %',
                    p_buyer_group_id, p_order_id
      USING ERRCODE = 'P0003';
  END IF;

  v_net := v_amount - v_fee;

  -- Ensure buyer account exists (safe idempotent upsert)
  INSERT INTO public.custody_accounts (group_id, total_deposited_usd)
  VALUES (p_buyer_group_id, 0)
  ON CONFLICT (group_id) DO NOTHING;

  -- Lock BOTH accounts in deterministic UUID order to prevent deadlocks.
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
  'L05-01: swap atômico com SQLSTATE distinguíveis. '
  'Error codes: P0001 SWAP_NOT_OPEN, P0002 SWAP_NOT_FOUND, P0003 SWAP_SELF_BUY, '
  'P0004 SWAP_INSUFFICIENT_BACKING. FOR UPDATE em swap_orders + custody_accounts '
  'em ordem UUID determinística. lock_timeout=2s.';

GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.execute_swap(uuid, uuid) FROM anon;

-- 3. Invariante pós-migration: ambas as funções devem ter search_path e lock_timeout
DO $$
DECLARE
  r RECORD;
  v_bad text := '';
BEGIN
  FOR r IN
    SELECT p.proname,
           pg_get_function_identity_arguments(p.oid) AS args,
           coalesce(p.proconfig, ARRAY[]::text[])    AS cfg
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('cancel_swap_order', 'execute_swap')
  LOOP
    IF NOT EXISTS (SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'search_path=%') THEN
      v_bad := v_bad || format('%s(%s) sem search_path; ', r.proname, r.args);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM unnest(r.cfg) c WHERE c LIKE 'lock_timeout=%') THEN
      v_bad := v_bad || format('%s(%s) sem lock_timeout; ', r.proname, r.args);
    END IF;
  END LOOP;

  IF v_bad <> '' THEN
    RAISE EXCEPTION '[L05-01] configuração ausente: %', v_bad
      USING ERRCODE = 'P0001';
  END IF;
END $$;
