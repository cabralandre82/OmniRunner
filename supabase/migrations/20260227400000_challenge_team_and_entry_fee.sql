-- ── 1. Add 'team' type to challenges ──────────────────────────────────────
ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_type_check;
ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_type_check
  CHECK (type IN ('one_vs_one', 'group', 'team'));

-- ── 2. Add 'team' column to challenge_participants ───────────────────────
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS team TEXT;

ALTER TABLE public.challenge_participants
  DROP CONSTRAINT IF EXISTS chk_participant_team;
ALTER TABLE public.challenge_participants
  ADD CONSTRAINT chk_participant_team
  CHECK (team IS NULL OR team IN ('A', 'B'));

-- ── 3. Add 'challenge_team_won' + 'challenge_team_completed' reasons ─────
ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;
ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check
  CHECK (reason IN (
    'session_completed',
    'challenge_one_vs_one_completed',
    'challenge_one_vs_one_won',
    'challenge_group_completed',
    'challenge_team_won',
    'challenge_team_completed',
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
    'institution_switch_burn',
    'institution_token_issue',
    'institution_token_burn',
    'admin_correction'
  ));

-- ── 4. Atomic wallet debit with balance check ───────────────────────────
CREATE OR REPLACE FUNCTION public.debit_wallet_checked(
  p_user_id uuid,
  p_amount  integer
)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = 'public'
AS $$
BEGIN
  IF p_amount <= 0 THEN
    RETURN true;
  END IF;

  UPDATE public.wallets
  SET
    balance_coins        = balance_coins - p_amount,
    lifetime_spent_coins = lifetime_spent_coins + p_amount,
    updated_at           = now()
  WHERE user_id = p_user_id
    AND balance_coins >= p_amount;

  RETURN FOUND;
END;
$$;

GRANT EXECUTE ON FUNCTION public.debit_wallet_checked(uuid, integer)
  TO authenticated, service_role;
