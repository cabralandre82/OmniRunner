-- ============================================================================
-- SECURITY_HARDENING.sql
--
-- Harden all SECURITY DEFINER functions:
--   1. SET search_path = public, pg_temp (prevent search_path hijack)
--   2. REVOKE EXECUTE from anon/authenticated/PUBLIC
--   3. GRANT EXECUTE only to service_role (Edge Functions / backend)
--
-- For functions that must be callable by authenticated users (RPCs called from
-- app/portal), we grant to authenticated but still set search_path.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. KPI compute functions (service_role ONLY)
--    These are called exclusively by the Edge Function cron job.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.compute_coaching_kpis_daily(date)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_kpis_daily(date) TO service_role;

ALTER FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) TO service_role;

ALTER FUNCTION public.compute_coaching_alerts_daily(date)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_alerts_daily(date) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Custody / Clearing / Swap functions (service_role ONLY)
--    Called by portal API routes via service client, not directly by users.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.confirm_custody_deposit(uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.confirm_custody_deposit(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.confirm_custody_deposit(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.confirm_custody_deposit(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_custody_deposit(uuid) TO service_role;

ALTER FUNCTION public.settle_clearing(uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.settle_clearing(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.settle_clearing(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.settle_clearing(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.settle_clearing(uuid) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Platform admin functions (service_role ONLY)
--    fn_platform_approve/reject/suspend are called from portal admin API.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.fn_platform_approve_assessoria(uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_platform_approve_assessoria(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_platform_approve_assessoria(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_platform_approve_assessoria(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_platform_approve_assessoria(uuid) TO authenticated;

ALTER FUNCTION public.fn_platform_reject_assessoria(uuid, text)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_platform_reject_assessoria(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_platform_reject_assessoria(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_platform_reject_assessoria(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_platform_reject_assessoria(uuid, text) TO authenticated;

ALTER FUNCTION public.fn_platform_suspend_assessoria(uuid, text)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_platform_suspend_assessoria(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_platform_suspend_assessoria(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_platform_suspend_assessoria(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_platform_suspend_assessoria(uuid, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. User-facing RPCs (authenticated + service_role)
--    Called directly from app via supabase.rpc(). Need authenticated access
--    but must still have safe search_path.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.fn_create_assessoria(text, text)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_create_assessoria(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_create_assessoria(text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_create_assessoria(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_create_assessoria(text, text) TO service_role;

ALTER FUNCTION public.fn_request_join(uuid, text)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_request_join(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_request_join(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_request_join(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_request_join(uuid, text) TO service_role;

ALTER FUNCTION public.fn_approve_join_request(uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_approve_join_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_approve_join_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_approve_join_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_approve_join_request(uuid) TO service_role;

ALTER FUNCTION public.fn_reject_join_request(uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_reject_join_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_reject_join_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_reject_join_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_reject_join_request(uuid) TO service_role;

ALTER FUNCTION public.fn_remove_member(uuid, uuid)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.fn_remove_member(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_remove_member(uuid, uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_remove_member(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_remove_member(uuid, uuid) TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. Helper / RLS-bypass functions (authenticated — used in policies)
--    These are STABLE helpers used inside RLS policy definitions.
--    They must be callable by authenticated to make policies work.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.staff_group_member_ids()
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.staff_group_member_ids() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.staff_group_member_ids() FROM anon;
GRANT EXECUTE ON FUNCTION public.staff_group_member_ids() TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_group_member_ids() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. Internal/system functions (service_role ONLY)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER FUNCTION public.compute_leaderboard_global_weekly(text, bigint, bigint)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.compute_leaderboard_global_weekly(text, bigint, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_leaderboard_global_weekly(text, bigint, bigint) FROM anon;
REVOKE ALL ON FUNCTION public.compute_leaderboard_global_weekly(text, bigint, bigint) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_leaderboard_global_weekly(text, bigint, bigint) TO service_role;

ALTER FUNCTION public.increment_profile_progress(uuid, integer, double precision, bigint)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.increment_profile_progress(uuid, integer, double precision, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.increment_profile_progress(uuid, integer, double precision, bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_profile_progress(uuid, integer, double precision, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_profile_progress(uuid, integer, double precision, bigint) TO authenticated;

ALTER FUNCTION public.increment_wallet_balance(uuid, integer)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.increment_wallet_balance(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.increment_wallet_balance(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_wallet_balance(uuid, integer) TO service_role;

ALTER FUNCTION public.increment_rate_limit(uuid, text, integer)
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.increment_rate_limit(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.increment_rate_limit(uuid, text, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_rate_limit(uuid, text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.increment_rate_limit(uuid, text, integer) TO service_role;

ALTER FUNCTION public.cleanup_rate_limits()
  SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM anon;
REVOKE ALL ON FUNCTION public.cleanup_rate_limits() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_rate_limits() TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. Fix coaching_members_role_check constraint (found during audit)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_members
  DROP CONSTRAINT IF EXISTS coaching_members_role_check;

ALTER TABLE public.coaching_members
  ADD CONSTRAINT coaching_members_role_check
  CHECK (role IN (
    'admin_master', 'coach', 'assistant', 'athlete',
    'coach', 'assistant', 'athlete'
  ));
