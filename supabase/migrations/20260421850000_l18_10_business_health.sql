-- L18-10 — `fn_rpc_latency_summary` business-health helper.
--
-- Backs the `/api/internal/business-health` endpoint. The endpoint
-- already issues table reads against `clearing_settlements`,
-- `custody_withdraws`, `custody_deposits`, `billing_webhook_deliveries`;
-- the only missing piece is a stable RPC over `pg_stat_statements`
-- (added in L19-07) that returns per-RPC latency percentiles for a
-- short rolling window.
--
-- We deliberately avoid time-series storage. `pg_stat_statements`
-- already keeps per-statement aggregates (calls, total_exec_time,
-- mean_exec_time, stddev_exec_time) since the last reset. We
-- approximate the percentiles from those four numbers:
--
--   p50  ≈ mean
--   p95  ≈ mean + 1.645 × stddev
--   p99  ≈ mean + 2.326 × stddev
--
-- This is a normal-distribution approximation and ONLY useful as a
-- coarse SLO indicator (the kind of thing an SRE wants to see go
-- red on the dashboard). It is NOT precise enough to feed into a
-- reliability SLA report — for that, the OLAP staging table
-- `analytics.rpc_latency_samples` (L08-06) holds raw histograms.
--
-- The `p_window_minutes` parameter is intentionally accepted but
-- not used — `pg_stat_statements` is a since-reset rolling window
-- without per-bucket history. Keeping the parameter in the
-- signature lets the API layer evolve the implementation later
-- (e.g. read from the OLAP histogram) without changing the contract.
--
-- Self-test asserts the function exists with the expected security
-- posture; correctness of the percentiles is asserted by the API
-- handler's integration test (covered separately).

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_rpc_latency_summary(
  p_rpc_name text,
  p_window_minutes int DEFAULT 5
)
RETURNS TABLE (
  rpc_name text,
  samples bigint,
  p50_ms double precision,
  p95_ms double precision,
  p99_ms double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_calls bigint;
  v_mean double precision;
  v_stddev double precision;
BEGIN
  IF p_rpc_name IS NULL OR p_rpc_name !~ '^[a-z_][a-z0-9_]*$' THEN
    RAISE EXCEPTION
      'fn_rpc_latency_summary: invalid p_rpc_name (expected snake_case)'
      USING ERRCODE = 'P0001';
  END IF;

  -- Sum across every (db, user, queryid) row that mentions the
  -- function — `pg_stat_statements` rows are partitioned by user,
  -- DB and prepared-statement plan, so a single RPC can have
  -- multiple stat rows.
  SELECT
    COALESCE(SUM(s.calls), 0),
    COALESCE(
      SUM(s.calls * s.mean_exec_time) / NULLIF(SUM(s.calls), 0),
      0
    ),
    COALESCE(
      SUM(s.calls * s.stddev_exec_time) / NULLIF(SUM(s.calls), 0),
      0
    )
  INTO v_calls, v_mean, v_stddev
  FROM pg_stat_statements s
  WHERE s.query ILIKE '%' || p_rpc_name || '%';

  rpc_name := p_rpc_name;
  samples := v_calls;
  p50_ms := v_mean;
  p95_ms := v_mean + 1.645 * v_stddev;
  p99_ms := v_mean + 2.326 * v_stddev;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION public.fn_rpc_latency_summary(text, int) IS
  'L18-10 — coarse latency percentiles for a named RPC, derived ' ||
  'from pg_stat_statements. Used by /api/internal/business-health.';

REVOKE ALL ON FUNCTION public.fn_rpc_latency_summary(text, int) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_rpc_latency_summary(text, int) FROM anon;
REVOKE ALL ON FUNCTION public.fn_rpc_latency_summary(text, int) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_rpc_latency_summary(text, int) TO service_role;

DO $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_rpc_latency_summary'
      AND p.prosecdef = true
  ) INTO v_exists;
  IF NOT v_exists THEN
    RAISE EXCEPTION
      'L18-10 self-test: fn_rpc_latency_summary missing or not SECURITY DEFINER';
  END IF;

  RAISE NOTICE 'L18-10 self-test: OK';
END
$$;

COMMIT;
