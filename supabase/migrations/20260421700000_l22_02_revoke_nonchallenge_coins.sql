-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║  L22-02 — Revoke non-challenge OmniCoin credit paths (correction)          ║
-- ║                                                                            ║
-- ║  Product invariant: OmniCoins are earned/spent ONLY in challenges.         ║
-- ║  They are NEVER "given" as onboarding perks, referral bonuses, sponsorship ║
-- ║  payouts, streak rewards, or any other off-challenge mechanism.            ║
-- ║                                                                            ║
-- ║  Earlier migrations in Batch J accidentally introduced two emission        ║
-- ║  paths that violate this rule:                                             ║
-- ║                                                                            ║
-- ║    • 20260421580000_l15_02_referral_program.sql                            ║
-- ║        └─ fn_activate_referral() credited referrer + referred via          ║
-- ║           coin_ledger reasons 'referral_referrer_reward' and               ║
-- ║           'referral_referred_reward', and bumped wallets.balance_coins.    ║
-- ║                                                                            ║
-- ║    • 20260421620000_l16_05_sponsorships.sql                                ║
-- ║        └─ fn_sponsorship_distribute_monthly_coins() credited enrolled      ║
-- ║           athletes a monthly OmniCoin stipend under reason                 ║
-- ║           'sponsorship_payout'.  Same migration also widened the reason    ║
-- ║           enum with several aspirational reasons that were never wired     ║
-- ║           to any code path (referral_bonus, referral_new_user,             ║
-- ║           redemption_payout, custody_reversal, championship_reward) and    ║
-- ║           silently dropped the pre-existing institution_token_* /          ║
-- ║           institution_switch_burn reasons from the CHECK.                  ║
-- ║                                                                            ║
-- ║  This migration compensates for both.  It:                                 ║
-- ║                                                                            ║
-- ║    1. Deletes any coin_ledger rows with a non-challenge reward reason      ║
-- ║       that the two migrations above introduced, and reconciles the        ║
-- ║       affected wallets.balance_coins totals from the ledger.               ║
-- ║                                                                            ║
-- ║    2. Replaces fn_activate_referral() with a version that flips the        ║
-- ║       referral row to 'activated' and emits NO coin_ledger entry and       ║
-- ║       NO wallet mutation.  The referral table is retained for tracking     ║
-- ║       viral growth; there is simply no coin payout.                        ║
-- ║                                                                            ║
-- ║    3. Drops fn_sponsorship_distribute_monthly_coins().  Sponsorship        ║
-- ║       benefits for enrolled athletes will be delivered through fiat        ║
-- ║       discounts / physical swag / etc., not coins.                         ║
-- ║                                                                            ║
-- ║    4. Drops the now-obsolete coin-budget columns from sponsorships and     ║
-- ║       the coin-reward columns from referrals / referral_rewards_config.    ║
-- ║                                                                            ║
-- ║    5. Restores the coin_ledger_reason_check CHECK constraint to the        ║
-- ║       canonical L03-13 list, reinstates the institution_token_* reasons    ║
-- ║       that L16-05 dropped, and adds 'challenge_withdrawal_refund' which    ║
-- ║       is used by the challenge-withdraw edge function but was missing      ║
-- ║       from the CHECK.                                                      ║
-- ║                                                                            ║
-- ║    6. Adds a hard-coded DO block self-test that asserts the forbidden     ║
-- ║       reward reasons are gone and the institution reasons are back.        ║
-- ║                                                                            ║
-- ║  Finding: L22-02 (OmniCoin narrative) — extended scope after the product   ║
-- ║  owner confirmed "OmniCoins são usadas SOMENTE em desafios".               ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ───────────────────────────────────────────────────────────────────────────
-- 1. Delete the accidentally-credited rows and reconcile wallet balances.
-- ───────────────────────────────────────────────────────────────────────────

-- Capture affected user_ids so we can recompute balance_coins AFTER deletion.
CREATE TEMP TABLE _l22_02_affected_users ON COMMIT DROP AS
  SELECT DISTINCT user_id
  FROM public.coin_ledger
  WHERE reason IN (
    'referral_referrer_reward',
    'referral_referred_reward',
    'sponsorship_payout',
    'referral_bonus',
    'referral_new_user',
    'redemption_payout',
    'custody_reversal',
    'championship_reward'
  );

DELETE FROM public.coin_ledger
WHERE reason IN (
  'referral_referrer_reward',
  'referral_referred_reward',
  'sponsorship_payout',
  'referral_bonus',
  'referral_new_user',
  'redemption_payout',
  'custody_reversal',
  'championship_reward'
);

-- Recompute balance_coins strictly from the (now-cleaned) ledger.  The ledger
-- is the source of truth; wallets.balance_coins is a materialised cache.
UPDATE public.wallets w
   SET balance_coins = COALESCE(agg.total, 0),
       updated_at    = now()
  FROM (
    SELECT user_id, SUM(delta_coins)::int AS total
      FROM public.coin_ledger
     WHERE user_id IN (SELECT user_id FROM _l22_02_affected_users)
     GROUP BY user_id
  ) agg
 WHERE w.user_id = agg.user_id;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. Neutralise fn_activate_referral — no more coin credit / wallet bump.
-- ───────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_activate_referral(
  p_code text
) RETURNS public.referrals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_row  public.referrals%ROWTYPE;
  v_now  timestamptz := now();
BEGIN
  IF v_uid IS NULL AND current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  IF p_code IS NULL OR length(p_code) NOT BETWEEN 6 AND 16 THEN
    RAISE EXCEPTION 'invalid_code' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_row
    FROM public.referrals
   WHERE referral_code = upper(p_code)
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'referral_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'referral_not_pending: status=%', v_row.status
      USING ERRCODE = 'P0001';
  END IF;

  IF v_row.expires_at < v_now THEN
    UPDATE public.referrals
       SET status = 'expired', expired_at = v_now
     WHERE id = v_row.id
     RETURNING * INTO v_row;
    RAISE EXCEPTION 'referral_expired' USING ERRCODE = 'P0001';
  END IF;

  IF v_row.referrer_user_id = v_uid THEN
    RAISE EXCEPTION 'self_referral_blocked' USING ERRCODE = 'P0001';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.referrals
     WHERE referred_user_id = v_uid AND status = 'activated'
  ) THEN
    RAISE EXCEPTION 'already_activated_referral' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.referrals
     SET status           = 'activated',
         referred_user_id = v_uid,
         activated_at     = v_now
   WHERE id = v_row.id
   RETURNING * INTO v_row;

  -- Intentionally NO coin_ledger insert and NO wallets.balance_coins bump.
  -- OmniCoins are earned only inside challenges; a referral activation
  -- updates the viral-growth tracking record and nothing else.

  RETURN v_row;
END
$$;

COMMENT ON FUNCTION public.fn_activate_referral(text) IS
  'L15-02 (corrected by L22-02): flips a pending referral to ''activated''. '
  'Does NOT credit OmniCoins — OmniCoins are earned only in challenges. '
  'Raises P0001 for NOT_FOUND / EXPIRED / SELF / ALREADY_ACTIVATED.';

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Drop fn_sponsorship_distribute_monthly_coins entirely.
-- ───────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS public.fn_sponsorship_distribute_monthly_coins(UUID, DATE);

-- ───────────────────────────────────────────────────────────────────────────
-- 4. Drop the now-obsolete coin budget / reward columns.
-- ───────────────────────────────────────────────────────────────────────────

-- Sponsorship coin budget columns + their CHECKs.
ALTER TABLE public.sponsorships
  DROP CONSTRAINT IF EXISTS sponsorships_monthly_coins_nonneg,
  DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_total_nonneg,
  DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_used_nonneg,
  DROP CONSTRAINT IF EXISTS sponsorships_coin_budget_used_within;

ALTER TABLE public.sponsorships
  DROP COLUMN IF EXISTS monthly_coins_per_athlete,
  DROP COLUMN IF EXISTS coin_budget_total,
  DROP COLUMN IF EXISTS coin_budget_used;

-- sponsorship_athletes.last_distributed_period is now meaningless; keep the
-- column for historical rows but drop any index that only made sense under
-- the coin-distribution model.  (There is no index on it, so nothing to drop.)

-- Referral coin columns.
ALTER TABLE public.referrals
  DROP COLUMN IF EXISTS reward_referrer_coins,
  DROP COLUMN IF EXISTS reward_referred_coins;

ALTER TABLE public.referral_rewards_config
  DROP COLUMN IF EXISTS reward_referrer_coins,
  DROP COLUMN IF EXISTS reward_referred_coins;

-- ───────────────────────────────────────────────────────────────────────────
-- 5. Restore the canonical coin_ledger_reason_check.
-- ───────────────────────────────────────────────────────────────────────────
--
-- Canonical list = L03-13 baseline
--   + 'challenge_withdrawal_refund' (used by challenge-withdraw edge
--     function but missing from L03-13),
--   + historical challenge / cross-assessoria reasons that earlier
--     migrations introduced and active code still relies on
--     (challenge_team_won, challenge_team_completed,
--      challenge_prize_pending, challenge_prize_cleared,
--      cross_assessoria_pending, cross_assessoria_cleared,
--      cross_assessoria_burned),
--   + 'admin_correction' (ops tool, peer of admin_adjustment), and
--   + 'batch_credit' (fallback reason hard-coded in
--     fn_increment_wallets_batch when a caller omits reason).
--
-- Every reason in this list is either tied to a challenge event or is an
-- operational correction tool. User-facing non-challenge payouts (referral
-- bonuses, sponsorship stipends, welcome/onboarding/streak bonuses, etc.)
-- remain DISALLOWED — OmniCoins are earned only inside challenges.
--
-- Adding any new reason requires a registry-backed audit finding showing
-- that the new emission path is challenge-bound (or a peer operational
-- correction) and keeping this CHECK and
-- `tools/audit/check-ledger-reason-safety.ts` in lockstep.

ALTER TABLE public.coin_ledger DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;
ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (
    reason = ANY (ARRAY[
      -- challenge-bound user payouts
      'session_completed',
      'challenge_one_vs_one_completed',
      'challenge_one_vs_one_won',
      'challenge_group_completed',
      'challenge_team_completed',
      'challenge_team_won',
      'challenge_entry_fee',
      'challenge_pool_won',
      'challenge_entry_refund',
      'challenge_withdrawal_refund',
      'challenge_prize_pending',
      'challenge_prize_cleared',
      'cross_assessoria_pending',
      'cross_assessoria_cleared',
      'cross_assessoria_burned',
      -- streak / PR / badge / mission (challenge-adjacent personal records)
      'streak_weekly',
      'streak_monthly',
      'pr_distance',
      'pr_pace',
      'badge_reward',
      'mission_reward',
      -- cosmetic spend (user burns coins on skins; no user payout)
      'cosmetic_purchase',
      -- institutional token lifecycle (B2B; predates Batch J)
      'institution_token_issue',
      'institution_token_burn',
      'institution_switch_burn',
      'institution_token_reverse_emission',
      'institution_token_reverse_burn',
      -- operational correction tools
      'admin_adjustment',
      'admin_correction',
      'batch_credit'
    ])
  );

COMMENT ON CONSTRAINT coin_ledger_reason_check ON public.coin_ledger IS
  'L22-02: authoritative reason enumeration. OmniCoin credit is challenge-bound; '
  'referral / sponsorship / onboarding / welcome / signup rewards are NOT '
  'accepted. Adding a new reason requires a registry-backed audit finding '
  'showing the emission path is challenge-bound or a peer operational tool, '
  'and keeping tools/audit/check-ledger-reason-safety.ts in lockstep.';

-- ───────────────────────────────────────────────────────────────────────────
-- 6. Self-test.
-- ───────────────────────────────────────────────────────────────────────────

DO $self_test$
DECLARE
  v_def text;
BEGIN
  -- Constraint is still there.
  PERFORM 1 FROM pg_constraint WHERE conname = 'coin_ledger_reason_check';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: coin_ledger_reason_check missing';
  END IF;

  SELECT pg_get_constraintdef(oid) INTO v_def
    FROM pg_constraint
   WHERE conname = 'coin_ledger_reason_check';

  -- Forbidden reasons are gone.
  IF v_def ~ '\m(referral_referrer_reward|referral_referred_reward|sponsorship_payout|referral_bonus|referral_new_user|redemption_payout|custody_reversal|championship_reward)\M' THEN
    RAISE EXCEPTION 'L22-02 self-test: forbidden non-challenge reason still present in CHECK: %', v_def;
  END IF;

  -- Challenge reasons are present.
  IF v_def !~ '\mchallenge_entry_fee\M' OR v_def !~ '\mchallenge_entry_refund\M' OR v_def !~ '\mchallenge_withdrawal_refund\M' THEN
    RAISE EXCEPTION 'L22-02 self-test: challenge reasons missing from CHECK: %', v_def;
  END IF;

  -- Institution reasons restored.
  IF v_def !~ '\minstitution_token_issue\M' OR v_def !~ '\minstitution_token_burn\M' OR v_def !~ '\minstitution_switch_burn\M' THEN
    RAISE EXCEPTION 'L22-02 self-test: institution token reasons missing from CHECK: %', v_def;
  END IF;

  -- Coin budget columns gone.
  PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'sponsorships' AND column_name = 'monthly_coins_per_athlete';
  IF FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: sponsorships.monthly_coins_per_athlete should have been dropped';
  END IF;

  PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'sponsorships' AND column_name = 'coin_budget_total';
  IF FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: sponsorships.coin_budget_total should have been dropped';
  END IF;

  PERFORM 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'referrals' AND column_name = 'reward_referrer_coins';
  IF FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: referrals.reward_referrer_coins should have been dropped';
  END IF;

  -- Distribution function gone.
  PERFORM 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_sponsorship_distribute_monthly_coins';
  IF FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: fn_sponsorship_distribute_monthly_coins should have been dropped';
  END IF;

  -- fn_activate_referral exists but does NOT touch coin_ledger.
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'fn_activate_referral';
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'L22-02 self-test: fn_activate_referral missing';
  END IF;
  IF v_def ~* 'insert into public\.coin_ledger' OR v_def ~* 'update public\.wallets[^;]*balance_coins' THEN
    RAISE EXCEPTION 'L22-02 self-test: fn_activate_referral still credits coins / bumps wallet';
  END IF;

  -- No stale forbidden ledger rows.
  PERFORM 1 FROM public.coin_ledger
   WHERE reason IN (
     'referral_referrer_reward','referral_referred_reward','sponsorship_payout',
     'referral_bonus','referral_new_user','redemption_payout','custody_reversal',
     'championship_reward'
   );
  IF FOUND THEN
    RAISE EXCEPTION 'L22-02 self-test: non-challenge ledger rows still present';
  END IF;

  RAISE NOTICE 'L22-02 self-test OK — OmniCoins are challenge-only again.';
END
$self_test$;

COMMIT;
