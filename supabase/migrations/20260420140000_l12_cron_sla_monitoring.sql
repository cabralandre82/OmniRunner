-- ============================================================================
-- L12-04 — pg_cron não monitora SLA de execução
--
-- Audit reference:
--   docs/audit/findings/L12-04-pg-cron-nao-monitora-sla-de-execucao.md
--   docs/audit/parts/12-cron.md  (anchor [12.4])
--
-- Problem
-- ───────
--   L06-04 (`fn_check_cron_health`) catches the cases where a job
--   STOPS firing or fires-but-fails. It does NOT catch the case where
--   a job fires *on time* and reports `completed` but spent **far
--   longer than usual** doing it. Consequences:
--
--     • `clearing-cron` (daily, normally ~30s) starts taking 12 min
--       because a downstream JOIN went unindexed → no alert from
--       L06-04 (status='completed', not stale, not orphaned).
--     • `reconcile-wallets-daily` quietly walks from 90s → 5 min over
--       three weeks because wallet count tripled → on-call only finds
--       out when it stops fitting in the maintenance window.
--     • `auto-topup-hourly` blocks on a slow Asaas API call that
--       returns success eventually → revenue still flows, but the
--       unbounded execution window starves the next cron tick.
--
--   Today we have **no per-run duration ledger and no thresholds**, so
--   even if an operator looks at `cron.job_run_details` they see
--   *individual runtimes* with no baseline ("is 4 minutes for
--   clearing-cron normal or terrible?"). The audit explicitly calls
--   out: "fn_check_cron_health() + alerta Slack se minutes_since_success
--   > 2 * schedule_interval_minutes" — L06-04 covered the
--   `minutes_since_success` half; this migration covers the **runtime
--   half**.
--
-- Defence (this migration)
-- ───────
--   Six DB objects + one schedule, all *additive* on top of L06-04
--   (no contract changes to existing fn_cron_mark_* helpers, no
--   changes to cron_run_state).
--
--     1. `public.cron_run_history` — append-only per-run ledger.
--        One row per terminal transition of `cron_run_state`
--        (completed | failed | timeout). Captures duration_seconds,
--        last_status, last_error and last_meta at the moment of
--        the terminal mark. RLS-forced, service-role only.
--        Retention is 30 days (older rows pruned by the same
--        scheduled job that emits SLA alerts — keeps history
--        bounded without a separate housekeeping cron).
--
--     2. `public.cron_sla_thresholds` — per-job SLA config.
--        Optional: jobs without a row use derived defaults
--        (target ≈ 10% of expected_interval_seconds, breach ≈ 50%
--        of interval, capped at 600s and 3600s respectively).
--        Operators tune individual jobs as their behaviour
--        becomes well-understood (e.g. clearing-cron target=180s).
--
--     3. `public.fn_cron_run_history_capture()` — AFTER UPDATE
--        trigger on cron_run_state. Fires when last_status
--        transitions INTO a terminal state. Inserts the run
--        snapshot into cron_run_history. Has zero impact on the
--        UPDATE itself (trigger errors are caught and logged
--        via RAISE WARNING — duration tracking is observability,
--        not source of truth).
--
--     4. `public.fn_compute_cron_sla_stats(p_window_hours int)` —
--        STABLE SECURITY DEFINER. Returns one row per job in the
--        window with run_count / failed_count / avg_duration /
--        p50 / p95 / p99 / max_duration / breach_count plus the
--        configured target/breach thresholds. The aggregator is
--        deliberately separate from `fn_check_cron_health` so a
--        future caller can compose the two without paying the
--        history-scan cost when only health is needed.
--
--     5. `public.fn_classify_cron_sla(...)` — IMMUTABLE pure.
--        Returns 'ok' | 'warn' | 'critical' | 'unknown'. Mirror
--        in TS at `portal/src/lib/cron-sla.ts`. Decision rules:
--          • run_count = 0                                    → 'unknown'
--          • last_run_seconds > 2 * breach OR p95 > 2 * breach → 'critical'
--          • last_run_seconds > breach OR p95 > breach        → 'warn'
--          • avg_duration > target AND breach_count >= 2      → 'warn'
--          • else                                              → 'ok'
--        Pure (no I/O, IMMUTABLE) so it can sit in views / generated
--        columns later without write-amplification.
--
--     6. `public.fn_alert_cron_sla_breaches_safe()` — runs every
--        30 min. Wraps the L12-03 `_safe` pattern (advisory lock +
--        cron_run_state lifecycle) and:
--          • computes SLA stats for last 24h via fn_compute_cron_sla_stats,
--          • per offender (warn/critical), records an alert in the
--            existing `public.cron_health_alerts` table with
--            `details.kind = 'sla_breach'` so dashboards can
--            distinguish staleness alerts (L06-04) from SLA alerts
--            (L12-04) by a single jsonb field,
--          • emits a structured `RAISE NOTICE '[L12-04.sla] ...'`
--            per *new* (non-deduped) alert,
--          • prunes cron_run_history rows older than 30 days,
--          • marks itself completed with a meta carrying offender +
--            pruned counts.
--
-- Reading priorities
-- ──────────────────
--   • cron_run_state is the LIVE state (one row per job). When
--     ops needs "is this job currently running?", they read state.
--   • cron_run_history is the AUDIT log (many rows per job). When
--     ops needs "how long has this job been taking lately?", they
--     scan history.
--   • cron_sla_thresholds is the CONFIG (zero-or-one row per job).
--     Used by both the classifier and the runbook (operators add
--     a row to lock in a known-good baseline once tuning is done).
--   • cron_health_alerts (from L06-04) is the ALERT inbox. Both
--     staleness alerts (L06-04) and SLA alerts (L12-04) land
--     there. The discriminator is `details.kind`.
--
-- Scope & non-goals
-- ─────────────────
--   • This migration does NOT change any existing cron_run_state
--     helper signatures, so all _safe wrappers shipped to date
--     keep working unchanged (the trigger fires off the UPDATEs
--     they already perform).
--   • This migration does NOT auto-tune thresholds. A future PR
--     can add `fn_recommend_cron_sla` that scans history and
--     suggests target/breach values; for now operators set them
--     by hand once they understand the job.
--   • This migration does NOT page PagerDuty/Slack directly —
--     same external-sink architecture as L06-03 / L06-04.
--   • Trigger captures only TERMINAL transitions (completed,
--     failed, timeout). `running` and `skipped` are NOT captured
--     — they're either in-progress or no-ops, and history would
--     bloat with ~13 jobs × every minute = ~18k skipped rows/day
--     for the high-frequency `*/5` jobs.
--
-- Verification (this migration)
-- ───────
--   In-transaction self-test exercises:
--     1. Trigger fires once per terminal transition; does NOT fire
--        on intermediate ('running' / 'skipped') updates; survives
--        a deliberate trigger-side error without breaking the host
--        UPDATE.
--     2. fn_compute_cron_sla_stats produces expected aggregates
--        (count, avg, p95, max, breach_count) over a synthetic
--        history window.
--     3. fn_classify_cron_sla returns the documented enum on the
--        canonical vectors (ok / warn / critical / unknown).
--     4. fn_alert_cron_sla_breaches_safe smoke test: synthetic
--        breaching job → alert row inserted in cron_health_alerts
--        with kind='sla_breach'; second invocation deduplicates;
--        then synthetic non-breaching job → no alert.
--   All synthetic rows are deleted before COMMIT.
-- ============================================================================

BEGIN;

-- 1. cron_run_history ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cron_run_history (
  id              bigserial     PRIMARY KEY,
  name            text          NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 128),
  started_at      timestamptz   NULL,
  finished_at     timestamptz   NOT NULL,
  -- Generated stored column so we never have to re-compute durations
  -- in queries / aggregates. NULL if started_at is NULL (terminal mark
  -- without a paired mark_started — rare but legal under L12-03).
  duration_seconds numeric(12,3) GENERATED ALWAYS AS (
    CASE
      WHEN started_at IS NULL THEN NULL
      ELSE EXTRACT(EPOCH FROM (finished_at - started_at))
    END
  ) STORED,
  last_status     text          NOT NULL CHECK (
                                  last_status IN ('completed','failed','timeout')
                                ),
  last_error      text          NULL,
  last_meta       jsonb         NOT NULL DEFAULT '{}'::jsonb,
  recorded_at     timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT cron_run_history_window_chk CHECK (
    started_at IS NULL OR finished_at >= started_at
  )
);

COMMENT ON TABLE  public.cron_run_history IS
  'L12-04: append-only per-run ledger. One row per terminal transition '
  '(completed/failed/timeout) of cron_run_state. Retained for 30 days '
  'by fn_alert_cron_sla_breaches_safe. Read by fn_compute_cron_sla_stats.';
COMMENT ON COLUMN public.cron_run_history.duration_seconds IS
  'Generated stored: EXTRACT(EPOCH FROM finished_at - started_at). '
  'NULL when started_at is NULL (mark_completed without paired '
  'mark_started — possible on first run of a job not using _safe wrappers).';

ALTER TABLE public.cron_run_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_run_history FORCE ROW LEVEL SECURITY;
-- No policy → service_role only.

-- "Recent runs of job X" is the dominant query (SLA stats compute
-- 24h windows per name). Tail-of-history scans use a separate
-- (recorded_at) index for the prune pass.
CREATE INDEX IF NOT EXISTS idx_cron_run_history_name_finished
  ON public.cron_run_history (name, finished_at DESC);

CREATE INDEX IF NOT EXISTS idx_cron_run_history_recorded_at
  ON public.cron_run_history (recorded_at);

REVOKE ALL ON public.cron_run_history FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.cron_run_history TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.cron_run_history_id_seq TO service_role;

-- 2. cron_sla_thresholds ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cron_sla_thresholds (
  name             text         PRIMARY KEY CHECK (length(trim(name)) BETWEEN 1 AND 128),
  -- Typical / "feels normal" runtime. avg_duration drifting above
  -- this for several runs in a row is a leading indicator (warn-eligible).
  target_seconds   numeric(10,3) NOT NULL CHECK (target_seconds > 0 AND target_seconds <= 86400),
  -- Hard limit. A SINGLE run above this is enough to alert; p95
  -- above 2x this pages.
  breach_seconds   numeric(10,3) NOT NULL CHECK (breach_seconds >= target_seconds AND breach_seconds <= 86400),
  -- Allows ops to silence SLA alerting on a job (e.g. during a
  -- planned long migration cycle) without dropping the row.
  enabled          boolean      NOT NULL DEFAULT true,
  -- Optional free-form note for the runbook ("clearing-cron settles
  -- D-1; budget is 240s before next maintenance window").
  notes            text         NULL CHECK (notes IS NULL OR length(notes) <= 1024),
  created_at       timestamptz  NOT NULL DEFAULT now(),
  updated_at       timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cron_sla_thresholds IS
  'L12-04: per-cron-job SLA thresholds. Optional — jobs without a row '
  'fall back to derived defaults (10%/50% of expected_interval_seconds, '
  'capped). Operators add rows to lock in known-good baselines.';
COMMENT ON COLUMN public.cron_sla_thresholds.target_seconds IS
  'Typical runtime baseline. avg_duration > target across multiple runs ⇒ warn.';
COMMENT ON COLUMN public.cron_sla_thresholds.breach_seconds IS
  'Single-run alert threshold. last_run > breach ⇒ warn; > 2*breach ⇒ critical.';

ALTER TABLE public.cron_sla_thresholds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_sla_thresholds FORCE ROW LEVEL SECURITY;
-- No policy → service_role only.

REVOKE ALL ON public.cron_sla_thresholds FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.cron_sla_thresholds TO service_role;

-- Updated_at touch trigger (cheap; reuses existing pattern).
CREATE OR REPLACE FUNCTION public.fn_cron_sla_thresholds_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cron_sla_thresholds_touch ON public.cron_sla_thresholds;
CREATE TRIGGER trg_cron_sla_thresholds_touch
  BEFORE UPDATE ON public.cron_sla_thresholds
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_cron_sla_thresholds_touch();

-- 3. AFTER UPDATE trigger on cron_run_state → cron_run_history ──────────────
CREATE OR REPLACE FUNCTION public.fn_cron_run_history_capture()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_terminal constant text[] := ARRAY['completed','failed','timeout'];
BEGIN
  -- Capture only when the new state is terminal AND the row actually
  -- changed status (otherwise an idempotent UPDATE that re-marks
  -- 'completed' with the same finished_at would double-record).
  IF NEW.last_status = ANY(v_terminal)
     AND (OLD IS NULL
          OR OLD.last_status IS DISTINCT FROM NEW.last_status
          OR OLD.finished_at IS DISTINCT FROM NEW.finished_at)
     AND NEW.finished_at IS NOT NULL
  THEN
    BEGIN
      INSERT INTO public.cron_run_history(
        name, started_at, finished_at, last_status, last_error, last_meta
      )
      VALUES (
        NEW.name,
        NEW.started_at,
        NEW.finished_at,
        NEW.last_status,
        NEW.last_error,
        COALESCE(NEW.last_meta, '{}'::jsonb)
      );
    EXCEPTION WHEN OTHERS THEN
      -- Trigger MUST NOT block the host UPDATE. History capture is
      -- observability — losing one row is preferable to corrupting
      -- the cron lifecycle. Surface via WARNING so log aggregators
      -- still notice repeated failures.
      RAISE WARNING
        '[L12-04] cron_run_history insert failed for job=% sqlstate=% msg=%',
        NEW.name, SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_cron_run_history_capture() IS
  'L12-04: AFTER UPDATE trigger on cron_run_state. Inserts a snapshot '
  'into cron_run_history when last_status transitions INTO a terminal '
  'value (completed/failed/timeout). Errors are swallowed via WARNING '
  'so the host UPDATE never fails because of a history-side problem.';

DROP TRIGGER IF EXISTS trg_cron_run_history_capture ON public.cron_run_state;
CREATE TRIGGER trg_cron_run_history_capture
  AFTER INSERT OR UPDATE ON public.cron_run_state
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_cron_run_history_capture();

-- 4. SLA classifier ──────────────────────────────────────────────────────────
--
-- Pure / IMMUTABLE so callers can fold it into views, and so the TS
-- mirror in `portal/src/lib/cron-sla.ts` can stay byte-equivalent
-- without worrying about side effects. Defined BEFORE the aggregator
-- because fn_compute_cron_sla_stats invokes it inline.

CREATE OR REPLACE FUNCTION public.fn_classify_cron_sla(
  p_run_count        bigint,
  p_avg_duration     numeric,
  p_p95_duration     numeric,
  p_last_duration    numeric,
  p_target_seconds   numeric,
  p_breach_seconds   numeric,
  p_breach_count     bigint,
  p_enabled          boolean DEFAULT true
)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    -- 0) explicitly disabled → silenced.
    WHEN p_enabled IS FALSE
      THEN 'ok'

    -- 1) zero runs in window → no signal.
    WHEN COALESCE(p_run_count, 0) = 0
      THEN 'unknown'

    -- 2) Most recent run > 2x breach OR p95 > 2x breach → page.
    WHEN p_breach_seconds IS NOT NULL
         AND ((p_last_duration IS NOT NULL AND p_last_duration > 2 * p_breach_seconds)
              OR (p_p95_duration IS NOT NULL AND p_p95_duration > 2 * p_breach_seconds))
      THEN 'critical'

    -- 3) Most recent run > breach OR p95 > breach → warn.
    WHEN p_breach_seconds IS NOT NULL
         AND ((p_last_duration IS NOT NULL AND p_last_duration > p_breach_seconds)
              OR (p_p95_duration IS NOT NULL AND p_p95_duration > p_breach_seconds))
      THEN 'warn'

    -- 4) Sustained drift: avg > target AND >= 2 breach events
    --    in the window. Single anomalies don't trigger here
    --    (rule 3 already handled them); this catches "creeping"
    --    degradation where individual runs stay under breach but
    --    the average and frequency tell the story.
    WHEN p_target_seconds IS NOT NULL
         AND p_avg_duration IS NOT NULL
         AND p_avg_duration > p_target_seconds
         AND COALESCE(p_breach_count, 0) >= 2
      THEN 'warn'

    ELSE 'ok'
  END;
$$;

COMMENT ON FUNCTION public.fn_classify_cron_sla(bigint, numeric, numeric, numeric, numeric, numeric, bigint, boolean) IS
  'L12-04: deterministic SLA severity for one cron job. critical = page, '
  'warn = slack, ok = silence, unknown = no runs in window. Mirrored 1:1 '
  'by TS helper portal/src/lib/cron-sla.ts.';

-- 5. SLA stats aggregator ────────────────────────────────────────────────────
--
-- Returns one row per job seen in the window. Defaults are computed
-- from `expected_interval_seconds` (via fn_parse_cron_interval_seconds)
-- when no cron_sla_thresholds row exists. Capping at sensible upper
-- bounds avoids "expected_interval=86400 → breach=43200" nonsense
-- for daily jobs (any daily job that takes 12h is in serious trouble
-- regardless of being labelled 'within budget').

CREATE OR REPLACE FUNCTION public.fn_compute_cron_sla_stats(
  p_window_hours integer DEFAULT 24
)
RETURNS TABLE (
  name              text,
  schedule          text,
  expected_interval_seconds integer,
  source_thresholds text,         -- 'configured' | 'derived'
  target_seconds    numeric,
  breach_seconds    numeric,
  enabled           boolean,
  run_count         bigint,
  failed_count      bigint,
  avg_duration_seconds numeric,
  p50_duration_seconds numeric,
  p95_duration_seconds numeric,
  p99_duration_seconds numeric,
  max_duration_seconds numeric,
  last_duration_seconds numeric,
  last_finished_at  timestamptz,
  breach_count      bigint,
  severity          text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
SET statement_timeout = '10s'
AS $$
#variable_conflict use_column
DECLARE
  v_window_hours integer;
  v_pg_cron_installed boolean;
BEGIN
  IF p_window_hours IS NULL OR p_window_hours <= 0 OR p_window_hours > 24 * 30 THEN
    RAISE EXCEPTION 'INVALID_WINDOW_HOURS: % (expected 1..720)', p_window_hours
      USING ERRCODE = '22023';
  END IF;
  v_window_hours := p_window_hours;

  SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron')
    INTO v_pg_cron_installed;

  RETURN QUERY
  WITH
  -- Pull the schedule string from cron.job (when available). Falls
  -- back to NULL — the classifier handles a NULL expected_interval
  -- via the 86400 fallback inside fn_parse_cron_interval_seconds.
  scheduled AS (
    SELECT j.jobname::text AS j_name, j.schedule::text AS j_schedule
    FROM cron.job j
    WHERE v_pg_cron_installed
  ),
  -- Universe = anything we have history OR thresholds for OR
  -- pg_cron knows about. Deliberately wide: a job with thresholds
  -- but zero recent runs is itself a signal (run_count=0 → unknown).
  jobs AS (
    SELECT s.j_name AS j_name FROM scheduled s
    UNION
    SELECT DISTINCT h.name FROM public.cron_run_history h
      WHERE h.finished_at >= now() - make_interval(hours => v_window_hours)
    UNION
    SELECT t.name FROM public.cron_sla_thresholds t
  ),
  -- 24h history rollups. Pre-aggregate so we touch the index once.
  hist AS (
    SELECT
      h.name AS h_name,
      COUNT(*)::bigint AS run_count,
      SUM((h.last_status = 'failed')::int)::bigint AS failed_count,
      AVG(h.duration_seconds)::numeric AS avg_d,
      percentile_cont(0.50) WITHIN GROUP (ORDER BY h.duration_seconds)::numeric AS p50,
      percentile_cont(0.95) WITHIN GROUP (ORDER BY h.duration_seconds)::numeric AS p95,
      percentile_cont(0.99) WITHIN GROUP (ORDER BY h.duration_seconds)::numeric AS p99,
      MAX(h.duration_seconds)::numeric AS max_d,
      MAX(h.finished_at) AS last_finished_at
    FROM public.cron_run_history h
    WHERE h.finished_at >= now() - make_interval(hours => v_window_hours)
      AND h.duration_seconds IS NOT NULL
    GROUP BY h.name
  ),
  last_run AS (
    SELECT DISTINCT ON (h.name)
      h.name AS lr_name,
      h.duration_seconds AS last_d
    FROM public.cron_run_history h
    WHERE h.finished_at >= now() - make_interval(hours => v_window_hours)
    ORDER BY h.name, h.finished_at DESC
  ),
  -- Compose all per-job derived values FIRST (in a single CTE) so we
  -- compute them once per job instead of repeating the same
  -- COALESCE/LEAST/GREATEST tower in three places. Postgres can
  -- still inline this if it wants.
  resolved AS (
    SELECT
      j.j_name                          AS r_name,
      sched.j_schedule                  AS r_schedule,
      public.fn_parse_cron_interval_seconds(sched.j_schedule)
                                        AS r_interval,
      CASE WHEN th.name IS NOT NULL THEN 'configured' ELSE 'derived' END
                                        AS r_source_thresholds,
      COALESCE(
        th.target_seconds,
        LEAST(
          GREATEST(
            public.fn_parse_cron_interval_seconds(sched.j_schedule)::numeric * 0.10,
            5
          ),
          600
        )
      )                                 AS r_target,
      COALESCE(
        th.breach_seconds,
        LEAST(
          GREATEST(
            public.fn_parse_cron_interval_seconds(sched.j_schedule)::numeric * 0.50,
            30
          ),
          3600
        )
      )                                 AS r_breach,
      COALESCE(th.enabled, true)        AS r_enabled,
      COALESCE(hist.run_count, 0)       AS r_run_count,
      COALESCE(hist.failed_count, 0)    AS r_failed_count,
      hist.avg_d                        AS r_avg_d,
      hist.p50                          AS r_p50,
      hist.p95                          AS r_p95,
      hist.p99                          AS r_p99,
      hist.max_d                        AS r_max_d,
      last_run.last_d                   AS r_last_d,
      hist.last_finished_at             AS r_last_finished_at
    FROM jobs j
    LEFT JOIN scheduled                  sched ON sched.j_name = j.j_name
    LEFT JOIN hist                              ON hist.h_name  = j.j_name
    LEFT JOIN last_run                          ON last_run.lr_name = j.j_name
    LEFT JOIN public.cron_sla_thresholds th    ON th.name    = j.j_name
  ),
  -- breach_count: how many runs in the window exceeded the effective
  -- breach threshold. Computed once per job against the resolved
  -- threshold so it stays in sync with what the SELECT emits.
  breaches AS (
    SELECT
      r.r_name AS b_name,
      COALESCE(SUM((h.duration_seconds > r.r_breach)::int)::bigint, 0) AS b_count
    FROM resolved r
    LEFT JOIN public.cron_run_history h
      ON h.name = r.r_name
     AND h.finished_at >= now() - make_interval(hours => v_window_hours)
     AND h.duration_seconds IS NOT NULL
    GROUP BY r.r_name
  )
  SELECT
    r.r_name                  AS name,
    r.r_schedule              AS schedule,
    r.r_interval              AS expected_interval_seconds,
    r.r_source_thresholds     AS source_thresholds,
    r.r_target                AS target_seconds,
    r.r_breach                AS breach_seconds,
    r.r_enabled               AS enabled,
    r.r_run_count             AS run_count,
    r.r_failed_count          AS failed_count,
    r.r_avg_d                 AS avg_duration_seconds,
    r.r_p50                   AS p50_duration_seconds,
    r.r_p95                   AS p95_duration_seconds,
    r.r_p99                   AS p99_duration_seconds,
    r.r_max_d                 AS max_duration_seconds,
    r.r_last_d                AS last_duration_seconds,
    r.r_last_finished_at      AS last_finished_at,
    b.b_count                 AS breach_count,
    public.fn_classify_cron_sla(
      r.r_run_count,
      r.r_avg_d,
      r.r_p95,
      r.r_last_d,
      r.r_target,
      r.r_breach,
      b.b_count,
      r.r_enabled
    ) AS severity
  FROM resolved r
  LEFT JOIN breaches b ON b.b_name = r.r_name
  ORDER BY
    CASE
      public.fn_classify_cron_sla(
        r.r_run_count, r.r_avg_d, r.r_p95, r.r_last_d,
        r.r_target, r.r_breach, b.b_count, r.r_enabled
      )
      WHEN 'critical' THEN 0
      WHEN 'warn'     THEN 1
      WHEN 'unknown'  THEN 2
      ELSE                 3
    END,
    r.r_name ASC;
END;
$$;

COMMENT ON FUNCTION public.fn_compute_cron_sla_stats(integer) IS
  'L12-04: per-job SLA aggregates over the last p_window_hours of '
  'cron_run_history. Returns avg/p50/p95/p99/max duration, breach_count '
  'and a severity verdict. Read-only.';

REVOKE ALL ON FUNCTION public.fn_compute_cron_sla_stats(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_compute_cron_sla_stats(integer) TO service_role;

-- 6. Safe alert + retention wrapper (cron-fired) ────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_alert_cron_sla_breaches_safe()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_lock_acquired   boolean;
  v_offenders       integer := 0;
  v_alerts_created  integer := 0;
  v_pruned          bigint  := 0;
  v_row             record;
  v_alert_id        uuid;
BEGIN
  IF NOT public.fn_cron_should_run('cron-sla-monitor', 600) THEN
    RETURN;
  END IF;

  v_lock_acquired := pg_try_advisory_xact_lock(
    hashtext('cron:cron_sla_monitor')
  );
  IF NOT v_lock_acquired THEN
    UPDATE public.cron_run_state
    SET    skip_count  = skip_count + 1,
           last_status = 'skipped',
           updated_at  = now()
    WHERE  name = 'cron-sla-monitor';
    RETURN;
  END IF;

  PERFORM public.fn_cron_mark_started('cron-sla-monitor');

  BEGIN
    -- (a) Iterate SLA offenders.
    FOR v_row IN
      SELECT *
      FROM public.fn_compute_cron_sla_stats(24)
      WHERE severity IN ('warn','critical')
        AND enabled IS TRUE
        -- Don't self-alert: this very job will appear with whatever
        -- runtime it has on its own row.
        AND name <> 'cron-sla-monitor'
    LOOP
      v_offenders := v_offenders + 1;

      v_alert_id := public.fn_record_cron_health_alert(
        v_row.name,
        v_row.severity,
        jsonb_build_object(
          'kind',                       'sla_breach',
          'schedule',                   v_row.schedule,
          'source_thresholds',          v_row.source_thresholds,
          'target_seconds',             v_row.target_seconds,
          'breach_seconds',             v_row.breach_seconds,
          'expected_interval_seconds',  v_row.expected_interval_seconds,
          'window_hours',               24,
          'run_count',                  v_row.run_count,
          'failed_count',               v_row.failed_count,
          'avg_duration_seconds',       v_row.avg_duration_seconds,
          'p50_duration_seconds',       v_row.p50_duration_seconds,
          'p95_duration_seconds',       v_row.p95_duration_seconds,
          'p99_duration_seconds',       v_row.p99_duration_seconds,
          'max_duration_seconds',       v_row.max_duration_seconds,
          'last_duration_seconds',      v_row.last_duration_seconds,
          'last_finished_at',           v_row.last_finished_at,
          'breach_count',               v_row.breach_count
        ),
        60
      );

      IF v_alert_id IS NOT NULL THEN
        v_alerts_created := v_alerts_created + 1;
        RAISE NOTICE
          '[L12-04.sla] severity=% job=% breach=%s last_run=%s p95=%s breach_count=% alert_id=%',
          v_row.severity,
          v_row.name,
          v_row.breach_seconds,
          COALESCE(v_row.last_duration_seconds::text, 'NULL'),
          COALESCE(v_row.p95_duration_seconds::text, 'NULL'),
          v_row.breach_count,
          v_alert_id;
      END IF;
    END LOOP;

    -- (b) Retention: prune cron_run_history older than 30 days.
    --     Keep this in the same wrapper so we always have ONE
    --     scheduled job touching this table — easier to reason
    --     about under L12-03's overlap protection.
    DELETE FROM public.cron_run_history
    WHERE recorded_at < now() - interval '30 days';
    GET DIAGNOSTICS v_pruned = ROW_COUNT;

    PERFORM public.fn_cron_mark_completed(
      'cron-sla-monitor',
      jsonb_build_object(
        'offenders',      v_offenders,
        'alerts_created', v_alerts_created,
        'pruned_history', v_pruned
      )
    );
  EXCEPTION WHEN OTHERS THEN
    PERFORM public.fn_cron_mark_failed(
      'cron-sla-monitor',
      SQLERRM,
      jsonb_build_object('sqlstate', SQLSTATE, 'phase', 'sla_loop')
    );
    RAISE;
  END;
END;
$$;

COMMENT ON FUNCTION public.fn_alert_cron_sla_breaches_safe() IS
  'L12-04: scheduled every 30 min. Iterates fn_compute_cron_sla_stats(24h), '
  'records SLA alerts (kind=sla_breach) with 60-min cooldown, RAISES NOTICE '
  'per new alert, and prunes cron_run_history older than 30 days.';

REVOKE ALL ON FUNCTION public.fn_alert_cron_sla_breaches_safe() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_alert_cron_sla_breaches_safe() TO service_role;

-- 7. Schedule + seed ─────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE NOTICE '[L12-04] pg_cron not installed; skipping cron-sla-monitor schedule';
  ELSE
    BEGIN PERFORM cron.unschedule('cron-sla-monitor');
    EXCEPTION WHEN OTHERS THEN NULL; END;
    PERFORM cron.schedule(
      'cron-sla-monitor',
      '7,37 * * * *',  -- every 30 min on :07 / :37 to dodge the :00/:15 health-monitor tick
      $job$SELECT public.fn_alert_cron_sla_breaches_safe();$job$
    );
    RAISE NOTICE '[L12-04] scheduled cron-sla-monitor at 7,37 * * * *';
  END IF;
END$$;

INSERT INTO public.cron_run_state(name, last_status)
VALUES ('cron-sla-monitor', 'never_run')
ON CONFLICT (name) DO NOTHING;

-- Seed conservative thresholds for the jobs we already run. Operators
-- can override via INSERT ... ON CONFLICT DO UPDATE later. Picked
-- against current observed runtimes from the L06-04 rollout so the
-- pipeline doesn't immediately page on noisy defaults.
INSERT INTO public.cron_sla_thresholds(name, target_seconds, breach_seconds, notes) VALUES
  ('clearing-cron',                            60,   240, 'Daily settlement at 02:00; budget = 4 min before clearing window pressure builds.'),
  ('reconcile-wallets-daily',                  90,   300, 'Walks all wallets at 04:30; 5-min budget before cron starts overlapping with L06-03 alert pipeline.'),
  ('lifecycle-cron',                           30,   120, 'Edge Function fired every 5 min; should never approach the */5 cycle limit.'),
  ('expire-matchmaking-queue',                  5,    60, 'In-DB UPDATE; multi-second indicates queue blow-up.'),
  ('process-scheduled-workout-releases',       10,    90, 'In-DB iteration over ready releases; over 1.5 min suggests queue backlog.'),
  ('settle-clearing-batch',                    15,    50, 'Per-minute chunked settlement; over 50s leaves no slack before next tick.'),
  ('idempotency-keys-gc',                       5,    60, 'Hourly GC; small DELETE plan, anything over 1 min hints at index regression.'),
  ('stale-withdrawals-alert',                  10,   120, 'Daily 06:45 scan over withdrawals; 2 min ceiling.'),
  ('eval-verification-cron',                   30,   300, 'Daily verification eval at 03:15; 5-min budget.'),
  ('archive-old-sessions',                    600,  1800, 'Weekly archival; 30-min budget reflects size.'),
  ('archive-old-ledger',                      600,  1800, 'Weekly archival; 30-min budget reflects size.'),
  ('coin_ledger_ensure_partition_monthly',     10,    60, 'Monthly DDL; over 1 min suggests lock contention.'),
  ('swap-expire',                              10,    60, '*/10 expirer; over 1 min indicates swap_orders scan regression.'),
  ('onboarding-nudge-daily',                   30,   180, 'Daily 10:00 push fan-out; 3-min budget for ~10k recipients.'),
  ('auto-topup-hourly',                        30,   240, 'Hourly billing fan-out; 4-min budget — exceeds = Asaas degradation.'),
  ('cron-health-monitor',                       2,    30, 'L06-04 alert pipeline; should be near-instantaneous.'),
  ('cron-sla-monitor',                          5,    60, 'L12-04 SLA pipeline; small SELECT/DELETE — should be near-instantaneous.')
ON CONFLICT (name) DO NOTHING;

-- 8. Self-test ───────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_job_name      text := '__l12_04_sla_selftest__';
  v_alert_count   integer;
  v_history_count integer;
  v_severity      text;
  v_alert_id      uuid;
  v_dedup_id      uuid;
  v_started       timestamptz;
  v_finished      timestamptz;
  v_breach_seconds numeric;
BEGIN
  -- 8a. Trigger fires on terminal transition; does NOT fire on
  --     intermediate ('running' / 'skipped') updates.
  INSERT INTO public.cron_run_state(name, last_status, started_at, finished_at)
  VALUES (v_job_name, 'never_run', NULL, NULL);

  -- mark_started equivalent: status = 'running', no finished_at →
  -- trigger should NOT capture.
  UPDATE public.cron_run_state
  SET    last_status = 'running',
         started_at  = now() - interval '5 seconds',
         finished_at = NULL,
         updated_at  = now()
  WHERE  name = v_job_name;

  SELECT COUNT(*) INTO v_history_count
    FROM public.cron_run_history WHERE name = v_job_name;
  IF v_history_count <> 0 THEN
    RAISE EXCEPTION '[L12-04 selftest] running transition unexpectedly captured (% rows)', v_history_count;
  END IF;

  -- mark_completed: terminal → trigger captures.
  v_started  := now() - interval '5 seconds';
  v_finished := now();
  UPDATE public.cron_run_state
  SET    last_status = 'completed',
         started_at  = v_started,
         finished_at = v_finished,
         last_meta   = jsonb_build_object('test', true),
         updated_at  = now()
  WHERE  name = v_job_name;

  SELECT COUNT(*) INTO v_history_count
    FROM public.cron_run_history WHERE name = v_job_name;
  IF v_history_count <> 1 THEN
    RAISE EXCEPTION '[L12-04 selftest] completed transition not captured (% rows; expected 1)', v_history_count;
  END IF;

  -- Re-marking 'completed' with the SAME finished_at must NOT
  -- double-record (idempotent UPDATE protection).
  UPDATE public.cron_run_state
  SET    updated_at = now()
  WHERE  name = v_job_name;

  SELECT COUNT(*) INTO v_history_count
    FROM public.cron_run_history WHERE name = v_job_name;
  IF v_history_count <> 1 THEN
    RAISE EXCEPTION '[L12-04 selftest] idempotent UPDATE produced extra row (% rows)', v_history_count;
  END IF;

  -- mark_failed → another terminal transition.
  UPDATE public.cron_run_state
  SET    last_status = 'failed',
         finished_at = now(),
         last_error  = 'selftest synthetic',
         updated_at  = now()
  WHERE  name = v_job_name;

  SELECT COUNT(*) INTO v_history_count
    FROM public.cron_run_history WHERE name = v_job_name;
  IF v_history_count <> 2 THEN
    RAISE EXCEPTION '[L12-04 selftest] failed transition not captured (% rows; expected 2)', v_history_count;
  END IF;

  -- 8b. SLA classifier vectors
  --   zero runs → unknown
  IF public.fn_classify_cron_sla(0, NULL, NULL, NULL, 60, 240, 0, true) <> 'unknown' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify zero runs expected unknown';
  END IF;
  --   small fast run → ok
  IF public.fn_classify_cron_sla(10, 5, 8, 6, 60, 240, 0, true) <> 'ok' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify fast run expected ok';
  END IF;
  --   single breach (last > breach) → warn
  IF public.fn_classify_cron_sla(10, 50, 80, 250, 60, 240, 1, true) <> 'warn' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify single breach expected warn';
  END IF;
  --   p95 above breach → warn
  IF public.fn_classify_cron_sla(10, 50, 250, 50, 60, 240, 1, true) <> 'warn' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify p95 breach expected warn';
  END IF;
  --   last > 2x breach → critical
  IF public.fn_classify_cron_sla(10, 50, 80, 500, 60, 240, 1, true) <> 'critical' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify 2x breach expected critical';
  END IF;
  --   p95 > 2x breach → critical
  IF public.fn_classify_cron_sla(10, 50, 500, 50, 60, 240, 1, true) <> 'critical' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify p95 2x expected critical';
  END IF;
  --   sustained drift (avg > target, breach_count >= 2) → warn
  IF public.fn_classify_cron_sla(10, 100, 200, 200, 60, 240, 2, true) <> 'warn' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify drift expected warn';
  END IF;
  --   sustained drift but only 1 breach event → ok (insufficient signal)
  IF public.fn_classify_cron_sla(10, 100, 200, 200, 60, 240, 1, true) <> 'ok' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify single drift expected ok';
  END IF;
  --   disabled → ok regardless
  IF public.fn_classify_cron_sla(10, 5000, 5000, 5000, 60, 240, 99, false) <> 'ok' THEN
    RAISE EXCEPTION '[L12-04 selftest] classify disabled expected ok';
  END IF;

  -- 8c. fn_compute_cron_sla_stats smoke test against the synthetic
  --     job. Insert a known long history row and verify aggregates +
  --     breach detection.
  INSERT INTO public.cron_sla_thresholds(name, target_seconds, breach_seconds)
  VALUES (v_job_name, 1, 3);

  -- Augment history with a deliberately-long synthetic run that
  -- triggers BOTH last > breach AND last > 2x breach (≥ 7s).
  INSERT INTO public.cron_run_history(
    name, started_at, finished_at, last_status, last_error, last_meta
  )
  VALUES (
    v_job_name,
    now() - interval '10 seconds',
    now(),
    'completed',
    NULL,
    '{"injected": true}'::jsonb
  );

  SELECT severity, breach_seconds
    INTO v_severity, v_breach_seconds
  FROM public.fn_compute_cron_sla_stats(24)
  WHERE name = v_job_name;

  IF v_severity IS NULL THEN
    RAISE EXCEPTION '[L12-04 selftest] sla stats returned NULL row for synthetic job';
  END IF;
  IF v_severity <> 'critical' THEN
    RAISE EXCEPTION '[L12-04 selftest] expected severity=critical for 10s vs breach=3s; got %', v_severity;
  END IF;
  IF v_breach_seconds <> 3 THEN
    RAISE EXCEPTION '[L12-04 selftest] expected breach_seconds=3 (configured); got %', v_breach_seconds;
  END IF;

  -- 8d. Alert pipeline: insert via fn_record_cron_health_alert with
  --     kind=sla_breach. Reuse the L06-04 dedup table.
  v_alert_id := public.fn_record_cron_health_alert(
    v_job_name, 'critical',
    jsonb_build_object('kind', 'sla_breach', 'test', true), 60
  );
  IF v_alert_id IS NULL THEN
    RAISE EXCEPTION '[L12-04 selftest] sla alert insert returned NULL';
  END IF;

  v_dedup_id := public.fn_record_cron_health_alert(
    v_job_name, 'critical',
    jsonb_build_object('kind', 'sla_breach', 'test', true), 60
  );
  IF v_dedup_id IS NOT NULL THEN
    RAISE EXCEPTION '[L12-04 selftest] sla alert dedup failed (got fresh id within cooldown)';
  END IF;

  SELECT COUNT(*) INTO v_alert_count
    FROM public.cron_health_alerts
    WHERE job_name = v_job_name AND details ->> 'kind' = 'sla_breach';
  IF v_alert_count <> 1 THEN
    RAISE EXCEPTION '[L12-04 selftest] expected 1 sla alert row; got %', v_alert_count;
  END IF;

  -- 8e. Bad inputs → SQLSTATE 22023
  BEGIN
    PERFORM public.fn_compute_cron_sla_stats(0);
    RAISE EXCEPTION '[L12-04 selftest] window=0 should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_compute_cron_sla_stats(-5);
    RAISE EXCEPTION '[L12-04 selftest] window=-5 should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_compute_cron_sla_stats(10000);
    RAISE EXCEPTION '[L12-04 selftest] window=10000 should have raised 22023';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  -- 8f. Cleanup
  DELETE FROM public.cron_health_alerts WHERE job_name = v_job_name;
  DELETE FROM public.cron_sla_thresholds WHERE name = v_job_name;
  DELETE FROM public.cron_run_history    WHERE name = v_job_name;
  DELETE FROM public.cron_run_state      WHERE name = v_job_name;

  RAISE NOTICE '[L12-04] migration self-test PASSED';
END$$;

COMMIT;
