-- ============================================================================
-- Push notification device tokens
-- Date: 2026-02-21
-- Sprint: 21.5.0
-- ============================================================================
-- Stores FCM/APNS tokens per user per device. One user may have multiple
-- devices. Tokens are upserted on app launch and cleared on sign-out.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token       TEXT NOT NULL,
  platform    TEXT NOT NULL CHECK (platform IN ('android', 'ios', 'web')),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_unique UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user
  ON public.device_tokens(user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

-- Users can manage their own tokens
CREATE POLICY device_tokens_insert ON public.device_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY device_tokens_select ON public.device_tokens
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY device_tokens_update ON public.device_tokens
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY device_tokens_delete ON public.device_tokens
  FOR DELETE USING (auth.uid() = user_id);

COMMIT;
