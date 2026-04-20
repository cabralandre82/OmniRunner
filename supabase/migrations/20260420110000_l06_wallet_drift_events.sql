-- ============================================================================
-- L06-03 — reconcile-wallets-cron sem alerta em drift > 0
--
-- Audit reference:
--   docs/audit/findings/L06-03-reconcile-wallets-cron-sem-alerta-em-drift-0.md
--   docs/audit/parts/06-coo.md  (anchor [6.3])
--
-- Problem
-- ───────
--   `supabase/functions/reconcile-wallets-cron/index.ts` calls
--   `public.reconcile_all_wallets()` daily, which auto-corrects any
--   wallet whose `balance_coins` drifts from `SUM(coin_ledger.delta_coins)`.
--   When drift IS detected (`drifted > 0`), the function only writes a
--   structured `console.error(...)` line — there is no:
--
--     • Persistent forensic record on the database side
--       (the function relies on the log aggregator never dropping a line),
--     • Severity-tiered escalation (1 wallet drifting is noteworthy;
--       50 wallets drifting in the same run is a P1 incident),
--     • Channel-aware notification (today the on-call has to be already
--       grepping logs to notice; nothing pages or pings).
--
--   Drift is the canonical signal that something in
--   `execute_burn_atomic`, `fn_increment_wallets_batch` or one of the
--   other authorised mutators has a bug. Missing it is the difference
--   between a 24h-MTTR incident and a quarterly accounting clean-up.
--
-- Defence (this migration)
-- ───────
--   • `public.wallet_drift_events`
--     Append-only forensic table that survives any log pipeline.
--     One row per reconcile run that *observed* drift (severity ≥ warn).
--     Severity is derived deterministically by
--     `fn_classify_wallet_drift_severity()` — same logic as the TS helper
--     in `_shared/wallet_drift.ts`, kept as a single source of truth so
--     SQL ad-hoc queries match what the edge function emitted.
--
--   • `fn_classify_wallet_drift_severity(p_drifted_count, p_warn_threshold)`
--     IMMUTABLE pure function. Returns 'ok' | 'warn' | 'critical'.
--     `p_warn_threshold` defaults to 10 — anything ≤ that is a warn,
--     anything above is a P1 critical.
--
--   • `fn_record_wallet_drift_event(p_run_id, p_total, p_drifted,
--                                    p_severity, p_notes)`
--     SECURITY DEFINER + locked search_path + lock_timeout=2s. Used by
--     the edge function to persist the event BEFORE attempting any
--     external alert (so a Slack/Sentry outage cannot lose the trail).
--
--   • `fn_mark_wallet_drift_event_alerted(p_event_id, p_channel, p_error)`
--     Updates the row after Slack/PagerDuty/etc. responds. `p_error IS NULL`
--     => alerted=true; otherwise alerted stays false and `alert_error` is
--     populated for the WALLET_RECONCILIATION_RUNBOOK forensic queries.
--
--   • RLS forced + service-role only — only the cron function (running
--     as service role) and the platform admin (querying via service role)
--     ever read or write this table.
--
--   • Indexes:
--       - `(observed_at DESC)` for the ops dashboard ("last 30 drift
--         events").
--       - Partial `(severity, observed_at)` WHERE `severity != 'ok' AND
--         alerted = false` for the on-call query "events that should
--         have been paged but weren't" — empty in steady state.
--
-- Verification (this migration)
-- ───────
--   In-transaction self-test exercises:
--     1. classify(0/1/10/11/9999) returns the documented enum
--     2. record() inserts a row and returns its id
--     3. mark_alerted() sets alerted=true on success path
--     4. mark_alerted() with p_error keeps alerted=false
--   All test rows are deleted before COMMIT — table is clean post-migration.
-- ============================================================================

BEGIN;

-- 1. Forensic table ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.wallet_drift_events (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id          uuid          NOT NULL,
  observed_at     timestamptz   NOT NULL DEFAULT now(),
  total_wallets   integer       NOT NULL CHECK (total_wallets >= 0),
  drifted_count   integer       NOT NULL CHECK (drifted_count >= 0),
  severity        text          NOT NULL CHECK (severity IN ('ok','warn','critical')),
  alerted         boolean       NOT NULL DEFAULT false,
  alert_channel   text          NULL CHECK (
                                  alert_channel IS NULL
                                  OR length(trim(alert_channel)) BETWEEN 2 AND 32
                                ),
  alert_error     text          NULL,
  notes           jsonb         NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE  public.wallet_drift_events IS
  'L06-03: forensic record of reconcile-wallets-cron drift detections. '
  'Persisted BEFORE any external alert so a Slack/PagerDuty outage cannot '
  'lose the trail. One row per reconcile run with severity ≥ warn.';
COMMENT ON COLUMN public.wallet_drift_events.run_id IS
  'request_id of the edge function invocation that produced this event.';
COMMENT ON COLUMN public.wallet_drift_events.severity IS
  'Output of fn_classify_wallet_drift_severity. Mirror in TS '
  '`_shared/wallet_drift.ts::classifyWalletDrift`.';
COMMENT ON COLUMN public.wallet_drift_events.alerted IS
  'true ⇔ external alert (Slack/PagerDuty) responded 2xx. '
  'false ⇔ either alerting was disabled (no webhook env) OR delivery failed; '
  'see alert_error for the failure reason.';
COMMENT ON COLUMN public.wallet_drift_events.notes IS
  'jsonb extension point: thresholds in effect, environment label, slack '
  'response status, etc. Must NOT contain PII.';

ALTER TABLE public.wallet_drift_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_drift_events FORCE ROW LEVEL SECURITY;
-- No policy created → only service_role (which bypasses RLS) can touch it.

CREATE INDEX IF NOT EXISTS idx_wallet_drift_events_observed_at
  ON public.wallet_drift_events (observed_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_drift_events_unalerted
  ON public.wallet_drift_events (severity, observed_at)
  WHERE severity != 'ok' AND alerted = false;

CREATE INDEX IF NOT EXISTS idx_wallet_drift_events_run_id
  ON public.wallet_drift_events (run_id);

-- 2. Severity classifier ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_classify_wallet_drift_severity(
  p_drifted_count  integer,
  p_warn_threshold integer DEFAULT 10
)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN p_drifted_count IS NULL OR p_drifted_count <= 0  THEN 'ok'
    WHEN p_drifted_count <= GREATEST(COALESCE(p_warn_threshold, 10), 0)
                                                          THEN 'warn'
    ELSE                                                       'critical'
  END;
$$;

COMMENT ON FUNCTION public.fn_classify_wallet_drift_severity(integer, integer) IS
  'L06-03: deterministic severity classification of reconcile-cron drift. '
  '0/null/negative → ok; 1..warn_threshold → warn; >warn_threshold → critical. '
  'Mirrored 1:1 by TS helper supabase/functions/_shared/wallet_drift.ts::classifyWalletDrift.';

-- 3. Persist drift event ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_record_wallet_drift_event(
  p_run_id          uuid,
  p_total_wallets   integer,
  p_drifted_count   integer,
  p_severity        text,
  p_notes           jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF p_run_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_RUN_ID: p_run_id is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_severity IS NULL OR p_severity NOT IN ('ok','warn','critical') THEN
    RAISE EXCEPTION 'INVALID_SEVERITY: % (expected ok|warn|critical)', p_severity
      USING ERRCODE = '22023';
  END IF;
  IF p_total_wallets IS NULL OR p_total_wallets < 0 THEN
    RAISE EXCEPTION 'INVALID_TOTAL_WALLETS: %', p_total_wallets
      USING ERRCODE = '22023';
  END IF;
  IF p_drifted_count IS NULL OR p_drifted_count < 0 THEN
    RAISE EXCEPTION 'INVALID_DRIFTED_COUNT: %', p_drifted_count
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.wallet_drift_events
    (run_id, total_wallets, drifted_count, severity, notes)
  VALUES
    (p_run_id, p_total_wallets, p_drifted_count, p_severity,
     COALESCE(p_notes, '{}'::jsonb))
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.fn_record_wallet_drift_event(uuid, integer, integer, text, jsonb) IS
  'L06-03: persist reconcile-wallets-cron drift event BEFORE any external '
  'alert attempt. Service-role only (RLS-forced table). Returns event id '
  'so caller can later mark it alerted via fn_mark_wallet_drift_event_alerted.';

-- 4. Mark event as alerted ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_mark_wallet_drift_event_alerted(
  p_event_id  uuid,
  p_channel   text,
  p_error     text DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
BEGIN
  IF p_event_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_EVENT_ID: p_event_id is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_channel IS NULL OR length(trim(p_channel)) < 2 THEN
    RAISE EXCEPTION 'INVALID_CHANNEL: % (expected non-empty label)', p_channel
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.wallet_drift_events
     SET alerted       = (p_error IS NULL),
         alert_channel = trim(p_channel),
         alert_error   = p_error
   WHERE id = p_event_id;

  RETURN FOUND;
END;
$$;

COMMENT ON FUNCTION public.fn_mark_wallet_drift_event_alerted(uuid, text, text) IS
  'L06-03: record outcome of external alert delivery. p_error IS NULL '
  '⇒ alerted=true; otherwise alerted stays false and alert_error keeps '
  'the failure reason for forensic queries.';

-- 5. Self-test ──────────────────────────────────────────────────────────────
DO $$
DECLARE
  v_run_id     uuid := gen_random_uuid();
  v_event_id   uuid;
  v_event_id2  uuid;
  v_severity   text;
  v_alerted    boolean;
  v_channel    text;
  v_err        text;
BEGIN
  -- 5.1 classifier table
  IF public.fn_classify_wallet_drift_severity(0)        != 'ok'        THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(0) != ok';   END IF;
  IF public.fn_classify_wallet_drift_severity(NULL)     != 'ok'        THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(NULL) != ok';END IF;
  IF public.fn_classify_wallet_drift_severity(-3)       != 'ok'        THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(-3) != ok';  END IF;
  IF public.fn_classify_wallet_drift_severity(1)        != 'warn'      THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(1) != warn'; END IF;
  IF public.fn_classify_wallet_drift_severity(10)       != 'warn'      THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(10) != warn';END IF;
  IF public.fn_classify_wallet_drift_severity(11)       != 'critical'  THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(11) != critical';END IF;
  IF public.fn_classify_wallet_drift_severity(9999)     != 'critical'  THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(9999) != critical';END IF;
  -- custom threshold
  IF public.fn_classify_wallet_drift_severity(5, 3)     != 'critical'  THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(5, threshold=3) != critical';
  END IF;
  IF public.fn_classify_wallet_drift_severity(3, 3)     != 'warn'      THEN
    RAISE EXCEPTION 'L06-03 self-test: classify(3, threshold=3) != warn';
  END IF;

  -- 5.2 record() happy path
  v_event_id := public.fn_record_wallet_drift_event(
    v_run_id, 100, 5, 'warn',
    jsonb_build_object('self_test', true, 'environment', 'migration')
  );
  IF v_event_id IS NULL THEN
    RAISE EXCEPTION 'L06-03 self-test: record() returned NULL';
  END IF;

  SELECT severity, alerted, alert_channel
    INTO v_severity, v_alerted, v_channel
    FROM public.wallet_drift_events WHERE id = v_event_id;
  IF v_severity != 'warn' OR v_alerted IS NOT FALSE OR v_channel IS NOT NULL THEN
    RAISE EXCEPTION 'L06-03 self-test: row shape unexpected severity=% alerted=% channel=%',
      v_severity, v_alerted, v_channel;
  END IF;

  -- 5.3 record() rejects bad inputs
  BEGIN
    PERFORM public.fn_record_wallet_drift_event(NULL, 1, 0, 'ok');
    RAISE EXCEPTION 'L06-03 self-test: record(NULL run_id) should have failed';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_record_wallet_drift_event(v_run_id, 1, 0, 'fatal');
    RAISE EXCEPTION 'L06-03 self-test: record(severity=fatal) should have failed';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_record_wallet_drift_event(v_run_id, -1, 0, 'ok');
    RAISE EXCEPTION 'L06-03 self-test: record(total=-1) should have failed';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  -- 5.4 mark_alerted() success path
  IF NOT public.fn_mark_wallet_drift_event_alerted(v_event_id, 'slack') THEN
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(success) returned false';
  END IF;
  SELECT alerted, alert_channel, alert_error
    INTO v_alerted, v_channel, v_err
    FROM public.wallet_drift_events WHERE id = v_event_id;
  IF v_alerted IS NOT TRUE OR v_channel != 'slack' OR v_err IS NOT NULL THEN
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(success) state wrong: alerted=% channel=% err=%',
      v_alerted, v_channel, v_err;
  END IF;

  -- 5.5 mark_alerted() failure path keeps alerted=false
  v_event_id2 := public.fn_record_wallet_drift_event(
    v_run_id, 100, 50, 'critical',
    jsonb_build_object('self_test', true)
  );
  IF NOT public.fn_mark_wallet_drift_event_alerted(v_event_id2, 'slack', 'HTTP 500') THEN
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(error) returned false';
  END IF;
  SELECT alerted, alert_channel, alert_error
    INTO v_alerted, v_channel, v_err
    FROM public.wallet_drift_events WHERE id = v_event_id2;
  IF v_alerted IS NOT FALSE OR v_channel != 'slack' OR v_err != 'HTTP 500' THEN
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(error) state wrong: alerted=% channel=% err=%',
      v_alerted, v_channel, v_err;
  END IF;

  -- 5.6 mark_alerted() rejects bad inputs
  BEGIN
    PERFORM public.fn_mark_wallet_drift_event_alerted(NULL, 'slack');
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(NULL id) should have failed';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;
  BEGIN
    PERFORM public.fn_mark_wallet_drift_event_alerted(v_event_id, '');
    RAISE EXCEPTION 'L06-03 self-test: mark_alerted(empty channel) should have failed';
  EXCEPTION WHEN sqlstate '22023' THEN NULL;
  END;

  -- 5.7 partial index targets unalerted criticals
  IF (SELECT count(*) FROM public.wallet_drift_events
        WHERE severity = 'critical' AND alerted = false) < 1 THEN
    RAISE EXCEPTION 'L06-03 self-test: critical+unalerted row not visible';
  END IF;

  -- 5.8 cleanup
  DELETE FROM public.wallet_drift_events WHERE id IN (v_event_id, v_event_id2);

  RAISE NOTICE '[L06-03] migration self-test PASSED';
END $$;

COMMIT;
