-- ============================================================================
-- Omni Runner — Token intent support: ledger reasons + inventory RPCs
-- Date: 2026-02-22
-- Sprint: 17.6.1
-- Origin: DECISAO 038 / Phase 18 — Module C (Institutional Token Economy)
-- ============================================================================

-- ── 1. Expand coin_ledger reasons ────────────────────────────────────────────

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
    'institution_token_burn'
  ));

-- ── 2. RPC: decrement_token_inventory ────────────────────────────────────────
-- Atomically decrements available_tokens. CHECK (>= 0) prevents overdraft.

CREATE OR REPLACE FUNCTION public.decrement_token_inventory(
  p_group_id UUID,
  p_amount   INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.coaching_token_inventory
  SET
    available_tokens = available_tokens - p_amount,
    lifetime_issued  = lifetime_issued + p_amount,
    updated_at       = now()
  WHERE group_id = p_group_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'INVENTORY_NOT_FOUND';
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 3. RPC: increment_inventory_burned ───────────────────────────────────────
-- Tracks lifetime burned tokens in inventory.

CREATE OR REPLACE FUNCTION public.increment_inventory_burned(
  p_group_id UUID,
  p_amount   INTEGER
)
RETURNS VOID AS $$
BEGIN
  UPDATE public.coaching_token_inventory
  SET
    lifetime_burned = lifetime_burned + p_amount,
    updated_at      = now()
  WHERE group_id = p_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
