-- ============================================================================
-- Omni Runner — Pending coins for cross-assessoria challenge prizes
-- Date: 2026-02-22
-- Sprint: 17.7.0
-- Origin: DECISAO 038 / Phase 18 — Module D (Cross-Institution Challenges)
-- ============================================================================
-- Same assessoria: prize goes directly to balance_coins (existing behavior)
-- Cross assessoria: prize goes to pending_coins, released after clearing
-- ============================================================================

BEGIN;

-- ── 1. Add pending_coins to wallets ──────────────────────────────────────────

ALTER TABLE public.wallets
  ADD COLUMN IF NOT EXISTS pending_coins INTEGER NOT NULL DEFAULT 0
    CHECK (pending_coins >= 0);

-- ── 2. Expand coin_ledger reasons ────────────────────────────────────────────

ALTER TABLE public.coin_ledger
  DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;

ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (reason IN (
    'session_completed','challenge_one_vs_one_completed','challenge_one_vs_one_won',
    'challenge_group_completed','streak_weekly','streak_monthly',
    'pr_distance','pr_pace','challenge_entry_fee','challenge_pool_won',
    'challenge_entry_refund','cosmetic_purchase','admin_adjustment',
    'badge_reward','mission_reward',
    'institution_switch_burn',
    'institution_token_issue',
    'institution_token_burn',
    'challenge_prize_pending',
    'challenge_prize_cleared'
  ));

-- ── 3. RPC: increment_wallet_pending ─────────────────────────────────────────
-- Atomically adjusts pending_coins. Used by settle-challenge for cross prizes.

CREATE OR REPLACE FUNCTION public.increment_wallet_pending(
  p_user_id UUID,
  p_delta   INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.wallets
  SET
    pending_coins = pending_coins + p_delta,
    updated_at    = now()
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.wallets (user_id, pending_coins)
    VALUES (p_user_id, GREATEST(0, p_delta));
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 4. RPC: release_pending_to_balance ───────────────────────────────────────
-- Moves a specific amount from pending to balance. Used by clearing system.

CREATE OR REPLACE FUNCTION public.release_pending_to_balance(
  p_user_id UUID,
  p_amount  INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.wallets
  SET
    pending_coins         = pending_coins - p_amount,
    balance_coins         = balance_coins + p_amount,
    lifetime_earned_coins = lifetime_earned_coins + p_amount,
    updated_at            = now()
  WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
