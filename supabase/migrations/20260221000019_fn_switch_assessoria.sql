-- ============================================================================
-- Omni Runner — RPC fn_switch_assessoria: burn + switch + membership
-- Date: 2026-02-22
-- Sprint: 17.5.2
-- Origin: DECISAO 038 / Phase 18 (Assessoria Ecosystem Core)
-- ============================================================================
-- Atomic operation:
--   1. Burn remaining coins (ledger + wallet)
--   2. Remove old atleta membership
--   3. Create new atleta membership
--   4. Update profiles.active_coaching_group_id
--
-- Idempotent: calling twice with the same group_id is a no-op.
-- ============================================================================

BEGIN;

-- ── 1. Expand coin_ledger reason CHECK to include institution_switch_burn ────

ALTER TABLE public.coin_ledger
  DROP CONSTRAINT IF EXISTS coin_ledger_reason_check;

ALTER TABLE public.coin_ledger
  ADD CONSTRAINT coin_ledger_reason_check CHECK (reason IN (
    'session_completed','challenge_one_vs_one_completed','challenge_one_vs_one_won',
    'challenge_group_completed','streak_weekly','streak_monthly',
    'pr_distance','pr_pace','challenge_entry_fee','challenge_pool_won',
    'challenge_entry_refund','cosmetic_purchase','admin_adjustment',
    'badge_reward','mission_reward',
    'institution_switch_burn'
  ));

-- ── 2. RPC: fn_switch_assessoria ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_switch_assessoria(p_new_group_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_uid          UUID;
  v_balance      INTEGER;
  v_old_group_id UUID;
  v_display_name TEXT;
  v_now_ms       BIGINT;
BEGIN
  -- Auth guard
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- Verify target group exists
  IF NOT EXISTS (SELECT 1 FROM public.coaching_groups WHERE id = p_new_group_id) THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;

  -- Current state
  SELECT active_coaching_group_id, display_name
    INTO v_old_group_id, v_display_name
    FROM public.profiles
    WHERE id = v_uid;

  -- Idempotency: already in this group
  IF v_old_group_id IS NOT DISTINCT FROM p_new_group_id THEN
    RETURN jsonb_build_object('status', 'already_member', 'burned', 0);
  END IF;

  v_now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  -- Burn remaining coins
  SELECT COALESCE(balance_coins, 0) INTO v_balance
    FROM public.wallets
    WHERE user_id = v_uid;
  v_balance := COALESCE(v_balance, 0);

  IF v_balance > 0 THEN
    INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
    VALUES (v_uid, -v_balance, 'institution_switch_burn', p_new_group_id::TEXT, v_now_ms);

    PERFORM public.increment_wallet_balance(v_uid, -v_balance);
  END IF;

  -- Remove old atleta membership (respects partial unique index)
  DELETE FROM public.coaching_members
    WHERE user_id = v_uid AND role = 'atleta';

  -- Create new membership (ON CONFLICT handles edge case where user
  -- already exists in the group with a staff role)
  INSERT INTO public.coaching_members (user_id, group_id, display_name, role, joined_at_ms)
  VALUES (v_uid, p_new_group_id, COALESCE(v_display_name, 'Runner'), 'atleta', v_now_ms)
  ON CONFLICT (group_id, user_id)
  DO UPDATE SET role = 'atleta', joined_at_ms = EXCLUDED.joined_at_ms;

  -- Update active group
  UPDATE public.profiles
    SET active_coaching_group_id = p_new_group_id, updated_at = now()
    WHERE id = v_uid;

  RETURN jsonb_build_object('status', 'switched', 'burned', v_balance);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
