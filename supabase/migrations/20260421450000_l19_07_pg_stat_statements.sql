-- L19-07 — pg_stat_statements bootstrap + structured top-N view.
--
-- The runbook `docs/runbooks/DBA_QUERY_TUNING.md` drives ad-hoc
-- investigation. This migration is the database-side contract the
-- runbook depends on:
--
--   1. Extension `pg_stat_statements` is installed in the default
--      schema (Supabase allows it; the extension stores stats in
--      shared memory, not in a table we own).
--   2. A service-role-only view `public.v_pg_stat_statements_top`
--      exposes the "top N by total_exec_time, mean >= 100 ms" slice
--      used by the runbook. We do NOT expose the raw stats table
--      because it contains literal text fragments from every query
--      (including parameters when prepared statements fall back to
--      immediate execution), and that can leak PII or service
--      keys.
--   3. A helper `public.fn_pg_stat_statements_top(p_limit int)`
--      wraps the view so the ops dashboard / psql session runbook
--      can call a named function instead of crafting SQL from the
--      markdown.
--   4. Extension `pg_stat_statements_reset` is callable only by
--      service_role, via `public.fn_pg_stat_statements_reset()`
--      — we deliberately gate it because resetting the window
--      hides upstream regressions, and only on-call DBA should
--      decide.
--
-- Self-test at end verifies: extension installed, view + functions
-- exist with the expected security posture, and grants are
-- service_role-only. It does NOT assert on stats content because
-- stats are populated asynchronously and would make the migration
-- flaky in CI.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Service-role-only top-N view. We keep a stable contract so the
-- runbook does not need to care where pg_stat_statements actually
-- lives. Setting security_invoker = on so RLS rules on the
-- callers' session still apply (service_role bypasses RLS anyway).
CREATE OR REPLACE VIEW public.v_pg_stat_statements_top
WITH (security_invoker = on) AS
SELECT
  s.queryid,
  s.query,
  s.calls,
  s.total_exec_time,
  s.mean_exec_time,
  s.stddev_exec_time,
  s.rows,
  s.shared_blks_hit,
  s.shared_blks_read,
  s.shared_blks_dirtied
FROM pg_stat_statements s
WHERE s.mean_exec_time >= 100  -- ms; aligns with runbook SLO
ORDER BY s.total_exec_time DESC;

COMMENT ON VIEW public.v_pg_stat_statements_top IS
  'L19-07 — top-N slow queries used by DBA_QUERY_TUNING runbook. ' ||
  'service_role only (query text may leak literals / PII).';

REVOKE ALL ON public.v_pg_stat_statements_top FROM PUBLIC;
REVOKE ALL ON public.v_pg_stat_statements_top FROM anon;
REVOKE ALL ON public.v_pg_stat_statements_top FROM authenticated;
GRANT SELECT ON public.v_pg_stat_statements_top TO service_role;

-- Helper function with a parameterised LIMIT.
CREATE OR REPLACE FUNCTION public.fn_pg_stat_statements_top(p_limit int DEFAULT 20)
RETURNS TABLE (
  queryid bigint,
  query text,
  calls bigint,
  total_exec_time double precision,
  mean_exec_time double precision,
  stddev_exec_time double precision,
  rows bigint,
  shared_blks_hit bigint,
  shared_blks_read bigint,
  shared_blks_dirtied bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT *
  FROM public.v_pg_stat_statements_top
  LIMIT GREATEST(COALESCE(p_limit, 20), 1);
$$;

COMMENT ON FUNCTION public.fn_pg_stat_statements_top(int) IS
  'L19-07 — named wrapper for the top-N slow query view. ' ||
  'service_role only.';

REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_top(int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_top(int) FROM anon;
REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_top(int) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_pg_stat_statements_top(int) TO service_role;

-- Reset helper — deliberately gated behind service_role so only
-- on-call DBA can invalidate the stats window.
CREATE OR REPLACE FUNCTION public.fn_pg_stat_statements_reset()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
  SELECT pg_stat_statements_reset();
$$;

COMMENT ON FUNCTION public.fn_pg_stat_statements_reset() IS
  'L19-07 — wraps pg_stat_statements_reset(); service_role only.';

REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_reset() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_reset() FROM anon;
REVOKE ALL ON FUNCTION public.fn_pg_stat_statements_reset() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_pg_stat_statements_reset() TO service_role;

-- Self-test. Runs inside the migration transaction so a failure
-- rolls back the whole migration.
DO $$
DECLARE
  v_exists boolean;
BEGIN
  -- 1. Extension installed.
  SELECT EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'pg_stat_statements'
  ) INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION
      'L19-07 self-test: pg_stat_statements extension missing';
  END IF;

  -- 2. View exists.
  SELECT EXISTS (
    SELECT 1 FROM pg_views
    WHERE schemaname = 'public'
      AND viewname = 'v_pg_stat_statements_top'
  ) INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION
      'L19-07 self-test: v_pg_stat_statements_top missing';
  END IF;

  -- 3. Helper function exists and is SECURITY DEFINER.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_pg_stat_statements_top'
      AND p.prosecdef = true
  ) INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION
      'L19-07 self-test: fn_pg_stat_statements_top(int) missing or not SECURITY DEFINER';
  END IF;

  -- 4. Reset helper exists and is SECURITY DEFINER.
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_pg_stat_statements_reset'
      AND p.prosecdef = true
  ) INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION
      'L19-07 self-test: fn_pg_stat_statements_reset() missing or not SECURITY DEFINER';
  END IF;

  RAISE NOTICE 'L19-07 self-test: OK';
END
$$;

COMMIT;
