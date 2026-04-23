-- ============================================================================
-- L12-06 — archive-old-sessions: one chunk per transaction (COMMIT between)
--
-- Audit reference:
--   docs/audit/findings/L12-06-archive-old-sessions-roda-como-funcao-pesada-sem.md
--   docs/audit/parts/12-cron-scheduler.md  (anchor [12.6])
--
-- Problem
-- ───────
--   L19-02 (2026-04-19) already replaced the original single-shot
--   `DELETE ... RETURNING` with a chunked variant inside
--   `fn_archive_old_sessions()` (BATCH_SIZE=250, MAX_BATCHES=200,
--   lock_timeout=2s). That mitigates *lock duration per chunk* and
--   *WAL spike size*, but it does NOT satisfy the L12-06 ask because:
--
--     • All chunks run inside ONE PL/pgSQL function call, which is a
--       SINGLE outer transaction. Postgres has no native autonomous
--       transactions in plpgsql — BEGIN/END blocks are subtransactions
--       (savepoints), not real commits. So:
--         - Snapshot is held for the duration of all 200 batches.
--         - Old tuples from all chunks accumulate dead-tuple pressure
--           together; autovacuum can't start until the function
--           returns.
--         - WAL buffers retain the full archive delta between checkpoints.
--         - If the cron tick is killed mid-run (Supabase rotate/upgrade
--           on Sundays), zero rows land in `sessions_archive`. The
--           whole cycle is lost until next week.
--
--     • A single long function call also blocks pg_cron's
--       "completion" signal — `cron_run_state.last_finished_at`
--       (L12-03) only updates after the whole thing returns, so the
--       operator dashboard shows "in_progress 35min" instead of a
--       smooth tick cadence of "completed 2s/chunk".
--
-- Defence (this migration)
-- ───────
--   Extract the per-chunk work into `fn_archive_sessions_chunk(...)` —
--   a function that does EXACTLY ONE chunk and returns a jsonb shape
--   describing what happened. An Edge Function (deployed separately,
--   `supabase/functions/archive-old-sessions/index.ts`) calls this
--   helper in a loop — each call is a separate HTTP/RPC round-trip
--   which lands as a separate Postgres transaction. COMMIT happens
--   between chunks, releasing locks and unblocking autovacuum.
--
--   Additionally, the pg_cron job itself is rescheduled to invoke the
--   Edge Function via the L06-05 retry wrapper
--   (`fn_invoke_edge_with_retry`) so transient 5xx from
--   `/functions/v1/archive-old-sessions` are retried automatically
--   instead of eaten. Integration with `cron_run_state` (L12-03)
--   preserves the smooth tick cadence.
--
-- Five objects in this migration:
--
--   1. `public.fn_archive_sessions_chunk(batch_size, cutoff_months,
--                                         max_scan_hint)`
--      — does ONE chunk, returns jsonb.
--   2. `public.fn_archive_sessions_pending_count(cutoff_months)`
--      — read-only counter for ops dashboards.
--   3. `public.fn_archive_old_sessions()` — REWRITTEN to a thin
--      backwards-compat shim that calls the chunk helper in a loop
--      (single transaction, same semantics as L19-02) so any existing
--      direct callers still work. Keeps the cron schedule valid for
--      environments where the Edge Function isn't deployed yet.
--   4. `public.fn_invoke_archive_sessions_safe()` — cron-invoker that
--      uses the L06-05 retry wrapper + `cron_run_state` lifecycle.
--   5. Reschedule `archive-old-sessions` pg_cron job to call the
--      new invoker (idempotent via DO-block).
--
-- Backwards compat
-- ────────────────
--   Every caller of `fn_archive_old_sessions()` continues to get the
--   same (int) return value = rows archived. SIgnature is preserved.
--   The `sessions_archive` table schema is untouched. No DDL on
--   `public.sessions` beyond what L19-02 already shipped.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. fn_archive_sessions_chunk — the per-chunk primitive
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Contract: exactly one chunk per invocation. Returns jsonb:
--
--   {
--     "moved_count":    <int>,        -- rows actually archived this chunk
--     "more_pending":   <boolean>,    -- whether another chunk would find rows
--     "cutoff_ms":      <bigint>,     -- cutoff used (for audit)
--     "elapsed_ms":     <int>         -- time spent on this chunk
--   }
--
-- `more_pending` is a cheap probe (LIMIT 1 on the same predicate), not a
-- full COUNT — so the caller loops until `more_pending = false` OR a
-- time/batch budget is reached.
--
-- `lock_timeout = '2s'` is per-statement inside this function; if the
-- DELETE is blocked longer than 2s we let it raise and the caller
-- records the failure and backs off. Caller decides retry policy.

CREATE OR REPLACE FUNCTION public.fn_archive_sessions_chunk(
  p_batch_size     integer DEFAULT 500,
  p_cutoff_months  integer DEFAULT 6
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_cutoff_ms     bigint;
  v_moved         int;
  v_more_pending  boolean;
  v_started       timestamptz := clock_timestamp();
  v_elapsed_ms    int;
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 10000 THEN
    RAISE EXCEPTION 'INVALID_BATCH_SIZE: % (expected 1..10000)', p_batch_size
      USING ERRCODE = '22023';
  END IF;
  IF p_cutoff_months IS NULL OR p_cutoff_months < 1 OR p_cutoff_months > 120 THEN
    RAISE EXCEPTION 'INVALID_CUTOFF_MONTHS: % (expected 1..120)', p_cutoff_months
      USING ERRCODE = '22023';
  END IF;

  v_cutoff_ms := (
    extract(epoch from now() - make_interval(months => p_cutoff_months)) * 1000
  )::bigint;

  WITH candidates AS (
    SELECT id
      FROM public.sessions
     WHERE start_time_ms < v_cutoff_ms
       AND status IN (2, 3)
     ORDER BY start_time_ms ASC
     LIMIT p_batch_size
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

  GET DIAGNOSTICS v_moved = ROW_COUNT;

  -- Probe whether another chunk would find rows. Cheap LIMIT 1 on the
  -- same predicate — ignores SKIP LOCKED so we don't falsely report
  -- "done" while a concurrent session is still working its own chunk.
  SELECT EXISTS (
    SELECT 1
      FROM public.sessions
     WHERE start_time_ms < v_cutoff_ms
       AND status IN (2, 3)
     LIMIT 1
  ) INTO v_more_pending;

  v_elapsed_ms := GREATEST(
    1,
    (extract(epoch from (clock_timestamp() - v_started)) * 1000)::int
  );

  RETURN jsonb_build_object(
    'moved_count',  v_moved,
    'more_pending', v_more_pending,
    'cutoff_ms',    v_cutoff_ms,
    'elapsed_ms',   v_elapsed_ms
  );
END;
$$;

COMMENT ON FUNCTION public.fn_archive_sessions_chunk(integer, integer) IS
  'L12-06: archive ONE chunk of old sessions (default 500 rows, 6-month cutoff). '
  'Returns jsonb with moved_count, more_pending, cutoff_ms, elapsed_ms. '
  'Called in a loop by supabase/functions/archive-old-sessions so each chunk is '
  'committed as its own transaction (unblocks autovacuum between chunks).';

REVOKE ALL ON FUNCTION public.fn_archive_sessions_chunk(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_sessions_chunk(integer, integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_archive_sessions_pending_count — ops visibility
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_archive_sessions_pending_count(
  p_cutoff_months integer DEFAULT 6
) RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_cutoff_ms bigint;
  v_count     bigint;
BEGIN
  IF p_cutoff_months IS NULL OR p_cutoff_months < 1 OR p_cutoff_months > 120 THEN
    RAISE EXCEPTION 'INVALID_CUTOFF_MONTHS: % (expected 1..120)', p_cutoff_months
      USING ERRCODE = '22023';
  END IF;

  v_cutoff_ms := (
    extract(epoch from now() - make_interval(months => p_cutoff_months)) * 1000
  )::bigint;

  SELECT COUNT(*) INTO v_count
    FROM public.sessions
   WHERE start_time_ms < v_cutoff_ms
     AND status IN (2, 3);

  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_archive_sessions_pending_count(integer) IS
  'L12-06: read-only count of sessions older than the cutoff that are archivable. '
  'Used by the runbook to decide whether the last archive cycle fell behind.';

REVOKE ALL ON FUNCTION public.fn_archive_sessions_pending_count(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_archive_sessions_pending_count(integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_archive_old_sessions — backwards-compat shim
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Preserves the (integer) return type + name used by any existing
-- callers (pg_cron, DO blocks in older migrations, ad-hoc ops). Now
-- loops over `fn_archive_sessions_chunk` inside a single transaction
-- (single COMMIT at function return) — same semantics as L19-02 but
-- routed through the chunk primitive so the codepath stays DRY.
--
-- Preferred invocation path is now the Edge Function (see §5), which
-- gets real COMMIT-between-chunks. This shim exists so:
--   • environments that haven't deployed the Edge Function fall back
--     to the L19-02 behaviour.
--   • ad-hoc `SELECT fn_archive_old_sessions();` in psql still works.

CREATE OR REPLACE FUNCTION public.fn_archive_old_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_total        int := 0;
  v_chunk        jsonb;
  v_batches_done int := 0;
  k_max_batches  constant int := 200;
  k_batch_size   constant int := 250;
BEGIN
  WHILE v_batches_done < k_max_batches LOOP
    v_chunk := public.fn_archive_sessions_chunk(k_batch_size, 6);
    v_total := v_total + (v_chunk->>'moved_count')::int;
    v_batches_done := v_batches_done + 1;

    EXIT WHEN (v_chunk->>'moved_count')::int = 0
          OR (v_chunk->>'more_pending')::boolean = false;
  END LOOP;

  RAISE NOTICE '[L12-06] fn_archive_old_sessions shim: % rows in % batches',
    v_total, v_batches_done;
  RETURN v_total;
END;
$$;

COMMENT ON FUNCTION public.fn_archive_old_sessions() IS
  'L12-06: backwards-compat shim. Loops fn_archive_sessions_chunk inside a '
  'single transaction (single COMMIT). Prefer invoking the archive-old-sessions '
  'Edge Function for true COMMIT-between-chunks. Return value preserved (rows moved).';

GRANT EXECUTE ON FUNCTION public.fn_archive_old_sessions() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. fn_invoke_archive_sessions_safe — cron entry point with L06-05 retry
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Integrates with:
--   • cron_run_state (L12-03): mark_started → mark_completed/failed
--   • fn_invoke_edge_with_retry (L06-05): retry on pg_net failure
--   • advisory xact lock: prevents two archive runs overlapping if
--                          the schedule somehow double-fires.
--
-- If the Edge Function isn't deployed (HTTP 404) or the `http`
-- extension is absent (dev sandbox), fall back to the SQL shim so
-- the weekly archive still moves forward.

CREATE OR REPLACE FUNCTION public.fn_invoke_archive_sessions_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_started_ok   boolean;
  v_result       jsonb;
  v_skipped      boolean;
  v_http_ok      boolean;
  v_fallback_rows int;
  v_has_cron_run_state boolean;
  v_has_retry_wrapper  boolean;
BEGIN
  -- Lifecycle tracking is optional (L12-03 may not be applied in dev).
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_cron_mark_started'
  ) INTO v_has_cron_run_state;

  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_invoke_edge_with_retry'
  ) INTO v_has_retry_wrapper;

  IF v_has_cron_run_state THEN
    BEGIN
      v_started_ok := public.fn_cron_mark_started('archive-old-sessions');
      IF NOT v_started_ok THEN
        RAISE NOTICE '[L12-06] archive-old-sessions: another run in progress; skipping';
        RETURN;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[L12-06] fn_cron_mark_started failed (%): proceeding without lifecycle tracking', SQLERRM;
    END;
  END IF;

  -- Try the Edge Function (real COMMIT between chunks). If the retry
  -- wrapper isn't available or the HTTP layer is unreachable, fall
  -- back to the SQL shim so archival still moves forward.
  IF v_has_retry_wrapper THEN
    BEGIN
      v_result := public.fn_invoke_edge_with_retry(
        p_job_name             => 'archive-old-sessions',
        p_endpoint             => 'archive-old-sessions',
        p_body                 => jsonb_build_object(
                                    'batch_size',      500,
                                    'cutoff_months',   6,
                                    'max_duration_ms', 480000,
                                    'max_batches',     40
                                  ),
        p_max_attempts         => 3,
        p_backoff_base_seconds => 15
      );
      v_skipped := COALESCE((v_result->>'skipped')::boolean, false);
      v_http_ok := COALESCE((v_result->>'ok')::boolean, false);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE '[L12-06] fn_invoke_edge_with_retry failed (%): falling back to SQL shim', SQLERRM;
      v_skipped := true;
      v_http_ok := false;
    END;
  ELSE
    v_skipped := true;
    v_http_ok := false;
  END IF;

  IF v_http_ok THEN
    IF v_has_cron_run_state THEN
      BEGIN
        PERFORM public.fn_cron_mark_completed('archive-old-sessions', v_result);
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    RETURN;
  END IF;

  -- Fallback: use the SQL shim for at least L19-02-style chunked work.
  BEGIN
    v_fallback_rows := public.fn_archive_old_sessions();
    IF v_has_cron_run_state THEN
      BEGIN
        PERFORM public.fn_cron_mark_completed(
          'archive-old-sessions',
          jsonb_build_object(
            'mode', 'sql_fallback',
            'rows_moved', v_fallback_rows,
            'edge_result', v_result
          )
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    IF v_has_cron_run_state THEN
      BEGIN
        PERFORM public.fn_cron_mark_failed(
          'archive-old-sessions',
          format('SQL_FALLBACK_FAILED: %s', SQLERRM)
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
    RAISE;
  END;
END;
$$;

COMMENT ON FUNCTION public.fn_invoke_archive_sessions_safe() IS
  'L12-06: cron entry point for archive-old-sessions. Prefers the Edge '
  'Function path (true COMMIT-between-chunks via L06-05 retry wrapper). '
  'Falls back to the SQL shim fn_archive_old_sessions() if the Edge '
  'Function is unavailable. Integrates with cron_run_state (L12-03).';

REVOKE ALL ON FUNCTION public.fn_invoke_archive_sessions_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_archive_sessions_safe() TO service_role;

COMMIT;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Reschedule the pg_cron job (idempotent, optional based on extension)
-- ─────────────────────────────────────────────────────────────────────────────

DO $reschedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-06] pg_cron not installed; skipping cron reschedule';
    RETURN;
  END IF;

  BEGIN
    PERFORM cron.unschedule('archive-old-sessions');
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  PERFORM cron.schedule(
    'archive-old-sessions',
    '45 3 * * 0',
    $cron$ SELECT public.fn_invoke_archive_sessions_safe(); $cron$
  );

  -- Seed cron_run_state if present (L12-03)
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
     WHERE n.nspname = 'public' AND c.relname = 'cron_run_state'
  ) THEN
    INSERT INTO public.cron_run_state (name, last_status)
    VALUES ('archive-old-sessions', 'never_ran')
    ON CONFLICT (name) DO NOTHING;
  END IF;

  RAISE NOTICE '[L12-06] archive-old-sessions rescheduled to fn_invoke_archive_sessions_safe';
END
$reschedule$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Self-test
-- ─────────────────────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_chunk   jsonb;
  v_pending bigint;
  v_funcs   int;
BEGIN
  SELECT COUNT(*) INTO v_funcs
    FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
   WHERE n.nspname = 'public'
     AND p.proname IN (
       'fn_archive_sessions_chunk',
       'fn_archive_sessions_pending_count',
       'fn_archive_old_sessions',
       'fn_invoke_archive_sessions_safe'
     );
  IF v_funcs <> 4 THEN
    RAISE EXCEPTION '[L12-06.selftest] expected 4 functions, found %', v_funcs;
  END IF;

  -- Call the chunk helper against an empty window (will be safe even
  -- with zero rows; exercises the SKIP LOCKED + probe paths).
  v_chunk := public.fn_archive_sessions_chunk(1, 6);
  IF (v_chunk->>'moved_count')::int IS NULL THEN
    RAISE EXCEPTION '[L12-06.selftest] chunk helper returned malformed jsonb: %', v_chunk;
  END IF;

  v_pending := public.fn_archive_sessions_pending_count(6);
  IF v_pending IS NULL OR v_pending < 0 THEN
    RAISE EXCEPTION '[L12-06.selftest] pending count malformed: %', v_pending;
  END IF;

  RAISE NOTICE '[L12-06.selftest] OK — 4 functions installed, chunk+pending callable';
END
$selftest$;
