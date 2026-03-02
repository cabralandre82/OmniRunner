-- Migration: Atomic burn plan with multi-issuer tracking and clearing bridge.
--
-- Closes P0 gaps:
--   1. compute_burn_plan: deterministic breakdown by issuer (same-club first)
--   2. execute_burn_atomic: single-transaction burn + clearing
--
-- Model invariant: every burn produces a breakdown by issuer_group_id.
-- Intra-club coins → release committed (R -= b, A += b).
-- Interclub coins  → create settlement (R -= b, D -= gross, D_creditor += net).
-- Legacy coins (NULL issuer) → burned without clearing.

-- 1. Compute burn plan: given user + redeemer + amount, returns breakdown.
-- Priority: redeemer's own coins first, then other clubs, then legacy (NULL).
CREATE OR REPLACE FUNCTION public.compute_burn_plan(
  p_user_id         uuid,
  p_redeemer_group_id uuid,
  p_amount          integer
)
  RETURNS TABLE(issuer_group_id uuid, amount integer)
  LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v_remaining integer := p_amount;
  v_issuer    uuid;
  v_balance   integer;
  v_take      integer;
BEGIN
  -- Phase 1: known issuers (same-club first, then others by largest balance)
  FOR v_issuer, v_balance IN
    SELECT cl.issuer_group_id, SUM(cl.delta_coins)::integer
    FROM public.coin_ledger cl
    WHERE cl.user_id = p_user_id
      AND cl.issuer_group_id IS NOT NULL
    GROUP BY cl.issuer_group_id
    HAVING SUM(cl.delta_coins) > 0
    ORDER BY
      CASE WHEN cl.issuer_group_id = p_redeemer_group_id THEN 0 ELSE 1 END,
      SUM(cl.delta_coins) DESC
  LOOP
    EXIT WHEN v_remaining <= 0;
    v_take := LEAST(v_balance, v_remaining);
    v_remaining := v_remaining - v_take;
    issuer_group_id := v_issuer;
    amount := v_take;
    RETURN NEXT;
  END LOOP;

  -- Phase 2: legacy coins (NULL issuer) — no clearing triggered
  IF v_remaining > 0 THEN
    SELECT COALESCE(SUM(cl.delta_coins), 0)::integer INTO v_balance
    FROM public.coin_ledger cl
    WHERE cl.user_id = p_user_id
      AND cl.issuer_group_id IS NULL;

    IF v_balance > 0 THEN
      v_take := LEAST(v_balance, v_remaining);
      v_remaining := v_remaining - v_take;
      issuer_group_id := NULL;
      amount := v_take;
      RETURN NEXT;
    END IF;
  END IF;

  IF v_remaining > 0 THEN
    RAISE EXCEPTION 'BURN_PLAN_SHORTFALL: could not allocate % coins (remaining=%)',
      p_amount, v_remaining;
  END IF;
END;
$$;

-- 2. Atomic burn: single transaction covering wallet debit, per-issuer ledger
--    entries, clearing event, settlements, and custody release.
CREATE OR REPLACE FUNCTION public.execute_burn_atomic(
  p_user_id           uuid,
  p_redeemer_group_id uuid,
  p_amount            integer,
  p_ref_id            uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_balance integer;
  v_remaining      integer := p_amount;
  v_breakdown      jsonb := '[]'::jsonb;
  v_issuer         uuid;
  v_issuer_balance integer;
  v_take           integer;
  v_now_ms         bigint := (extract(epoch from now()) * 1000)::bigint;
  v_event_id       uuid;
  v_fee_rate       numeric(5,2);
  v_gross          numeric(14,2);
  v_fee            numeric(14,2);
  v_net            numeric(14,2);
  v_settlement_id  uuid;
  v_has_custody    boolean;
BEGIN
  -- 1. Lock wallet and verify balance
  SELECT balance_coins INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, requested=%',
      COALESCE(v_wallet_balance, 0), p_amount;
  END IF;

  -- 2. Compute burn plan and insert per-issuer ledger entries
  FOR v_issuer, v_issuer_balance IN
    SELECT bp.issuer_group_id, bp.amount
    FROM public.compute_burn_plan(p_user_id, p_redeemer_group_id, p_amount) bp
  LOOP
    v_breakdown := v_breakdown || jsonb_build_object(
      'issuer_group_id', v_issuer,
      'amount', v_issuer_balance
    );

    INSERT INTO public.coin_ledger
      (user_id, delta_coins, reason, ref_id, issuer_group_id, created_at_ms)
    VALUES
      (p_user_id, -v_issuer_balance, 'institution_token_burn',
       p_ref_id, v_issuer, v_now_ms);
  END LOOP;

  -- 3. Debit wallet (total)
  UPDATE public.wallets
  SET balance_coins = balance_coins - p_amount
  WHERE user_id = p_user_id;

  -- 4. Create clearing event
  INSERT INTO public.clearing_events
    (burn_ref_id, athlete_user_id, redeemer_group_id, total_coins, breakdown)
  VALUES
    (p_ref_id, p_user_id, p_redeemer_group_id, p_amount, v_breakdown)
  RETURNING id INTO v_event_id;

  -- 5. Get clearing fee rate
  SELECT rate_pct INTO v_fee_rate
  FROM public.platform_fee_config
  WHERE fee_type = 'clearing' AND is_active = true;
  v_fee_rate := COALESCE(v_fee_rate, 3.0);

  -- 6. Process each issuer in breakdown
  FOR v_issuer, v_issuer_balance IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = p_redeemer_group_id THEN
      -- Intra-club: release committed (R -= b, A += b)
      SELECT EXISTS(
        SELECT 1 FROM public.custody_accounts WHERE group_id = v_issuer
      ) INTO v_has_custody;

      IF v_has_custody THEN
        BEGIN
          PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
        EXCEPTION WHEN OTHERS THEN
          NULL; -- Custody not yet active for this club
        END;
      END IF;
    ELSE
      -- Interclub: create settlement
      v_gross := v_issuer_balance::numeric;
      v_fee := ROUND(v_gross * v_fee_rate) / 100;
      v_net := v_gross - v_fee;

      INSERT INTO public.clearing_settlements
        (clearing_event_id, creditor_group_id, debtor_group_id,
         coin_amount, gross_amount_usd, fee_rate_pct,
         fee_amount_usd, net_amount_usd, status)
      VALUES
        (v_event_id, p_redeemer_group_id, v_issuer,
         v_issuer_balance, v_gross, v_fee_rate,
         v_fee, v_net, 'pending')
      RETURNING id INTO v_settlement_id;

      -- Auto-settle (best-effort; failures stay pending for netting cron)
      BEGIN
        PERFORM public.settle_clearing(v_settlement_id);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'event_id', v_event_id,
    'breakdown', v_breakdown,
    'total_burned', p_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.compute_burn_plan TO service_role;
GRANT EXECUTE ON FUNCTION public.execute_burn_atomic TO service_role;
