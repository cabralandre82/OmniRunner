-- ============================================================================
-- P1-SEC-01: Apply REVOKE/GRANT to legacy coaching RPCs.
-- These functions already have SET search_path = public, pg_temp (from
-- 20260303300000_fix_coaching_roles.sql) but were never locked down with
-- REVOKE ALL FROM PUBLIC / GRANT TO authenticated.
-- ============================================================================

-- fn_create_assessoria(text, text)
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_create_assessoria(text, text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_create_assessoria(text, text) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_create_assessoria(text, text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_create_assessoria(text, text) TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_create_assessoria(text, text) not found, skipping';
END $$;

-- fn_request_join(uuid, text)
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_request_join(uuid, text) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_request_join(uuid, text) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_request_join(uuid, text) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_request_join(uuid, text) TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_request_join(uuid, text) not found, skipping';
END $$;

-- fn_approve_join_request(uuid)
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_approve_join_request(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_approve_join_request(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_approve_join_request(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_approve_join_request(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_approve_join_request(uuid) not found, skipping';
END $$;

-- fn_reject_join_request(uuid)
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_reject_join_request(uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_reject_join_request(uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_reject_join_request(uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_reject_join_request(uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_reject_join_request(uuid) not found, skipping';
END $$;

-- fn_remove_member(uuid, uuid)
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.fn_remove_member(uuid, uuid) FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.fn_remove_member(uuid, uuid) FROM anon;
  GRANT EXECUTE ON FUNCTION public.fn_remove_member(uuid, uuid) TO authenticated;
  GRANT EXECUTE ON FUNCTION public.fn_remove_member(uuid, uuid) TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_remove_member(uuid, uuid) not found, skipping';
END $$;

-- staff_group_member_ids() — RLS helper, used internally
DO $$ BEGIN
  REVOKE ALL ON FUNCTION public.staff_group_member_ids() FROM PUBLIC;
  REVOKE ALL ON FUNCTION public.staff_group_member_ids() FROM anon;
  GRANT EXECUTE ON FUNCTION public.staff_group_member_ids() TO authenticated;
  GRANT EXECUTE ON FUNCTION public.staff_group_member_ids() TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'staff_group_member_ids() not found, skipping';
END $$;
