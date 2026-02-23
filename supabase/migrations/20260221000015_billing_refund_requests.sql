-- ============================================================================
-- Omni Runner — billing_refund_requests
-- Date: 2026-02-21
-- Sprint: 35.3.1
-- Origin: DECISAO 051 — Política de Reembolsos
-- ============================================================================
-- Tracks refund requests from admin_master through platform review.
-- Lifecycle: requested → approved → processed | rejected
-- The actual Stripe refund is executed by the platform team after approval.
-- ============================================================================

BEGIN;

-- ── 1. Table ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.billing_refund_requests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  purchase_id     UUID NOT NULL REFERENCES public.billing_purchases(id) ON DELETE CASCADE,
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'requested'
                  CHECK (status IN ('requested', 'approved', 'processed', 'rejected')),
  reason          TEXT NOT NULL CHECK (length(reason) >= 3),
  refund_type     TEXT NOT NULL DEFAULT 'full'
                  CHECK (refund_type IN ('full', 'partial')),
  amount_cents    INTEGER,
  credits_to_debit INTEGER,
  requested_by    UUID NOT NULL REFERENCES auth.users(id),
  reviewed_by     UUID REFERENCES auth.users(id),
  review_notes    TEXT,
  requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_at     TIMESTAMPTZ,
  processed_at    TIMESTAMPTZ
);

COMMENT ON TABLE public.billing_refund_requests IS
  'Refund request lifecycle: requested → approved → processed | rejected. '
  'Platform team reviews and executes via Stripe Dashboard. See DECISAO 051.';

COMMENT ON COLUMN public.billing_refund_requests.reason IS
  'Admin-provided reason for the refund request.';

COMMENT ON COLUMN public.billing_refund_requests.refund_type IS
  'full = entire purchase amount; partial = specific amount_cents.';

COMMENT ON COLUMN public.billing_refund_requests.amount_cents IS
  'For partial refunds: the amount in cents to refund. NULL for full refunds.';

COMMENT ON COLUMN public.billing_refund_requests.credits_to_debit IS
  'Calculated credits to remove from inventory upon processing. '
  'Full: credits_amount of purchase. Partial: floor(credits * amount / price).';

COMMENT ON COLUMN public.billing_refund_requests.reviewed_by IS
  'Platform team member who approved or rejected the request.';

-- ── 2. Indexes ──────────────────────────────────────────────────────────────

CREATE INDEX idx_refund_requests_group
  ON public.billing_refund_requests(group_id, requested_at DESC);

CREATE INDEX idx_refund_requests_purchase
  ON public.billing_refund_requests(purchase_id);

CREATE INDEX idx_refund_requests_status
  ON public.billing_refund_requests(status)
  WHERE status IN ('requested', 'approved');

-- Prevent duplicate open requests for the same purchase
CREATE UNIQUE INDEX idx_refund_requests_open_unique
  ON public.billing_refund_requests(purchase_id)
  WHERE status IN ('requested', 'approved');

-- ── 3. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.billing_refund_requests ENABLE ROW LEVEL SECURITY;

-- admin_master can read their group's refund requests
CREATE POLICY "refund_requests_admin_read" ON public.billing_refund_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_refund_requests.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
  );

-- admin_master can submit refund requests for their group
CREATE POLICY "refund_requests_admin_insert" ON public.billing_refund_requests
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = billing_refund_requests.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role = 'admin_master'
    )
    AND requested_by = auth.uid()
  );

-- Status transitions (approved/rejected/processed) via service_role only

-- ── 4. Expand billing_purchases status to include 'refunded' ────────────────

ALTER TABLE public.billing_purchases
  DROP CONSTRAINT IF EXISTS billing_purchases_status_check;

ALTER TABLE public.billing_purchases
  ADD CONSTRAINT billing_purchases_status_check
  CHECK (status IN ('pending', 'paid', 'fulfilled', 'cancelled', 'refunded'));

-- ── 5. Expand billing_events event_type to include 'refund_requested' ───────

ALTER TABLE public.billing_events
  DROP CONSTRAINT IF EXISTS billing_events_event_type_check;

ALTER TABLE public.billing_events
  ADD CONSTRAINT billing_events_event_type_check
  CHECK (event_type IN (
    'created',
    'payment_confirmed',
    'fulfilled',
    'cancelled',
    'refunded',
    'refund_requested',
    'note_added'
  ));

COMMIT;
