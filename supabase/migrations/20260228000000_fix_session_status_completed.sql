-- ============================================================================
-- Fix: session status for "completed" is 3, not 2
-- Date: 2026-02-28
-- DECISÃO 117
-- ============================================================================
-- The Dart enum WorkoutStatus maps: initial=0, running=1, paused=2,
-- completed=3, discarded=4. The backfill_strava_sessions RPC and several
-- Edge Functions incorrectly used status=2 (paused) for completed sessions.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Fix existing backfilled sessions: status 2 → 3 (only Strava source)
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.sessions
SET status = 3
WHERE source = 'strava'
  AND status = 2;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Fix backfill_strava_sessions RPC: use status=3 (completed)
-- ═══════════════════════════════════════════════════════════════════════════

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
    _start_ms := EXTRACT(EPOCH FROM _row.activity_date) * 1000;
    _end_ms   := _start_ms + (_row.elapsed_time_s * 1000);
    _pace     := _row.moving_time_s / (_row.distance_m / 1000.0);
    _verified := true;
    _flags    := '{}';

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
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.backfill_strava_sessions(UUID)
  TO authenticated, service_role;

COMMIT;
