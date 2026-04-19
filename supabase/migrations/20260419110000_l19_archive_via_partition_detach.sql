-- ============================================================================
-- L19-02 — Archive cron via DETACH PARTITION (zero-bloat) + chunked DELETE
-- ============================================================================
--
-- The archive cron jobs introduced by
-- `20260320000000_strava_time_index_and_partitioning.sql` use a single
-- `DELETE ... RETURNING` per run:
--
--   - `fn_archive_old_ledger`  : deletes rows older than 12 months
--                                 from `public.coin_ledger` and inserts
--                                 them into `public.coin_ledger_archive`.
--   - `fn_archive_old_sessions`: same pattern against `public.sessions`
--                                 (cutoff 6 months, status IN (2,3)).
--
-- Both patterns mark dead tuples in the source table at scale (one tuple
-- per archived row). With weekly cadence and 100k users × 50tx/month,
-- the ledger archive can mark 600k dead tuples per run; sessions archive
-- can mark ≥ 200k. autovacuum will not catch up between weekly runs in
-- the steady state, so the table accumulates ~50% bloat and queries
-- start scanning dead pages.
--
-- This migration replaces both archive functions with bloat-free
-- alternatives:
--
--   coin_ledger
--   ───────────
--   `coin_ledger` is partitioned monthly by `created_at_ms` (L19-01).
--   The archive is a O(1) DDL `ALTER TABLE ... DETACH PARTITION`
--   followed by an INSERT-SELECT into `coin_ledger_archive` and a
--   DROP of the standalone partition. Cost: zero dead tuples in
--   `coin_ledger`, zero WAL churn outside the cutover, zero VACUUM
--   pressure.
--
--   sessions
--   ────────
--   `sessions` is NOT partitioned (deferred — partitioning sessions
--   on `start_time_ms` is tracked separately). For now, the archive
--   uses chunked DELETE (250-row batches) under `lock_timeout = '2s'`
--   so any single run can be interrupted by competing transactions
--   without holding locks for minutes. autovacuum is tuned more
--   aggressively on `sessions` (scale_factor 0.05) so that the bloat
--   produced by the chunked DELETE is reclaimed within the week
--   instead of accumulating for months.
--
-- The cron schedule registered by L12-02
-- (`archive-old-sessions @ 45 3 * * 0`, `archive-old-ledger @ 15 5 * * 0`)
-- continues to call `fn_archive_old_sessions()` and
-- `fn_archive_old_ledger()` — only the implementations change. No
-- changes to `cron.job` are required.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- ─────────────────────────────────────────────────────────────────────────────
-- 0. Pre-flight: sync sessions_archive schema with sessions
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `sessions_archive` was created via `LIKE sessions INCLUDING ALL` in
-- `20260320000000_strava_time_index_and_partitioning.sql`. That clones
-- the schema at migration time but does NOT propagate later ALTERs
-- to `sessions`. Subsequent migrations added columns to `sessions`
-- (e.g. `total_elevation_m` in `20260322000000_p0_critical_fixes.sql`)
-- without updating `sessions_archive`. The previous archive function
-- did `INSERT INTO sessions_archive SELECT *` which silently succeeded
-- only because no rows ever crossed the 6-month cutoff in environments
-- post-`p0_critical_fixes` (the function would error with
-- "INSERT has more expressions than target columns" if rows did cross).
--
-- Add any sessions columns that don't exist on sessions_archive,
-- defensively, before redefining the archive function. Idempotent
-- via `ADD COLUMN IF NOT EXISTS`.

ALTER TABLE public.sessions_archive
  ADD COLUMN IF NOT EXISTS total_elevation_m DOUBLE PRECISION NOT NULL DEFAULT 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Storage tuning for sessions (mitigation for chunked DELETE bloat)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Default autovacuum settings are too lazy for a table that gets a
-- weekly chunked DELETE sweep. We override per-table:
--
--   autovacuum_vacuum_scale_factor = 0.05  (default 0.20)
--     → autovacuum kicks in when 5% of the table is dead, not 20%.
--   autovacuum_vacuum_threshold    = 1000  (default 50)
--     → don't bother with tiny dirty deltas; absolute floor.
--   autovacuum_analyze_scale_factor = 0.02 (default 0.10)
--     → planner stats stay fresh after the archive sweep.
--   fillfactor = 90
--     → reserves 10% per page for HOT updates, reducing the chance
--       that a session row update creates a new tuple instead of
--       reusing the existing slot.
--
-- We do NOT set autovacuum_vacuum_cost_delay/cost_limit at table
-- level — those are global tuning that the platform team should
-- handle in supabase config; defaults are reasonable for our
-- workload.

ALTER TABLE public.sessions SET (
  autovacuum_vacuum_scale_factor   = 0.05,
  autovacuum_vacuum_threshold      = 1000,
  autovacuum_analyze_scale_factor  = 0.02,
  fillfactor                       = 90
);

COMMENT ON TABLE public.sessions IS
  'Athlete activity sessions. Storage tuned per L19-02 for aggressive autovacuum (scale_factor=0.05) since fn_archive_old_sessions performs chunked DELETE weekly.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_archive_old_ledger — DETACH PARTITION-based (replaces DELETE)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Algorithm:
--
--   cutoff_ms := unix-ms of (now() - 12 months), truncated to month
--   FOR each partition `coin_ledger_pYYYYMM` of `coin_ledger` whose
--       upper-bound is ≤ cutoff_ms (i.e. the entire partition is
--       inside the archive window):
--     - Set lock_timeout to bound DDL impact.
--     - DETACH PARTITION (instant; reads/writes against `coin_ledger`
--       continue against the remaining partitions).
--     - INSERT-SELECT all rows from the standalone table into
--       `coin_ledger_archive`. This IS a row-by-row copy, but it
--       happens against the standalone (no longer parent of any
--       cron'd queries), so there is no impact on the live table.
--     - DROP the standalone partition.
--   END LOOP
--
-- Partial-partition archives (where cutoff falls mid-month) are NOT
-- handled — a partition is archived only if its entire upper bound is
-- past the cutoff. Edge case: a row dated 2025-04-29 stays in
-- `coin_ledger_p202504` until 2026-05 even if the cutoff sweep ran
-- on 2026-04-30. This is acceptable because the audit trail value
-- of recent ledger rows in `coin_ledger` (vs in archive) is high.
--
-- Idempotency: re-running on the same day is a no-op (no partitions
-- match the cutoff a second time).

CREATE OR REPLACE FUNCTION public.fn_archive_old_ledger()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '5s'
AS $$
DECLARE
  v_cutoff_ms        bigint;
  v_partition_name   text;
  v_partition_bound  text;
  v_upper_ms         bigint;
  v_rows_in_part     bigint;
  v_total_archived   bigint := 0;
  v_partitions_done  int    := 0;
  v_rec              record;
BEGIN
  -- Cutoff aligned to the start of the month 12 months ago.
  v_cutoff_ms := (extract(epoch from date_trunc('month', now() - interval '12 months')) * 1000)::bigint;

  FOR v_rec IN
    SELECT c.relname                                   AS partition_name,
           pg_get_expr(c.relpartbound, c.oid)          AS partition_bound
      FROM pg_inherits i
      JOIN pg_class c   ON c.oid = i.inhrelid
      JOIN pg_class p   ON p.oid = i.inhparent
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE p.relname  = 'coin_ledger'
       AND n.nspname  = 'public'
       AND c.relname <> 'coin_ledger_default'
     ORDER BY c.relname
  LOOP
    -- partition_bound looks like:
    --   FOR VALUES FROM ('1704067200000') TO ('1706745600000')
    -- We extract the upper bound (TO clause). Defensive: if regex
    -- doesn't match (unexpected partition shape), skip the partition.
    v_upper_ms := NULLIF(
      substring(v_rec.partition_bound from $re$TO\s*\(\s*'?(-?\d+)'?\s*\)$re$),
      ''
    )::bigint;

    IF v_upper_ms IS NULL THEN
      RAISE NOTICE '[L19-02] skipping partition % — unparseable bound: %',
        v_rec.partition_name, v_rec.partition_bound;
      CONTINUE;
    END IF;

    IF v_upper_ms > v_cutoff_ms THEN
      -- Partition is still inside retention window; nothing to do.
      CONTINUE;
    END IF;

    v_partition_name := v_rec.partition_name;

    BEGIN
      EXECUTE format(
        'ALTER TABLE public.coin_ledger DETACH PARTITION public.%I',
        v_partition_name
      );

      EXECUTE format(
        'INSERT INTO public.coin_ledger_archive '
        'SELECT * FROM public.%I',
        v_partition_name
      );
      GET DIAGNOSTICS v_rows_in_part = ROW_COUNT;

      EXECUTE format('DROP TABLE public.%I', v_partition_name);

      v_total_archived  := v_total_archived + v_rows_in_part;
      v_partitions_done := v_partitions_done + 1;

      RAISE NOTICE '[L19-02] archived partition % (% rows)',
        v_partition_name, v_rows_in_part;
    EXCEPTION WHEN lock_not_available THEN
      RAISE NOTICE '[L19-02] partition % busy (lock_timeout) — leaving for next run',
        v_partition_name;
      -- Continue to the next partition; current partition will be
      -- retried next week.
      CONTINUE;
    END;
  END LOOP;

  RAISE NOTICE '[L19-02] archive cycle done: % partitions, % rows',
    v_partitions_done, v_total_archived;

  -- Return value preserves the contract of the previous fn (rows moved).
  -- Callers (cron) only inspect logs; pg_cron does not care about the
  -- return value.
  RETURN v_total_archived::int;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_archive_old_ledger() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_archive_old_sessions — chunked DELETE (replaces single bulk DELETE)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- `sessions` cannot use the partition-detach pattern yet (table is not
-- partitioned). Instead we do a chunked DELETE that:
--
--   - holds locks for max 2s per chunk (lock_timeout) so portal writes
--     are not blocked,
--   - moves at most BATCH_SIZE rows per iteration,
--   - aborts cleanly when no more rows match the cutoff,
--   - bounds total work via MAX_BATCHES so a single cron tick cannot
--     run for more than ~10 minutes (BATCH_SIZE 250 * MAX_BATCHES 200
--     × ~150ms per chunk = ~7.5 min upper bound).
--
-- The bloat is mitigated (not eliminated) by the autovacuum tuning in
-- §1 above. Sessions partitioning is the proper fix and is tracked as
-- a follow-up (Wave 2 candidate; mirrors the L19-01 pattern with
-- PARTITION BY RANGE (start_time_ms)).

CREATE OR REPLACE FUNCTION public.fn_archive_old_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_cutoff_ms     bigint;
  v_chunk_moved   int;
  v_total_moved   int := 0;
  v_batches_done  int := 0;
  k_batch_size    constant int := 250;
  k_max_batches   constant int := 200;
BEGIN
  v_cutoff_ms := (extract(epoch from now() - interval '6 months') * 1000)::bigint;

  WHILE v_batches_done < k_max_batches LOOP
    BEGIN
      WITH candidates AS (
        SELECT id
          FROM public.sessions
         WHERE start_time_ms < v_cutoff_ms
           AND status IN (2, 3)
         ORDER BY start_time_ms ASC
         LIMIT k_batch_size
         FOR UPDATE SKIP LOCKED
      ),
      moved AS (
        DELETE FROM public.sessions s
         USING candidates c
         WHERE s.id = c.id
        RETURNING s.*
      )
      INSERT INTO public.sessions_archive
      SELECT * FROM moved;

      GET DIAGNOSTICS v_chunk_moved = ROW_COUNT;
    EXCEPTION WHEN lock_not_available THEN
      -- Portal write contention; back off and let next tick try.
      RAISE NOTICE '[L19-02] sessions archive: lock_timeout on batch %, backing off',
        v_batches_done;
      EXIT;
    END;

    EXIT WHEN v_chunk_moved = 0;

    v_total_moved  := v_total_moved + v_chunk_moved;
    v_batches_done := v_batches_done + 1;
  END LOOP;

  RAISE NOTICE '[L19-02] sessions archive cycle done: % rows in % batches',
    v_total_moved, v_batches_done;

  RETURN v_total_moved;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_archive_old_sessions() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Comments cross-referencing audit findings
-- ─────────────────────────────────────────────────────────────────────────────

COMMENT ON FUNCTION public.fn_archive_old_ledger() IS
  'L19-02: archive coin_ledger via DETACH PARTITION (zero bloat). Iterates monthly partitions whose upper bound is past the 12-month cutoff and detaches → INSERT INTO coin_ledger_archive → DROP. lock_timeout=5s prevents long-running DDL holding locks; busy partitions are skipped and retried next week.';

COMMENT ON FUNCTION public.fn_archive_old_sessions() IS
  'L19-02: archive sessions via chunked DELETE (BATCH=250, lock_timeout=2s, MAX_BATCHES=200). Mitigates bloat vs the previous single-shot DELETE; full elimination requires partitioning sessions on start_time_ms (deferred to Wave 2).';
