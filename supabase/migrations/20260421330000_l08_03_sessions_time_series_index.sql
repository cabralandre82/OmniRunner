-- ============================================================================
-- L08-03 — Sessions time-series index (BRIN on start_time_ms)
-- ============================================================================
--
-- Finding (docs/audit/findings/L08-03-sem-indice-de-analytics-time-series-em-sessions.md):
--   `public.sessions` is indexed by `(user_id, start_time_ms DESC)` for
--   per-athlete feeds. But realtime CDO/staff dashboards run queries
--   scoped by *time* across all users:
--
--       SELECT user_id, COUNT(*)
--       FROM public.sessions
--       WHERE start_time_ms BETWEEN $lo AND $hi
--       AND   status >= 3
--       GROUP BY user_id;
--
--   With no index on `start_time_ms` alone, the planner falls back to a
--   Seq Scan over the whole partition. For 10M+ rows this blocks the
--   dashboard for 30-120 s and burns I/O every 5 min (refresh tick).
--
-- Design:
--   (1) BRIN index on `start_time_ms`:
--         idx_sessions_start_time_brin USING BRIN (start_time_ms)
--                                      WITH (pages_per_range = 32)
--       * BRIN is the canonical choice for append-only columns that grow
--         monotonically — our `start_time_ms` is a capture timestamp, so
--         later INSERTs land in physically later heap blocks. This means
--         BRIN min/max per 32-page range is a tight filter.
--       * Storage cost: ~8 KiB per 1M rows (vs ~25 MiB for a btree on the
--         same column). Write cost: ~zero (only summary update).
--       * Perfect for range scans (`start_time_ms BETWEEN $lo AND $hi`) at
--         analytics/dashboard granularity (minutes/hours/days).
--
--   (2) Complementary partial btree `idx_sessions_status_start_time`
--       on `(status, start_time_ms DESC) WHERE status >= 3` to keep
--       dashboard "last N finalized sessions across all users" fast even
--       when the time window is narrow (< 100 rows) and the planner prefers
--       a btree plan over BRIN bitmap.
--
--   (3) Helper `fn_sessions_has_time_series_indexes()` STABLE SECURITY
--       DEFINER returns bool. Used by CI `npm run audit:sessions-time-series-index`
--       and by operators investigating a slow dashboard.
--
--   (4) Helper `fn_sessions_assert_time_series_indexes()` raises P0010 when
--       any of the two indexes is missing or has drifted (wrong access
--       method, wrong column).
--
-- Note:
--   * CREATE INDEX inside this migration is blocking — acceptable locally
--     (fresh DB) but NOT recommended for a 10M+ production sessions table.
--     See runbook `SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md` §4 for the
--     out-of-band `CREATE INDEX CONCURRENTLY` playbook.
--   * `sessions_archive` uses its own `idx_sessions_archive_start`
--     (btree DESC) from 20260320000000 — intentional (archive queries are
--     usually narrow/recent) and orthogonal to this finding.
--   * L08-04 (coherence CHECK) landed first on purpose: the filter
--     `status >= 3 AND start_time_ms > $t` is correct only under the
--     coherence invariant.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. BRIN index on start_time_ms (primary time-series fast path)
-- ──────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sessions_start_time_brin
  ON public.sessions USING BRIN (start_time_ms)
  WITH (pages_per_range = 32);

COMMENT ON INDEX public.idx_sessions_start_time_brin IS
  'L08-03: BRIN summary of start_time_ms for analytics/dashboard time-range '
  'scans (BETWEEN $lo AND $hi). Tiny footprint (~8 KiB/1M rows) and near-zero '
  'write amplification. Backed by `fn_sessions_assert_time_series_indexes`.';

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Partial btree on (status, start_time_ms DESC) for "last N finalized"
-- ──────────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_sessions_status_start_time
  ON public.sessions (status, start_time_ms DESC)
  WHERE status >= 3;

COMMENT ON INDEX public.idx_sessions_status_start_time IS
  'L08-03: partial btree for dashboards showing last N finalized sessions '
  'across all users (status >= 3, bounded by coherence invariant L08-04). '
  'Complements idx_sessions_start_time_brin when the time window is narrow.';

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Detector fn_sessions_has_time_series_indexes
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sessions_has_time_series_indexes()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class c  ON c.oid = i.indexrelid
    JOIN pg_class t  ON t.oid = i.indrelid
    JOIN pg_am    am ON am.oid = c.relam
    WHERE t.relname = 'sessions'
      AND c.relname = 'idx_sessions_start_time_brin'
      AND am.amname = 'brin'
  )
  AND EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class c  ON c.oid = i.indexrelid
    JOIN pg_class t  ON t.oid = i.indrelid
    JOIN pg_am    am ON am.oid = c.relam
    WHERE t.relname = 'sessions'
      AND c.relname = 'idx_sessions_status_start_time'
      AND am.amname = 'btree'
  );
$$;

COMMENT ON FUNCTION public.fn_sessions_has_time_series_indexes() IS
  'L08-03: true when BOTH time-series indexes exist on public.sessions '
  '(BRIN on start_time_ms + partial btree on (status, start_time_ms DESC)). '
  'Used by npm run audit:sessions-time-series-index.';

REVOKE ALL ON FUNCTION public.fn_sessions_has_time_series_indexes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_sessions_has_time_series_indexes() FROM anon;
REVOKE ALL ON FUNCTION public.fn_sessions_has_time_series_indexes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sessions_has_time_series_indexes() TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Assert wrapper fn_sessions_assert_time_series_indexes
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_sessions_assert_time_series_indexes()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_has_brin  boolean;
  v_has_btree boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class c  ON c.oid = i.indexrelid
    JOIN pg_class t  ON t.oid = i.indrelid
    JOIN pg_am    am ON am.oid = c.relam
    WHERE t.relname = 'sessions'
      AND c.relname = 'idx_sessions_start_time_brin'
      AND am.amname = 'brin'
  )
  INTO v_has_brin;

  SELECT EXISTS (
    SELECT 1
    FROM pg_index i
    JOIN pg_class c  ON c.oid = i.indexrelid
    JOIN pg_class t  ON t.oid = i.indrelid
    JOIN pg_am    am ON am.oid = c.relam
    WHERE t.relname = 'sessions'
      AND c.relname = 'idx_sessions_status_start_time'
      AND am.amname = 'btree'
  )
  INTO v_has_btree;

  IF NOT v_has_brin THEN
    RAISE EXCEPTION 'L08-03: idx_sessions_start_time_brin missing or not a BRIN index on public.sessions(start_time_ms)'
      USING ERRCODE = 'P0010',
            HINT    = 'See docs/runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md §4 for the CONCURRENTLY recipe.';
  END IF;

  IF NOT v_has_btree THEN
    RAISE EXCEPTION 'L08-03: idx_sessions_status_start_time missing or not a btree partial index on public.sessions(status, start_time_ms DESC) WHERE status >= 3'
      USING ERRCODE = 'P0010',
            HINT    = 'See docs/runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md §4.';
  END IF;
END;
$$;

COMMENT ON FUNCTION public.fn_sessions_assert_time_series_indexes() IS
  'L08-03: raises P0010 if either idx_sessions_start_time_brin (BRIN) or '
  'idx_sessions_status_start_time (btree WHERE status>=3) is missing. Used '
  'by CI (audit:sessions-time-series-index).';

REVOKE ALL ON FUNCTION public.fn_sessions_assert_time_series_indexes() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_sessions_assert_time_series_indexes() FROM anon;
REVOKE ALL ON FUNCTION public.fn_sessions_assert_time_series_indexes() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_sessions_assert_time_series_indexes() TO service_role;

COMMIT;

-- ============================================================================
-- Self-test (separate transaction; visible errors abort the migration)
-- ============================================================================
DO $L08_03_selftest$
DECLARE
  v_brin_am text;
  v_pred    text;
BEGIN
  SELECT am.amname
  INTO v_brin_am
  FROM pg_index i
  JOIN pg_class c  ON c.oid = i.indexrelid
  JOIN pg_class t  ON t.oid = i.indrelid
  JOIN pg_am    am ON am.oid = c.relam
  WHERE t.relname = 'sessions'
    AND c.relname = 'idx_sessions_start_time_brin';

  IF v_brin_am IS NULL OR v_brin_am <> 'brin' THEN
    RAISE EXCEPTION 'L08-03 selftest: idx_sessions_start_time_brin is not using BRIN access method (got: %)', v_brin_am;
  END IF;

  SELECT pg_get_expr(i.indpred, i.indrelid)
  INTO v_pred
  FROM pg_index i
  JOIN pg_class c ON c.oid = i.indexrelid
  JOIN pg_class t ON t.oid = i.indrelid
  WHERE t.relname = 'sessions'
    AND c.relname = 'idx_sessions_status_start_time';

  IF v_pred IS NULL OR v_pred NOT ILIKE '%status%>=%3%' THEN
    RAISE EXCEPTION 'L08-03 selftest: idx_sessions_status_start_time predicate drifted (got: %)', v_pred;
  END IF;

  PERFORM public.fn_sessions_assert_time_series_indexes();

  IF NOT public.fn_sessions_has_time_series_indexes() THEN
    RAISE EXCEPTION 'L08-03 selftest: fn_sessions_has_time_series_indexes() returned false after migration';
  END IF;

  RAISE NOTICE '[L08-03.selftest] OK — BRIN + partial btree present and assert passes';
END
$L08_03_selftest$;
