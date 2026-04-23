-- L05-08 — Withdrawal progress timeline primitives.
--
-- `public.custody_withdrawals.status` already has the four-state
-- machine (pending → processing → completed | failed, plus
-- cancelled). What the portal lacks today is (a) a record of
-- *when* each transition happened and (b) a canonical ETA / SLA
-- breach flag the UI can render without re-inventing the policy.
--
-- This migration introduces:
--
--   1. `custody_withdrawal_events` — append-only transition log,
--      service_role-managed, RLS only lets the owning host group
--      read its own rows.
--   2. `fn_record_withdrawal_event` — trigger fired on
--      INSERT / status UPDATE of `custody_withdrawals` that writes
--      the event row idempotently.
--   3. `fn_withdrawal_timeline(uuid)` — jsonb contract the portal
--      calls to render the 4-step timeline (pending / processing /
--      completed / failed) with `expected_completion_at` and
--      `sla_breached` flags baked in.
--
-- SLA defaults (from docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md):
--   * pending   → processing   : 2 minutes
--   * processing → completed   : 10 minutes (business hours)
--                                up to 48h weekend/holiday (PIX)
--   * failure estornado no wallet até D+2
--
-- The function intentionally returns jsonb (not setof) so the
-- portal can cache a single row per withdrawal ID.

BEGIN;

CREATE TABLE IF NOT EXISTS public.custody_withdrawal_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  withdrawal_id   uuid NOT NULL REFERENCES public.custody_withdrawals(id)
                     ON DELETE CASCADE,
  status          text NOT NULL CHECK (
                     status IN (
                       'pending','processing','completed','failed','cancelled'
                     )
                   ),
  provider_ref    text,
  reason          text,
  metadata        jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT custody_withdrawal_events_unique
    UNIQUE (withdrawal_id, status)
);

COMMENT ON TABLE public.custody_withdrawal_events IS
  'L05-08 — append-only withdrawal state-transition log. ' ||
  'One row per (withdrawal_id, status). Trigger-populated.';

CREATE INDEX IF NOT EXISTS idx_custody_withdrawal_events_withdrawal
  ON public.custody_withdrawal_events(withdrawal_id, created_at);

ALTER TABLE public.custody_withdrawal_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS withdrawal_events_own_group
  ON public.custody_withdrawal_events;
CREATE POLICY withdrawal_events_own_group
  ON public.custody_withdrawal_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.custody_withdrawals w
      JOIN public.coaching_members cm ON cm.group_id = w.group_id
      WHERE w.id = custody_withdrawal_events.withdrawal_id
        AND cm.user_id = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

GRANT SELECT ON TABLE public.custody_withdrawal_events TO authenticated;
GRANT ALL ON TABLE public.custody_withdrawal_events TO service_role;

-- ── 2. Trigger that records state transitions ──────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_record_withdrawal_event()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.custody_withdrawal_events (
      withdrawal_id, status, provider_ref, reason, metadata
    ) VALUES (
      NEW.id, NEW.status, NEW.payout_reference, NULL, '{}'::jsonb
    )
    ON CONFLICT (withdrawal_id, status) DO NOTHING;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.custody_withdrawal_events (
      withdrawal_id, status, provider_ref, reason, metadata
    ) VALUES (
      NEW.id,
      NEW.status,
      NEW.payout_reference,
      NULL,
      jsonb_build_object(
        'from', OLD.status,
        'to', NEW.status,
        'at', NEW.completed_at
      )
    )
    ON CONFLICT (withdrawal_id, status) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_custody_withdrawals_events
  ON public.custody_withdrawals;
CREATE TRIGGER trg_custody_withdrawals_events
  AFTER INSERT OR UPDATE OF status
  ON public.custody_withdrawals
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_record_withdrawal_event();

-- ── 3. Timeline helper the portal calls ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_withdrawal_timeline(
  p_withdrawal_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_w      record;
  v_events jsonb;
  v_eta    timestamptz;
  v_sla_breached boolean;
  v_now    timestamptz := now();
  v_sla_pending_to_processing_minutes constant int := 2;
  v_sla_processing_to_completed_minutes constant int := 10;
BEGIN
  IF p_withdrawal_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT id, group_id, status, created_at, completed_at,
         amount_usd, net_local_amount, target_currency, payout_reference
    INTO v_w
    FROM public.custody_withdrawals
   WHERE id = p_withdrawal_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_agg(
           jsonb_build_object(
             'status', status,
             'at', created_at,
             'provider_ref', provider_ref,
             'reason', reason,
             'metadata', metadata
           )
           ORDER BY created_at
         )
    INTO v_events
    FROM public.custody_withdrawal_events
   WHERE withdrawal_id = p_withdrawal_id;

  IF v_events IS NULL THEN
    v_events := '[]'::jsonb;
  END IF;

  -- Expected completion: for pending we expect processing within 2min +
  -- completion within 10min after that. For processing we expect
  -- completion 10min after the processing event. For terminal states
  -- ETA is null.
  IF v_w.status = 'pending' THEN
    v_eta := v_w.created_at
               + make_interval(mins =>
                   v_sla_pending_to_processing_minutes
                   + v_sla_processing_to_completed_minutes);
  ELSIF v_w.status = 'processing' THEN
    v_eta := COALESCE(
      (SELECT created_at FROM public.custody_withdrawal_events
         WHERE withdrawal_id = p_withdrawal_id AND status = 'processing'
         ORDER BY created_at LIMIT 1),
      v_w.created_at
    ) + make_interval(mins => v_sla_processing_to_completed_minutes);
  ELSE
    v_eta := NULL;
  END IF;

  v_sla_breached := v_eta IS NOT NULL AND v_now > v_eta;

  RETURN jsonb_build_object(
    'withdrawal_id', v_w.id,
    'status', v_w.status,
    'created_at', v_w.created_at,
    'completed_at', v_w.completed_at,
    'amount_usd', v_w.amount_usd,
    'net_local_amount', v_w.net_local_amount,
    'target_currency', v_w.target_currency,
    'provider_ref', v_w.payout_reference,
    'events', v_events,
    'expected_completion_at', v_eta,
    'sla_breached', v_sla_breached,
    'refund_eta_days', CASE WHEN v_w.status = 'failed' THEN 2 ELSE NULL END
  );
END;
$$;

COMMENT ON FUNCTION public.fn_withdrawal_timeline(uuid) IS
  'L05-08 — canonical timeline contract for the portal withdraw UI.';

REVOKE ALL ON FUNCTION public.fn_withdrawal_timeline(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_withdrawal_timeline(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_withdrawal_timeline(uuid) TO service_role;

-- ── 4. Backfill one 'pending' event per historical withdrawal ──────────────
-- The trigger only fires going forward; historical rows get seeded here so
-- the timeline helper never returns an empty events array.

INSERT INTO public.custody_withdrawal_events (
  withdrawal_id, status, provider_ref, metadata
)
SELECT id, 'pending', payout_reference,
       jsonb_build_object('backfill', true)
  FROM public.custody_withdrawals
  ON CONFLICT (withdrawal_id, status) DO NOTHING;

INSERT INTO public.custody_withdrawal_events (
  withdrawal_id, status, provider_ref, metadata, created_at
)
SELECT id, status, payout_reference,
       jsonb_build_object('backfill', true),
       COALESCE(completed_at, created_at)
  FROM public.custody_withdrawals
 WHERE status IN ('processing','completed','failed','cancelled')
  ON CONFLICT (withdrawal_id, status) DO NOTHING;

-- ── 5. Self-test ───────────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_custody_withdrawals_events'
  ) THEN
    RAISE EXCEPTION 'L05-08 self-test: trigger missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'fn_withdrawal_timeline'
      AND p.prosecdef = true
  ) THEN
    RAISE EXCEPTION
      'L05-08 self-test: fn_withdrawal_timeline not SECURITY DEFINER';
  END IF;

  -- Unknown id returns NULL (not error)
  IF public.fn_withdrawal_timeline(
       '00000000-0000-0000-0000-00000000DEAD'::uuid
     ) IS NOT NULL
  THEN
    RAISE EXCEPTION
      'L05-08 self-test: timeline for unknown id should be NULL';
  END IF;

  RAISE NOTICE 'L05-08 self-test: OK';
END
$$;

COMMIT;
