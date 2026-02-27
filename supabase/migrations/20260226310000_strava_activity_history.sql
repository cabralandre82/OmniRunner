-- ============================================================================
-- Strava Activity History — baseline for anti-cheat bootstrapping
-- Date: 2026-02-26
-- ============================================================================
-- Stores recent Strava activities imported on connect. Used to build an
-- athlete baseline (typical pace, distance, HR) before they start betting.

BEGIN;

CREATE TABLE IF NOT EXISTS public.strava_activity_history (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  strava_activity_id  BIGINT NOT NULL,
  name                TEXT,
  distance_m          DOUBLE PRECISION NOT NULL DEFAULT 0,
  moving_time_s       INTEGER NOT NULL DEFAULT 0,
  elapsed_time_s      INTEGER NOT NULL DEFAULT 0,
  average_speed       DOUBLE PRECISION,
  max_speed           DOUBLE PRECISION,
  average_heartrate   DOUBLE PRECISION,
  max_heartrate       DOUBLE PRECISION,
  start_date          TEXT,
  summary_polyline    TEXT,
  activity_type       TEXT,
  imported_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_strava_history_dedup
  ON public.strava_activity_history(user_id, strava_activity_id);

CREATE INDEX idx_strava_history_user
  ON public.strava_activity_history(user_id);

ALTER TABLE public.strava_activity_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "strava_history_own_read" ON public.strava_activity_history
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "strava_history_own_insert" ON public.strava_activity_history
  FOR INSERT WITH CHECK (auth.uid() = user_id);

COMMIT;
