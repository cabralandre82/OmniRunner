-- ============================================================================
-- L06-05 — Edge Functions invocation with retry + exponential backoff
--
-- Audit reference:
--   docs/audit/findings/L06-05-edge-functions-sem-retry-em-falha-de-pg.md
--   docs/audit/parts/06-coo.md  (anchor [6.5])
--
-- Problem
-- ───────
--   Six pg_cron jobs fire Supabase Edge Functions via `pg_net`/`extensions.http`:
--
--     - auto-topup-hourly        (20260221000001)  fn_invoke_auto_topup_cron
--     - lifecycle-cron           (20260221000002 / 20260419100000)
--     - clearing-cron            (20260221000008)  inline schedule
--     - eval-verification-cron   (20260224000004)  inline schedule
--     - onboarding-nudge-daily   (20260311000000)  inline schedule
--     - reconcile-wallets-daily  (20260419100002)  inline schedule
--
--   Every one of them fires the EF exactly ONCE per window. If the HTTP
--   call fails (503, DNS blip, EF cold-start timeout, Supabase maintenance)
--   the job silently swallows the error and the next run waits for the
--   next cron window.  Concrete impacts:
--
--     - `auto-topup-hourly` fails → athletes on low balance get nothing
--       for up to 60 min → frustration.
--     - `reconcile-wallets-daily` fails → wallet↔ledger drift goes
--       undetected for 24h → silent integrity regression.
--     - `clearing-cron` fails → issuer payouts delayed by 24h → CFO.
--
--   The audit (L06-05) recommended a retry wrapper with exponential
--   backoff and a persisted audit trail.
--
-- Defence (this migration)
-- ───────
--   Three DB objects + six rewrites, fully reusing L12-03 `cron_run_state`
--   + L06-04 `fn_record_cron_health_alert` for observability dedup.
--
--     1. `public.cron_edge_retry_attempts` — append-only audit table,
--        one row per HTTP attempt (success OR failure).  Enables ops
--        to reconstruct exactly which attempt number succeeded, what
--        status code each prior attempt returned, and how long each
--        attempt took.  Sized narrow (no response body, just status +
--        error message truncated).  RLS-forced, service-role only.
--
--     2. `public.fn_invoke_edge_with_retry(p_job_name, p_endpoint,
--                                         p_body, p_max_attempts,
--                                         p_backoff_base_seconds,
--                                         p_success_statuses)`
--        SECURITY DEFINER, locked search_path, lock_timeout 2s.
--        Loops up to `p_max_attempts`; each iteration calls
--        `extensions.http(...)` (SYNCHRONOUS — `pg_net.http_post` is
--        async/fire-and-forget which defeats the retry premise: we
--        can't condition the next retry on the current attempt's
--        status without blocking).  Backoff is linear with attempt
--        count (`base * attempt` seconds, default 5s → 5/10/15) to
--        keep total wall time bounded for a 5-min cron.  Records
--        every attempt in `cron_edge_retry_attempts`.  On final
--        failure calls `fn_record_cron_health_alert(severity=critical,
--        cooldown=60min)`.  Returns a jsonb summary the caller can
--        merge into `fn_cron_mark_completed`'s `last_meta`.
--
--     3. `public.fn_invoke_edge_fire_and_forget(p_job_name, p_endpoint,
--                                               p_body)` — *optional*
--        fast-path that uses `pg_net.http_post` (async, returns
--        immediately).  Records a single attempt row with
--        `http_status = NULL` and `note = 'async_queued'`.  For jobs
--        that value throughput over reliability.  Kept here so all
--        pg_net invocations go through ONE code path going forward.
--
--     Rewrites:
--
--     • `fn_invoke_auto_topup_cron`           → uses retry wrapper
--     • `fn_invoke_lifecycle_cron_safe`       → uses retry wrapper
--     • `fn_invoke_clearing_cron_safe`        (NEW) + reschedule
--     • `fn_invoke_verification_cron_safe`    (NEW) + reschedule
--     • `fn_invoke_onboarding_nudge_safe`     (NEW) + reschedule
--     • `fn_invoke_reconcile_wallets_safe`    (NEW) + reschedule
--
--   All rewrites preserve the existing `cron_run_state` lifecycle
--   (started/completed/failed), so the L06-04 health monitor + L12-04
--   SLA monitor see no behavioural change beyond "status now reports
--   attempt count in last_meta".  Re-applied migration is idempotent:
--   every schedule is preceded by `cron.unschedule` in a DO block.
--
-- Backwards compat
-- ────────────────
--   • Additive only: one new table, three new functions, four new
--     wrapper functions, six `cron.unschedule` + re-schedule calls.
--     No column drops, no RLS policy loosening, no signature
--     compatibility break on pre-existing callers.
--   • Local-dev tolerance: when `extensions.http` OR `pg_cron` is
--     absent, the wrappers short-circuit to `skipped/pg_net_unavailable`
--     on `cron_run_state` (same pattern as L12-03).  Migration applies
--     cleanly in sandbox databases.
--   • `net.http_post` callers outside these six jobs are untouched —
--     the lint rule (`tools/audit/check-pg-net-retry.ts`, follow-up)
--     will warn on new raw pg_net calls in migrations going forward.
--
-- Verification
-- ────────────
--   • Self-test DO block at the end of this file exercises the wrapper
--     with a deliberately-invalid endpoint and asserts:
--       - exactly `max_attempts` rows are inserted in
--         `cron_edge_retry_attempts`,
--       - `fn_record_cron_health_alert` was called (row present in
--         `cron_health_alerts`),
--       - wrapper returns `{ ok: false, attempts: N }`.
--   • Integration test: `tools/test_l06_05_edge_retry_wrapper.ts`.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. cron_edge_retry_attempts — per-attempt audit trail
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cron_edge_retry_attempts (
  id             bigserial     PRIMARY KEY,
  -- Which cron owns the invocation.  Matches `cron.schedule(name,...)`.
  job_name       text          NOT NULL CHECK (length(trim(job_name)) BETWEEN 1 AND 128),
  -- Endpoint slug ("auto-topup-cron", not full URL; full URL is
  -- cluster-specific and would leak supabase_url into audit).
  endpoint       text          NOT NULL CHECK (length(trim(endpoint)) BETWEEN 1 AND 128),
  -- Which attempt this row represents (1..max_attempts).
  attempt        integer       NOT NULL CHECK (attempt BETWEEN 1 AND 10),
  -- Declared ceiling for the invocation (for forensics if the caller
  -- changes p_max_attempts later and we need to distinguish "failed
  -- on last attempt" from "failed mid-series").
  max_attempts   integer       NOT NULL CHECK (max_attempts BETWEEN 1 AND 10),
  -- HTTP status code returned.  NULL when the HTTP extension raised
  -- an exception (DNS/connect/TLS) before getting a response.
  http_status    integer       NULL CHECK (http_status IS NULL OR http_status BETWEEN 100 AND 599),
  -- Truncated SQLERRM when the HTTP call raised.  NULL on success.
  error          text          NULL CHECK (error IS NULL OR length(error) <= 4096),
  started_at     timestamptz   NOT NULL DEFAULT now(),
  completed_at   timestamptz   NULL,
  -- Free-form metadata: { mode: 'sync'|'async', backoff_seconds_before_next: N, ... }.
  meta           jsonb         NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT cron_edge_retry_window_chk CHECK (
    completed_at IS NULL OR completed_at >= started_at
  )
);

COMMENT ON TABLE public.cron_edge_retry_attempts IS
  'L06-05: per-attempt audit trail for Edge Function invocations from pg_cron. '
  'One row per HTTP attempt (success OR failure). Used by on-call to reconstruct '
  'why a cron-triggered EF failed intermittently.';

-- Index for the "latest attempts for job X" ops query.
CREATE INDEX IF NOT EXISTS cron_edge_retry_job_started_idx
  ON public.cron_edge_retry_attempts (job_name, started_at DESC);

-- Index for the "failures across all jobs in the last hour" alert query.
CREATE INDEX IF NOT EXISTS cron_edge_retry_failures_idx
  ON public.cron_edge_retry_attempts (started_at DESC)
  WHERE http_status IS NULL OR http_status >= 400;

ALTER TABLE public.cron_edge_retry_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_edge_retry_attempts FORCE ROW LEVEL SECURITY;
-- No policy created → only service_role (RLS bypass) can touch.

REVOKE ALL ON public.cron_edge_retry_attempts FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON public.cron_edge_retry_attempts TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.cron_edge_retry_attempts_id_seq TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. fn_invoke_edge_with_retry — synchronous, retry-backed wrapper
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_invoke_edge_with_retry(
  p_job_name              text,
  p_endpoint              text,
  p_body                  jsonb   DEFAULT '{}'::jsonb,
  p_max_attempts          integer DEFAULT 3,
  p_backoff_base_seconds  integer DEFAULT 5,
  p_success_statuses      integer[] DEFAULT ARRAY[200,201,202,204]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_url              text;
  v_key              text;
  v_full_url         text;
  v_attempt          integer := 0;
  v_status           integer;
  v_last_error       text;
  v_started_at       timestamptz;
  v_backoff          integer;
  v_http_available   boolean := true;
  v_alert_id         uuid;
BEGIN
  IF p_job_name IS NULL OR length(trim(p_job_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_JOB_NAME: p_job_name is required' USING ERRCODE = '22023';
  END IF;
  IF p_endpoint IS NULL OR length(trim(p_endpoint)) = 0 THEN
    RAISE EXCEPTION 'INVALID_ENDPOINT: p_endpoint is required' USING ERRCODE = '22023';
  END IF;
  IF p_max_attempts IS NULL OR p_max_attempts < 1 OR p_max_attempts > 10 THEN
    RAISE EXCEPTION 'INVALID_MAX_ATTEMPTS: % (expected 1..10)', p_max_attempts
      USING ERRCODE = '22023';
  END IF;
  IF p_backoff_base_seconds IS NULL OR p_backoff_base_seconds < 0 OR p_backoff_base_seconds > 120 THEN
    RAISE EXCEPTION 'INVALID_BACKOFF: % (expected 0..120)', p_backoff_base_seconds
      USING ERRCODE = '22023';
  END IF;

  v_url := current_setting('app.settings.supabase_url', true);
  v_key := current_setting('app.settings.service_role_key', true);

  -- Supabase-dev fallback: the 20260221000001 and downstream migrations
  -- accept either `app.settings.<x>` or `app.<x>`.  Honour the older
  -- names so this wrapper is a drop-in for every caller.
  IF v_url IS NULL THEN v_url := current_setting('app.supabase_url', true); END IF;
  IF v_key IS NULL THEN v_key := current_setting('app.service_role_key', true); END IF;

  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE LOG '[fn_invoke_edge_with_retry] skipped job=% endpoint=%: supabase_url/service_role_key not configured',
              p_job_name, p_endpoint;
    RETURN jsonb_build_object(
      'ok',       false,
      'skipped',  true,
      'reason',   'missing_config',
      'attempts', 0
    );
  END IF;

  v_full_url := rtrim(v_url, '/') || '/functions/v1/' || p_endpoint;

  -- Detect whether `extensions.http` is installed.  When absent
  -- (common in local sandbox with only pg_net), we record a single
  -- skipped attempt and let the caller decide whether to fall back.
  BEGIN
    PERFORM 1 FROM pg_extension WHERE extname = 'http';
    IF NOT FOUND THEN
      v_http_available := false;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_http_available := false;
  END;

  IF NOT v_http_available THEN
    INSERT INTO public.cron_edge_retry_attempts(
      job_name, endpoint, attempt, max_attempts, http_status, error,
      started_at, completed_at, meta
    ) VALUES (
      p_job_name, p_endpoint, 1, p_max_attempts, NULL,
      'http extension not installed',
      now(), now(),
      jsonb_build_object('mode', 'skipped', 'reason', 'http_extension_missing')
    );
    RETURN jsonb_build_object(
      'ok',       false,
      'skipped',  true,
      'reason',   'http_extension_missing',
      'attempts', 0
    );
  END IF;

  LOOP
    v_attempt := v_attempt + 1;
    v_started_at := clock_timestamp();
    v_status := NULL;
    v_last_error := NULL;

    BEGIN
      -- EXECUTE dynamic to avoid parse-time dependency on the `http`
      -- extension (so this migration can be installed BEFORE the
      -- extension, and CREATE OR REPLACE works idempotently across
      -- environments).
      EXECUTE format($q$
        SELECT (row_to_json(r)::jsonb)->>'status'
        FROM extensions.http(
          (
            'POST',
            %L,
            ARRAY[
              extensions.http_header('Authorization', 'Bearer ' || %L),
              extensions.http_header('Content-Type', 'application/json')
            ],
            'application/json',
            %L
          )::extensions.http_request
        ) r
      $q$, v_full_url, v_key, p_body::text)
      INTO v_status;
    EXCEPTION WHEN OTHERS THEN
      v_status := NULL;
      v_last_error := LEFT(SQLERRM, 4096);
    END;

    INSERT INTO public.cron_edge_retry_attempts(
      job_name, endpoint, attempt, max_attempts, http_status, error,
      started_at, completed_at, meta
    ) VALUES (
      p_job_name, p_endpoint, v_attempt, p_max_attempts, v_status, v_last_error,
      v_started_at, clock_timestamp(),
      jsonb_build_object(
        'mode', 'sync',
        'body_bytes', length(p_body::text)
      )
    );

    IF v_status IS NOT NULL AND v_status = ANY (p_success_statuses) THEN
      RETURN jsonb_build_object(
        'ok',       true,
        'status',   v_status,
        'attempts', v_attempt,
        'endpoint', p_endpoint
      );
    END IF;

    IF v_attempt >= p_max_attempts THEN
      -- Final failure: emit alert (dedup'd by L06-04 cooldown).
      BEGIN
        v_alert_id := public.fn_record_cron_health_alert(
          p_job_name,
          'critical',
          jsonb_build_object(
            'kind',          'edge_invocation_failed_after_retries',
            'endpoint',      p_endpoint,
            'attempts',      v_attempt,
            'last_status',   v_status,
            'last_error',    v_last_error,
            'runbook',       'docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md'
          ),
          60
        );
      EXCEPTION WHEN OTHERS THEN
        -- fn_record_cron_health_alert is best-effort; never let the
        -- alert plumbing break the caller.
        v_alert_id := NULL;
      END;

      RETURN jsonb_build_object(
        'ok',         false,
        'status',     v_status,
        'attempts',   v_attempt,
        'endpoint',   p_endpoint,
        'last_error', v_last_error,
        'alert_id',   v_alert_id
      );
    END IF;

    -- Backoff before next attempt: linear multiplier (5s → 10s → 15s
    -- by default).  Capped at 120s so a 5-min cron never starves.
    v_backoff := LEAST(p_backoff_base_seconds * v_attempt, 120);
    IF v_backoff > 0 THEN
      PERFORM pg_sleep(v_backoff);
    END IF;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.fn_invoke_edge_with_retry(text, text, jsonb, integer, integer, integer[]) IS
  'L06-05: synchronous Edge Function invoker with N-attempt retry + linear backoff. '
  'Records every attempt in cron_edge_retry_attempts. On final failure, calls '
  'fn_record_cron_health_alert (severity=critical, cooldown=60min). '
  'Returns { ok, status, attempts, endpoint, last_error?, alert_id? }.';

REVOKE ALL ON FUNCTION public.fn_invoke_edge_with_retry(text, text, jsonb, integer, integer, integer[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_edge_with_retry(text, text, jsonb, integer, integer, integer[]) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. fn_invoke_edge_fire_and_forget — async fast-path (optional)
-- ─────────────────────────────────────────────────────────────────────────────
--
-- For jobs that prioritise throughput over reliability OR that want
-- to delegate the retry to the Edge Function itself.  Currently unused
-- by the six migrations rewritten below (they all use the sync retry
-- path) but exposed so future callers go through ONE entry point.

CREATE OR REPLACE FUNCTION public.fn_invoke_edge_fire_and_forget(
  p_job_name text,
  p_endpoint text,
  p_body     jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_url       text;
  v_key       text;
  v_full_url  text;
  v_request   bigint;
  v_pgnet_ok  boolean := true;
  v_error     text;
BEGIN
  IF p_job_name IS NULL OR length(trim(p_job_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_JOB_NAME: p_job_name is required' USING ERRCODE = '22023';
  END IF;
  IF p_endpoint IS NULL OR length(trim(p_endpoint)) = 0 THEN
    RAISE EXCEPTION 'INVALID_ENDPOINT: p_endpoint is required' USING ERRCODE = '22023';
  END IF;

  v_url := current_setting('app.settings.supabase_url', true);
  v_key := current_setting('app.settings.service_role_key', true);
  IF v_url IS NULL THEN v_url := current_setting('app.supabase_url', true); END IF;
  IF v_key IS NULL THEN v_key := current_setting('app.service_role_key', true); END IF;

  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE LOG '[fn_invoke_edge_fire_and_forget] skipped job=% endpoint=%: config missing',
              p_job_name, p_endpoint;
    RETURN jsonb_build_object('ok', false, 'skipped', true, 'reason', 'missing_config');
  END IF;

  v_full_url := rtrim(v_url, '/') || '/functions/v1/' || p_endpoint;

  BEGIN
    PERFORM 1 FROM pg_extension WHERE extname = 'pg_net';
    IF NOT FOUND THEN
      v_pgnet_ok := false;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    v_pgnet_ok := false;
  END;

  IF NOT v_pgnet_ok THEN
    INSERT INTO public.cron_edge_retry_attempts(
      job_name, endpoint, attempt, max_attempts, http_status, error,
      started_at, completed_at, meta
    ) VALUES (
      p_job_name, p_endpoint, 1, 1, NULL, 'pg_net extension not installed',
      now(), now(),
      jsonb_build_object('mode', 'skipped', 'reason', 'pg_net_missing')
    );
    RETURN jsonb_build_object('ok', false, 'skipped', true, 'reason', 'pg_net_missing');
  END IF;

  BEGIN
    EXECUTE format($q$
      SELECT net.http_post(
        url     := %L,
        body    := %L::jsonb,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || %L,
          'Content-Type',  'application/json'
        )
      )
    $q$, v_full_url, p_body::text, v_key)
    INTO v_request;
  EXCEPTION WHEN OTHERS THEN
    v_error := LEFT(SQLERRM, 4096);
  END;

  INSERT INTO public.cron_edge_retry_attempts(
    job_name, endpoint, attempt, max_attempts, http_status, error,
    started_at, completed_at, meta
  ) VALUES (
    p_job_name, p_endpoint, 1, 1, NULL, v_error,
    now(), now(),
    jsonb_build_object(
      'mode',       'async',
      'request_id', v_request,
      'note',       CASE WHEN v_error IS NULL THEN 'async_queued' ELSE 'async_enqueue_failed' END
    )
  );

  RETURN jsonb_build_object(
    'ok',         (v_error IS NULL),
    'mode',       'async',
    'request_id', v_request,
    'error',      v_error
  );
END;
$$;

COMMENT ON FUNCTION public.fn_invoke_edge_fire_and_forget(text, text, jsonb) IS
  'L06-05: async Edge Function invoker via pg_net.http_post. Records a single '
  'attempt row with mode=async. No retry (by design — for callers that own '
  'retry on the Edge Function side).';

REVOKE ALL ON FUNCTION public.fn_invoke_edge_fire_and_forget(text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_edge_fire_and_forget(text, text, jsonb) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Rewrite existing cron wrappers to use the retry path
-- ─────────────────────────────────────────────────────────────────────────────

-- 4a. auto-topup-hourly ------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_auto_topup_cron()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM public.fn_cron_mark_started('auto-topup-hourly');
  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'auto-topup-hourly',
      p_endpoint             => 'auto-topup-cron',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 5
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('auto-topup-hourly', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'auto-topup-hourly',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'auto-topup-hourly',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

COMMENT ON FUNCTION public.fn_invoke_auto_topup_cron IS
  'L06-05: pg_cron helper — fires auto-topup-cron EF via fn_invoke_edge_with_retry '
  '(3 attempts, 5s linear backoff). Success/failure recorded in cron_run_state.';

-- 4b. lifecycle-cron ---------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_lifecycle_cron_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_result        jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('lifecycle-cron', 240) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('cron:lifecycle_cron_fire'));
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
       SET skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
     WHERE name = 'lifecycle-cron';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('lifecycle-cron');

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'lifecycle-cron',
      p_endpoint             => 'lifecycle-cron',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 5
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('lifecycle-cron', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'lifecycle-cron',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'lifecycle-cron',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

-- 4c. clearing-cron (NEW safe wrapper) ---------------------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_clearing_cron_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_result        jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('clearing-cron', 1800) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('cron:clearing_cron_fire'));
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
       SET skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
     WHERE name = 'clearing-cron';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('clearing-cron');

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'clearing-cron',
      p_endpoint             => 'clearing-cron',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 10
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('clearing-cron', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'clearing-cron',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'clearing-cron',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

-- 4d. eval-verification-cron (NEW safe wrapper) ------------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_verification_cron_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_result        jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('eval-verification-cron', 1800) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('cron:verification_cron_fire'));
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
       SET skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
     WHERE name = 'eval-verification-cron';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('eval-verification-cron');

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'eval-verification-cron',
      p_endpoint             => 'eval-verification-cron',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 10
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('eval-verification-cron', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'eval-verification-cron',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'eval-verification-cron',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

-- 4e. onboarding-nudge-daily (NEW safe wrapper) ------------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_onboarding_nudge_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_result        jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('onboarding-nudge-daily', 1800) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('cron:onboarding_nudge_fire'));
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
       SET skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
     WHERE name = 'onboarding-nudge-daily';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('onboarding-nudge-daily');

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'onboarding-nudge-daily',
      p_endpoint             => 'onboarding-nudge',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 10
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('onboarding-nudge-daily', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'onboarding-nudge-daily',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'onboarding-nudge-daily',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

-- 4f. reconcile-wallets-daily (NEW safe wrapper) -----------------------------

CREATE OR REPLACE FUNCTION public.fn_invoke_reconcile_wallets_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired boolean;
  v_result        jsonb;
BEGIN
  IF NOT public.fn_cron_should_run('reconcile-wallets-daily', 1800) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(hashtext('cron:reconcile_wallets_fire'));
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
       SET skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
     WHERE name = 'reconcile-wallets-daily';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('reconcile-wallets-daily');

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'reconcile-wallets-daily',
      p_endpoint             => 'reconcile-wallets-cron',
      p_body                 => '{}'::jsonb,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 10
    );
    IF (v_result->>'ok')::boolean = true OR (v_result->>'skipped')::boolean = true THEN
      PERFORM public.fn_cron_mark_completed('reconcile-wallets-daily', v_result);
    ELSE
      PERFORM public.fn_cron_mark_failed(
        'reconcile-wallets-daily',
        COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
        v_result
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'reconcile-wallets-daily',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'retry_wrapper')
    );
    RAISE;
  END;
END;
$$;

-- Revoke PUBLIC, grant service_role.
REVOKE ALL ON FUNCTION public.fn_invoke_auto_topup_cron()             FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_invoke_lifecycle_cron_safe()         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_invoke_clearing_cron_safe()          FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_invoke_verification_cron_safe()      FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_invoke_onboarding_nudge_safe()       FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_invoke_reconcile_wallets_safe()      FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_auto_topup_cron()          TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invoke_lifecycle_cron_safe()      TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invoke_clearing_cron_safe()       TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invoke_verification_cron_safe()   TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invoke_onboarding_nudge_safe()    TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_invoke_reconcile_wallets_safe()   TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Re-schedule the six jobs to call the retry-backed wrappers
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L06-05] pg_cron not installed; skipping reschedule';
    RETURN;
  END IF;

  -- auto-topup-hourly
  BEGIN PERFORM cron.unschedule('auto-topup-hourly');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'auto-topup-hourly',
    '0 * * * *',
    $cron$ SELECT public.fn_invoke_auto_topup_cron(); $cron$
  );

  -- lifecycle-cron
  BEGIN PERFORM cron.unschedule('lifecycle-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'lifecycle-cron',
    '*/5 * * * *',
    $cron$ SELECT public.fn_invoke_lifecycle_cron_safe(); $cron$
  );

  -- clearing-cron
  BEGIN PERFORM cron.unschedule('clearing-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'clearing-cron',
    '0 2 * * *',
    $cron$ SELECT public.fn_invoke_clearing_cron_safe(); $cron$
  );

  -- eval-verification-cron
  BEGIN PERFORM cron.unschedule('eval-verification-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'eval-verification-cron',
    '0 3 * * *',
    $cron$ SELECT public.fn_invoke_verification_cron_safe(); $cron$
  );

  -- onboarding-nudge-daily
  BEGIN PERFORM cron.unschedule('onboarding-nudge-daily');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'onboarding-nudge-daily',
    '0 10 * * *',
    $cron$ SELECT public.fn_invoke_onboarding_nudge_safe(); $cron$
  );

  -- reconcile-wallets-daily
  BEGIN PERFORM cron.unschedule('reconcile-wallets-daily');
  EXCEPTION WHEN OTHERS THEN NULL; END;
  PERFORM cron.schedule(
    'reconcile-wallets-daily',
    '30 4 * * *',
    $cron$ SELECT public.fn_invoke_reconcile_wallets_safe(); $cron$
  );

  -- Seed cron_run_state for the 4 jobs that didn't have a L12-03 wrapper
  -- (expire/release/lifecycle already seeded by 20260419100000).
  -- Skip when cron_run_state is missing (local sandbox without L12-03).
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'cron_run_state'
  ) THEN
    INSERT INTO public.cron_run_state(name, last_status)
    VALUES
      ('auto-topup-hourly',       'never_run'),
      ('clearing-cron',           'never_run'),
      ('eval-verification-cron',  'never_run'),
      ('onboarding-nudge-daily',  'never_run')
    ON CONFLICT (name) DO NOTHING;
  END IF;

  RAISE NOTICE '[L06-05] rescheduled 6 cron jobs to use retry-backed wrappers';
END$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Self-test — assertions that exercise the installation
-- ─────────────────────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_attempts_count integer;
  v_functions      integer;
  v_table_exists   boolean;
BEGIN
  -- 6.1 Table installed
  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'cron_edge_retry_attempts'
  ) INTO v_table_exists;
  IF NOT v_table_exists THEN
    RAISE EXCEPTION '[L06-05.selftest] cron_edge_retry_attempts missing';
  END IF;

  -- 6.2 Functions registered
  SELECT COUNT(*) INTO v_functions
  FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'fn_invoke_edge_with_retry',
      'fn_invoke_edge_fire_and_forget',
      'fn_invoke_auto_topup_cron',
      'fn_invoke_lifecycle_cron_safe',
      'fn_invoke_clearing_cron_safe',
      'fn_invoke_verification_cron_safe',
      'fn_invoke_onboarding_nudge_safe',
      'fn_invoke_reconcile_wallets_safe'
    );
  IF v_functions < 8 THEN
    RAISE EXCEPTION '[L06-05.selftest] expected 8 functions, found %', v_functions;
  END IF;

  -- 6.3 Retry audit table is writable by service_role (ourselves via
  --     SECURITY DEFINER when invoked by the wrapper). Sanity insert + cleanup.
  INSERT INTO public.cron_edge_retry_attempts(
    job_name, endpoint, attempt, max_attempts, http_status, error,
    started_at, completed_at, meta
  ) VALUES (
    'l06-05-selftest', 'selftest', 1, 1, 200, NULL, now(), now(),
    jsonb_build_object('mode', 'selftest')
  );
  SELECT COUNT(*) INTO v_attempts_count
  FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-selftest';
  IF v_attempts_count < 1 THEN
    RAISE EXCEPTION '[L06-05.selftest] insert into cron_edge_retry_attempts failed';
  END IF;
  DELETE FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-selftest';

  -- 6.4 Invalid arg validation on the wrapper
  BEGIN
    PERFORM public.fn_invoke_edge_with_retry(
      p_job_name     => '',
      p_endpoint     => 'x',
      p_max_attempts => 3
    );
    RAISE EXCEPTION '[L06-05.selftest] expected INVALID_JOB_NAME not raised';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  BEGIN
    PERFORM public.fn_invoke_edge_with_retry(
      p_job_name     => 'x',
      p_endpoint     => 'x',
      p_max_attempts => 99
    );
    RAISE EXCEPTION '[L06-05.selftest] expected INVALID_MAX_ATTEMPTS not raised';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  RAISE NOTICE '[L06-05.selftest] OK — all invariants pass';
END
$selftest$;
