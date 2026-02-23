-- ============================================================================
-- Omni Runner — billing_events dedup for Stripe webhooks
-- Date: 2026-02-21
-- Sprint: 31.3.0
-- Origin: DECISAO 049 (Payment Gateway — Stripe)
-- ============================================================================
-- Adds stripe_event_id to billing_events for idempotent webhook processing.
-- Partial UNIQUE index (WHERE NOT NULL) so pre-existing rows without a
-- Stripe event ID are unaffected.
-- ============================================================================

ALTER TABLE public.billing_events
  ADD COLUMN IF NOT EXISTS stripe_event_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_billing_events_stripe_dedup
  ON public.billing_events(stripe_event_id)
  WHERE stripe_event_id IS NOT NULL;

COMMENT ON COLUMN public.billing_events.stripe_event_id IS
  'Stripe event ID (evt_...) for webhook dedup. UNIQUE partial index prevents '
  'double-processing. See DECISAO 049, Sprint 31.3.0.';
