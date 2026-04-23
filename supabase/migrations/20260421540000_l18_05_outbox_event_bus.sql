-- L18-05 — Durable outbox event bus.
--
-- Today, whenever a session flips `is_verified=true`, the caller is
-- expected to imperatively chain: update leaderboard → recompute
-- skill bracket → evaluate badges → notify coach → refresh KPIs.
-- Every edge function that writes `sessions` must remember the
-- exact call order and error-handling matrix. One forgotten call
-- produces silent desync — the finding flags that as the top
-- Principal-Eng risk for Wave 1.
--
-- This migration introduces a **durable outbox** (as opposed to
-- the volatile `pg_notify` hinted at in the original proposal):
--
--   1. `public.outbox_events` — append-only log with a dedup key,
--      status state-machine, attempts counter, backoff timer,
--      last_error column, and DLQ status.
--
--   2. `fn_outbox_emit(event_key, event_type, aggregate_id,
--      aggregate_type, payload)` — writer, idempotent via
--      UNIQUE(event_key).
--
--   3. `fn_outbox_claim(limit_rows, visibility_seconds)` —
--      consumer-side lease: pulls up to N rows with
--      `FOR UPDATE SKIP LOCKED`, flips to `processing`, and sets
--      `next_attempt_at = now() + visibility` so poisoning by a
--      crashed worker is time-bounded.
--
--   4. `fn_outbox_complete(id)` / `fn_outbox_fail(id, err, backoff)`
--      / `fn_outbox_dlq(max_attempts)` — ack/nack lifecycle.
--
--   5. Trigger on `public.sessions` — first implemented consumer
--      signal: emits `session.verified` whenever a session flips
--      from `is_verified=false` to `is_verified=true`.
--
-- The edge-function consumer itself is deliberately OUT of scope
-- for this migration (a follow-up PR wires `session-events-consumer`
-- to drain the queue via the claim RPC). The point of L18-05 is
-- to make the orchestration **explicit and durable** at the data
-- layer so downstream consumers can evolve independently.
--
-- Idempotency contract: an event_key like "session.verified:<uuid>"
-- means the producer NEVER emits the same logical event twice, and
-- any consumer MUST be safe to re-run on retry (because the lease
-- expires into another worker on crash).

BEGIN;

-- ── 1. Outbox table ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.outbox_events (
  id                bigserial PRIMARY KEY,
  event_key         text NOT NULL,
  event_type        text NOT NULL,
  aggregate_id      uuid,
  aggregate_type    text NOT NULL,
  payload           jsonb NOT NULL DEFAULT '{}'::jsonb,
  status            text NOT NULL DEFAULT 'pending',
  attempts          integer NOT NULL DEFAULT 0,
  next_attempt_at   timestamptz NOT NULL DEFAULT now(),
  last_error        text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  completed_at      timestamptz,
  CONSTRAINT outbox_events_event_key_unique UNIQUE (event_key),
  CONSTRAINT chk_outbox_status CHECK (
    status IN ('pending','processing','completed','failed','dead')
  ),
  CONSTRAINT chk_outbox_event_type CHECK (
    event_type IN (
      'session.verified',
      'session.archived',
      'challenge.completed',
      'challenge.winner_selected',
      'championship.cancelled',
      'championship.settled',
      'withdrawal.pending',
      'withdrawal.processing',
      'withdrawal.completed',
      'withdrawal.failed',
      'user.created',
      'user.deleted',
      'badge.awarded',
      'coin.emitted',
      'coin.burned'
    )
  ),
  CONSTRAINT chk_outbox_aggregate_type CHECK (
    aggregate_type IN (
      'session','user','championship','challenge',
      'withdrawal','wallet','badge'
    )
  ),
  CONSTRAINT chk_outbox_event_key_length CHECK (
    length(event_key) BETWEEN 1 AND 200
  ),
  CONSTRAINT chk_outbox_last_error_length CHECK (
    last_error IS NULL OR length(last_error) <= 2000
  ),
  CONSTRAINT chk_outbox_attempts CHECK (attempts >= 0 AND attempts <= 100),
  CONSTRAINT chk_outbox_completed_at CHECK (
    (status = 'completed' AND completed_at IS NOT NULL)
    OR (status <> 'completed' AND completed_at IS NULL)
    OR (status = 'dead')
  )
);

COMMENT ON TABLE public.outbox_events IS
  'L18-05 — durable outbox for cross-aggregate event choreography. event_key must be deterministic (e.g. session.verified:<uuid>) so producers can be idempotent via ON CONFLICT DO NOTHING.';

CREATE INDEX IF NOT EXISTS idx_outbox_events_ready
  ON public.outbox_events(next_attempt_at)
  WHERE status IN ('pending','processing');

CREATE INDEX IF NOT EXISTS idx_outbox_events_aggregate
  ON public.outbox_events(aggregate_type, aggregate_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_outbox_events_type_time
  ON public.outbox_events(event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_outbox_events_dead
  ON public.outbox_events(status, updated_at DESC)
  WHERE status IN ('failed','dead');

ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outbox_events_admin_only
  ON public.outbox_events;
CREATE POLICY outbox_events_admin_only
  ON public.outbox_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.platform_role = 'admin'
    )
  );

REVOKE ALL  ON public.outbox_events FROM PUBLIC;
GRANT SELECT ON public.outbox_events TO authenticated;
GRANT ALL    ON public.outbox_events TO service_role;
GRANT USAGE  ON SEQUENCE outbox_events_id_seq TO service_role;

-- ── 2. updated_at trigger ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_outbox_touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_outbox_touch_updated_at ON public.outbox_events;
CREATE TRIGGER trg_outbox_touch_updated_at
  BEFORE UPDATE ON public.outbox_events
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_outbox_touch_updated_at();

-- ── 3. Writer RPC ──────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_outbox_emit(
  p_event_key      text,
  p_event_type     text,
  p_aggregate_type text,
  p_aggregate_id   uuid,
  p_payload        jsonb DEFAULT '{}'::jsonb
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF p_event_key IS NULL OR length(p_event_key) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EVENT_KEY';
  END IF;
  IF p_event_type IS NULL OR length(p_event_type) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_EVENT_TYPE';
  END IF;
  IF p_aggregate_type IS NULL OR length(p_aggregate_type) = 0 THEN
    RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'INVALID_AGGREGATE_TYPE';
  END IF;

  INSERT INTO public.outbox_events (
    event_key, event_type, aggregate_type, aggregate_id, payload
  ) VALUES (
    p_event_key,
    p_event_type,
    p_aggregate_type,
    p_aggregate_id,
    coalesce(p_payload, '{}'::jsonb)
  )
  ON CONFLICT ON CONSTRAINT outbox_events_event_key_unique DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id; -- NULL when the row already existed (idempotent replay)
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbox_emit(
  text, text, text, uuid, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbox_emit(
  text, text, text, uuid, jsonb
) TO service_role;

COMMENT ON FUNCTION public.fn_outbox_emit(text, text, text, uuid, jsonb) IS
  'L18-05 — enqueue one outbox event. Returns the new id, or NULL when event_key already existed (idempotent producer replay safe).';

-- ── 4. Claim / ack / nack / DLQ ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_outbox_claim(
  p_limit              integer DEFAULT 50,
  p_visibility_seconds integer DEFAULT 60
) RETURNS SETOF public.outbox_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
SET lock_timeout = '2s'
AS $$
DECLARE
  v_limit      integer := greatest(1, least(coalesce(p_limit, 50), 1000));
  v_visibility integer := greatest(5, least(coalesce(p_visibility_seconds, 60), 3600));
BEGIN
  RETURN QUERY
  WITH cte AS (
    SELECT id FROM public.outbox_events
      WHERE status IN ('pending','processing')
        AND next_attempt_at <= now()
      ORDER BY next_attempt_at ASC, id ASC
      FOR UPDATE SKIP LOCKED
      LIMIT v_limit
  )
  UPDATE public.outbox_events oe
     SET status          = 'processing',
         attempts        = oe.attempts + 1,
         next_attempt_at = now() + make_interval(secs => v_visibility)
    FROM cte
   WHERE oe.id = cte.id
  RETURNING oe.*;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbox_claim(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbox_claim(integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbox_complete(p_id bigint)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows integer;
BEGIN
  UPDATE public.outbox_events
     SET status       = 'completed',
         completed_at = now(),
         last_error   = NULL
   WHERE id = p_id
     AND status IN ('processing','pending');
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows = 1;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbox_complete(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbox_complete(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbox_fail(
  p_id              bigint,
  p_error           text,
  p_backoff_seconds integer DEFAULT 30,
  p_max_attempts    integer DEFAULT 8
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row public.outbox_events%ROWTYPE;
  v_backoff integer := greatest(1, least(coalesce(p_backoff_seconds, 30), 86400));
  v_max     integer := greatest(1, least(coalesce(p_max_attempts, 8), 100));
  v_new_status text;
BEGIN
  SELECT * INTO v_row FROM public.outbox_events WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = 'P0002', MESSAGE = 'OUTBOX_NOT_FOUND';
  END IF;

  IF v_row.attempts >= v_max THEN
    v_new_status := 'dead';
  ELSE
    v_new_status := 'failed';
  END IF;

  UPDATE public.outbox_events
     SET status          = v_new_status,
         last_error      = left(coalesce(p_error, ''), 2000),
         next_attempt_at = CASE
                             WHEN v_new_status = 'dead' THEN now()
                             ELSE now() + make_interval(secs => v_backoff)
                           END
   WHERE id = p_id;

  -- Failed events are eligible for re-claim after the backoff;
  -- the claim RPC only selects pending/processing, so flip
  -- back to pending unless we DLQ'd it.
  IF v_new_status = 'failed' THEN
    UPDATE public.outbox_events SET status = 'pending' WHERE id = p_id;
  END IF;

  RETURN v_new_status;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbox_fail(bigint, text, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbox_fail(bigint, text, integer, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbox_dlq(p_max_attempts integer DEFAULT 8)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows integer;
  v_cap  integer := greatest(1, least(coalesce(p_max_attempts, 8), 100));
BEGIN
  UPDATE public.outbox_events
     SET status = 'dead'
   WHERE status IN ('pending','processing','failed')
     AND attempts >= v_cap;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbox_dlq(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbox_dlq(integer) TO service_role;

-- ── 5. Session-verified producer trigger ───────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_emit_session_verified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.is_verified = true
     AND (OLD.is_verified IS DISTINCT FROM true)
  THEN
    BEGIN
      PERFORM public.fn_outbox_emit(
        p_event_key      => 'session.verified:' || NEW.id::text,
        p_event_type     => 'session.verified',
        p_aggregate_type => 'session',
        p_aggregate_id   => NEW.id,
        p_payload        => jsonb_build_object(
          'user_id',       NEW.user_id,
          'session_id',    NEW.id,
          'distance_m',    NEW.total_distance_m,
          'moving_ms',     NEW.moving_ms,
          'verified_at',   now()
        )
      );
    EXCEPTION WHEN OTHERS THEN
      -- NEVER block the writer because of an outbox failure;
      -- log for operator follow-up and move on.
      RAISE WARNING 'L18-05: fn_outbox_emit failed (session %): %',
        NEW.id, SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DO $trig$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'sessions') THEN
    DROP TRIGGER IF EXISTS trg_emit_session_verified ON public.sessions;
    CREATE TRIGGER trg_emit_session_verified
      AFTER UPDATE OF is_verified ON public.sessions
      FOR EACH ROW
      EXECUTE FUNCTION public.fn_emit_session_verified();
  END IF;
END
$trig$;

-- ── 6. Retention registration ─────────────────────────────────────────────

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
      'outbox_events',
      30,
      true,
      10000,
      'created_at',
      'L18-05 — completed outbox events pruned after 30 days; dead rows kept for forensics via separate manual sweep.'
    )
    ON CONFLICT DO NOTHING;
  END IF;
END
$retention$;

-- ── 7. Self-test ──────────────────────────────────────────────────────────

DO $$
DECLARE
  v_id    bigint;
  v_dup   bigint;
  v_state text;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'fn_outbox_emit'
  ) THEN
    RAISE EXCEPTION 'L18-05 self-test: fn_outbox_emit missing';
  END IF;

  -- (a) emit writes, returns id
  v_id := public.fn_outbox_emit(
    p_event_key      => 'selftest.event:' || gen_random_uuid()::text,
    p_event_type     => 'session.verified',
    p_aggregate_type => 'session',
    p_aggregate_id   => gen_random_uuid(),
    p_payload        => jsonb_build_object('selftest', true)
  );
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'L18-05 self-test: emit returned NULL id';
  END IF;

  -- (b) dedup on same event_key
  v_dup := public.fn_outbox_emit(
    p_event_key      => (SELECT event_key FROM public.outbox_events WHERE id = v_id),
    p_event_type     => 'session.verified',
    p_aggregate_type => 'session',
    p_aggregate_id   => gen_random_uuid(),
    p_payload        => '{}'::jsonb
  );
  IF v_dup IS NOT NULL THEN
    RAISE EXCEPTION 'L18-05 self-test: duplicate emit should have returned NULL';
  END IF;

  -- (c) empty event_key rejected
  BEGIN
    PERFORM public.fn_outbox_emit('', 'session.verified', 'session', NULL);
    RAISE EXCEPTION 'L18-05 self-test: empty event_key should have raised 22023';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  -- (d) invalid event_type blocked by CHECK
  BEGIN
    INSERT INTO public.outbox_events (
      event_key, event_type, aggregate_type, aggregate_id, payload
    ) VALUES (
      'selftest.bogus:' || gen_random_uuid()::text,
      'bogus.event',
      'session',
      gen_random_uuid(),
      '{}'::jsonb
    );
    RAISE EXCEPTION 'L18-05 self-test: bogus event_type should have been blocked';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  -- (e) complete RPC flips status
  PERFORM public.fn_outbox_complete(v_id);
  SELECT status INTO v_state FROM public.outbox_events WHERE id = v_id;
  IF v_state <> 'completed' THEN
    RAISE EXCEPTION 'L18-05 self-test: complete did not flip status (got %)', v_state;
  END IF;

  -- Cleanup self-test rows
  DELETE FROM public.outbox_events
   WHERE payload ->> 'selftest' = 'true'
      OR event_key LIKE 'selftest.%';

  RAISE NOTICE 'L18-05 self-test: OK';
END
$$;

COMMIT;
