-- ============================================================================
-- Product event tracking — lightweight append-only analytics
-- Date: 2026-02-21
-- Sprint: 21.4.0
-- ============================================================================
-- Captures product milestones: onboarding completion, first challenge,
-- first championship launch, flow abandonment. No PII beyond user_id.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.product_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id),
  event_name  TEXT NOT NULL,
  properties  JSONB NOT NULL DEFAULT '{}',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_product_events_user
  ON public.product_events(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_product_events_name
  ON public.product_events(event_name, created_at DESC);

ALTER TABLE public.product_events ENABLE ROW LEVEL SECURITY;

-- Users can insert their own events
CREATE POLICY product_events_insert ON public.product_events
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Users can read their own events (for dedup checks)
CREATE POLICY product_events_select ON public.product_events
  FOR SELECT USING (auth.uid() = user_id);

-- Staff can read events for their group's athletes (aggregated dashboards)
CREATE POLICY product_events_staff_read ON public.product_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      JOIN public.coaching_members target_cm
        ON target_cm.group_id = cm.group_id
        AND target_cm.user_id = product_events.user_id
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

COMMIT;
