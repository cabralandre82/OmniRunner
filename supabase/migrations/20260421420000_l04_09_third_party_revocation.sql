-- ============================================================================
-- L04-09 — Third-party OAuth revocation primitives
-- ============================================================================
--
-- Finding (docs/audit/findings/L04-09-terceiros-strava-trainingpeaks-nao-ha-processo-de-revogacao.md):
--   Deleting a user locally leaves their Strava (and future
--   TrainingPeaks) OAuth tokens **active at the provider**. Webhook
--   events continue to flow into our pipeline, violating LGPD Art. 18
--   VIII (communication to third parties). Finding prescribes:
--     * Call Strava `POST /oauth/deauthorize` at token deletion time.
--     * Record the event in a consent log.
--
-- Scope of THIS migration (queue + audit primitives):
--   (1) `third_party_revocations` table — one row per revocation
--       request. Fed automatically by triggers on token tables.
--   (2) `fn_request_third_party_revocation(user_id, provider, note)`
--       — manual / RPC entry point (exposed to service_role only).
--   (3) Trigger on `public.strava_connections` that enqueues a
--       revocation row whenever a connection is deleted (including
--       cascade from `auth.users` erasure).
--   (4) Auto-registration in L10-08 append-only registry — the
--       revocation log is itself immutable.
--   (5) Helper `fn_third_party_revocations_due(limit)` for the
--       worker to pull pending jobs in FIFO order.
--   (6) Helper `fn_complete_third_party_revocation(id, outcome,
--       http_status, error_message)` that marks a row done or
--       failed. Retries live in a `retry_count` column with an
--       exponential back-off computed by the worker.
--
-- Explicitly NOT in this migration (tracked as follow-ups):
--   * The HTTP worker that calls `POST /oauth/deauthorize` at
--     Strava — it lives in an Edge Function and requires the
--     `STRAVA_CLIENT_ID` + `STRAVA_CLIENT_SECRET` secrets. The
--     contract is defined here; the worker is follow-up
--     `L04-09-strava-worker`.
--   * TrainingPeaks revocation — TP API integration is not yet
--     shipped. When it is, extend the CHECK on `provider` and
--     add a second worker. Follow-up `L04-09-tp-worker`.
--
-- Security properties preserved:
--   * The log table is append-only (L10-08). A worker can mark a
--     row "completed" only via the helper which UPDATEs the row;
--     since UPDATE is blocked by L10-08, the helper writes a **new
--     row** in `third_party_revocations` with `status='completed'`
--     and links to the original `request_id`. That way the trail
--     is append-only AND we still have a state machine.
--   * Trigger runs with SECURITY DEFINER and explicit search_path.
--   * Grants: only service_role can INSERT or call the helpers;
--     `authenticated` cannot see other users' revocation events.
-- ============================================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Revocation log (append-only)
-- ──────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.third_party_revocations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid,
  user_id         uuid,
  provider        text NOT NULL
                  CHECK (provider IN ('strava', 'training_peaks')),
  event           text NOT NULL
                  CHECK (event IN (
                    'requested',
                    'attempted',
                    'completed',
                    'failed',
                    'skipped_missing_token',
                    'skipped_provider_error_4xx',
                    'abandoned'
                  )),
  http_status     integer,
  error_message   text,
  retry_count     integer NOT NULL DEFAULT 0
                  CHECK (retry_count BETWEEN 0 AND 20),
  reason          text,
  payload_snapshot jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.third_party_revocations IS
  'L04-09: append-only log of third-party OAuth revocation events. '
  'Every state transition is a new row linked by request_id. See '
  'docs/runbooks/THIRD_PARTY_REVOCATION_RUNBOOK.md for the worker contract.';

CREATE INDEX IF NOT EXISTS idx_third_party_revocations_user_created
  ON public.third_party_revocations (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_third_party_revocations_pending
  ON public.third_party_revocations (provider, created_at)
  WHERE event = 'requested';

ALTER TABLE public.third_party_revocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.third_party_revocations FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS third_party_revocations_service_rw
  ON public.third_party_revocations;
CREATE POLICY third_party_revocations_service_rw
  ON public.third_party_revocations
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Register in L10-08 append-only registry.
DO $install_guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_audit_install_append_only_guard'
  ) THEN
    PERFORM public.fn_audit_install_append_only_guard(
      'public', 'third_party_revocations',
      'L04-09: append-only log of third-party OAuth revocations'
    );
  ELSE
    RAISE NOTICE '[L04-09] L10-08 installer missing; third_party_revocations '
                 'is NOT append-only protected in this env. Apply '
                 '20260421350000_l10_08_audit_logs_append_only.sql.';
  END IF;
END
$install_guard$;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Entry point — manual / RPC request
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_request_third_party_revocation(
  p_user_id  uuid,
  p_provider text,
  p_reason   text DEFAULT 'manual',
  p_snapshot jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_request_id uuid := gen_random_uuid();
BEGIN
  IF p_user_id IS NULL OR p_provider IS NULL THEN
    RAISE EXCEPTION 'L04-09: p_user_id and p_provider are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_provider NOT IN ('strava', 'training_peaks') THEN
    RAISE EXCEPTION 'L04-09: unknown provider %', p_provider
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.third_party_revocations
    (id, request_id, user_id, provider, event, reason, payload_snapshot)
  VALUES
    (v_request_id, v_request_id, p_user_id, p_provider,
     'requested', p_reason, p_snapshot);

  RETURN v_request_id;
END
$$;

COMMENT ON FUNCTION public.fn_request_third_party_revocation(uuid, text, text, jsonb) IS
  'L04-09: enqueue a revocation request. Worker picks it up via '
  'fn_third_party_revocations_due. Returns the request_id for cross-linking.';

REVOKE ALL ON FUNCTION public.fn_request_third_party_revocation(uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_request_third_party_revocation(uuid, text, text, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.fn_request_third_party_revocation(uuid, text, text, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_request_third_party_revocation(uuid, text, text, jsonb) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Auto-enqueue trigger on strava_connections DELETE
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_strava_connection_enqueue_revocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
BEGIN
  -- Capture a snapshot (without exposing the token) so the worker has
  -- context for retries / debugging. Never log the token itself.
  PERFORM public.fn_request_third_party_revocation(
    OLD.user_id,
    'strava',
    'strava_connection_deleted',
    jsonb_build_object(
      'strava_athlete_id', OLD.strava_athlete_id,
      'scope', OLD.scope,
      'had_refresh_token', OLD.refresh_token IS NOT NULL,
      'expires_at', OLD.expires_at
    )
  );
  RETURN OLD;
END
$$;

COMMENT ON FUNCTION public.fn_strava_connection_enqueue_revocation() IS
  'L04-09: enqueue a revocation when a strava_connections row is '
  'deleted (cascade from auth.users or explicit DELETE). Token is '
  'never written to the log.';

DROP TRIGGER IF EXISTS trg_strava_connection_revoke
  ON public.strava_connections;
CREATE TRIGGER trg_strava_connection_revoke
  AFTER DELETE ON public.strava_connections
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_strava_connection_enqueue_revocation();

-- ──────────────────────────────────────────────────────────────────────────
-- 4. Worker pull — pending revocations in FIFO with retry budget
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_third_party_revocations_due(
  p_provider text,
  p_limit    integer DEFAULT 50
)
RETURNS TABLE (
  request_id   uuid,
  user_id      uuid,
  provider     text,
  retry_count  integer,
  requested_at timestamptz,
  snapshot     jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
BEGIN
  IF p_provider IS NULL THEN
    RAISE EXCEPTION 'L04-09: p_provider is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_limit IS NULL OR p_limit <= 0 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'L04-09: p_limit must be in 1..1000'
      USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
    WITH latest AS (
      SELECT DISTINCT ON (r.request_id)
        r.request_id, r.user_id, r.provider, r.retry_count, r.created_at,
        r.event, r.payload_snapshot
        FROM public.third_party_revocations r
       WHERE r.provider = p_provider
       ORDER BY r.request_id, r.created_at DESC
    )
    SELECT l.request_id, l.user_id, l.provider, l.retry_count, l.created_at,
           l.payload_snapshot
      FROM latest l
     WHERE l.event IN ('requested', 'failed')
     ORDER BY l.created_at ASC
     LIMIT p_limit;
END
$$;

COMMENT ON FUNCTION public.fn_third_party_revocations_due(text, integer) IS
  'L04-09: returns the most recent state per request_id whose current '
  'state is requested or failed — what the worker should attempt next.';

REVOKE ALL ON FUNCTION public.fn_third_party_revocations_due(text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_third_party_revocations_due(text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.fn_third_party_revocations_due(text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_third_party_revocations_due(text, integer) TO service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 5. Worker write-back — record attempt outcome as a NEW row
-- ──────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_complete_third_party_revocation(
  p_request_id     uuid,
  p_outcome        text,
  p_http_status    integer DEFAULT NULL,
  p_error_message  text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_origin public.third_party_revocations%ROWTYPE;
  v_id     uuid := gen_random_uuid();
BEGIN
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'L04-09: p_request_id is required'
      USING ERRCODE = '22023';
  END IF;
  IF p_outcome NOT IN (
       'completed', 'failed', 'skipped_missing_token',
       'skipped_provider_error_4xx', 'abandoned', 'attempted'
     ) THEN
    RAISE EXCEPTION 'L04-09: unknown outcome %', p_outcome
      USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_origin
    FROM public.third_party_revocations
   WHERE request_id = p_request_id
   ORDER BY created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'L04-09: request_id % not found', p_request_id
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.third_party_revocations
    (id, request_id, user_id, provider, event, http_status, error_message,
     retry_count, reason, payload_snapshot)
  VALUES
    (v_id,
     p_request_id,
     v_origin.user_id,
     v_origin.provider,
     p_outcome,
     p_http_status,
     p_error_message,
     CASE WHEN p_outcome = 'failed' THEN v_origin.retry_count + 1
          ELSE v_origin.retry_count END,
     v_origin.reason,
     v_origin.payload_snapshot);

  RETURN v_id;
END
$$;

COMMENT ON FUNCTION public.fn_complete_third_party_revocation(uuid, text, integer, text) IS
  'L04-09: worker write-back. Does NOT update the original row '
  '(append-only via L10-08); inserts a new state row linked by request_id.';

REVOKE ALL ON FUNCTION public.fn_complete_third_party_revocation(uuid, text, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_complete_third_party_revocation(uuid, text, integer, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_complete_third_party_revocation(uuid, text, integer, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_complete_third_party_revocation(uuid, text, integer, text) TO service_role;

COMMIT;

-- ============================================================================
-- Self-test (separate transaction — errors abort the migration)
-- ============================================================================
DO $L04_09_selftest$
DECLARE
  v_test_user uuid;
  v_req_id    uuid;
  v_done_id   uuid;
  v_n         integer;
  v_blocked   boolean := false;
BEGIN
  -- Pick any user for the self-test; skip if the table is empty
  -- (fresh migration in empty env).
  SELECT id INTO v_test_user FROM auth.users LIMIT 1;
  IF v_test_user IS NULL THEN
    RAISE NOTICE '[L04-09.selftest] no auth.users rows yet — skipping insert/flow test';
    RETURN;
  END IF;

  -- (a) Enqueue a request manually.
  v_req_id := public.fn_request_third_party_revocation(
    v_test_user, 'strava', 'selftest', NULL
  );

  -- (b) It must be visible in the "due" view.
  SELECT count(*) INTO v_n
    FROM public.fn_third_party_revocations_due('strava', 10)
   WHERE request_id = v_req_id;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'L04-09 selftest: newly enqueued request not visible in due view';
  END IF;

  -- (c) Worker write-back as "completed" appends a new row.
  v_done_id := public.fn_complete_third_party_revocation(
    v_req_id, 'completed', 200, NULL
  );

  -- (d) After completion, request is NOT in "due" anymore.
  SELECT count(*) INTO v_n
    FROM public.fn_third_party_revocations_due('strava', 10)
   WHERE request_id = v_req_id;
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'L04-09 selftest: completed request still marked as due';
  END IF;

  -- (e) Append-only: DELETE on the log is blocked with P0010
  --     (only when L10-08 is installed).
  IF EXISTS (
    SELECT 1 FROM pg_tables
     WHERE schemaname = 'public' AND tablename = 'audit_append_only_config'
  ) THEN
    BEGIN
      DELETE FROM public.third_party_revocations WHERE id = v_done_id;
      RAISE EXCEPTION 'L04-09 selftest: DELETE on third_party_revocations should be blocked';
    EXCEPTION WHEN SQLSTATE 'P0010' THEN
      v_blocked := true;
    END;
    IF NOT v_blocked THEN
      RAISE EXCEPTION 'L04-09 selftest: append-only guard did not fire';
    END IF;
  END IF;

  -- (f) Unknown provider rejected.
  BEGIN
    PERFORM public.fn_request_third_party_revocation(v_test_user, 'garmin', 'selftest', NULL);
    RAISE EXCEPTION 'L04-09 selftest: unknown provider should be rejected';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL; END;

  RAISE NOTICE '[L04-09.selftest] OK — revocation queue shipped, invariants enforced';
END
$L04_09_selftest$;
