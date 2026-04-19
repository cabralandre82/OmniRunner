-- ============================================================================
-- L12-03 — Cron overlap protection (advisory locks + cron_run_state)
-- ============================================================================
--
-- Three of our pg_cron jobs run every 5 minutes:
--
--   - lifecycle-cron                       (HTTP-fired Edge Function)
--   - expire-matchmaking-queue             (in-DB SQL function)
--   - process-scheduled-workout-releases   (in-DB SQL function)
--
-- The audit (L12-03) flagged the overlap risk: if execution N takes
-- longer than 5 minutes, execution N+1 starts on top of N and processes
-- the same rows twice. For the matchmaking queue this manifests as
-- entries flipping `waiting → expired` twice (idempotent at the row
-- level but doubles the audit chatter); for `process_scheduled_releases`
-- it can manifest as the SAME release row being released twice if a
-- second worker picks it up between the SELECT and UPDATE in the LOOP
-- (the function does NOT use SELECT ... FOR UPDATE SKIP LOCKED).
--
-- For the HTTP-fired `lifecycle-cron` the risk is worse: pg_net's
-- `extensions.http(...)` queues the request and returns IMMEDIATELY,
-- so pg_cron does not wait for the Edge Function to finish before
-- scheduling the next fire. Two slow Edge Function instances can
-- absolutely run concurrently.
--
-- This migration introduces THREE complementary defences:
--
--   (a) `public.cron_run_state` — a single-row-per-job table that
--       tracks each scheduled job's lifecycle (`started_at`,
--       `finished_at`, `last_status`, `run_count`, `skip_count`,
--       `last_error`, `last_meta`). Read by `fn_cron_should_run` to
--       decide whether to skip; written by `fn_cron_mark_*` helpers.
--       Doubles as observability surface for ops dashboards.
--
--   (b) `pg_try_advisory_xact_lock` wrappers (`fn_*_safe`) for the
--       in-DB SQL jobs. These give us hard mutex semantics inside
--       Postgres at zero round-trip cost — if a previous run is
--       still in-flight (txn open), the new run skips immediately.
--       The lock auto-releases on transaction end, so no orphaned
--       locks if the worker crashes.
--
--   (c) `fn_invoke_lifecycle_cron_safe` for the HTTP-fired job. The
--       advisory lock alone does not help here (pg_net is
--       fire-and-forget), so we additionally consult
--       `cron_run_state.started_at` and skip if a previous fire
--       started within the safety window. The Edge Function (out of
--       this migration's scope) marks completion via
--       `fn_cron_mark_completed`; until then we treat it as in-flight.
--
-- Re-applied migrations are safe: every `cron.schedule` call is
-- preceded by a defensive `cron.unschedule` and the table uses
-- `CREATE TABLE IF NOT EXISTS`. The wrappers use
-- `CREATE OR REPLACE FUNCTION`.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. cron_run_state — single-row-per-job execution timeline
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cron_run_state (
  -- Job name. Matches the value passed to `cron.schedule(name, ...)`.
  name           text PRIMARY KEY,

  -- When the most recent run started. NULL = never run since gate
  -- introduction. Updated by `fn_cron_mark_started`.
  started_at     timestamptz,

  -- When the most recent run finished (or was marked timeout). NULL
  -- means the run is currently in flight OR the previous run never
  -- called `fn_cron_mark_completed/failed/timeout` (treat as orphan
  -- after `max_runtime_seconds` elapses).
  finished_at    timestamptz,

  -- Outcome of the most recent terminal mark.
  --   running    — started, not yet finished
  --   completed  — finished_at populated by mark_completed
  --   failed     — finished_at populated by mark_failed
  --   skipped    — fn_cron_should_run rejected the attempt
  --   timeout    — sweep flagged a stale `running` row past the window
  last_status    text NOT NULL DEFAULT 'never_run',

  -- Lifetime counters since gate introduction. Useful for ops to
  -- spot-check that the job is actually firing at the expected rate
  -- (e.g. `*/5` job over 24h → ~288 runs/day).
  run_count      bigint NOT NULL DEFAULT 0,
  skip_count     bigint NOT NULL DEFAULT 0,

  -- Last terminal error message, when last_status = failed. Truncated
  -- to a sane length to keep the row narrow.
  last_error     text,

  -- Free-form structured payload from the most recent run (e.g.
  -- `{"processed": 47}` for the matchmaking expirer). Inspected by
  -- the cron health runbook.
  last_meta      jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- When this row was first inserted (rarely useful, but cheap).
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),

  -- Last_status must be one of the canonical values. Anything else
  -- is a bug in a caller and we want it to fail loudly.
  CONSTRAINT cron_run_state_status_chk CHECK (
    last_status IN (
      'never_run','running','completed','failed','skipped','timeout'
    )
  ),

  -- finished_at must be ≥ started_at when both are present.
  CONSTRAINT cron_run_state_window_chk CHECK (
    finished_at IS NULL
    OR started_at IS NULL
    OR finished_at >= started_at
  )
);

COMMENT ON TABLE public.cron_run_state IS
  'L12-03: per-job execution state for pg_cron + edge-function crons. Read by fn_cron_should_run; updated by fn_cron_mark_* helpers.';

-- Cheap index for a "what ran recently across all jobs" view.
CREATE INDEX IF NOT EXISTS cron_run_state_updated_at_idx
  ON public.cron_run_state (updated_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Helper functions
-- ─────────────────────────────────────────────────────────────────────────────

-- Returns TRUE iff the job named `p_name` should fire NOW.
--
-- Rules:
--   - if no row exists → seed with `never_run` + return TRUE.
--   - if last_status = 'running' AND started_at > now() - max_runtime
--     → previous run still in safety window → skip.
--   - if last_status = 'running' AND started_at <= now() - max_runtime
--     → presumed orphan; mark `timeout` and ALLOW the new run.
--   - otherwise → return TRUE.
--
-- This function does NOT itself call `fn_cron_mark_started` — the
-- wrapper that consumes its return value is responsible for that
-- (so callers can do additional pre-flight work in between).
CREATE OR REPLACE FUNCTION public.fn_cron_should_run(
  p_name text,
  p_max_runtime_seconds int DEFAULT 600
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.cron_run_state%ROWTYPE;
BEGIN
  IF p_max_runtime_seconds IS NULL OR p_max_runtime_seconds <= 0 THEN
    RAISE EXCEPTION 'fn_cron_should_run: max_runtime_seconds must be positive';
  END IF;

  SELECT * INTO v_row FROM public.cron_run_state WHERE name = p_name;

  IF NOT FOUND THEN
    INSERT INTO public.cron_run_state(name) VALUES (p_name)
    ON CONFLICT (name) DO NOTHING;
    RETURN TRUE;
  END IF;

  IF v_row.last_status = 'running' THEN
    IF v_row.started_at IS NOT NULL
       AND v_row.started_at > now() - make_interval(secs => p_max_runtime_seconds)
    THEN
      -- Previous run still within safety window → skip this attempt.
      UPDATE public.cron_run_state
      SET    skip_count   = skip_count + 1,
             last_status  = 'skipped',
             updated_at   = now()
      WHERE  name = p_name;
      RETURN FALSE;
    ELSE
      -- Previous run is outside safety window. The mark_started call
      -- will record `running` again; we mark `timeout` here so ops
      -- can see that the previous run never reported terminal status.
      UPDATE public.cron_run_state
      SET    last_status  = 'timeout',
             finished_at  = now(),
             last_error   = 'presumed timeout: started_at past safety window',
             updated_at   = now()
      WHERE  name = p_name;
      RETURN TRUE;
    END IF;
  END IF;

  RETURN TRUE;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cron_should_run(text, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cron_should_run(text, int) TO service_role;

-- Mark a job as started. Idempotent in the same transaction
-- (multiple calls in one txn are pointless but harmless).
CREATE OR REPLACE FUNCTION public.fn_cron_mark_started(p_name text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.cron_run_state(name, started_at, last_status, run_count, updated_at)
  VALUES (p_name, now(), 'running', 1, now())
  ON CONFLICT (name) DO UPDATE
    SET started_at  = now(),
        finished_at = NULL,
        last_status = 'running',
        run_count   = public.cron_run_state.run_count + 1,
        last_error  = NULL,
        updated_at  = now();
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cron_mark_started(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cron_mark_started(text) TO service_role;

-- Mark a job as completed successfully. `p_meta` is merged on top of
-- the previous `last_meta` (jsonb concat semantics — keys in p_meta
-- win) so callers can add structured output without clobbering
-- standing keys.
CREATE OR REPLACE FUNCTION public.fn_cron_mark_completed(
  p_name text,
  p_meta jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.cron_run_state
  SET    finished_at = now(),
         last_status = 'completed',
         last_error  = NULL,
         last_meta   = COALESCE(last_meta, '{}'::jsonb) || COALESCE(p_meta, '{}'::jsonb),
         updated_at  = now()
  WHERE  name = p_name;

  IF NOT FOUND THEN
    -- Caller didn't go through mark_started — be permissive and
    -- create the row in a completed state. This keeps observability
    -- intact even if a future caller forgets the lifecycle pair.
    INSERT INTO public.cron_run_state(name, started_at, finished_at, last_status, run_count, last_meta)
    VALUES (p_name, now(), now(), 'completed', 1, COALESCE(p_meta, '{}'::jsonb));
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cron_mark_completed(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cron_mark_completed(text, jsonb) TO service_role;

-- Mark a job as failed. Truncates `p_error` to 4096 chars so the row
-- stays narrow even on long stack traces.
CREATE OR REPLACE FUNCTION public.fn_cron_mark_failed(
  p_name  text,
  p_error text,
  p_meta  jsonb DEFAULT '{}'::jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.cron_run_state
  SET    finished_at = now(),
         last_status = 'failed',
         last_error  = LEFT(COALESCE(p_error, '<no message>'), 4096),
         last_meta   = COALESCE(last_meta, '{}'::jsonb) || COALESCE(p_meta, '{}'::jsonb),
         updated_at  = now()
  WHERE  name = p_name;

  IF NOT FOUND THEN
    INSERT INTO public.cron_run_state(
      name, started_at, finished_at, last_status, run_count, last_error, last_meta
    )
    VALUES (
      p_name, now(), now(), 'failed', 1,
      LEFT(COALESCE(p_error, '<no message>'), 4096),
      COALESCE(p_meta, '{}'::jsonb)
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_cron_mark_failed(text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cron_mark_failed(text, text, jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Safe wrapper: fn_expire_queue_entries_safe
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Wraps the existing `fn_expire_queue_entries` with:
--   - cron_run_state should-run gate (skips if previous run within 4 min)
--   - pg_try_advisory_xact_lock for hard mutex inside Postgres
--   - mark_started / mark_completed / mark_failed lifecycle
--   - structured `last_meta` carrying processed row count
--
-- The advisory-lock key is `hashtext('cron:expire_matchmaking_queue')`.
-- Choosing a unique string per job avoids collisions with other
-- advisory_lock callers. We use the int4 hashtext form (single-key
-- variant) — collisions across the cron job set are extremely
-- unlikely for the small number of names we use.

CREATE OR REPLACE FUNCTION public.fn_expire_queue_entries_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_processed     int := 0;
BEGIN
  IF NOT public.fn_cron_should_run('expire-matchmaking-queue', 240) THEN
    -- Previous run still in safety window. fn_cron_should_run already
    -- bumped skip_count.
    RETURN;
  END IF;

  -- Belt-and-suspenders: even if the should-run gate said yes,
  -- another worker might race in. The advisory lock is the hard
  -- guarantee. xact-scope means it is auto-released at the end of
  -- this function's implicit transaction.
  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:expire_matchmaking_queue')
  );
  IF NOT v_lock_acquired THEN
    -- Race lost; previous worker still has the lock. Mark as skip
    -- so the run_count doesn't keep growing.
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'expire-matchmaking-queue';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('expire-matchmaking-queue');

  BEGIN
    -- Re-implement inline rather than calling the legacy function so
    -- we can capture the row count cheaply without an extra round-trip.
    WITH affected AS (
      UPDATE public.challenge_queue
         SET status = 'expired', updated_at = now()
       WHERE status = 'waiting'
         AND expires_at < now()
       RETURNING 1
    )
    SELECT count(*) INTO v_processed FROM affected;

    PERFORM public.fn_cron_mark_completed(
      'expire-matchmaking-queue',
      jsonb_build_object('processed', v_processed)
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'expire-matchmaking-queue',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE)
    );
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_expire_queue_entries_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_expire_queue_entries_safe() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Safe wrapper: fn_process_scheduled_releases_safe
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Same pattern as above, delegating to the existing
-- `fn_process_scheduled_releases` (which returns int = rows touched).

CREATE OR REPLACE FUNCTION public.fn_process_scheduled_releases_safe()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_processed     int := 0;
BEGIN
  IF NOT public.fn_cron_should_run('process-scheduled-workout-releases', 240) THEN
    RETURN 0;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:process_scheduled_releases')
  );
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'process-scheduled-workout-releases';
    RETURN 0;
  END IF;

  PERFORM public.fn_cron_mark_started('process-scheduled-workout-releases');

  BEGIN
    v_processed := public.fn_process_scheduled_releases();
    PERFORM public.fn_cron_mark_completed(
      'process-scheduled-workout-releases',
      jsonb_build_object('processed', v_processed)
    );
    RETURN v_processed;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'process-scheduled-workout-releases',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE)
    );
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_process_scheduled_releases_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_process_scheduled_releases_safe() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Safe HTTP-fired wrapper: fn_invoke_lifecycle_cron_safe
-- ─────────────────────────────────────────────────────────────────────────────
--
-- The `lifecycle-cron` Edge Function is fired with `extensions.http(...)`
-- which is fire-and-forget — pg_net queues the request and pg_cron
-- moves on. Two concerns we need to address:
--
--   (a) avoid stacking concurrent EF invocations when the EF runs
--       longer than 5 minutes (overlap risk per L12-03), and
--   (b) preserve the EF's existing health-check / observability
--       behaviour.
--
-- Strategy: the wrapper consults `cron_run_state` and only fires the
-- HTTP call if no in-flight invocation exists OR the previous one
-- is presumed timed out (started_at past 4 min — Edge Functions are
-- generally bounded at 60-150s on Supabase but we leave headroom).
-- We mark `started` here (NOT inside the EF — keeping the EF
-- untouched in this migration). We DO NOT mark `completed`; the
-- next fire that finds `started_at` outside the window will mark
-- `timeout` and proceed. This is acceptable because:
--   - the EF is idempotent at the row level (championship/challenge
--     state machines are state-guarded),
--   - `cron_run_state` is observability, not source of truth,
--   - a follow-up PR can add `mark_completed` calls inside the EF.
--
-- Once that follow-up lands, the `last_status = 'completed'` rows
-- will start appearing and the timeout branch will go quiet.

CREATE OR REPLACE FUNCTION public.fn_invoke_lifecycle_cron_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
BEGIN
  IF NOT public.fn_cron_should_run('lifecycle-cron', 240) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:lifecycle_cron_fire')
  );
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'lifecycle-cron';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('lifecycle-cron');

  -- Defensive: tolerate environments without pg_net (local dev).
  -- We don't call fn_cron_mark_failed here because absence of pg_net
  -- is structural, not an operational failure.
  BEGIN
    PERFORM extensions.http(
      (
        'POST',
        current_setting('app.settings.supabase_url') || '/functions/v1/lifecycle-cron',
        ARRAY[
          extensions.http_header('Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')),
          extensions.http_header('Content-Type', 'application/json')
        ],
        'application/json',
        '{}'
      )::extensions.http_request
    );
  EXCEPTION
    WHEN undefined_function OR undefined_table OR undefined_object THEN
      -- pg_net not installed in this environment; mark the run as
      -- completed with a meta flag so ops can see the no-op.
      PERFORM public.fn_cron_mark_completed(
        'lifecycle-cron',
        jsonb_build_object('skipped_reason', 'pg_net_unavailable')
      );
      RETURN;
    WHEN OTHERS THEN
      PERFORM public.fn_cron_mark_failed(
        'lifecycle-cron',
        SQLERRM,
        jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'http_fire')
      );
      RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_invoke_lifecycle_cron_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_lifecycle_cron_safe() TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Reschedule the three high-frequency jobs to use the *_safe versions
-- ─────────────────────────────────────────────────────────────────────────────
--
-- Re-scheduling is idempotent: each block tries to unschedule first,
-- swallows the not-found error, then schedules the safe wrapper. If
-- pg_cron is not present (local dev), the whole DO block is a no-op.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-03] pg_cron not installed; skipping reschedule';
    RETURN;
  END IF;

  -- expire-matchmaking-queue → fn_expire_queue_entries_safe
  BEGIN PERFORM cron.unschedule('expire-matchmaking-queue');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'expire-matchmaking-queue',
    '*/5 * * * *',
    $cron$ SELECT public.fn_expire_queue_entries_safe(); $cron$
  );

  -- process-scheduled-workout-releases → fn_process_scheduled_releases_safe
  BEGIN PERFORM cron.unschedule('process-scheduled-workout-releases');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'process-scheduled-workout-releases',
    '*/5 * * * *',
    $cron$ SELECT public.fn_process_scheduled_releases_safe(); $cron$
  );

  -- lifecycle-cron → fn_invoke_lifecycle_cron_safe
  BEGIN PERFORM cron.unschedule('lifecycle-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'lifecycle-cron',
    '*/5 * * * *',
    $cron$ SELECT public.fn_invoke_lifecycle_cron_safe(); $cron$
  );

  RAISE NOTICE '[L12-03] rescheduled 3 cron jobs to use *_safe wrappers';
END$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. RLS — cron_run_state is service-role-only
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.cron_run_state ENABLE ROW LEVEL SECURITY;

-- No policies = no rows visible. Service role bypasses RLS, which is
-- exactly what we want: only the cron helpers (SECURITY DEFINER) and
-- ops queries via supabase admin write/read this table.

REVOKE ALL ON public.cron_run_state FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.cron_run_state TO service_role;
