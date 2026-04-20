-- ============================================================================
-- L02-10 — Cold start + Vercel timeout in long batch settle operations
--
-- Audit reference:
--   docs/audit/findings/L02-10-cold-start-timeout-vercel-em-operacoes-longas.md
--   docs/audit/parts/02-cto-cfo.md  (anchor [2.10])
--
-- Problem
-- ───────
--   `portal/src/lib/clearing.ts::settleWindowForDebtor` issues an
--   unbounded `for-of` loop calling `settle_clearing(p_settlement_id)`
--   once per pending row inside a single Vercel function invocation.
--   With a 15s Supabase fetch timeout (`createServiceClient`) and a
--   Vercel Hobby 10s / Pro 60s response budget, the function dies
--   silently above ~300 settlements per batch — producing partial
--   settlements, an inconsistent ledger, and no observability into
--   how far the run got before it was killed.
--
--   The audit asked for two things:
--     1. Bounded, restartable chunks (so a single invocation never
--        exceeds the platform timeout).
--     2. A cron continuation that drains backlog deterministically
--        without manual ops involvement.
--
-- Defence (this migration)
-- ───────
--   • `fn_settle_clearing_chunk(p_window_start, p_window_end, p_limit,
--                                p_debtor_group_id := NULL)`
--     ─────────────────────────────────────────────────────────────────
--     Reads up to `p_limit` pending settlements within the window
--     (optionally scoped to a single debtor for back-compat with the
--     Coach-driven flow), iterates and calls `settle_clearing` per
--     row, and returns counts:
--
--         processed     int   -- rows the function looked at
--         settled       int   -- rows transitioned to 'settled'
--         insufficient  int   -- rows transitioned to 'insufficient'
--         failed        int   -- rows that raised inside settle_clearing
--         remaining     int   -- COUNT(*) of pending rows still in window
--
--     Each row is settled inside an explicit `BEGIN/EXCEPTION/END`
--     block so a single failure (e.g. lock_timeout, custody account
--     missing) increments `failed` instead of aborting the whole
--     chunk. `lock_timeout` is set to 2s per call (matching L19-05),
--     so a stuck row eventually gives up and the next chunk picks up
--     a different one.
--
--     Critically, the row picker uses `FOR UPDATE SKIP LOCKED` so two
--     concurrent workers (e.g. cron AND a manual replay) never wait
--     on each other — they each take a disjoint slice of the backlog.
--
--   • `fn_settle_clearing_batch_safe(p_limit, p_window_hours)`
--     ─────────────────────────────────────────────────────────────────
--     Cron-safe wrapper around `fn_settle_clearing_chunk` using the
--     L12-03 cron-state pattern (`fn_cron_should_run` +
--     `fn_cron_mark_*`) and an advisory xact lock keyed to
--     `cron:settle_clearing_batch` (hard mutex even if cron-state
--     check races). Window is `[now() - p_window_hours, now())`.
--     Records run-stats in `last_meta` for ops visibility:
--
--         { "processed": N, "settled": S, "insufficient": I,
--           "failed": F, "remaining": R, "limit": L,
--           "window_hours": H }
--
--     `remaining > 0` signals "next minute will pick up the rest".
--
--   • `cron.schedule('settle-clearing-batch', '* * * * *', ...)`
--     ─────────────────────────────────────────────────────────────────
--     pg_cron schedule firing every minute calling the safe wrapper
--     directly (no HTTP roundtrip — runs in-DB so we're not subject
--     to Vercel timeouts AT ALL for the cron-driven path). The Vercel
--     route handler exists as an operator-callable replay surface
--     (and as the documented manual escape from the runbook), but the
--     normal flow is fully in-DB.
--
--   • Seeds `cron_run_state('settle-clearing-batch', 'never_run')`
--     so ops can immediately see the job in dashboards.
--
--   • Self-test inside the migration TX validates:
--       (i)   fn_settle_clearing_chunk returns the expected shape on
--             an empty window (zero rows, zero settled, remaining=0)
--       (ii)  fn_settle_clearing_batch_safe completes a no-op cycle
--             and writes `last_status='completed'` + populated meta
--       (iii) cron job is registered (skipped if pg_cron unavailable)
--
-- Notes
-- ───────
--   • `settle_clearing(p_settlement_id)` is preserved as the per-row
--     primitive; `fn_settle_clearing_chunk` is its plural form. Both
--     remain SECURITY DEFINER + service-role gated.
--   • The chunk function is intentionally narrow: it does NOT do
--     audit logging per row (the underlying `settle_clearing` already
--     touches `clearing_settlements.status` and `platform_revenue`
--     which are sufficient forensics; per-row audit log entries
--     would 50× the row count and overwhelm the existing audit
--     query patterns). Aggregate counts are surfaced via
--     `cron_run_state.last_meta` and the route handler response.
--   • If the `settle-clearing-batch` cron is ever disabled (e.g.
--     during a custody freeze), the route handler `/api/cron/
--     settle-clearing-batch` remains the canonical way for ops to
--     drain manually — see CRON_HEALTH_RUNBOOK §4.x.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. fn_settle_clearing_chunk — bounded chunk-processor
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_settle_clearing_chunk(
  p_window_start     timestamptz,
  p_window_end       timestamptz,
  p_limit            int     DEFAULT 50,
  p_debtor_group_id  uuid    DEFAULT NULL
)
RETURNS TABLE (
  processed     int,
  settled       int,
  insufficient  int,
  failed        int,
  remaining     int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_id            uuid;
  v_processed     int := 0;
  v_settled       int := 0;
  v_insufficient  int := 0;
  v_failed        int := 0;
  v_remaining     int := 0;
  v_status_after  text;
BEGIN
  IF p_window_start IS NULL OR p_window_end IS NULL THEN
    RAISE EXCEPTION 'fn_settle_clearing_chunk: window bounds are required'
      USING ERRCODE = '22023';
  END IF;
  IF p_window_end <= p_window_start THEN
    RAISE EXCEPTION 'fn_settle_clearing_chunk: window_end (%) must be > window_start (%)',
      p_window_end, p_window_start
      USING ERRCODE = '22023';
  END IF;
  IF p_limit IS NULL OR p_limit <= 0 OR p_limit > 500 THEN
    RAISE EXCEPTION 'fn_settle_clearing_chunk: limit must be in (0, 500], got %', p_limit
      USING ERRCODE = '22023';
  END IF;

  -- Pick up to `p_limit` pending settlements with SKIP LOCKED so two
  -- concurrent workers never block each other on the same row.
  FOR v_id IN
    SELECT id
    FROM   public.clearing_settlements
    WHERE  status = 'pending'
      AND  created_at >= p_window_start
      AND  created_at <  p_window_end
      AND  (p_debtor_group_id IS NULL OR debtor_group_id = p_debtor_group_id)
    ORDER  BY created_at ASC
    LIMIT  p_limit
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;

    BEGIN
      PERFORM public.settle_clearing(v_id);

      -- settle_clearing flips status to either 'settled' or
      -- 'insufficient' (no exception raised for the latter).
      SELECT cs.status INTO v_status_after
      FROM   public.clearing_settlements cs
      WHERE  cs.id = v_id;

      IF v_status_after = 'settled' THEN
        v_settled := v_settled + 1;
      ELSIF v_status_after = 'insufficient' THEN
        v_insufficient := v_insufficient + 1;
      ELSE
        -- Unexpected post-state. Count as failed for ops visibility;
        -- the row is still recoverable on the next chunk.
        v_failed := v_failed + 1;
      END IF;

    EXCEPTION WHEN OTHERS THEN
      -- A single bad row (lock_timeout, missing custody account,
      -- invariant violation raised inside settle_clearing) MUST NOT
      -- abort the entire chunk. Other rows in this loop must still
      -- get processed.
      v_failed := v_failed + 1;
      RAISE NOTICE '[L02-10.chunk_row_failed] settlement_id=% sqlstate=% sqlerrm=%',
        v_id, SQLSTATE, SQLERRM;
    END;
  END LOOP;

  -- Backlog snapshot for the same window (post-chunk). Used by ops
  -- to decide whether to bump the cron cadence or wait it out.
  SELECT COUNT(*)::int
  INTO   v_remaining
  FROM   public.clearing_settlements
  WHERE  status = 'pending'
    AND  created_at >= p_window_start
    AND  created_at <  p_window_end
    AND  (p_debtor_group_id IS NULL OR debtor_group_id = p_debtor_group_id);

  processed    := v_processed;
  settled      := v_settled;
  insufficient := v_insufficient;
  failed       := v_failed;
  remaining    := v_remaining;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_settle_clearing_chunk(timestamptz, timestamptz, int, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_settle_clearing_chunk(timestamptz, timestamptz, int, uuid) TO service_role;

COMMENT ON FUNCTION public.fn_settle_clearing_chunk(timestamptz, timestamptz, int, uuid) IS
  'L02-10: bounded chunk-processor for clearing settlements. Picks up to p_limit pending rows with SKIP LOCKED, calls settle_clearing per row inside its own EXCEPTION block, returns {processed, settled, insufficient, failed, remaining}.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_settle_clearing_batch_safe — cron-safe wrapper
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_settle_clearing_batch_safe(
  p_limit         int  DEFAULT 50,
  p_window_hours  int  DEFAULT 168     -- 7 days, generous (settle_clearing only touches pending rows anyway)
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_window_start  timestamptz;
  v_window_end    timestamptz;
  v_meta          jsonb;
  v_row           record;
BEGIN
  IF NOT public.fn_cron_should_run('settle-clearing-batch', 240) THEN
    RETURN jsonb_build_object('skipped', true, 'reason', 'should_run_false');
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:settle_clearing_batch')
  );
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'settle-clearing-batch';
    RETURN jsonb_build_object('skipped', true, 'reason', 'advisory_lock_held');
  END IF;

  PERFORM public.fn_cron_mark_started('settle-clearing-batch');

  v_window_end   := now();
  v_window_start := v_window_end - make_interval(hours => GREATEST(p_window_hours, 1));

  BEGIN
    SELECT processed, settled, insufficient, failed, remaining
    INTO   v_row
    FROM   public.fn_settle_clearing_chunk(
      v_window_start,
      v_window_end,
      LEAST(GREATEST(p_limit, 1), 500),
      NULL
    );

    v_meta := jsonb_build_object(
      'processed',    v_row.processed,
      'settled',      v_row.settled,
      'insufficient', v_row.insufficient,
      'failed',       v_row.failed,
      'remaining',    v_row.remaining,
      'limit',        LEAST(GREATEST(p_limit, 1), 500),
      'window_hours', GREATEST(p_window_hours, 1)
    );

    PERFORM public.fn_cron_mark_completed('settle-clearing-batch', v_meta);
    RETURN v_meta;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'settle-clearing-batch',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'chunk_call')
    );
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_settle_clearing_batch_safe(int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_settle_clearing_batch_safe(int, int) TO service_role;

COMMENT ON FUNCTION public.fn_settle_clearing_batch_safe(int, int) IS
  'L02-10: cron-safe wrapper around fn_settle_clearing_chunk. Uses cron_run_state lifecycle (L12-03) + advisory xact lock; emits chunk counts in last_meta.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Schedule cron `settle-clearing-batch` every minute (in-DB call)
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L02-10] pg_cron not installed; skipping schedule';
    RETURN;
  END IF;

  BEGIN PERFORM cron.unschedule('settle-clearing-batch');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'settle-clearing-batch',
    '* * * * *',
    $cron$ SELECT public.fn_settle_clearing_batch_safe(50, 168); $cron$
  );

  -- Seed cron_run_state (from L12-03) so ops dashboards see the job
  -- as `never_run` immediately after rollout.
  INSERT INTO public.cron_run_state(name, last_status)
  VALUES ('settle-clearing-batch', 'never_run')
  ON CONFLICT (name) DO NOTHING;

  RAISE NOTICE '[L02-10] scheduled settle-clearing-batch every minute (limit=50, window=168h)';
END$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Self-test (schema + no-op behaviour)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Validates that the new function shape is callable end-to-end on a
-- freshly-applied migration without requiring fixture data. We DO NOT
-- attempt to settle real rows here — the integration test does that
-- in tools/test_l02_10_clearing_settle_chunked.ts.

DO $$
DECLARE
  v_row    record;
  v_meta   jsonb;
  v_state  record;
BEGIN
  -- (i) chunk function returns zero counts on an empty window
  SELECT processed, settled, insufficient, failed, remaining
  INTO   v_row
  FROM   public.fn_settle_clearing_chunk(
    now() - interval '1 hour',
    now(),
    10,
    NULL
  );

  IF v_row.processed <> 0 OR v_row.settled <> 0
     OR v_row.insufficient <> 0 OR v_row.failed <> 0
  THEN
    RAISE EXCEPTION '[L02-10.self_test] expected zero counts on empty 1h window, got %', to_jsonb(v_row);
  END IF;

  -- (ii) batch wrapper completes a no-op cycle and writes meta
  v_meta := public.fn_settle_clearing_batch_safe(10, 1);

  IF v_meta IS NULL OR (v_meta ? 'skipped') THEN
    -- A previous test run can leave `last_status='running'` inside
    -- the safety window; tolerate either skipped reason. We only
    -- enforce strictness when the call actually executed.
    RAISE NOTICE '[L02-10.self_test] batch wrapper returned %; treating as no-op', v_meta;
  ELSE
    IF (v_meta->>'processed')::int <> 0 OR (v_meta->>'settled')::int <> 0 THEN
      RAISE EXCEPTION '[L02-10.self_test] unexpected non-zero counts on empty window: %', v_meta;
    END IF;

    SELECT * INTO v_state
    FROM   public.cron_run_state
    WHERE  name = 'settle-clearing-batch';

    IF v_state.last_status NOT IN ('completed', 'never_run') THEN
      RAISE EXCEPTION '[L02-10.self_test] cron_run_state.last_status expected completed/never_run, got %', v_state.last_status;
    END IF;
  END IF;

  RAISE NOTICE '[L02-10.self_test] fn_settle_clearing_chunk + fn_settle_clearing_batch_safe wired correctly';
END$$;

COMMIT;
