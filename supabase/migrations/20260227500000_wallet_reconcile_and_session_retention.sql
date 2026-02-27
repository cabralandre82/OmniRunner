-- Migration: Wallet reconciliation RPC + session retention policy
-- DECISÃO 095 — M7 & M4

-- ═══════════════════════════════════════════════════════════════════════════
-- M7: Reconcile wallet balance against coin_ledger (source of truth).
-- If balance_coins != SUM(delta_coins), fix the wallet and log the drift.
-- Returns JSON: { reconciled: bool, drift: int, new_balance: int }
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.reconcile_wallet(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ledger_sum   INTEGER;
  v_current_bal  INTEGER;
  v_drift        INTEGER;
BEGIN
  SELECT COALESCE(SUM(delta_coins), 0)
    INTO v_ledger_sum
    FROM public.coin_ledger
   WHERE user_id = p_user_id;

  SELECT balance_coins
    INTO v_current_bal
    FROM public.wallets
   WHERE user_id = p_user_id
     FOR UPDATE;

  IF v_current_bal IS NULL THEN
    RETURN jsonb_build_object(
      'reconciled', false,
      'error', 'WALLET_NOT_FOUND'
    );
  END IF;

  v_drift := v_ledger_sum - v_current_bal;

  IF v_drift = 0 THEN
    UPDATE public.wallets
       SET last_reconciled_at_ms = (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT,
           updated_at = now()
     WHERE user_id = p_user_id;

    RETURN jsonb_build_object(
      'reconciled', true,
      'drift', 0,
      'new_balance', v_current_bal
    );
  END IF;

  -- Fix the drift
  UPDATE public.wallets
     SET balance_coins = GREATEST(v_ledger_sum, 0),
         last_reconciled_at_ms = (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT,
         updated_at = now()
   WHERE user_id = p_user_id;

  -- Log drift as a ledger correction entry for audit trail
  INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, note, created_at_ms)
  VALUES (
    p_user_id,
    0,
    'admin_correction',
    NULL,
    format('reconcile drift=%s old_bal=%s ledger_sum=%s', v_drift, v_current_bal, v_ledger_sum),
    (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT
  );

  RETURN jsonb_build_object(
    'reconciled', true,
    'drift', v_drift,
    'new_balance', GREATEST(v_ledger_sum, 0)
  );
END;
$$;

COMMENT ON FUNCTION public.reconcile_wallet IS
  'Compares wallet.balance_coins against SUM(coin_ledger.delta_coins). '
  'Fixes drift and logs a zero-delta correction entry for audit trail.';

-- Allow admin_correction reason in coin_ledger
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;
ALTER TABLE public.coin_ledger ADD CONSTRAINT coin_ledger_reason_check CHECK (reason IN (
  'session_completed',
  'challenge_one_vs_one_completed', 'challenge_one_vs_one_won',
  'challenge_group_completed', 'challenge_group_won',
  'challenge_team_won', 'challenge_team_completed',
  'challenge_entry_fee', 'challenge_entry_refund', 'challenge_pool_won',
  'streak_weekly', 'streak_monthly',
  'pr_distance', 'pr_pace',
  'badge_reward', 'badge_earned',
  'mission_reward', 'mission_completed',
  'cosmetic_purchase',
  'admin_adjustment', 'admin_correction',
  'cross_assessoria_pending', 'cross_assessoria_cleared', 'cross_assessoria_burned',
  'institution_switch_burn', 'institution_token_issue', 'institution_token_burn',
  'institution_credit'
));


-- ═══════════════════════════════════════════════════════════════════════════
-- Batch reconciliation: reconcile ALL wallets and return summary.
-- Designed to be called by a periodic cron Edge Function.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.reconcile_all_wallets()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total     INTEGER := 0;
  v_drifted   INTEGER := 0;
  v_result    JSONB;
  r           RECORD;
BEGIN
  FOR r IN SELECT user_id FROM public.wallets LOOP
    v_result := public.reconcile_wallet(r.user_id);
    v_total := v_total + 1;
    IF (v_result ->> 'drift')::INTEGER != 0 THEN
      v_drifted := v_drifted + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'total_wallets', v_total,
    'drifted', v_drifted,
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.reconcile_all_wallets IS
  'Batch reconciliation: iterates all wallets and fixes any balance drift. '
  'Returns { total_wallets, drifted, run_at }.';


-- ═══════════════════════════════════════════════════════════════════════════
-- M4: Session retention — archive sessions older than 2 years.
-- Moves old sessions to sessions_archive and deletes originals.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.sessions_archive (LIKE public.sessions INCLUDING ALL);

ALTER TABLE public.sessions_archive ENABLE ROW LEVEL SECURITY;

CREATE POLICY "archive_own_read" ON public.sessions_archive
  FOR SELECT USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.archive_old_sessions(p_retention_days INTEGER DEFAULT 730)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff_ms BIGINT;
  v_archived  INTEGER;
BEGIN
  v_cutoff_ms := (EXTRACT(EPOCH FROM (now() - (p_retention_days || ' days')::INTERVAL)) * 1000)::BIGINT;

  WITH moved AS (
    INSERT INTO public.sessions_archive
    SELECT * FROM public.sessions
     WHERE start_time_ms < v_cutoff_ms
       AND status IN ('completed', 'synced')
    ON CONFLICT DO NOTHING
    RETURNING id
  )
  SELECT COUNT(*) INTO v_archived FROM moved;

  DELETE FROM public.sessions
   WHERE start_time_ms < v_cutoff_ms
     AND status IN ('completed', 'synced')
     AND id IN (SELECT id FROM public.sessions_archive);

  RETURN jsonb_build_object(
    'archived', v_archived,
    'cutoff_date', to_timestamp(v_cutoff_ms / 1000.0),
    'run_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.archive_old_sessions IS
  'Archives completed sessions older than p_retention_days (default 730/2y). '
  'Moves to sessions_archive, then deletes originals. Idempotent via ON CONFLICT.';
