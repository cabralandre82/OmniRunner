-- L12-08: clearing-cron deterministic cutoff in BR timezone
--
-- Problem
-- ───────
--   `clearing-cron` was scheduled at 02:00 UTC = 23:00 BRT (UTC-3).
--   Consequences:
--     a) Ledger entries created between 23:00 BRT and 00:00 BRT are
--        "in today BRT" from the user's perspective but already in
--        yesterday UTC from the cron's perspective. A run kicked at
--        02:00:00 UTC captures them; a run kicked at 02:00:05 UTC
--        (pg_cron jitter) captures different content because `now()`
--        moved — the cutoff was tied to wallclock rather than a
--        deterministic day boundary.
--     b) For Brazilian users (the product's primary audience), the
--        consolidation cutoff happens *before* their civil day ends,
--        so a loss in the last hour of the BRT day appears only in
--        the *next* week's clearing run — off-by-one reporting for
--        clubs and auditors.
--
--   The audit's proposed fix is deterministic, TZ-anchored cutoffs:
--   aggregate WHERE `created_at < date_trunc('day', now() AT TIME
--   ZONE <tz>)`. Implement that here and document the contract so
--   any future aggregator (SQL or Edge Function) uses the same clock.
--
-- Defence (this migration)
-- ───────
--   1. `public.fn_clearing_cutoff_utc(p_timezone, p_as_of)`
--      IMMUTABLE/STABLE helper that returns the start of today in
--      the given TZ, expressed in UTC. Callers that want "everything
--      up to but excluding today" use this as the upper bound:
--
--          WHERE created_at < public.fn_clearing_cutoff_utc('America/Sao_Paulo')
--
--      Returns a `timestamptz` so PostgREST serialises to ISO-8601
--      without TZ gymnastics.
--
--   2. Reschedule `clearing-cron` from `0 2 * * *` (02:00 UTC =
--      23:00 BRT, **before** BRT midnight) to `15 3 * * *` (03:15
--      UTC = 00:15 BRT, **after** BRT midnight + 15 min offset to
--      dodge the 03:00 UTC thundering herd from L12-02). The L12-02
--      `cron_sla_thresholds` entry for `clearing-cron` is NOT
--      changed (schedule is scoped to tested latency, not time-of-day).
--
--   3. Rewrite `fn_invoke_clearing_cron_safe()` to:
--        - compute `v_cutoff_utc` via the new helper
--        - pass it in the Edge Function body as
--          `{ "cutoff_utc": "...", "timezone": "America/Sao_Paulo" }`
--        - persist the cutoff in `cron_run_state.last_meta` so ops
--          can answer "what window did yesterday's run close?" in
--          one SELECT.
--      The Edge Function doesn't exist in the repo yet (tracked as a
--      separate follow-up), but if/when it materialises, the body
--      contract is now explicit and testable.
--
--   4. Self-test + grants.
--
-- Interaction with existing code
-- ───────
--   - `fn_settle_clearing_batch_safe` (L02-10) uses a rolling window
--     of `[now() - p_window_hours, now())`. That window is bounded
--     (168 h default) — it doesn't care about calendar days. This
--     migration does NOT change its cutoff logic; L12-08 is about
--     the CRON AGGREGATOR, not the SETTLE BATCH runner.
--   - L06-05's `fn_invoke_clearing_cron_safe` shape and return
--     contract stay identical; we only change what we put in the
--     body and `last_meta`.
--
-- Tests
-- ───────
--   tools/test_l12_08_clearing_cron_deterministic_cutoff.ts

SET search_path = public, pg_catalog, pg_temp;
SET client_min_messages = warning;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. fn_clearing_cutoff_utc — deterministic start-of-today helper
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_clearing_cutoff_utc(
  p_timezone text        DEFAULT 'America/Sao_Paulo',
  p_as_of    timestamptz DEFAULT NULL
) RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_as_of  timestamptz;
  v_local  timestamp;
  v_cutoff timestamptz;
BEGIN
  IF p_timezone IS NULL OR length(trim(p_timezone)) = 0 THEN
    RAISE EXCEPTION 'INVALID_TIMEZONE: p_timezone is required'
      USING ERRCODE = '22023';
  END IF;

  -- Validate the TZ (reuse L12-07 helper if installed, otherwise
  -- fall through to the AT TIME ZONE call which will raise on error).
  IF NOT public.fn_is_valid_timezone(p_timezone) THEN
    RAISE EXCEPTION 'INVALID_TIMEZONE: % is not a valid IANA zone', p_timezone
      USING ERRCODE = '22023';
  END IF;

  v_as_of := COALESCE(p_as_of, now());

  -- Convert v_as_of (UTC timestamptz) into local wall time for p_timezone.
  v_local := v_as_of AT TIME ZONE p_timezone;

  -- Truncate to midnight local, then flip back to UTC.
  v_cutoff := date_trunc('day', v_local) AT TIME ZONE p_timezone;

  RETURN v_cutoff;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_clearing_cutoff_utc(text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_clearing_cutoff_utc(text, timestamptz)
  TO service_role;

COMMENT ON FUNCTION public.fn_clearing_cutoff_utc(text, timestamptz) IS
  'L12-08: deterministic start-of-today in the given IANA TZ, returned '
  'as UTC timestamptz. Aggregators use this as the strict upper bound '
  'when building a "D-1" clearing window (WHERE created_at < cutoff).';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Rewrite fn_invoke_clearing_cron_safe — deterministic body + meta
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_invoke_clearing_cron_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_have_lock     boolean;
  v_result        jsonb;
  v_cutoff_utc    timestamptz;
  v_timezone      text := 'America/Sao_Paulo';
  v_body          jsonb;
  v_cron_state    boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
     WHERE n.nspname = 'public' AND c.relname = 'cron_run_state'
  ) INTO v_cron_state;

  IF v_cron_state THEN
    IF NOT public.fn_cron_should_run('clearing-cron', 1800) THEN
      RETURN;
    END IF;
  END IF;

  v_have_lock := pg_try_advisory_xact_lock(hashtext('cron:clearing_fire'));
  IF NOT v_have_lock THEN
    IF v_cron_state THEN
      UPDATE public.cron_run_state
         SET last_finished_at = now(),
             last_status      = 'skipped',
             updated_at       = now()
       WHERE name = 'clearing-cron';
    END IF;
    RETURN;
  END IF;

  v_cutoff_utc := public.fn_clearing_cutoff_utc(v_timezone);
  v_body := jsonb_build_object(
    'cutoff_utc', to_char(v_cutoff_utc AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'timezone',   v_timezone,
    'run_kind',   'daily_aggregate'
  );

  IF v_cron_state THEN
    PERFORM public.fn_cron_mark_started('clearing-cron');
  END IF;

  BEGIN
    v_result := public.fn_invoke_edge_with_retry(
      p_job_name             => 'clearing-cron',
      p_endpoint             => 'clearing-cron',
      p_body                 => v_body,
      p_max_attempts         => 3,
      p_backoff_base_seconds => 10
    );

    IF v_cron_state THEN
      IF (v_result->>'ok')::boolean = true
         OR (v_result->>'skipped')::boolean = true THEN
        PERFORM public.fn_cron_mark_completed(
          'clearing-cron',
          v_result || jsonb_build_object(
            'cutoff_utc', v_body->'cutoff_utc',
            'timezone',   v_body->'timezone'
          )
        );
      ELSE
        PERFORM public.fn_cron_mark_failed(
          'clearing-cron',
          COALESCE(v_result->>'last_error', 'edge invocation failed after retries'),
          v_result || jsonb_build_object(
            'cutoff_utc', v_body->'cutoff_utc',
            'timezone',   v_body->'timezone'
          )
        );
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    IF v_cron_state THEN
      PERFORM public.fn_cron_mark_failed(
        'clearing-cron',
        SQLERRM,
        jsonb_build_object(
          'sqlstate',   SQLSTATE,
          'phase',      'retry_wrapper',
          'cutoff_utc', v_body->'cutoff_utc',
          'timezone',   v_body->'timezone'
        )
      );
    END IF;
    RAISE;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_invoke_clearing_cron_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_invoke_clearing_cron_safe()
  TO service_role;

COMMENT ON FUNCTION public.fn_invoke_clearing_cron_safe() IS
  'L06-05 + L12-08: cron entry point for clearing-cron. Uses retry '
  'wrapper + cron_run_state lifecycle + TZ-anchored cutoff in body.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Reschedule clearing-cron: 0 2 * * * (23:00 BRT) → 15 3 * * * (00:15 BRT)
-- ─────────────────────────────────────────────────────────────────────────────

DO $reschedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-08] pg_cron not installed; skipping reschedule.';
    RETURN;
  END IF;

  BEGIN PERFORM cron.unschedule('clearing-cron');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  PERFORM cron.schedule(
    'clearing-cron',
    '15 3 * * *',
    $cron$ SELECT public.fn_invoke_clearing_cron_safe(); $cron$
  );

  RAISE NOTICE '[L12-08] clearing-cron rescheduled to 15 3 * * * (00:15 BRT, 15 min after midnight America/Sao_Paulo).';
END$reschedule$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Self-test
-- ─────────────────────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_cutoff   timestamptz;
  v_schedule text;
  v_fn_ok    boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
     WHERE n.nspname = 'public' AND p.proname = 'fn_clearing_cutoff_utc'
  ) INTO v_fn_ok;
  IF NOT v_fn_ok THEN
    RAISE EXCEPTION 'L12-08: fn_clearing_cutoff_utc not registered';
  END IF;

  -- Cutoff for a known timestamp in BRT. 2026-04-21 05:00 UTC
  -- (= 02:00 BRT) → start-of-BRT-day = 2026-04-21 03:00 UTC.
  v_cutoff := public.fn_clearing_cutoff_utc(
    'America/Sao_Paulo',
    '2026-04-21 05:00:00+00'::timestamptz);
  IF v_cutoff <> '2026-04-21 03:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'L12-08: cutoff on 2026-04-21 05:00 UTC expected 2026-04-21 03:00 UTC, got %',
      v_cutoff;
  END IF;

  -- Cutoff for 2026-04-21 02:00 UTC (= 2026-04-20 23:00 BRT, still
  -- "yesterday BRT") → start-of-BRT-day = 2026-04-20 03:00 UTC.
  v_cutoff := public.fn_clearing_cutoff_utc(
    'America/Sao_Paulo',
    '2026-04-21 02:00:00+00'::timestamptz);
  IF v_cutoff <> '2026-04-20 03:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'L12-08: cutoff on 2026-04-21 02:00 UTC expected 2026-04-20 03:00 UTC, got %',
      v_cutoff;
  END IF;

  -- UTC timezone should return the UTC midnight unchanged.
  v_cutoff := public.fn_clearing_cutoff_utc(
    'UTC',
    '2026-04-21 05:00:00+00'::timestamptz);
  IF v_cutoff <> '2026-04-21 00:00:00+00'::timestamptz THEN
    RAISE EXCEPTION 'L12-08: cutoff on 2026-04-21 05:00 UTC with UTC tz expected 2026-04-21 00:00 UTC, got %',
      v_cutoff;
  END IF;

  -- Invalid TZ must raise 22023.
  BEGIN
    PERFORM public.fn_clearing_cutoff_utc('Mars/Olympus', now());
    RAISE EXCEPTION 'L12-08: cutoff accepted invalid TZ';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- NULL TZ must raise 22023.
  BEGIN
    PERFORM public.fn_clearing_cutoff_utc(NULL, now());
    RAISE EXCEPTION 'L12-08: cutoff accepted NULL TZ';
  EXCEPTION WHEN sqlstate '22023' THEN NULL; END;

  -- Cron rescheduled to the new shape (if pg_cron available).
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    SELECT schedule INTO v_schedule
      FROM cron.job
     WHERE jobname = 'clearing-cron';
    IF v_schedule IS NULL THEN
      RAISE EXCEPTION 'L12-08: clearing-cron job missing after reschedule';
    END IF;
    IF v_schedule <> '15 3 * * *' THEN
      RAISE EXCEPTION 'L12-08: expected schedule "15 3 * * *", got "%"', v_schedule;
    END IF;
  END IF;

  RAISE NOTICE '[L12-08.selftest] OK — all invariants pass';
END$selftest$;
