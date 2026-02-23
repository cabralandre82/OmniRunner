-- ============================================================================
-- Notification log — dedup guard for smart push notifications
-- Date: 2026-02-21
-- Sprint: 21.5.1
-- ============================================================================
-- Prevents duplicate notifications. Each (user_id, rule, context_id) tuple
-- is unique within a configurable window. Service-role writes only.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.notification_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rule        TEXT NOT NULL,
  context_id  TEXT NOT NULL DEFAULT '',
  sent_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_log_dedup
  ON public.notification_log(user_id, rule, context_id, sent_at DESC);

ALTER TABLE public.notification_log ENABLE ROW LEVEL SECURITY;

-- Users can read their own notification history
CREATE POLICY notification_log_select ON public.notification_log
  FOR SELECT USING (auth.uid() = user_id);

COMMIT;
