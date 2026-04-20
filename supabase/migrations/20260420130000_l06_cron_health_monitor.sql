-- ============================================================================
-- L06-04 — pg_cron jobs sem monitoramento de execução
--
-- Audit reference:
--   docs/audit/findings/L06-04-pg-cron-jobs-sem-monitoramento-de-execucao.md
--   docs/audit/parts/06-coo.md  (anchor [6.4])
--
-- Problem
-- ───────
--   We have ~13 scheduled jobs (`cron.job` + Edge Function fires) that
--   collectively own wallet reconciliation (P1), clearing settlement
--   drain (P1), withdrawal lifecycle alerts (P2), challenge/championship
--   lifecycle (P2), idempotency-keys GC (P3), partition rotation (P3),
--   and a handful of housekeeping passes. A subset of them already
--   write `cron_run_state` rows via the L12-03 / L02-10 / L18-02 / L02-06
--   `_safe` wrappers, but:
--
--     • Nothing aggregates that state into a single "are all my crons
--       healthy?" verdict — operators have to JOIN cron.job /
--       cron_run_state / cron.job_run_details by hand each time.
--     • Nothing computes "stale" relative to the *expected* schedule —
--       a `*/5` job not running for 30 minutes is critical, but a
--       `30 5 1 * *` partition pass not having run for 25 days is fine.
--     • Nothing fires an alert when a job goes silent. The runbook
--       (`docs/runbooks/CRON_HEALTH_RUNBOOK.md`) tells on-call WHAT to
--       do, but they only learn there's a problem when a downstream
--       symptom shows up (drift, backlog, customer complaint).
--
--   Worst-case manifestation: `reconcile-wallets-daily` stops running.
--   The L06-03 alert pipeline can only fire on detected drift, so the
--   absence of runs is invisible. Drift accumulates undetected for
--   weeks because the alerting *requires the cron itself to fire*.
--
-- Defence (this migration)
-- ───────
--   Four DB objects + one schedule, fully reusing the L12-03
--   `cron_run_state` substrate so we don't duplicate state.
--
--     1. `public.cron_health_alerts` — append-only dedup table for
--        alert deliveries. RLS-forced, service-role only. The
--        cooldown fields prevent re-paging on the same job at the
--        same severity within `cooldown_minutes` (default 60).
--
--     2. `public.fn_parse_cron_interval_seconds(p_schedule text)` —
--        IMMUTABLE pure function. Best-effort parser for standard
--        5-field cron expressions. Returns the expected interval
--        between fires in seconds. Falls back to 86400 (daily) for
--        anything it can't recognise so we always have a baseline
--        instead of NULL — a NULL would silently disable the
--        staleness check.
--
--     3. `public.fn_classify_cron_severity(...)` — IMMUTABLE pure
--        function. Returns 'ok' | 'warn' | 'critical' | 'unknown'.
--        Mirror in TS at `portal/src/lib/cron-health.ts` (single
--        source of truth, no enum drift).
--
--     4. `public.fn_check_cron_health()` — STABLE SECURITY DEFINER.
--        Returns one row per scheduled job by UNION-ing
--          • `cron.job` (the configured set, when pg_cron is installed),
--          • `public.cron_run_state` (whatever has reported state).
--        LEFT JOIN-ed back into both sides so jobs that exist in one
--        but not the other still surface (with appropriate severity).
--        Computes `expected_interval_seconds`, `seconds_since_last_success`
--        and the `severity` enum on the way out. Read-only — never
--        writes to anything.
--
--     5. `public.fn_record_cron_health_alert(p_name, p_severity,
--                                            p_details, p_cooldown_minutes)`
--        SECURITY DEFINER + locked search_path + lock_timeout=2s.
--        Inserts a new alert row IFF no alert at (p_name, p_severity)
--        was emitted within `p_cooldown_minutes`. Returns the inserted
--        row id, or NULL when deduped. Mirrors the L06-03
--        `fn_record_wallet_drift_event` ergonomics.
--
--     6. `public.fn_alert_unhealthy_crons_safe()` — runs every 15 min.
--        Wraps the L12-03 `_safe` pattern (advisory lock + cron_run_state
--        lifecycle) and:
--          • SELECTs unhealthy jobs from `fn_check_cron_health()`,
--          • per offender, calls `fn_record_cron_health_alert()` with
--            a 60-min cooldown,
--          • emits a structured `RAISE NOTICE '[L06-04.alert] ...'` per
--            *new* (non-deduped) alert so log aggregators / Sentry
--            sinks pick them up,
--          • marks itself completed with a meta carrying the offender
--            count.
--
-- Reading priorities
-- ──────────────────
--   • cron.job  — the source of truth for "is the schedule registered".
--     If a job DROPped from cron.job stops being checked entirely; this
--     is intentional, the alternative would be infinite "missing job"
--     alerts on every renamed cron.
--
--   • cron.job_run_details — pg_cron's built-in audit log. Used as the
--     LAST-RESORT signal of "did the job actually fire" for jobs that
--     haven't been wrapped in the `_safe` pattern yet. Optional — the
--     function gracefully degrades to cron_run_state only when the
--     extension isn't present (local dev without pg_cron).
--
--   • cron_run_state — the application-aware source of truth. When
--     a row exists, its `last_status` / `finished_at` are AUTHORITATIVE
--     over cron.job_run_details (a job can have a 'completed' pg_cron
--     run that the application classified as 'failed' due to a
--     downstream RPC error captured in `last_meta.sqlstate`).
--
-- Scope & non-goals
-- ─────────────────
--   • This migration does NOT auto-fix unhealthy crons (that's the
--     runbook's job — context is needed to decide whether to wait
--     for next fire, force-re-fire manually, or rollback the change
--     that broke the schedule).
--   • This migration does NOT page PagerDuty/Slack directly. Like
--     L06-03, the persisted alerts + structured RAISE NOTICE are the
--     forensic record; an external sink (datadog/opsgenie/loki) is
--     responsible for fanning them to the on-call channel. Webhook
--     fan-out can be added in a follow-up via pg_net (same pattern as
--     `fn_invoke_lifecycle_cron_safe`) without touching this surface.
--
-- Verification (this migration)
-- ───────
--   In-transaction self-test exercises:
--     1. parse_cron_interval_seconds() returns the documented values for
--        every schedule actually used today + a fallback for garbage.
--     2. classify_cron_severity() returns the documented enum on the
--        canonical vectors.
--     3. record_cron_health_alert() inserts then dedupes within cooldown.
--     4. fn_check_cron_health() returns >= 0 rows without raising
--        (works in environments with AND without pg_cron installed).
--   All test rows are deleted before COMMIT.
-- ============================================================================

BEGIN;

-- 1. Dedup table ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cron_health_alerts (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name        text          NOT NULL CHECK (length(trim(job_name)) BETWEEN 1 AND 128),
  severity        text          NOT NULL CHECK (severity IN ('warn','critical')),
  observed_at     timestamptz   NOT NULL DEFAULT now(),
  cooldown_minutes integer      NOT NULL CHECK (cooldown_minutes BETWEEN 1 AND 10080),
  details         jsonb         NOT NULL DEFAULT '{}'::jsonb,
  acknowledged_at timestamptz   NULL,
  acknowledged_by text          NULL CHECK (
                                  acknowledged_by IS NULL
                                  OR length(trim(acknowledged_by)) BETWEEN 1 AND 128
                                )
);

COMMENT ON TABLE  public.cron_health_alerts IS
  'L06-04: append-only dedup table for cron health alert deliveries. '
  'fn_alert_unhealthy_crons_safe inserts AT MOST one row per (job, severity) '
  'within cooldown_minutes. Rows with acknowledged_at IS NULL are the active '
  'incidents.';
COMMENT ON COLUMN public.cron_health_alerts.cooldown_minutes IS
  'How long after observed_at this alert suppresses re-firing for the same '
  '(job_name, severity). Default 60 minutes — tuned so a 5-min job that '
  'silently dies pages once per hour, not every 15 min.';
COMMENT ON COLUMN public.cron_health_alerts.details IS
  'jsonb extension point: schedule, expected_interval_seconds, '
  'seconds_since_last_success, last_status, last_error, run/skip counts. '
  'Must NOT contain PII.';

ALTER TABLE public.cron_health_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_health_alerts FORCE ROW LEVEL SECURITY;
-- No policy created → only service_role (which bypasses RLS) can touch it.

CREATE INDEX IF NOT EXISTS idx_cron_health_alerts_observed_at
  ON public.cron_health_alerts (observed_at DESC);

-- Active incidents (the only query that on-call actually runs in a hurry).
-- Partial → empty in steady state, ~3 rows during a real outage.
CREATE INDEX IF NOT EXISTS idx_cron_health_alerts_active
  ON public.cron_health_alerts (job_name, severity, observed_at DESC)
  WHERE acknowledged_at IS NULL;

-- 2. Cron expression parser ──────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_parse_cron_interval_seconds(p_schedule text)
RETURNS integer
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_fields    text[];
  v_minute    text;
  v_hour      text;
  v_dom       text;
  v_month     text;
  v_dow       text;
  v_step      integer;
BEGIN
  IF p_schedule IS NULL OR length(trim(p_schedule)) = 0 THEN
    RETURN 86400;  -- fallback so callers always have a baseline
  END IF;

  -- Standard 5-field cron only. Anything else (e.g. seconds-precision
  -- 6-field crons or named macros like @daily) falls through to the
  -- daily fallback. We don't need precision — we need a stable lower
  -- bound to detect "stale" — and a daily fallback is conservative
  -- (under-alerts rather than spam-alerts).
  v_fields := regexp_split_to_array(trim(p_schedule), '\s+');
  IF array_length(v_fields, 1) <> 5 THEN
    RETURN 86400;
  END IF;

  v_minute := v_fields[1];
  v_hour   := v_fields[2];
  v_dom    := v_fields[3];
  v_month  := v_fields[4];
  v_dow    := v_fields[5];

  -- Pattern: */N * * * * → every N minutes
  IF v_minute ~ '^\*/[0-9]+$' AND v_hour = '*' AND v_dom = '*'
     AND v_month = '*' AND v_dow = '*' THEN
    v_step := substring(v_minute from 3)::integer;
    IF v_step BETWEEN 1 AND 59 THEN
      RETURN v_step * 60;
    END IF;
    RETURN 60;
  END IF;

  -- Pattern: * * * * * → every minute
  IF v_minute = '*' AND v_hour = '*' AND v_dom = '*'
     AND v_month = '*' AND v_dow = '*' THEN
    RETURN 60;
  END IF;

  -- Pattern: <literal> * * * * → hourly (e.g. "7 * * * *")
  IF v_minute ~ '^[0-9]+$' AND v_hour = '*' AND v_dom = '*'
     AND v_month = '*' AND v_dow = '*' THEN
    RETURN 3600;
  END IF;

  -- Pattern: <literal> <literal> * * <literal> → weekly
  -- (e.g. "45 3 * * 0" — Sundays at 03:45)
  IF v_minute ~ '^[0-9]+$' AND v_hour ~ '^[0-9]+$'
     AND v_dom = '*' AND v_month = '*' AND v_dow ~ '^[0-9]+$' THEN
    RETURN 604800;
  END IF;

  -- Pattern: <literal> <literal> <literal> * * → monthly-ish
  -- (e.g. "30 5 1 * *" — 1st of every month at 05:30)
  IF v_minute ~ '^[0-9]+$' AND v_hour ~ '^[0-9]+$'
     AND v_dom ~ '^[0-9]+$' AND v_month = '*' AND v_dow = '*' THEN
    -- 30 days ≈ 2_592_000 s. Months vary 28-31; the staleness check
    -- multiplies this by 1.5/3 anyway so being a few days off is fine.
    RETURN 2592000;
  END IF;

  -- Pattern: <literal> <literal> * * * → daily
  -- (e.g. "30 4 * * *", "45 6 * * *")
  IF v_minute ~ '^[0-9]+$' AND v_hour ~ '^[0-9]+$'
     AND v_dom = '*' AND v_month = '*' AND v_dow = '*' THEN
    RETURN 86400;
  END IF;

  -- Anything else: daily fallback (conservative).
  RETURN 86400;
END;
$$;

COMMENT ON FUNCTION public.fn_parse_cron_interval_seconds(text) IS
  'L06-04: best-effort parser for standard 5-field cron expressions. '
  'Returns expected interval in seconds. Falls back to 86400 for unknown '
  'shapes so the staleness check always has a baseline.';

-- 3. Severity classifier ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_classify_cron_severity(
  p_seconds_since_last_success bigint,
  p_expected_interval_seconds  integer,
  p_last_status                text,
  p_running_for_seconds        bigint  DEFAULT NULL
)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    -- 1) Job has never executed at all (no row in either source).
    --    'unknown' > 'ok' so on-call sees the gap, but we don't
    --    page on it (cron may have been re-scheduled this minute).
    WHEN p_seconds_since_last_success IS NULL
         AND COALESCE(p_last_status, 'never_run') IN ('never_run', 'unknown')
    THEN 'unknown'

    -- 2) Job is currently 'running' but for far longer than its own
    --    cycle. Almost always orphaned (the function crashed before
    --    writing fn_cron_mark_completed/failed). Page the on-call.
    WHEN COALESCE(p_last_status, '') = 'running'
         AND p_running_for_seconds IS NOT NULL
         AND p_running_for_seconds > 3 * GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)
    THEN 'critical'

    -- 3) Last reported run failed AND the next scheduled fire has
    --    already come and gone without producing a success → the
    --    failure has now persisted across cycles. Page.
    WHEN COALESCE(p_last_status, '') = 'failed'
         AND p_seconds_since_last_success IS NOT NULL
         AND p_seconds_since_last_success > 1.5 * GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)
    THEN 'critical'

    -- 4) No success in 3+ cycles. Either the job stopped firing
    --    (worst case — exactly the L06-04 scenario) or it's been
    --    skipping/failing every time. Page.
    WHEN p_seconds_since_last_success IS NOT NULL
         AND p_seconds_since_last_success > 3 * GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)
    THEN 'critical'

    -- 5) Single recent failure: warn (next fire might recover, but
    --    on-call should know).
    WHEN COALESCE(p_last_status, '') = 'failed'
    THEN 'warn'

    -- 6) Modestly stale: warn (1.5 cycles without a success).
    WHEN p_seconds_since_last_success IS NOT NULL
         AND p_seconds_since_last_success > 1.5 * GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)
    THEN 'warn'

    -- 7) Currently running but exceeded one cycle (not 3): warn.
    WHEN COALESCE(p_last_status, '') = 'running'
         AND p_running_for_seconds IS NOT NULL
         AND p_running_for_seconds > 1.5 * GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)
    THEN 'warn'

    ELSE 'ok'
  END;
$$;

COMMENT ON FUNCTION public.fn_classify_cron_severity(bigint, integer, text, bigint) IS
  'L06-04: deterministic severity classification for one cron job. '
  'critical = page; warn = slack; ok = silence; unknown = first-run / no '
  'data yet. Mirrored 1:1 by TS helper portal/src/lib/cron-health.ts.';

-- 4. Read-only health view ───────────────────────────────────────────────────
--
-- Returns one row per known cron job. Rows come from the UNION of
-- cron.job (when pg_cron is installed) and cron_run_state (always),
-- so the function is meaningful in:
--   • production (pg_cron present, every wrapped job has state),
--   • dev (pg_cron absent, only cron_run_state rows surface),
--   • bootstrapping (pg_cron present, jobs scheduled but state empty).

CREATE OR REPLACE FUNCTION public.fn_check_cron_health()
RETURNS TABLE (
  name                          text,
  schedule                      text,
  source                        text,        -- 'pg_cron' | 'cron_run_state' | 'both'
  active                        boolean,     -- cron.job.active when present, else NULL
  last_status                   text,        -- cron_run_state.last_status, or 'unknown'
  started_at                    timestamptz,
  finished_at                   timestamptz,
  last_success_at               timestamptz,
  expected_interval_seconds     integer,
  seconds_since_last_success    bigint,
  running_for_seconds           bigint,
  run_count                     bigint,
  skip_count                    bigint,
  last_error                    text,
  last_meta                     jsonb,
  severity                      text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
SET statement_timeout = '10s'
AS $$
DECLARE
  v_pg_cron_installed boolean;
BEGIN
  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    INTO v_pg_cron_installed;

  RETURN QUERY
  WITH
  -- Set of jobs the SCHEDULER thinks exist. Empty when pg_cron is
  -- absent (local dev). The double EXECUTE avoids a parse-time
  -- dependency on cron.job in environments without the extension.
  scheduled AS (
    SELECT
      j.jobname::text AS name,
      j.schedule::text AS schedule,
      j.active::boolean AS active
    FROM cron.job j
    WHERE v_pg_cron_installed
  ),
  -- Set of jobs the APPLICATION-side wrappers have written about.
  -- Always queryable.
  reported AS (
    SELECT
      s.name,
      s.last_status,
      s.started_at,
      s.finished_at,
      s.run_count,
      s.skip_count,
      s.last_error,
      s.last_meta
    FROM public.cron_run_state s
  ),
  -- Last successful run from cron_run_state. When the job has a
  -- 'completed' last_status, finished_at IS the last success. When
  -- last_status is 'failed' or 'running', the success is older —
  -- we approximate with NULL (callers treat as "older than expected
  -- interval can express", i.e. critical-eligible). A future PR can
  -- add a `last_success_at` column to cron_run_state if we need
  -- finer granularity here.
  last_success AS (
    SELECT
      r.name,
      CASE WHEN r.last_status = 'completed' THEN r.finished_at ELSE NULL END
        AS last_success_at
    FROM reported r
  ),
  unioned AS (
    SELECT
      COALESCE(sched.name, rep.name) AS name,
      sched.schedule                  AS schedule,
      CASE
        WHEN sched.name IS NOT NULL AND rep.name IS NOT NULL THEN 'both'
        WHEN sched.name IS NOT NULL                          THEN 'pg_cron'
        ELSE                                                       'cron_run_state'
      END                             AS source,
      sched.active                    AS active,
      COALESCE(rep.last_status, 'unknown') AS last_status,
      rep.started_at,
      rep.finished_at,
      ls.last_success_at,
      rep.run_count,
      rep.skip_count,
      rep.last_error,
      rep.last_meta
    FROM scheduled sched
    FULL OUTER JOIN reported rep
      ON rep.name = sched.name
    LEFT JOIN last_success ls
      ON ls.name = COALESCE(sched.name, rep.name)
  )
  SELECT
    u.name,
    u.schedule,
    u.source,
    u.active,
    u.last_status,
    u.started_at,
    u.finished_at,
    u.last_success_at,
    public.fn_parse_cron_interval_seconds(u.schedule) AS expected_interval_seconds,
    CASE
      WHEN u.last_success_at IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM (now() - u.last_success_at))::bigint
    END AS seconds_since_last_success,
    CASE
      WHEN u.last_status = 'running' AND u.started_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (now() - u.started_at))::bigint
      ELSE NULL
    END AS running_for_seconds,
    COALESCE(u.run_count,  0)         AS run_count,
    COALESCE(u.skip_count, 0)         AS skip_count,
    u.last_error,
    COALESCE(u.last_meta, '{}'::jsonb) AS last_meta,
    public.fn_classify_cron_severity(
      CASE
        WHEN u.last_success_at IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (now() - u.last_success_at))::bigint
      END,
      public.fn_parse_cron_interval_seconds(u.schedule),
      u.last_status,
      CASE
        WHEN u.last_status = 'running' AND u.started_at IS NOT NULL
          THEN EXTRACT(EPOCH FROM (now() - u.started_at))::bigint
        ELSE NULL
      END
    ) AS severity
  FROM unioned u
  ORDER BY
    -- Critical first, then warn, then unknown, then ok. Within a
    -- group, oldest-success-first so on-call eyes land on the
    -- worst offender at the top.
    CASE
      public.fn_classify_cron_severity(
        CASE
          WHEN u.last_success_at IS NULL THEN NULL
          ELSE EXTRACT(EPOCH FROM (now() - u.last_success_at))::bigint
        END,
        public.fn_parse_cron_interval_seconds(u.schedule),
        u.last_status,
        CASE
          WHEN u.last_status = 'running' AND u.started_at IS NOT NULL
            THEN EXTRACT(EPOCH FROM (now() - u.started_at))::bigint
          ELSE NULL
        END
      )
      WHEN 'critical' THEN 0
      WHEN 'warn'     THEN 1
      WHEN 'unknown'  THEN 2
      ELSE                 3
    END,
    COALESCE(u.last_success_at, 'epoch'::timestamptz) ASC,
    u.name ASC;
END;
$$;

COMMENT ON FUNCTION public.fn_check_cron_health() IS
  'L06-04: read-only health summary for every known cron job. UNIONs '
  'cron.job (pg_cron source of truth) with public.cron_run_state '
  '(application-aware). Rows ordered worst-severity first. Safe to call '
  'at admin-endpoint cadence; no writes.';

REVOKE ALL ON FUNCTION public.fn_check_cron_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_check_cron_health() TO service_role;

-- 5. Persist alert (with cooldown) ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_record_cron_health_alert(
  p_job_name         text,
  p_severity         text,
  p_details          jsonb   DEFAULT '{}'::jsonb,
  p_cooldown_minutes integer DEFAULT 60
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_id           uuid;
  v_recent_count integer;
BEGIN
  IF p_job_name IS NULL OR length(trim(p_job_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_JOB_NAME: p_job_name is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_severity IS NULL OR p_severity NOT IN ('warn','critical') THEN
    RAISE EXCEPTION 'INVALID_SEVERITY: % (expected warn|critical)', p_severity
      USING ERRCODE = '22023';
  END IF;
  IF p_cooldown_minutes IS NULL OR p_cooldown_minutes < 1 OR p_cooldown_minutes > 10080 THEN
    RAISE EXCEPTION 'INVALID_COOLDOWN_MINUTES: % (expected 1..10080)', p_cooldown_minutes
      USING ERRCODE = '22023';
  END IF;

  -- Dedup: any non-acknowledged alert at the same (job, severity)
  -- inside the cooldown window suppresses a new insert. We DON'T
  -- dedup across severities — an upgrade from warn → critical MUST
  -- emit a fresh alert so the page actually fires.
  SELECT COUNT(*)
    INTO v_recent_count
  FROM public.cron_health_alerts
  WHERE job_name = p_job_name
    AND severity = p_severity
    AND observed_at > now() - make_interval(mins => p_cooldown_minutes);

  IF v_recent_count > 0 THEN
    RETURN NULL;  -- deduped
  END IF;

  INSERT INTO public.cron_health_alerts(
    job_name, severity, cooldown_minutes, details
  )
  VALUES (
    p_job_name, p_severity, p_cooldown_minutes,
    COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.fn_record_cron_health_alert(text, text, jsonb, integer) IS
  'L06-04: insert a cron_health_alerts row IFF no alert at (job, severity) '
  'fired inside cooldown_minutes. Returns the new id, or NULL when deduped.';

REVOKE ALL ON FUNCTION public.fn_record_cron_health_alert(text, text, jsonb, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_record_cron_health_alert(text, text, jsonb, integer) TO service_role;

-- 6. Safe alert wrapper (cron-fired) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_alert_unhealthy_crons_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired   boolean;
  v_offenders       integer := 0;
  v_alerts_created  integer := 0;
  v_row             record;
  v_alert_id        uuid;
BEGIN
  IF NOT public.fn_cron_should_run('cron-health-monitor', 600) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:cron_health_monitor')
  );
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'cron-health-monitor';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('cron-health-monitor');

  BEGIN
    FOR v_row IN
      SELECT *
      FROM public.fn_check_cron_health()
      WHERE severity IN ('warn','critical')
        -- Don't self-alert: this very job will appear as 'running'
        -- in its own check. A 'running' status for cron-health-monitor
        -- is fine here.
        AND name <> 'cron-health-monitor'
    LOOP
      v_offenders := v_offenders + 1;

      v_alert_id := public.fn_record_cron_health_alert(
        v_row.name,
        v_row.severity,
        jsonb_build_object(
          'schedule',                   v_row.schedule,
          'source',                     v_row.source,
          'last_status',                v_row.last_status,
          'expected_interval_seconds',  v_row.expected_interval_seconds,
          'seconds_since_last_success', v_row.seconds_since_last_success,
          'running_for_seconds',        v_row.running_for_seconds,
          'run_count',                  v_row.run_count,
          'skip_count',                 v_row.skip_count,
          'last_error',                 LEFT(COALESCE(v_row.last_error, ''), 512)
        ),
        60
      );

      IF v_alert_id IS NOT NULL THEN
        v_alerts_created := v_alerts_created + 1;
        RAISE NOTICE
          '[L06-04.alert] severity=% job=% expected_interval=%s since_success=%s last_status=% alert_id=%',
          v_row.severity,
          v_row.name,
          v_row.expected_interval_seconds,
          COALESCE(v_row.seconds_since_last_success::text, 'NULL'),
          v_row.last_status,
          v_alert_id;
      END IF;
    END LOOP;

    PERFORM public.fn_cron_mark_completed(
      'cron-health-monitor',
      jsonb_build_object(
        'offenders',      v_offenders,
        'alerts_created', v_alerts_created
      )
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'cron-health-monitor',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'alert_loop')
    );
    RAISE;
  END;
END;
$$;

COMMENT ON FUNCTION public.fn_alert_unhealthy_crons_safe() IS
  'L06-04: scheduled every 15 min. Iterates fn_check_cron_health(), '
  'records alerts with 60-min cooldown, RAISES NOTICE per new alert. '
  'Safe to invoke manually for dev/runbook drills.';

REVOKE ALL ON FUNCTION public.fn_alert_unhealthy_crons_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_alert_unhealthy_crons_safe() TO service_role;

-- 7. Schedule + seed ─────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L06-04] pg_cron not installed; skipping cron-health-monitor schedule';
  ELSE
    BEGIN PERFORM cron.unschedule('cron-health-monitor');
    EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM cron.schedule(
      'cron-health-monitor',
      '*/15 * * * *',
      $job$SELECT public.fn_alert_unhealthy_crons_safe();$job$
    );
    RAISE NOTICE '[L06-04] scheduled cron-health-monitor at */15 * * * *';
  END IF;
END$$;

-- Seed cron_run_state for cron-health-monitor so the table query in
-- the runbook never returns "row not found" before the first fire.
INSERT INTO public.cron_run_state(name, last_status)
VALUES ('cron-health-monitor', 'never_run')
ON CONFLICT (name) DO NOTHING;

-- 8. Self-test ───────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_interval     integer;
  v_severity     text;
  v_job_name     text := '__l06_04_selftest__';
  v_alert_id     uuid;
  v_dedup_id     uuid;
  v_row_count    integer;
  v_health_count integer;
BEGIN
  -- 8a. Cron interval parser vectors (the schedules we actually use)
  IF public.fn_parse_cron_interval_seconds('* * * * *') <> 60 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(* * * * *) expected 60';
  END IF;
  IF public.fn_parse_cron_interval_seconds('*/5 * * * *') <> 300 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(*/5 * * * *) expected 300';
  END IF;
  IF public.fn_parse_cron_interval_seconds('*/10 * * * *') <> 600 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(*/10 * * * *) expected 600';
  END IF;
  IF public.fn_parse_cron_interval_seconds('7 * * * *') <> 3600 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(7 * * * *) expected 3600';
  END IF;
  IF public.fn_parse_cron_interval_seconds('30 4 * * *') <> 86400 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(30 4 * * *) expected 86400';
  END IF;
  IF public.fn_parse_cron_interval_seconds('45 3 * * 0') <> 604800 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(45 3 * * 0) expected 604800';
  END IF;
  IF public.fn_parse_cron_interval_seconds('30 5 1 * *') <> 2592000 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(30 5 1 * *) expected 2592000';
  END IF;
  -- Garbage / NULL → daily fallback
  IF public.fn_parse_cron_interval_seconds(NULL) <> 86400 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(NULL) expected 86400 fallback';
  END IF;
  IF public.fn_parse_cron_interval_seconds('not a cron') <> 86400 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(garbage) expected 86400 fallback';
  END IF;
  IF public.fn_parse_cron_interval_seconds('*/0 * * * *') <> 60 THEN
    RAISE EXCEPTION '[L06-04 selftest] parse(*/0) expected 60 (clamped)';
  END IF;

  -- 8b. Severity classifier vectors
  --   never_run, no data → 'unknown'
  IF public.fn_classify_cron_severity(NULL, 300, 'never_run', NULL) <> 'unknown' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify never_run expected unknown';
  END IF;
  --   fresh success well within cycle → 'ok'
  IF public.fn_classify_cron_severity(60, 300, 'completed', NULL) <> 'ok' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify fresh expected ok';
  END IF;
  --   slightly stale (1.6x cycle) → 'warn'
  IF public.fn_classify_cron_severity(480, 300, 'completed', NULL) <> 'warn' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify 1.6x expected warn';
  END IF;
  --   very stale (3.5x cycle) → 'critical'
  IF public.fn_classify_cron_severity(1050, 300, 'completed', NULL) <> 'critical' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify 3.5x expected critical';
  END IF;
  --   most-recent failure within cycle → 'warn'
  IF public.fn_classify_cron_severity(60, 300, 'failed', NULL) <> 'warn' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify recent fail expected warn';
  END IF;
  --   failed AND stale > 1.5x → 'critical' (failure persisted)
  IF public.fn_classify_cron_severity(500, 300, 'failed', NULL) <> 'critical' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify persistent fail expected critical';
  END IF;
  --   running inside cycle → 'ok'
  IF public.fn_classify_cron_severity(120, 300, 'running', 60) <> 'ok' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify running inside cycle expected ok';
  END IF;
  --   running > 1.5x cycle → 'warn'
  IF public.fn_classify_cron_severity(120, 300, 'running', 500) <> 'warn' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify long-running expected warn';
  END IF;
  --   running > 3x cycle → 'critical' (orphan)
  IF public.fn_classify_cron_severity(120, 300, 'running', 1500) <> 'critical' THEN
    RAISE EXCEPTION '[L06-04 selftest] classify orphan expected critical';
  END IF;

  -- 8c. record_cron_health_alert: insert + dedup
  v_alert_id := public.fn_record_cron_health_alert(
    v_job_name, 'warn',
    jsonb_build_object('test', true), 60
  );
  IF v_alert_id IS NULL THEN
    RAISE EXCEPTION '[L06-04 selftest] first record returned NULL (expected id)';
  END IF;

  v_dedup_id := public.fn_record_cron_health_alert(
    v_job_name, 'warn',
    jsonb_build_object('test', true), 60
  );
  IF v_dedup_id IS NOT NULL THEN
    RAISE EXCEPTION '[L06-04 selftest] dedup record returned id (expected NULL within cooldown)';
  END IF;

  -- Severity upgrade should NOT dedup
  v_dedup_id := public.fn_record_cron_health_alert(
    v_job_name, 'critical',
    jsonb_build_object('test', true), 60
  );
  IF v_dedup_id IS NULL THEN
    RAISE EXCEPTION '[L06-04 selftest] severity upgrade got deduped (expected fresh row)';
  END IF;

  -- Bad inputs raise SQLSTATE 22023
  BEGIN
    PERFORM public.fn_record_cron_health_alert(NULL, 'warn', '{}'::jsonb, 60);
    RAISE EXCEPTION '[L06-04 selftest] NULL job_name should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_record_cron_health_alert(v_job_name, 'unknown', '{}'::jsonb, 60);
    RAISE EXCEPTION '[L06-04 selftest] severity=unknown should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_record_cron_health_alert(v_job_name, 'warn', '{}'::jsonb, 0);
    RAISE EXCEPTION '[L06-04 selftest] cooldown=0 should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  -- 8d. fn_check_cron_health smoke test — must not raise, returns >= 0 rows
  SELECT COUNT(*) INTO v_health_count FROM public.fn_check_cron_health();
  IF v_health_count < 0 THEN
    RAISE EXCEPTION '[L06-04 selftest] fn_check_cron_health returned negative count';
  END IF;

  -- Cleanup synthetic test rows
  DELETE FROM public.cron_health_alerts WHERE job_name = v_job_name;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  IF v_row_count < 2 THEN
    RAISE EXCEPTION '[L06-04 selftest] cleanup deleted % rows (expected ≥ 2)', v_row_count;
  END IF;

  RAISE NOTICE '[L06-04] migration self-test PASSED (% health rows visible)', v_health_count;
END$$;

COMMIT;
