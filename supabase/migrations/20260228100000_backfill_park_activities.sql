-- ============================================================================
-- Backfill park_activities for imported Strava sessions
-- Date: 2026-02-28
-- Origin: DECISÃO 122 — Park detection for backfilled sessions
-- ============================================================================
-- Problem: park detection only ran on webhook-received activities.
-- Sessions created via importStravaHistory + backfill_strava_sessions never
-- got a park_activities record, so park screens showed zero data.
--
-- Fix: add start_lat/start_lng to strava_activity_history, then create
-- backfill_park_activities RPC that matches sessions to parks using haversine.
-- ============================================================================

BEGIN;

-- 1. Add start coordinates to strava_activity_history
ALTER TABLE public.strava_activity_history
  ADD COLUMN IF NOT EXISTS start_lat DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS start_lng DOUBLE PRECISION;

-- 2. Haversine helper (meters between two points)
CREATE OR REPLACE FUNCTION public._haversine_m(
  lat1 DOUBLE PRECISION, lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION, lng2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE STRICT
AS $$
  SELECT 6371000.0 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
    COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
    POWER(SIN(RADIANS(lng2 - lng1) / 2), 2)
  ))
$$;

-- 3. RPC: backfill park_activities for a user's sessions
CREATE OR REPLACE FUNCTION public.backfill_park_activities(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _inserted INTEGER := 0;
  _rec RECORD;
  _park RECORD;
  _dist DOUBLE PRECISION;
  _display TEXT;
BEGIN
  -- Get user display name once
  SELECT display_name INTO _display
  FROM public.profiles
  WHERE id = p_user_id;

  -- Find sessions with Strava start coordinates that don't have a park_activity yet
  FOR _rec IN
    SELECT
      s.id         AS session_id,
      s.strava_activity_id,
      s.total_distance_m,
      s.moving_ms,
      s.avg_pace_sec_km,
      s.avg_bpm,
      s.start_time_ms,
      h.start_lat,
      h.start_lng
    FROM public.sessions s
    JOIN public.strava_activity_history h
      ON h.user_id = s.user_id
     AND h.strava_activity_id = s.strava_activity_id
    WHERE s.user_id = p_user_id
      AND s.source = 'strava'
      AND s.status = 3
      AND s.total_distance_m >= 1000
      AND h.start_lat IS NOT NULL
      AND h.start_lng IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.park_activities pa
        WHERE pa.session_id = s.id
      )
    ORDER BY s.start_time_ms DESC
  LOOP
    -- Check against all parks
    FOR _park IN
      SELECT id, center_lat, center_lng, radius_m
      FROM public.parks
    LOOP
      _dist := public._haversine_m(
        _rec.start_lat, _rec.start_lng,
        _park.center_lat, _park.center_lng
      );

      IF _dist <= _park.radius_m THEN
        INSERT INTO public.park_activities (
          park_id, user_id, session_id, strava_activity_id,
          display_name, distance_m, moving_time_s,
          avg_pace_sec_km, avg_heartrate, start_time
        ) VALUES (
          _park.id,
          p_user_id,
          _rec.session_id,
          _rec.strava_activity_id,
          _display,
          _rec.total_distance_m,
          COALESCE(_rec.moving_ms / 1000, 0),
          _rec.avg_pace_sec_km,
          _rec.avg_bpm,
          to_timestamp(_rec.start_time_ms / 1000.0)
        )
        ON CONFLICT (session_id) WHERE session_id IS NOT NULL
        DO NOTHING;

        _inserted := _inserted + 1;
        EXIT; -- one park per session
      END IF;
    END LOOP;
  END LOOP;

  RETURN _inserted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.backfill_park_activities(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_park_activities(UUID) TO service_role;

COMMIT;
