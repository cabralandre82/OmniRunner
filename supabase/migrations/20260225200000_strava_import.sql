-- ============================================================================
-- Strava Import — sessions source tracking + server-side Strava tokens
-- Date: 2026-02-25
-- ============================================================================
-- Enables importing activities from Strava (Garmin, Coros, Suunto, etc.)
-- and counting them for challenges. Anti-cheat runs on imported GPS streams.

BEGIN;

-- 1. Track where each session came from
ALTER TABLE public.sessions
  ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'app'
    CHECK (source IN ('app', 'strava', 'watch', 'manual')),
  ADD COLUMN IF NOT EXISTS strava_activity_id BIGINT,
  ADD COLUMN IF NOT EXISTS device_name TEXT;

COMMENT ON COLUMN public.sessions.source IS
  'Origin of this session: app (tracked in OmniRunner), strava (imported via Strava API), watch (standalone watch app), manual (manual entry).';

COMMENT ON COLUMN public.sessions.strava_activity_id IS
  'Strava activity ID. Set when source=strava. Used for dedup on import.';

COMMENT ON COLUMN public.sessions.device_name IS
  'Device that recorded the session (e.g. Garmin Forerunner 265).';

CREATE UNIQUE INDEX IF NOT EXISTS idx_sessions_strava_dedup
  ON public.sessions(user_id, strava_activity_id)
  WHERE strava_activity_id IS NOT NULL;

-- 2. Server-side Strava tokens (for webhook-triggered imports)
-- The app stores tokens locally, but the webhook needs server-side access.
CREATE TABLE IF NOT EXISTS public.strava_connections (
  user_id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  strava_athlete_id BIGINT NOT NULL,
  access_token     TEXT NOT NULL,
  refresh_token    TEXT NOT NULL,
  expires_at       INTEGER NOT NULL,
  scope            TEXT NOT NULL DEFAULT 'activity:read_all,activity:write',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.strava_connections IS
  'Server-side Strava OAuth tokens for webhook-triggered activity imports.';

ALTER TABLE public.strava_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "strava_connections_own_read" ON public.strava_connections
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "strava_connections_own_upsert" ON public.strava_connections
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "strava_connections_own_update" ON public.strava_connections
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "strava_connections_own_delete" ON public.strava_connections
  FOR DELETE USING (auth.uid() = user_id);

COMMIT;
