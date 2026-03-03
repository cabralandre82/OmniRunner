-- ============================================================================
-- Migration: Gateway Fee Tracking + Fee Formula Fix + Reason CHECK Update
--
-- Fixes:
--   P0-1: custody_deposits now tracks gross_amount_usd / gateway_fee_usd
--         so that amount_usd = net received = coins_equivalent (1:1 peg).
--   P0-2: Enforces 1 OmniCoin = 1 USD net backing via CHECK constraint.
--   P1-1: Fee formula in execute_burn_atomic corrected to avoid rounding fragility.
--   P2-1: coin_ledger reason CHECK updated with new institution/team reasons.
-- ============================================================================

-- 1. Add gateway fee tracking columns to custody_deposits.
--    Model (Option B): assessoria pays gross, gateway keeps fee, net = coins * $1.
--    amount_usd (existing) = net received = exactly coins_equivalent.
ALTER TABLE public.custody_deposits
  ADD COLUMN IF NOT EXISTS gross_amount_usd  numeric(14,2),
  ADD COLUMN IF NOT EXISTS gateway_fee_usd   numeric(14,2) DEFAULT 0
    CHECK (gateway_fee_usd >= 0);

-- 2. Enforce the 1:1 peg: net received must equal coins issued.
--    amount_usd IS the net (what actually enters custody per coin).
ALTER TABLE public.custody_deposits
  ADD CONSTRAINT chk_peg_1_to_1
    CHECK (amount_usd = coins_equivalent::numeric);

-- 3. Enforce gross = net + gateway_fee when both are filled.
ALTER TABLE public.custody_deposits
  ADD CONSTRAINT chk_gross_fee_net
    CHECK (
      gross_amount_usd IS NULL
      OR gross_amount_usd = amount_usd + COALESCE(gateway_fee_usd, 0)
    );

-- 4. Backfill existing rows: gross was unknown, assume net = amount_usd.
UPDATE public.custody_deposits
SET gross_amount_usd = amount_usd,
    gateway_fee_usd  = 0
WHERE gross_amount_usd IS NULL;

-- 5. Fix fee formula in execute_burn_atomic.
--    Old: ROUND(v_gross * v_fee_rate) / 100   (fragile integer rounding)
--    New: ROUND(v_gross * v_fee_rate / 100, 2) (explicit 2-decimal rounding)
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
  SELECT balance_coins INTO v_wallet_balance
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_balance IS NULL OR v_wallet_balance < p_amount THEN
    RAISE EXCEPTION 'INSUFFICIENT_BALANCE: balance=%, requested=%',
      COALESCE(v_wallet_balance, 0), p_amount;
  END IF;

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

  UPDATE public.wallets
  SET balance_coins = balance_coins - p_amount
  WHERE user_id = p_user_id;

  INSERT INTO public.clearing_events
    (burn_ref_id, athlete_user_id, redeemer_group_id, total_coins, breakdown)
  VALUES
    (p_ref_id, p_user_id, p_redeemer_group_id, p_amount, v_breakdown)
  RETURNING id INTO v_event_id;

  SELECT rate_pct INTO v_fee_rate
  FROM public.platform_fee_config
  WHERE fee_type = 'clearing' AND is_active = true;
  v_fee_rate := COALESCE(v_fee_rate, 3.0);

  FOR v_issuer, v_issuer_balance IN
    SELECT
      (entry->>'issuer_group_id')::uuid,
      (entry->>'amount')::integer
    FROM jsonb_array_elements(v_breakdown) AS entry
    WHERE entry->>'issuer_group_id' IS NOT NULL
  LOOP
    IF v_issuer = p_redeemer_group_id THEN
      SELECT EXISTS(
        SELECT 1 FROM public.custody_accounts WHERE group_id = v_issuer
      ) INTO v_has_custody;

      IF v_has_custody THEN
        BEGIN
          PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
        EXCEPTION WHEN OTHERS THEN
          NULL;
        END;
      END IF;
    ELSE
      v_gross := v_issuer_balance::numeric;
      v_fee := ROUND(v_gross * v_fee_rate / 100, 2);
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

-- 6. Update coin_ledger reason CHECK to include all current reasons.
ALTER TABLE public.coin_ledger
  DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;

ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (reason IN (
    'session_completed',
    'challenge_one_vs_one_completed',
    'challenge_one_vs_one_won',
    'challenge_group_completed',
    'streak_weekly',
    'streak_monthly',
    'pr_distance',
    'pr_pace',
    'challenge_entry_fee',
    'challenge_pool_won',
    'challenge_entry_refund',
    'cosmetic_purchase',
    'admin_adjustment',
    'badge_reward',
    'mission_reward',
    'cross_assessoria_pending',
    'cross_assessoria_cleared',
    'cross_assessoria_burned',
    'institution_token_issue',
    'institution_token_burn',
    'challenge_team_completed',
    'challenge_team_won',
    'admin_correction'
  ));

GRANT EXECUTE ON FUNCTION public.execute_burn_atomic TO service_role;
