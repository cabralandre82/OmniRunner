-- ============================================================================
-- Fix: backfill_strava_sessions uses wrong column name (activity_date)
-- Fix: existing webhook-uploaded points have wrong Storage path prefix
-- Date: 2026-03-17
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix backfill_strava_sessions: _row.activity_date → _row.start_date
-- ═══════════════════════════════════════════════════════════════════════════
-- The 20260228000000 migration introduced a typo: it referenced
-- _row.activity_date, but the strava_activity_history table column is
-- start_date. This caused all post-migration backfills to fail.

CREATE OR REPLACE FUNCTION public.backfill_strava_sessions(
  p_user_id UUID
) RETURNS INTEGER AS $$
DECLARE
  _row        RECORD;
  _count      INTEGER := 0;
  _sid        UUID;
  _start_ms   BIGINT;
  _end_ms     BIGINT;
  _pace       DOUBLE PRECISION;
  _verified   BOOLEAN;
  _flags      TEXT[];
  _min_dist   CONSTANT DOUBLE PRECISION := 1000;
BEGIN
  FOR _row IN
    SELECT *
    FROM public.strava_activity_history
    WHERE user_id = p_user_id
      AND distance_m >= _min_dist
      AND moving_time_s > 0
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.sessions
      WHERE user_id = p_user_id
        AND strava_activity_id = _row.strava_activity_id
    ) THEN
      CONTINUE;
    END IF;

    _sid      := gen_random_uuid();
    _verified := true;
    _flags    := '{}';

    BEGIN
      _start_ms := EXTRACT(EPOCH FROM (_row.start_date::timestamptz)) * 1000;
    EXCEPTION WHEN OTHERS THEN
      _start_ms := EXTRACT(EPOCH FROM _row.imported_at) * 1000;
    END;
    _end_ms   := _start_ms + (_row.elapsed_time_s * 1000);
    _pace     := _row.moving_time_s / (_row.distance_m / 1000.0);

    IF _pace < 150 THEN
      _flags := array_append(_flags, 'SPEED_IMPOSSIBLE');
      _verified := false;
    END IF;

    IF _pace < 180 OR _pace > 1200 THEN
      _flags := array_append(_flags, 'IMPLAUSIBLE_PACE');
      _verified := false;
    END IF;

    IF _row.moving_time_s < 60 THEN
      _flags := array_append(_flags, 'TOO_SHORT_DURATION');
      _verified := false;
    END IF;

    INSERT INTO public.sessions (
      id, user_id, status, start_time_ms, end_time_ms,
      total_distance_m, moving_ms, avg_pace_sec_km,
      avg_bpm, max_bpm,
      is_verified, integrity_flags,
      is_synced, source, strava_activity_id
    ) VALUES (
      _sid, p_user_id, 3, _start_ms, _end_ms,
      _row.distance_m, _row.moving_time_s * 1000, _pace,
      CASE WHEN _row.average_heartrate IS NOT NULL
           THEN _row.average_heartrate::integer ELSE NULL END,
      CASE WHEN _row.max_heartrate IS NOT NULL
           THEN _row.max_heartrate::integer ELSE NULL END,
      _verified, _flags,
      true, 'strava', _row.strava_activity_id
    )
    ON CONFLICT (user_id, strava_activity_id)
      WHERE strava_activity_id IS NOT NULL
      DO NOTHING;

    IF FOUND THEN
      _count := _count + 1;
    END IF;
  END LOOP;

  RETURN _count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
   SET search_path = public;

GRANT EXECUTE ON FUNCTION public.backfill_strava_sessions(UUID)
  TO authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Fix existing webhook-uploaded points with wrong Storage path prefix
-- ═══════════════════════════════════════════════════════════════════════════
-- The strava-webhook was uploading points with path
-- "session-points/<uid>/<sid>.json" (bucket name duplicated as folder).
-- Fix the points_path column so RunDetailsScreen can find them.

UPDATE public.sessions
SET points_path = REGEXP_REPLACE(points_path, '^session-points/', '')
WHERE points_path LIKE 'session-points/%'
  AND source = 'strava';

-- Allow reading old files uploaded with the legacy path prefix.
-- Legacy objects: name = "session-points/<uid>/<sid>.json"
-- foldername[1] = 'session-points', foldername[2] = uid
CREATE POLICY "session_points_legacy_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'session-points'
    AND (storage.foldername(name))[1] = 'session-points'
    AND (storage.foldername(name))[2] = auth.uid()::text
  );

COMMIT;
