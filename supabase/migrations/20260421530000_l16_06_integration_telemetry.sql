-- L16-06 — Integration telemetry (Strava / TrainingPeaks / etc).
--
-- Problem: `strava-webhook`, `strava-register-webhook`,
-- `trainingpeaks-oauth`, `trainingpeaks-sync` are all shipped
-- code paths that execute daily, but we have **zero visibility**
-- into:
--
--   • How many athletes are connected per provider?
--   • How many webhook events / syncs happen per day?
--   • What is the token-refresh error rate?
--   • Which users are getting `token_refresh_failed` repeatedly
--     (bad credentials, revoked scopes)?
--
-- This blocks the CAO wave because any "reduce integration
-- churn" initiative lacks a numerator. It also blocks the L06
-- COO wave because on-call can't tell whether a Strava outage
-- is starting (the outages are currently discovered via user
-- tickets).
--
-- This migration adds three primitives:
--
--   1. `public.integration_events` — append-only telemetry log,
--      one row per OAuth / webhook / sync event, with PII minimised.
--
--   2. `public.fn_log_integration_event(...)` — service-role-only
--      SECURITY DEFINER helper for edge functions to emit events
--      without exposing raw INSERT privilege.
--
--   3. `public.fn_integration_health_snapshot(provider, hours)` —
--      STABLE SECURITY DEFINER aggregator returning a dashboard-
--      ready `jsonb` payload: connected athletes, events by type,
--      error rate, p50/p95 latency.  Platform-admin only.
--
-- Retention: 90 days, registered with audit_logs_retention_config.
--
-- LGPD: no email, no IP, no exact coordinates. `user_id` may be
-- anonymised by `fn_delete_user_data` (FK ON DELETE SET NULL) so
-- historical aggregates survive erasure without violating Art. 18.

BEGIN;

-- ── 1. Append-only events log ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.integration_events (
  id            bigserial PRIMARY KEY,
  user_id       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  provider      text NOT NULL,
  event_type    text NOT NULL,
  status        text NOT NULL,
  error_code    text,
  latency_ms    integer,
  external_id   text,
  metadata      jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_integration_provider CHECK (
    provider IN (
      'strava','trainingpeaks','garmin','polar',
      'coros','suunto','apple_health','google_fit'
    )
  ),
  CONSTRAINT chk_integration_event_type CHECK (
    event_type IN (
      'oauth_start',
      'oauth_callback_success',
      'oauth_callback_error',
      'token_refresh_success',
      'token_refresh_failure',
      'webhook_received',
      'webhook_dedup',
      'webhook_validated',
      'session_imported',
      'session_ignored',
      'sync_success',
      'sync_failure',
      'disconnect',
      'token_revoked'
    )
  ),
  CONSTRAINT chk_integration_status CHECK (
    status IN ('success','error','skipped','ignored')
  ),
  CONSTRAINT chk_integration_error_code_length CHECK (
    error_code IS NULL OR length(error_code) <= 64
  ),
  CONSTRAINT chk_integration_external_id_length CHECK (
    external_id IS NULL OR length(external_id) <= 128
  ),
  CONSTRAINT chk_integration_latency CHECK (
    latency_ms IS NULL OR (latency_ms >= 0 AND latency_ms < 600000)
  )
);

COMMENT ON TABLE public.integration_events IS
  'L16-06 — append-only telemetry of OAuth/webhook/sync events per provider. PII-minimised (no IP, no email). Retention 90d via audit_logs_retention_config.';

CREATE INDEX IF NOT EXISTS idx_integration_events_provider_type_time
  ON public.integration_events(provider, event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_integration_events_user_time
  ON public.integration_events(user_id, created_at DESC)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_integration_events_errors
  ON public.integration_events(provider, created_at DESC)
  WHERE status = 'error';

ALTER TABLE public.integration_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS integration_events_own_read
  ON public.integration_events;
CREATE POLICY integration_events_own_read
  ON public.integration_events
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

GRANT SELECT ON public.integration_events TO authenticated;
GRANT ALL   ON public.integration_events TO service_role;
GRANT USAGE ON SEQUENCE integration_events_id_seq TO service_role;

-- ── 2. Writer helper (service-role only) ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_log_integration_event(
  p_provider    text,
  p_event_type  text,
  p_status      text,
  p_user_id     uuid    DEFAULT NULL,
  p_error_code  text    DEFAULT NULL,
  p_latency_ms  integer DEFAULT NULL,
  p_external_id text    DEFAULT NULL,
  p_metadata    jsonb   DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id          bigint;
  v_error_code  text := left(coalesce(p_error_code, ''), 64);
  v_external_id text := left(coalesce(p_external_id, ''), 128);
  v_latency     integer := p_latency_ms;
BEGIN
  IF p_provider IS NULL OR length(p_provider) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_PROVIDER';
  END IF;
  IF p_event_type IS NULL OR length(p_event_type) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EVENT_TYPE';
  END IF;
  IF p_status IS NULL OR length(p_status) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_STATUS';
  END IF;

  IF v_latency IS NOT NULL AND v_latency < 0 THEN
    v_latency := 0;
  END IF;
  IF v_latency IS NOT NULL AND v_latency >= 600000 THEN
    v_latency := 599999;
  END IF;

  INSERT INTO public.integration_events (
    user_id, provider, event_type, status,
    error_code, latency_ms, external_id, metadata
  ) VALUES (
    p_user_id,
    p_provider,
    p_event_type,
    p_status,
    nullif(v_error_code, ''),
    v_latency,
    nullif(v_external_id, ''),
    coalesce(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_log_integration_event(
  text, text, text, uuid, text, integer, text, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_log_integration_event(
  text, text, text, uuid, text, integer, text, jsonb
) TO service_role;

COMMENT ON FUNCTION public.fn_log_integration_event(
  text, text, text, uuid, text, integer, text, jsonb
) IS
  'L16-06 — single entry point for edge functions to record integration telemetry. Inputs are clamped (error_code <=64, external_id <=128, latency in [0, 599999]). Rejects empty provider/event_type/status with 22023.';

-- ── 3. Health snapshot aggregator (platform-admin only) ────────────────────

CREATE OR REPLACE FUNCTION public.fn_integration_health_snapshot(
  p_provider      text    DEFAULT NULL,
  p_window_hours  integer DEFAULT 24
) RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_window_hours integer := greatest(1, least(coalesce(p_window_hours, 24), 720));
  v_since        timestamptz := now() - make_interval(hours => v_window_hours);
  v_providers    text[] := CASE
    WHEN p_provider IS NULL THEN ARRAY[
      'strava','trainingpeaks','garmin','polar',
      'coros','suunto','apple_health','google_fit'
    ]
    ELSE ARRAY[p_provider]
  END;
  v_result jsonb := '{}'::jsonb;
  v_prov   text;
  v_block  jsonb;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.platform_role = 'admin'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FORBIDDEN';
  END IF;

  FOREACH v_prov IN ARRAY v_providers LOOP
    WITH w AS (
      SELECT * FROM public.integration_events
       WHERE provider = v_prov
         AND created_at >= v_since
    ),
    by_type AS (
      SELECT event_type, status, count(*) AS n
        FROM w GROUP BY event_type, status
    ),
    totals AS (
      SELECT
        count(*)::bigint                                    AS total,
        count(*) FILTER (WHERE status = 'error')::bigint     AS errors,
        count(*) FILTER (WHERE status = 'success')::bigint   AS successes,
        count(DISTINCT user_id) FILTER (WHERE user_id IS NOT NULL) AS affected_users,
        percentile_cont(0.5)  WITHIN GROUP (ORDER BY latency_ms) FILTER (WHERE latency_ms IS NOT NULL) AS p50,
        percentile_cont(0.95) WITHIN GROUP (ORDER BY latency_ms) FILTER (WHERE latency_ms IS NOT NULL) AS p95
      FROM w
    )
    SELECT jsonb_build_object(
      'window_hours',    v_window_hours,
      'total_events',    coalesce((SELECT total FROM totals), 0),
      'error_count',     coalesce((SELECT errors FROM totals), 0),
      'success_count',   coalesce((SELECT successes FROM totals), 0),
      'affected_users',  coalesce((SELECT affected_users FROM totals), 0),
      'error_rate',      CASE
                           WHEN coalesce((SELECT total FROM totals), 0) = 0 THEN 0
                           ELSE round(
                             (SELECT errors FROM totals)::numeric /
                             (SELECT total FROM totals)::numeric, 4)
                         END,
      'latency_p50_ms',  coalesce((SELECT p50 FROM totals), 0),
      'latency_p95_ms',  coalesce((SELECT p95 FROM totals), 0),
      'by_event_type',   coalesce(
        (SELECT jsonb_object_agg(event_type || ':' || status, n)
           FROM by_type),
        '{}'::jsonb)
    ) INTO v_block;

    v_result := v_result || jsonb_build_object(v_prov, v_block);
  END LOOP;

  RETURN jsonb_build_object(
    'generated_at', now(),
    'providers',    v_result
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_integration_health_snapshot(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_integration_health_snapshot(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_integration_health_snapshot(text, integer) TO service_role;

COMMENT ON FUNCTION public.fn_integration_health_snapshot(text, integer) IS
  'L16-06 — returns integration dashboard payload. Only platform_role=admin callers are allowed (42501 otherwise). Window clamped to [1,720] hours.';

-- ── 4. Connected-athletes aggregator (public-but-gated) ────────────────────

CREATE OR REPLACE FUNCTION public.fn_integration_connected_counts()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_strava_count bigint := 0;
  v_tp_count     bigint := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.platform_role = 'admin'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'FORBIDDEN';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'strava_connections') THEN
    SELECT count(*) INTO v_strava_count FROM public.strava_connections;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'coaching_device_links') THEN
    SELECT count(*) INTO v_tp_count
      FROM public.coaching_device_links
     WHERE provider = 'trainingpeaks';
  END IF;

  RETURN jsonb_build_object(
    'strava',        v_strava_count,
    'trainingpeaks', v_tp_count,
    'generated_at',  now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_integration_connected_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_integration_connected_counts() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_integration_connected_counts() TO service_role;

-- ── 5. Register 90-day retention ───────────────────────────────────────────

DO $retention$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class WHERE relname = 'audit_logs_retention_config'
  ) THEN
    INSERT INTO public.audit_logs_retention_config (
      schema_name, table_name, retention_days, enabled, batch_limit,
      timestamp_column, note
    ) VALUES (
      'public',
      'integration_events',
      90,
      true,
      10000,
      'created_at',
      'L16-06 — integration telemetry; 90d retention.'
    )
    ON CONFLICT DO NOTHING;
  END IF;
END
$retention$;

-- ── 6. Self-test ───────────────────────────────────────────────────────────

DO $$
DECLARE
  v_id bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'fn_log_integration_event'
  ) THEN
    RAISE EXCEPTION 'L16-06 self-test: fn_log_integration_event missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'fn_integration_health_snapshot'
  ) THEN
    RAISE EXCEPTION 'L16-06 self-test: fn_integration_health_snapshot missing';
  END IF;

  -- (a) happy-path writer
  v_id := public.fn_log_integration_event(
    p_provider    => 'strava',
    p_event_type  => 'webhook_received',
    p_status      => 'success',
    p_latency_ms  => 42,
    p_external_id => 'test-activity-1',
    p_metadata    => jsonb_build_object('selftest', true)
  );
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'L16-06 self-test: writer returned NULL id';
  END IF;

  -- (b) empty provider rejected
  BEGIN
    PERFORM public.fn_log_integration_event('', 'oauth_start', 'success');
    RAISE EXCEPTION 'L16-06 self-test: empty provider should have raised 22023';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- (c) invalid enum blocked by CHECK
  BEGIN
    INSERT INTO public.integration_events (provider, event_type, status)
      VALUES ('strava', 'bogus_type', 'success');
    RAISE EXCEPTION 'L16-06 self-test: bogus event_type should have been rejected';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- (d) latency clamping
  v_id := public.fn_log_integration_event(
    p_provider    => 'trainingpeaks',
    p_event_type  => 'sync_failure',
    p_status      => 'error',
    p_error_code  => 'TOKEN_EXPIRED',
    p_latency_ms  => 9999999,
    p_metadata    => jsonb_build_object('selftest', true)
  );
  IF (
    SELECT latency_ms FROM public.integration_events WHERE id = v_id
  ) <> 599999 THEN
    RAISE EXCEPTION 'L16-06 self-test: latency clamping failed';
  END IF;

  -- Cleanup
  DELETE FROM public.integration_events
   WHERE metadata ->> 'selftest' = 'true';

  RAISE NOTICE 'L16-06 self-test: OK';
END
$$;

COMMIT;
