-- Harden remaining SECURITY DEFINER functions that were missed in earlier passes.
-- Each block uses exception handling so the migration succeeds even if a function
-- does not exist in the target database.

-- fn_friends_activity_feed(int, int)
DO $$ BEGIN
  ALTER FUNCTION public.fn_friends_activity_feed SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_friends_activity_feed FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.fn_friends_activity_feed TO authenticated;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_friends_activity_feed not found, skipping';
END $$;

-- execute_withdrawal(uuid)
DO $$ BEGIN
  ALTER FUNCTION public.execute_withdrawal SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.execute_withdrawal FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.execute_withdrawal TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'execute_withdrawal not found, skipping';
END $$;

-- custody_commit_coins(uuid, integer)
DO $$ BEGIN
  ALTER FUNCTION public.custody_commit_coins SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.custody_commit_coins FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.custody_commit_coins TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'custody_commit_coins not found, skipping';
END $$;

-- custody_release_committed(uuid, integer)
DO $$ BEGIN
  ALTER FUNCTION public.custody_release_committed SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.custody_release_committed FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.custody_release_committed TO service_role;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'custody_release_committed not found, skipping';
END $$;

-- fn_platform_get_assessoria_detail
DO $$ BEGIN
  ALTER FUNCTION public.fn_platform_get_assessoria_detail SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_platform_get_assessoria_detail FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.fn_platform_get_assessoria_detail TO authenticated;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_platform_get_assessoria_detail not found, skipping';
END $$;

-- fn_platform_list_assessorias
DO $$ BEGIN
  ALTER FUNCTION public.fn_platform_list_assessorias SET search_path = public, pg_temp;
  REVOKE ALL ON FUNCTION public.fn_platform_list_assessorias FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.fn_platform_list_assessorias TO authenticated;
EXCEPTION WHEN undefined_function THEN
  RAISE NOTICE 'fn_platform_list_assessorias not found, skipping';
END $$;
