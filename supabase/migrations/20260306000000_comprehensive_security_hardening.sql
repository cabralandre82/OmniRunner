-- ============================================================================
-- Comprehensive SECURITY DEFINER hardening pass.
-- Ensures ALL known functions have:
--   1. SET search_path = public, pg_temp
--   2. REVOKE ALL FROM PUBLIC / anon
--   3. GRANT EXECUTE TO appropriate roles
--
-- Each block is wrapped in exception handling so migration succeeds even if
-- the function does not exist in this environment.
-- ============================================================================

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: generate_weekly_goal
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.generate_weekly_goal(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.generate_weekly_goal(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.generate_weekly_goal(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.generate_weekly_goal(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.generate_weekly_goal(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: evaluate_badges_retroactive
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.evaluate_badges_retroactive(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.evaluate_badges_retroactive(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.evaluate_badges_retroactive(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.evaluate_badges_retroactive(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Helper: recalculate_profile_progress
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.recalculate_profile_progress(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.recalculate_profile_progress(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.recalculate_profile_progress(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.recalculate_profile_progress(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Verification: eval_athlete_verification
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.eval_athlete_verification(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.eval_athlete_verification(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.eval_athlete_verification(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.eval_athlete_verification(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Verification: eval_verification_client_wrapper
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.eval_verification_client_wrapper() SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.eval_verification_client_wrapper() FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.eval_verification_client_wrapper() FROM anon;
  GRANT EXECUTE ON FUNCTION public.eval_verification_client_wrapper() TO authenticated;
  GRANT EXECUTE ON FUNCTION public.eval_verification_client_wrapper() TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Verification: is_user_verified
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.is_user_verified(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.is_user_verified(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.is_user_verified(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.is_user_verified(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.is_user_verified(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Verification monetization gates (triggers)
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.trg_verify_challenge_stake() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.trg_verify_token_intent_amount() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Social: complete_social_profile
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.complete_social_profile SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.complete_social_profile FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.complete_social_profile FROM anon;
  GRANT EXECUTE ON FUNCTION public.complete_social_profile TO authenticated;
  GRANT EXECUTE ON FUNCTION public.complete_social_profile TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Parks: trg_park_activity_refresh
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.trg_park_activity_refresh() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_refresh_park_leaderboard(text) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_refresh_park_leaderboard(text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_refresh_park_leaderboard(text) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_refresh_park_leaderboard(text) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Coaching feed
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_coaching_feed SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_coaching_feed FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_coaching_feed FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_coaching_feed TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_coaching_feed TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Leaderboard V2
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_snapshot_leaderboard_daily SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_daily FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_daily FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_snapshot_leaderboard_daily TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_snapshot_leaderboard_weekly SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_weekly FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_weekly FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_snapshot_leaderboard_weekly TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_snapshot_leaderboard_monthly SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_monthly FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_snapshot_leaderboard_monthly FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_snapshot_leaderboard_monthly TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Progression
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_calculate_progression SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_calculate_progression FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_calculate_progression FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_calculate_progression TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_evaluate_badges SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_evaluate_badges FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_evaluate_badges FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_evaluate_badges TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_update_level SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_update_level FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_update_level FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_update_level TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_check_streak_freeze SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_check_streak_freeze FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_check_streak_freeze FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_check_streak_freeze TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_submit_session SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_submit_session FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_submit_session FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_submit_session TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_submit_session TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Invite codes
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_lookup_group_by_invite_code(text) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_lookup_group_by_invite_code(text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_lookup_group_by_invite_code(text) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_lookup_group_by_invite_code(text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_lookup_group_by_invite_code(text) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_coaching_generate_invite_code(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_coaching_generate_invite_code(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_coaching_generate_invite_code(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_coaching_generate_invite_code(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_coaching_generate_invite_code(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Onboarding
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_staff_create_assessoria SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_staff_create_assessoria FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_staff_create_assessoria FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_staff_create_assessoria TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_staff_create_assessoria TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_staff_join_group SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_staff_join_group FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_staff_join_group FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_staff_join_group TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_staff_join_group TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Assessoria partnerships
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_list_my_partnerships SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_list_my_partnerships FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_list_my_partnerships FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_list_my_partnerships TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_list_my_partnerships TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_list_potential_partners SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_list_potential_partners FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_list_potential_partners FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_list_potential_partners TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_list_potential_partners TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_request_partnership SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_request_partnership FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_request_partnership FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_request_partnership TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_request_partnership TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_respond_partnership SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_respond_partnership FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_respond_partnership FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_respond_partnership TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_respond_partnership TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_cancel_partnership SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_cancel_partnership FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_cancel_partnership FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_cancel_partnership TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_cancel_partnership TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_partner_groups SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_partner_groups FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_partner_groups FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_partner_groups TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_partner_groups TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Challenge queue
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_expire_stale_queue_entries() SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_expire_stale_queue_entries() FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_expire_stale_queue_entries() FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_expire_stale_queue_entries() TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_challenge_skill_tier(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_challenge_skill_tier(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_challenge_skill_tier(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_challenge_skill_tier(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_challenge_skill_tier(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_matchmake_queue SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_matchmake_queue FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_matchmake_queue FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_matchmake_queue TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Challenge: entry_fee
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_challenge_lock_entry_fee(uuid, integer) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_challenge_lock_entry_fee(uuid, integer) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_challenge_lock_entry_fee(uuid, integer) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_challenge_lock_entry_fee(uuid, integer) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Trigger: auto-create athlete_verification on new profile
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.trg_auto_create_verification() SET search_path = public, pg_temp;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Strava import
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_import_execution SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_import_execution FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_import_execution FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_import_execution TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_backfill_strava_history SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_backfill_strava_history FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_backfill_strava_history FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_backfill_strava_history TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Financial RPCs — P1-9: REVOKE/GRANT hardening
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  ALTER FUNCTION public.fn_create_billing_purchase SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_create_billing_purchase FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_billing_purchase FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_billing_purchase TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_fulfill_purchase SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_fulfill_purchase FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_fulfill_purchase FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_fulfill_purchase TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.fn_charge_workout_credits SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_charge_workout_credits FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_charge_workout_credits FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_charge_workout_credits TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.reconcile_wallet(uuid) SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.reconcile_wallet(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.reconcile_wallet(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.reconcile_wallet(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.reconcile_all_wallets() SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.reconcile_all_wallets() FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.reconcile_all_wallets() FROM anon;
  GRANT EXECUTE ON FUNCTION public.reconcile_all_wallets() TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  ALTER FUNCTION public.archive_old_sessions SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.archive_old_sessions FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.archive_old_sessions FROM anon;
  GRANT EXECUTE ON FUNCTION public.archive_old_sessions TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Badge inventory
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_activate_badge_for_inventory FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_activate_badge_for_inventory FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_activate_badge_for_inventory TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_deactivate_badge_for_inventory FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_deactivate_badge_for_inventory FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_deactivate_badge_for_inventory TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_create_badge_sale_order FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_badge_sale_order FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_badge_sale_order TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Billing limits
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_check_purchase_limit FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_check_purchase_limit FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_check_purchase_limit TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_auto_topup_check FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_auto_topup_check FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_auto_topup_check TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Workout delivery (already has search_path, but add REVOKE/GRANT)
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_create_delivery_batch FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_delivery_batch FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_delivery_batch TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_create_delivery_batch TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_generate_delivery_items FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_generate_delivery_items FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_generate_delivery_items TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_generate_delivery_items TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_mark_item_published FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_mark_item_published FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_mark_item_published TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_mark_item_published TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_athlete_confirm_item FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_athlete_confirm_item FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_athlete_confirm_item TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_athlete_confirm_item TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Wearables
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_export_to_wearable FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_export_to_wearable FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_export_to_wearable TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_log_wearable_execution FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_log_wearable_execution FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_log_wearable_execution TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_log_wearable_execution TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Analytics / KPIs
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM anon;
  GRANT EXECUTE ON FUNCTION public.compute_coaching_kpis_daily(date) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM anon;
  GRANT EXECUTE ON FUNCTION public.compute_coaching_alerts_daily(date) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Announcements
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_create_announcement FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_announcement FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_announcement TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_create_announcement TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_mark_announcement_read FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_mark_announcement_read FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_mark_announcement_read TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_mark_announcement_read TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- CRM: fn_assign_tag
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_assign_tag FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_assign_tag FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_assign_tag TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_assign_tag TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Attendance
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_record_attendance FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_record_attendance FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_record_attendance TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_record_attendance TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_check_in_group_session FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_check_in_group_session FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_check_in_group_session TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_check_in_group_session TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Workout builder
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_save_workout_template FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_save_workout_template FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_save_workout_template TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_save_workout_template TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- TrainingPeaks (frozen but still needs hardening)
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_create_tp_sync_record FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_tp_sync_record FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_tp_sync_record TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_tp_mark_synced FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_tp_mark_synced FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_tp_mark_synced TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;

-- ────────────────────────────────────────────────────────────────────────────
-- Portal audit
-- ────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_get_user_id_by_email(text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_get_user_id_by_email(text) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_get_user_id_by_email(text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_get_user_id_by_email(text) TO service_role;
EXCEPTION WHEN undefined_function THEN NULL;
END $$;
