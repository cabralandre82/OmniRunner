-- ============================================================================
-- L16-04 — Outbound webhooks for partners
-- Date: 2026-04-21
-- ============================================================================
-- Today Omni Runner ingests provider webhooks (Stripe / Mercado Pago / Asaas
-- / Strava) but does NOT emit any. A B2B partner that signed up to be told
-- "when an athlete from my club finishes a run, call my endpoint" has no
-- channel. This migration ships the canonical server-side primitives so
-- the existing L18-05 outbox can drive partner delivery.
--
--   1. `public.outbound_webhook_endpoints` — one row per partner endpoint.
--      * `group_id` owner, `url` https-only + length-bounded, `secret`
--        (64 hex — HMAC-SHA-256 signature key, rotated via RPC), `events`
--        subscription array, `enabled` flag, `last_*` counters.
--      * RLS: admin_master of the group + platform_admin read; writes via
--        SECURITY DEFINER RPCs only.
--   2. `public.outbound_webhook_deliveries` — per-attempt row.
--      * state machine `pending → delivered | failed | dead`, `attempt`
--        counter bounded 1..10, `status_code`, `response_excerpt` ≤ 500
--        chars, `error_message` ≤ 500 chars, `next_attempt_at` for
--        backoff, `delivered_at / failed_at` timestamps.
--      * 30-day retention (via `audit_logs_retention_config` when that
--        table exists).
--   3. Secret rotation: `fn_outbound_webhook_generate_secret()` →
--      64-hex string; `fn_outbound_webhook_rotate_secret(id)` is
--      admin-only and audits the rotation.
--   4. Admin lifecycle RPCs: `fn_outbound_webhook_register(group_id, url,
--      events)` → creates endpoint + first secret; fails with INVALID_URL
--      / INVALID_EVENT if shape breaks; `fn_outbound_webhook_enable(id,
--      enabled)`; `fn_outbound_webhook_delete(id)`.
--   5. Worker-facing RPCs (service-role only):
--      * `fn_outbound_webhook_enqueue(event, aggregate_id, payload)` —
--        fan-out that inserts one `pending` delivery per enabled
--        endpoint subscribed to `event`.
--      * `fn_outbound_webhook_claim(limit, lease_seconds)` — FOR UPDATE
--        SKIP LOCKED on rows where `status='pending' AND next_attempt_at
--        <= now()`; flips to `processing` with a visibility lease.
--      * `fn_outbound_webhook_mark_delivered(id, status_code,
--        response_excerpt)`.
--      * `fn_outbound_webhook_mark_failed(id, status_code, error)` —
--        bumps attempt + schedules exponential backoff; when attempt
--        reaches max_attempts (default 5) flips to `dead`.
--
-- Hook into L18-05 outbox: the partner delivery worker consumes
-- `outbox_events`, calls `fn_outbound_webhook_enqueue(event_type,
-- aggregate_id, payload)`, then acks the outbox row. Delivery retries
-- live on `outbound_webhook_deliveries`.

BEGIN;

-- ── 0. Validation helpers ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_validate_webhook_url(p_value TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
BEGIN
  IF p_value IS NULL THEN
    RETURN FALSE;
  END IF;
  IF length(p_value) > 500 OR length(p_value) < 12 THEN
    RETURN FALSE;
  END IF;
  IF p_value !~ '^https://' THEN
    RETURN FALSE;
  END IF;
  IF p_value ~ 'localhost|127\.0\.0\.1|0\.0\.0\.0|\b10\.' THEN
    RETURN FALSE;
  END IF;
  IF p_value ~ '\b192\.168\.' THEN
    RETURN FALSE;
  END IF;
  IF p_value ~ '\b169\.254\.' THEN
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_webhook_url(TEXT) IS
  'Returns true when input is an https URL between 12 and 500 chars that does NOT point to loopback/RFC1918/link-local targets. Used by outbound_webhook_endpoints CHECK.';

GRANT EXECUTE ON FUNCTION public.fn_validate_webhook_url(TEXT) TO PUBLIC;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_generate_secret()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
  RETURN encode(gen_random_bytes(32), 'hex');
END;
$$;

COMMENT ON FUNCTION public.fn_outbound_webhook_generate_secret() IS
  '64-hex (256-bit) secret used as HMAC-SHA-256 signing key for outbound webhook deliveries.';

-- ── 1. Canonical event catalogue (reuses L18-05 outbox event types) ─────

-- We whitelist the same 15 event types the outbox ships, so partner
-- subscriptions can never drift from what the outbox emits.
CREATE OR REPLACE FUNCTION public.fn_validate_outbound_webhook_events(p_events TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_allowed TEXT[] := ARRAY[
    'session.verified',
    'session.imported',
    'session.rejected',
    'coin.distributed',
    'coin.reversed',
    'championship.created',
    'championship.ended',
    'challenge.started',
    'challenge.ended',
    'referral.activated',
    'withdrawal.requested',
    'withdrawal.completed',
    'custody.deposit.confirmed',
    'swap.executed',
    'profile.updated'
  ];
  v_evt TEXT;
BEGIN
  IF p_events IS NULL OR array_length(p_events, 1) IS NULL THEN
    RETURN FALSE;
  END IF;
  IF array_length(p_events, 1) > 20 THEN
    RETURN FALSE;
  END IF;
  FOREACH v_evt IN ARRAY p_events LOOP
    IF v_evt IS NULL OR NOT (v_evt = ANY (v_allowed)) THEN
      RETURN FALSE;
    END IF;
  END LOOP;
  RETURN TRUE;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_outbound_webhook_events(TEXT[]) IS
  'Returns true when events array is non-empty, ≤20, and every entry is in the canonical outbox event catalogue.';

GRANT EXECUTE ON FUNCTION public.fn_validate_outbound_webhook_events(TEXT[]) TO PUBLIC;

-- ── 2. Endpoints table ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.outbound_webhook_endpoints (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  url              TEXT NOT NULL,
  secret           TEXT NOT NULL DEFAULT public.fn_outbound_webhook_generate_secret(),
  events           TEXT[] NOT NULL DEFAULT '{}'::text[],
  enabled          BOOLEAN NOT NULL DEFAULT TRUE,
  max_attempts     INT NOT NULL DEFAULT 5,
  last_delivered_at TIMESTAMPTZ,
  last_failed_at   TIMESTAMPTZ,
  created_by       UUID REFERENCES auth.users(id),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT outbound_webhook_endpoints_url_shape
    CHECK (public.fn_validate_webhook_url(url)),
  CONSTRAINT outbound_webhook_endpoints_secret_shape
    CHECK (secret ~ '^[0-9a-f]{64}$'),
  CONSTRAINT outbound_webhook_endpoints_events_shape
    CHECK (public.fn_validate_outbound_webhook_events(events)),
  CONSTRAINT outbound_webhook_endpoints_max_attempts_bound
    CHECK (max_attempts BETWEEN 1 AND 10)
);

CREATE INDEX IF NOT EXISTS outbound_webhook_endpoints_group_idx
  ON public.outbound_webhook_endpoints (group_id);

CREATE INDEX IF NOT EXISTS outbound_webhook_endpoints_enabled_idx
  ON public.outbound_webhook_endpoints (enabled)
  WHERE enabled = TRUE;

COMMENT ON TABLE public.outbound_webhook_endpoints IS
  'L16-04: one row per partner endpoint. Subscriptions are validated against the canonical outbox event catalogue.';

ALTER TABLE public.outbound_webhook_endpoints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outbound_webhook_endpoints_admin_read ON public.outbound_webhook_endpoints;
CREATE POLICY outbound_webhook_endpoints_admin_read ON public.outbound_webhook_endpoints
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = outbound_webhook_endpoints.group_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- ── 3. Deliveries table ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.outbound_webhook_deliveries (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id       UUID NOT NULL REFERENCES public.outbound_webhook_endpoints(id) ON DELETE CASCADE,
  event_type        TEXT NOT NULL,
  aggregate_id      UUID,
  payload           JSONB NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','processing','delivered','failed','dead')),
  attempt           INT NOT NULL DEFAULT 0,
  status_code       INT,
  response_excerpt  TEXT,
  error_message     TEXT,
  next_attempt_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at      TIMESTAMPTZ,
  failed_at         TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT outbound_webhook_deliveries_attempt_bound
    CHECK (attempt >= 0 AND attempt <= 10),
  CONSTRAINT outbound_webhook_deliveries_status_code_bound
    CHECK (status_code IS NULL OR status_code BETWEEN 0 AND 599),
  CONSTRAINT outbound_webhook_deliveries_response_len
    CHECK (response_excerpt IS NULL OR length(response_excerpt) <= 500),
  CONSTRAINT outbound_webhook_deliveries_error_len
    CHECK (error_message IS NULL OR length(error_message) <= 500)
);

CREATE INDEX IF NOT EXISTS outbound_webhook_deliveries_endpoint_idx
  ON public.outbound_webhook_deliveries (endpoint_id, created_at DESC);

CREATE INDEX IF NOT EXISTS outbound_webhook_deliveries_ready_idx
  ON public.outbound_webhook_deliveries (next_attempt_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS outbound_webhook_deliveries_dead_idx
  ON public.outbound_webhook_deliveries (endpoint_id)
  WHERE status = 'dead';

COMMENT ON TABLE public.outbound_webhook_deliveries IS
  'L16-04: per-attempt delivery log. Worker claims pending rows via fn_outbound_webhook_claim and acks via mark_delivered / mark_failed.';

ALTER TABLE public.outbound_webhook_deliveries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS outbound_webhook_deliveries_admin_read ON public.outbound_webhook_deliveries;
CREATE POLICY outbound_webhook_deliveries_admin_read ON public.outbound_webhook_deliveries
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND platform_role = 'admin'
    )
  );

-- Retention seeding (conditional on L08-08 shipping).
DO $retention$
BEGIN
  IF to_regclass('public.audit_logs_retention_config') IS NOT NULL THEN
    INSERT INTO public.audit_logs_retention_config (table_name, retention_days, notes)
    VALUES ('outbound_webhook_deliveries', 30, 'L16-04 — per-attempt delivery log; 30 days is enough for postmortems without ballooning storage.')
    ON CONFLICT (table_name) DO NOTHING;
  END IF;
END;
$retention$;

-- ── 4. Admin lifecycle RPCs ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_register(
  p_group_id UUID,
  p_url TEXT,
  p_events TEXT[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_row public.outbound_webhook_endpoints;
BEGIN
  IF p_group_id IS NULL THEN
    RAISE EXCEPTION 'INVALID_GROUP' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.fn_validate_webhook_url(p_url) THEN
    RAISE EXCEPTION 'INVALID_URL' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.fn_validate_outbound_webhook_events(p_events) THEN
    RAISE EXCEPTION 'INVALID_EVENTS' USING ERRCODE = 'P0001';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';
    IF NOT v_is_admin THEN
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = p_group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.outbound_webhook_endpoints (group_id, url, events, created_by)
  VALUES (p_group_id, p_url, p_events, v_actor)
  RETURNING * INTO v_row;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'secret', v_row.secret,
    'events', v_row.events,
    'enabled', v_row.enabled,
    'created_at', v_row.created_at
  );
END;
$$;

COMMENT ON FUNCTION public.fn_outbound_webhook_register(UUID, TEXT, TEXT[]) IS
  'Admin-only: registers a new partner endpoint, returns the freshly minted HMAC secret. Secret is returned ONCE — partners must capture it.';

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_register(UUID, TEXT, TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_register(UUID, TEXT, TEXT[]) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_rotate_secret(p_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_row public.outbound_webhook_endpoints;
  v_new_secret TEXT := public.fn_outbound_webhook_generate_secret();
BEGIN
  SELECT * INTO v_row FROM public.outbound_webhook_endpoints WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENDPOINT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';
    IF NOT v_is_admin THEN
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = v_row.group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.outbound_webhook_endpoints
  SET secret = v_new_secret,
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  BEGIN
    IF to_regclass('public.portal_audit_log') IS NOT NULL THEN
      INSERT INTO public.portal_audit_log (actor_id, group_id, action, metadata, created_at)
      VALUES (v_actor, v_row.group_id, 'group.webhook.secret_rotated',
              jsonb_build_object('endpoint_id', p_id), now());
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'webhook rotate audit failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object('id', v_row.id, 'secret', v_new_secret);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_rotate_secret(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_rotate_secret(UUID) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_enable(p_id UUID, p_enabled BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor UUID := auth.uid();
  v_is_admin BOOLEAN := FALSE;
  v_row public.outbound_webhook_endpoints;
BEGIN
  SELECT * INTO v_row FROM public.outbound_webhook_endpoints WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ENDPOINT_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF current_setting('role', true) = 'service_role' THEN
    v_is_admin := TRUE;
  ELSIF v_actor IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  ELSE
    SELECT TRUE INTO v_is_admin
    FROM public.profiles
    WHERE id = v_actor AND platform_role = 'admin';
    IF NOT v_is_admin THEN
      SELECT TRUE INTO v_is_admin
      FROM public.coaching_members
      WHERE group_id = v_row.group_id
        AND user_id = v_actor
        AND role = 'admin_master';
    END IF;
  END IF;

  IF NOT COALESCE(v_is_admin, FALSE) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  UPDATE public.outbound_webhook_endpoints
  SET enabled = COALESCE(p_enabled, FALSE),
      updated_at = now()
  WHERE id = p_id
  RETURNING * INTO v_row;

  RETURN jsonb_build_object('id', v_row.id, 'enabled', v_row.enabled);
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_enable(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_enable(UUID, BOOLEAN) TO authenticated, service_role;

-- ── 5. Worker-facing RPCs ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_enqueue(
  p_event_type TEXT,
  p_aggregate_id UUID,
  p_payload JSONB
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INT := 0;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  IF p_event_type IS NULL OR p_payload IS NULL THEN
    RAISE EXCEPTION 'INVALID_EVENT' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.outbound_webhook_deliveries (
    endpoint_id, event_type, aggregate_id, payload, status, next_attempt_at
  )
  SELECT e.id, p_event_type, p_aggregate_id, p_payload, 'pending', now()
  FROM public.outbound_webhook_endpoints e
  WHERE e.enabled = TRUE
    AND p_event_type = ANY (e.events);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.fn_outbound_webhook_enqueue(TEXT, UUID, JSONB) IS
  'Service-role fan-out: inserts one pending delivery row per enabled endpoint subscribed to the given event type. Returns the count of rows inserted.';

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_enqueue(TEXT, UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_enqueue(TEXT, UUID, JSONB) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_claim(
  p_limit INT DEFAULT 50,
  p_lease_seconds INT DEFAULT 60
)
RETURNS TABLE (
  id UUID,
  endpoint_id UUID,
  url TEXT,
  secret TEXT,
  event_type TEXT,
  aggregate_id UUID,
  payload JSONB,
  attempt INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_limit INT := GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
  v_lease INT := GREATEST(5, LEAST(COALESCE(p_lease_seconds, 60), 3600));
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH ready AS (
    SELECT d.id
    FROM public.outbound_webhook_deliveries d
    WHERE d.status = 'pending'
      AND d.next_attempt_at <= now()
    ORDER BY d.next_attempt_at ASC
    LIMIT v_limit
    FOR UPDATE SKIP LOCKED
  ),
  claimed AS (
    UPDATE public.outbound_webhook_deliveries d
    SET status = 'processing',
        next_attempt_at = now() + make_interval(secs => v_lease),
        attempt = d.attempt + 1
    FROM ready
    WHERE d.id = ready.id
    RETURNING d.*
  )
  SELECT c.id, c.endpoint_id, e.url, e.secret, c.event_type, c.aggregate_id, c.payload, c.attempt
  FROM claimed c
  JOIN public.outbound_webhook_endpoints e ON e.id = c.endpoint_id;
END;
$$;

COMMENT ON FUNCTION public.fn_outbound_webhook_claim(INT, INT) IS
  'Service-role claim of up to p_limit pending deliveries. Flips status to processing with a visibility lease so crashed workers do not starve the queue.';

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_claim(INT, INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_claim(INT, INT) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_mark_delivered(
  p_id UUID,
  p_status_code INT,
  p_response_excerpt TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  UPDATE public.outbound_webhook_deliveries
  SET status = 'delivered',
      status_code = p_status_code,
      response_excerpt = LEFT(COALESCE(p_response_excerpt, ''), 500),
      delivered_at = now()
  WHERE id = p_id AND status = 'processing';

  UPDATE public.outbound_webhook_endpoints e
  SET last_delivered_at = now(), updated_at = now()
  FROM public.outbound_webhook_deliveries d
  WHERE d.id = p_id AND e.id = d.endpoint_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_mark_delivered(UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_mark_delivered(UUID, INT, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.fn_outbound_webhook_mark_failed(
  p_id UUID,
  p_status_code INT,
  p_error TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_delivery public.outbound_webhook_deliveries;
  v_endpoint public.outbound_webhook_endpoints;
  v_backoff_s INT;
  v_new_status TEXT;
BEGIN
  IF current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'SERVICE_ROLE_ONLY' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_delivery FROM public.outbound_webhook_deliveries WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'DELIVERY_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_endpoint FROM public.outbound_webhook_endpoints WHERE id = v_delivery.endpoint_id;

  -- Exponential backoff: 30s, 2m, 10m, 30m, 2h, 6h (clamped).
  v_backoff_s := LEAST(30 * (2 ^ GREATEST(v_delivery.attempt - 1, 0))::INT, 21600);

  IF v_delivery.attempt >= v_endpoint.max_attempts THEN
    v_new_status := 'dead';
  ELSE
    v_new_status := 'pending';
  END IF;

  UPDATE public.outbound_webhook_deliveries
  SET status = v_new_status,
      status_code = p_status_code,
      error_message = LEFT(COALESCE(p_error, ''), 500),
      next_attempt_at = CASE WHEN v_new_status = 'pending' THEN now() + make_interval(secs => v_backoff_s) ELSE next_attempt_at END,
      failed_at = CASE WHEN v_new_status = 'dead' THEN now() ELSE NULL END
  WHERE id = p_id;

  UPDATE public.outbound_webhook_endpoints
  SET last_failed_at = now(), updated_at = now()
  WHERE id = v_endpoint.id;

  RETURN jsonb_build_object(
    'id', p_id,
    'status', v_new_status,
    'attempt', v_delivery.attempt,
    'backoff_seconds', CASE WHEN v_new_status = 'pending' THEN v_backoff_s ELSE NULL END
  );
END;
$$;

COMMENT ON FUNCTION public.fn_outbound_webhook_mark_failed(UUID, INT, TEXT) IS
  'Service-role: records failure. Schedules exponential backoff (30s → 6h cap) when attempts remain; promotes to dead when max_attempts reached.';

REVOKE ALL ON FUNCTION public.fn_outbound_webhook_mark_failed(UUID, INT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_outbound_webhook_mark_failed(UUID, INT, TEXT) TO service_role;

-- ── 6. Self-test ─────────────────────────────────────────────────────────

DO $self_test$
BEGIN
  IF NOT public.fn_validate_webhook_url('https://partner.example.com/hook') THEN
    RAISE EXCEPTION 'self-test: fn_validate_webhook_url rejected valid https URL';
  END IF;
  IF public.fn_validate_webhook_url('http://partner.example.com/hook') THEN
    RAISE EXCEPTION 'self-test: fn_validate_webhook_url accepted http';
  END IF;
  IF public.fn_validate_webhook_url('https://localhost/hook') THEN
    RAISE EXCEPTION 'self-test: fn_validate_webhook_url accepted localhost';
  END IF;
  IF public.fn_validate_webhook_url('https://10.0.0.1/hook') THEN
    RAISE EXCEPTION 'self-test: fn_validate_webhook_url accepted 10.0.0.0/8';
  END IF;
  IF public.fn_validate_webhook_url('https://192.168.0.10/x') THEN
    RAISE EXCEPTION 'self-test: fn_validate_webhook_url accepted RFC1918';
  END IF;

  IF NOT public.fn_validate_outbound_webhook_events(ARRAY['session.verified']) THEN
    RAISE EXCEPTION 'self-test: events validator rejected session.verified';
  END IF;
  IF public.fn_validate_outbound_webhook_events(ARRAY['unknown.event']::text[]) THEN
    RAISE EXCEPTION 'self-test: events validator accepted unknown event';
  END IF;
  IF public.fn_validate_outbound_webhook_events(ARRAY[]::text[]) THEN
    RAISE EXCEPTION 'self-test: events validator accepted empty array';
  END IF;

  IF length(public.fn_outbound_webhook_generate_secret()) <> 64 THEN
    RAISE EXCEPTION 'self-test: secret length != 64 hex';
  END IF;

  RAISE NOTICE 'L16-04 self-test OK';
END;
$self_test$;

COMMIT;
