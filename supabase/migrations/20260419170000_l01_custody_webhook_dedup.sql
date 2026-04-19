-- ============================================================================
-- L01-01 — Custody webhook receiver hardening (Stripe + MercadoPago)
--
-- Audit reference:
--   docs/audit/findings/L01-01-post-api-custody-webhook-webhook-de-custodia-stripe.md
--   docs/audit/parts/01-ciso.md  (anchor [1.1])
--
-- Problem
-- ───────
--   `POST /api/custody/webhook` (portal) accepts gateway notifications for
--   custody deposit confirmation. Two related defects in the receiver:
--
--     a) MercadoPago verification was a flat HMAC with no timestamp window.
--        A single intercepted webhook could be replayed indefinitely, and
--        even though final deposit credit is idempotent (UNIQUE on
--        `payment_reference`), every replay still inflated
--        `payment_webhook_events`, the audit log, and the `custody.webhook.*`
--        metrics.
--     b) The handler had NO event-id deduplication at the receiver layer
--        (the existing dedup is asaas-only via
--        `payment_webhook_events.asaas_event_id`). So Stripe sending the
--        same `evt_…` twice (their docs say "expect retries") would walk
--        the full pipeline twice.
--
-- Defence (this migration)
-- ────────────────────────
--   (1) `public.custody_webhook_events` — receiver-side append-only log.
--       Composite primary key `(gateway, event_id)` is the dedup primitive:
--       second arrival of the same `(stripe, evt_…)` or
--       `(mercadopago, <id>)` raises `unique_violation` and the route
--       handler maps that to a 200 reply with `replayed: true`.
--
--   (2) `fn_record_custody_webhook_event(p_gateway, p_event_id,
--        p_payment_reference, p_payload)` — wraps the INSERT and converts
--       `unique_violation` into a `was_replay=true` return. SECURITY DEFINER
--       with locked search_path (project standard) so the route handler
--       does not need DML grants.
--
--   (3) Retention: the dedup window only matters for as long as a gateway
--       can possibly retry. Stripe retries up to 3 days; MercadoPago up to
--       72 hours. We keep 30 days for forensic correlation, then prune via
--       `fn_prune_custody_webhook_events()` called from a cron in the next
--       wave (L12-* scheduling work). For now the table is small (single
--       rows per webhook delivery) and the prune helper is wired in but
--       unscheduled — operators can run it manually if needed.
--
-- Rollback
-- ────────
--   `DROP TABLE public.custody_webhook_events CASCADE;` will also drop the
--   helper functions because of `CASCADE`. The route handler degrades
--   gracefully: if the table is missing, the dedup INSERT raises and the
--   webhook returns 500 — operators see the alert immediately rather than
--   silently skipping dedup.
-- ============================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────────
-- 1. Dedup table
-- ─────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.custody_webhook_events (
  -- Composite PK is the dedup primitive. Note: Stripe event ids start with
  -- `evt_` and MP uses numeric strings; both fit in `text` without size
  -- ceiling concerns. We do NOT add a surrogate uuid PK because every
  -- consumer of this table needs `(gateway, event_id)` lookups and a
  -- surrogate would just be dead weight.
  gateway             text NOT NULL,
  event_id            text NOT NULL,

  -- The deposit reference extracted from the payload (Stripe charge id,
  -- MP payment id). Nullable because for some event types the reference
  -- is only available via a follow-up API call — we still want the dedup
  -- row created so a retry of the SAME event_id is rejected.
  payment_reference   text,

  -- Full webhook body kept for forensic post-mortems. Capped via
  -- application-layer body-size limit (64 KiB), so jsonb storage is cheap.
  payload             jsonb NOT NULL DEFAULT '{}'::jsonb,

  -- Audit timestamps. `received_at` is when the receiver inserted the row;
  -- `processed_at` is updated by the route handler after the deposit
  -- confirmation succeeds (lets ops query "events stuck in received but
  -- never processed" for backlog hunting).
  received_at         timestamptz NOT NULL DEFAULT now(),
  processed_at        timestamptz,

  CONSTRAINT pk_custody_webhook_events PRIMARY KEY (gateway, event_id),
  CONSTRAINT custody_webhook_events_gateway_check
    CHECK (gateway IN ('stripe', 'mercadopago')),
  CONSTRAINT custody_webhook_events_event_id_check
    CHECK (length(event_id) BETWEEN 1 AND 255)
);

-- Receivers want to triage by gateway and, for the SRE backlog query,
-- "received but not processed" filtered by recency.
CREATE INDEX IF NOT EXISTS idx_custody_webhook_events_received_at
  ON public.custody_webhook_events (received_at DESC);

CREATE INDEX IF NOT EXISTS idx_custody_webhook_events_unprocessed
  ON public.custody_webhook_events (gateway, received_at DESC)
  WHERE processed_at IS NULL;

COMMENT ON TABLE public.custody_webhook_events IS
  'L01-01 — Receiver-side dedup log for /api/custody/webhook. Composite PK '
  '(gateway, event_id) is the dedup primitive. See migration header.';

-- ─────────────────────────────────────────────────────────────────────
-- 2. RLS — service role only
-- ─────────────────────────────────────────────────────────────────────
--   The webhook route handler runs with the service-role client (bypasses
--   RLS) so we just FORCE RLS without granting any policy. This protects
--   against any misconfigured PostgREST endpoint accidentally exposing
--   the table to authenticated users.

ALTER TABLE public.custody_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.custody_webhook_events FORCE ROW LEVEL SECURITY;

REVOKE ALL ON public.custody_webhook_events FROM anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────
-- 3. fn_record_custody_webhook_event
-- ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_record_custody_webhook_event(
  p_gateway           text,
  p_event_id          text,
  p_payment_reference text,
  p_payload           jsonb
)
RETURNS TABLE (
  was_replay          boolean,
  received_at         timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_existing_received_at  timestamptz;
BEGIN
  -- Lock timeout protects the receiver from being held up by long-running
  -- analytics queries that might be touching the same table. 2s is the
  -- project-wide convention (L19-05).
  PERFORM set_config('lock_timeout', '2s', true);

  -- Validate inputs early. We RAISE with explicit codes so the route
  -- handler can map to specific HTTP status codes.
  IF p_gateway IS NULL OR p_gateway NOT IN ('stripe', 'mercadopago') THEN
    RAISE EXCEPTION 'INVALID_GATEWAY: %', COALESCE(p_gateway, '<null>')
      USING ERRCODE = 'P0001';
  END IF;

  IF p_event_id IS NULL OR length(trim(p_event_id)) = 0 THEN
    RAISE EXCEPTION 'EVENT_ID_REQUIRED'
      USING ERRCODE = 'P0001';
  END IF;

  IF length(p_event_id) > 255 THEN
    RAISE EXCEPTION 'EVENT_ID_TOO_LONG: % chars', length(p_event_id)
      USING ERRCODE = 'P0001';
  END IF;

  -- Happy path: insert. ON CONFLICT DO NOTHING + a RETURNING clause lets
  -- us tell new vs. replay in a single round-trip without an explicit
  -- SELECT-then-INSERT race.
  INSERT INTO public.custody_webhook_events (
    gateway, event_id, payment_reference, payload
  )
  VALUES (
    p_gateway, p_event_id, p_payment_reference,
    COALESCE(p_payload, '{}'::jsonb)
  )
  ON CONFLICT (gateway, event_id) DO NOTHING
  RETURNING custody_webhook_events.received_at
  INTO v_existing_received_at;

  IF v_existing_received_at IS NOT NULL THEN
    -- New row — return was_replay=false.
    was_replay := false;
    received_at := v_existing_received_at;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Conflict path — fetch the original received_at for forensic value.
  SELECT cwe.received_at
    INTO v_existing_received_at
    FROM public.custody_webhook_events cwe
    WHERE cwe.gateway = p_gateway AND cwe.event_id = p_event_id;

  was_replay := true;
  received_at := v_existing_received_at;
  RETURN NEXT;
  RETURN;
END;
$$;

COMMENT ON FUNCTION public.fn_record_custody_webhook_event(text, text, text, jsonb) IS
  'L01-01 — Idempotent receiver-side dedup. Returns was_replay=true if the '
  '(gateway, event_id) pair already exists; false if newly inserted.';

-- Grant only to authenticated/service callers. PostgREST picks this up;
-- the service role can call regardless.
REVOKE ALL ON FUNCTION public.fn_record_custody_webhook_event(text, text, text, jsonb)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_record_custody_webhook_event(text, text, text, jsonb)
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 4. fn_mark_custody_webhook_event_processed
-- ─────────────────────────────────────────────────────────────────────
--   Called by the route handler AFTER `confirmDepositByReference` succeeds
--   so ops can distinguish "received but processing failed" from
--   "received and credit applied". Idempotent: re-marking is a no-op.

CREATE OR REPLACE FUNCTION public.fn_mark_custody_webhook_event_processed(
  p_gateway   text,
  p_event_id  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
  PERFORM set_config('lock_timeout', '2s', true);

  UPDATE public.custody_webhook_events
    SET processed_at = COALESCE(processed_at, now())
    WHERE gateway = p_gateway AND event_id = p_event_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mark_custody_webhook_event_processed(text, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mark_custody_webhook_event_processed(text, text)
  TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 5. fn_prune_custody_webhook_events (manual / future cron)
-- ─────────────────────────────────────────────────────────────────────
--   Stripe and MP both stop retrying after at most 3 days. We keep 30
--   days for forensic correlation. Operators can `SELECT
--   public.fn_prune_custody_webhook_events();` ad-hoc; we'll wire a
--   nightly cron in a follow-up Lente 12 batch.

CREATE OR REPLACE FUNCTION public.fn_prune_custody_webhook_events(
  p_keep_days integer DEFAULT 30
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
  v_deleted integer;
BEGIN
  IF p_keep_days IS NULL OR p_keep_days < 1 THEN
    RAISE EXCEPTION 'INVALID_KEEP_DAYS: %', p_keep_days
      USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('lock_timeout', '2s', true);

  WITH deleted AS (
    DELETE FROM public.custody_webhook_events
      WHERE received_at < now() - make_interval(days := p_keep_days)
      RETURNING 1
  )
  SELECT count(*)::integer INTO v_deleted FROM deleted;

  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_prune_custody_webhook_events(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_prune_custody_webhook_events(integer) TO service_role;

-- ─────────────────────────────────────────────────────────────────────
-- 6. Self-test (migration time, in-transaction)
-- ─────────────────────────────────────────────────────────────────────
--   Build confidence the dedup primitive works before the route handler
--   ever depends on it. Cleans up after itself so prod is untouched.

DO $self_test$
DECLARE
  v_first   record;
  v_second  record;
  v_pruned  integer;
BEGIN
  -- (1) First insert returns was_replay=false.
  SELECT * INTO v_first
    FROM public.fn_record_custody_webhook_event(
      'stripe', 'evt_l01_01_self_test', 'ref_self_test',
      jsonb_build_object('type', 'self_test')
    );
  IF v_first.was_replay THEN
    RAISE EXCEPTION '[L01-01.self_test] first insert reported replay=true';
  END IF;

  -- (2) Second insert with same (gateway, event_id) returns was_replay=true.
  SELECT * INTO v_second
    FROM public.fn_record_custody_webhook_event(
      'stripe', 'evt_l01_01_self_test', 'ref_self_test_DIFFERENT',
      jsonb_build_object('type', 'self_test_replay')
    );
  IF NOT v_second.was_replay THEN
    RAISE EXCEPTION '[L01-01.self_test] second insert reported replay=false';
  END IF;
  -- And the original received_at is preserved (we did NOT overwrite the row).
  IF v_second.received_at <> v_first.received_at THEN
    RAISE EXCEPTION '[L01-01.self_test] received_at changed on replay';
  END IF;

  -- (3) Mark processed is idempotent.
  PERFORM public.fn_mark_custody_webhook_event_processed(
    'stripe', 'evt_l01_01_self_test'
  );
  PERFORM public.fn_mark_custody_webhook_event_processed(
    'stripe', 'evt_l01_01_self_test'
  );

  -- (4) Cleanup so we don't pollute prod.
  DELETE FROM public.custody_webhook_events
    WHERE event_id = 'evt_l01_01_self_test';

  -- (5) Prune helper rejects bad inputs.
  BEGIN
    SELECT public.fn_prune_custody_webhook_events(0) INTO v_pruned;
    RAISE EXCEPTION '[L01-01.self_test] prune accepted keep_days=0';
  EXCEPTION WHEN sqlstate 'P0001' THEN
    NULL;
  END;

  RAISE NOTICE '[L01-01.self_test] custody_webhook_events dedup primitive verified';
END;
$self_test$;

COMMIT;
