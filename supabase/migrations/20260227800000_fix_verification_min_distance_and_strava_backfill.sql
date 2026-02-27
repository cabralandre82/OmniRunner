-- ============================================================================
-- Fix verification minimum distance + Strava history backfill to sessions
-- Date: 2026-02-26
-- DECISÃO 109
-- ============================================================================
--
-- Two bugs fixed:
--
-- 1. eval_athlete_verification() and get_verification_state() used
--    total_distance_m >= 200 (200m). Should be >= 1000 (1km).
--    The Edge Function already used 1000m; the RPCs were out of sync.
--
-- 2. Historical Strava runs imported via importStravaHistory() are saved
--    to strava_activity_history but NOT to sessions. The strava-webhook
--    only fires for NEW activities. This function backfills existing
--    history records into sessions so they count for verification.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. FIX eval_athlete_verification — min distance 200 → 1000
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.eval_athlete_verification(
  p_user_id UUID
)
RETURNS TABLE (
  new_status            TEXT,
  new_trust_score       INTEGER,
  calibration_runs      INTEGER
) AS $$
DECLARE
  _total_verified_sessions  INTEGER;
  _total_flagged_sessions   INTEGER;
  _recent_flagged           INTEGER;
  _total_distance_m         DOUBLE PRECISION;
  _avg_distance_m           DOUBLE PRECISION;
  _current_status           TEXT;
  _current_score            INTEGER;
  _new_status               TEXT;
  _new_score                INTEGER;
  _valid_runs               INTEGER;
  _flags                    TEXT[];
  _now                      TIMESTAMPTZ := now();

  _min_distance_m           CONSTANT DOUBLE PRECISION := 1000;
  _verified_min_runs        CONSTANT INTEGER := 7;
  _verified_min_score       CONSTANT INTEGER := 80;
  _downgrade_flag_threshold CONSTANT INTEGER := 3;
  _recent_window            CONSTANT INTERVAL := '30 days';
BEGIN
  SELECT av.verification_status, av.trust_score, av.calibration_valid_runs
  INTO _current_status, _current_score, _valid_runs
  FROM public.athlete_verification av
  WHERE av.user_id = p_user_id;

  IF NOT FOUND THEN
    INSERT INTO public.athlete_verification (user_id)
    VALUES (p_user_id)
    ON CONFLICT DO NOTHING;

    _current_status := 'UNVERIFIED';
    _current_score := 0;
    _valid_runs := 0;
  END IF;

  -- Count verified sessions (is_verified=true, distance >= 1km)
  SELECT COUNT(*)
  INTO _total_verified_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = true
    AND s.total_distance_m >= _min_distance_m;

  SELECT COUNT(*)
  INTO _total_flagged_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false;

  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false
    AND s.created_at >= (_now - _recent_window);

  SELECT COALESCE(SUM(s.total_distance_m), 0),
         CASE WHEN COUNT(*) > 0
              THEN COALESCE(SUM(s.total_distance_m), 0) / COUNT(*)
              ELSE 0
         END
  INTO _total_distance_m, _avg_distance_m
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = true
    AND s.total_distance_m >= _min_distance_m;

  -- ── Compute trust_score (0..100) ─────────────────────────────────────
  _new_score := 0;
  _flags := '{}';

  _new_score := _new_score + LEAST(_total_verified_sessions * 5, 35);

  IF _avg_distance_m >= 1000 AND _total_verified_sessions >= 3 THEN
    _new_score := _new_score + 15;
    _flags := array_append(_flags, 'consistent_distance');
  ELSIF _avg_distance_m >= 500 THEN
    _new_score := _new_score + 8;
  END IF;

  IF _total_distance_m >= 50000 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'high_volume_runner');
  ELSIF _total_distance_m >= 20000 THEN
    _new_score := _new_score + 14;
  ELSIF _total_distance_m >= 10000 THEN
    _new_score := _new_score + 8;
  END IF;

  IF _total_flagged_sessions = 0 AND _total_verified_sessions >= 5 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'clean_record');
  ELSIF _total_flagged_sessions = 0 THEN
    _new_score := _new_score + 12;
  ELSIF _total_flagged_sessions <= 1 THEN
    _new_score := _new_score + 6;
  END IF;

  IF _recent_flagged >= _downgrade_flag_threshold THEN
    _new_score := GREATEST(_new_score - 30, 0);
    _flags := array_append(_flags, 'recent_integrity_issues');
  ELSIF _recent_flagged > 0 THEN
    _new_score := GREATEST(_new_score - (_recent_flagged * 10), 0);
  END IF;

  IF _total_verified_sessions >= 20 THEN
    _new_score := _new_score + 10;
    _flags := array_append(_flags, 'veteran_runner');
  ELSIF _total_verified_sessions >= 10 THEN
    _new_score := _new_score + 5;
  END IF;

  _new_score := LEAST(GREATEST(_new_score, 0), 100);

  -- ── State machine transitions ────────────────────────────────────────
  _valid_runs := _total_verified_sessions;
  _new_status := _current_status;

  IF _current_status = 'UNVERIFIED' THEN
    IF _total_verified_sessions >= 1 THEN
      _new_status := 'CALIBRATING';
    END IF;

  ELSIF _current_status = 'CALIBRATING' THEN
    IF _recent_flagged >= _downgrade_flag_threshold THEN
      _new_status := 'UNVERIFIED';
      _valid_runs := 0;
    ELSIF _total_verified_sessions >= _verified_min_runs
      AND _new_score >= _verified_min_score
      AND _recent_flagged = 0 THEN
      _new_status := 'VERIFIED';
    ELSIF _total_verified_sessions >= _verified_min_runs THEN
      _new_status := 'MONITORED';
    END IF;

  ELSIF _current_status = 'MONITORED' THEN
    IF _recent_flagged >= _downgrade_flag_threshold THEN
      _new_status := 'CALIBRATING';
      _valid_runs := GREATEST(_total_verified_sessions - _recent_flagged, 0);
    ELSIF _new_score >= _verified_min_score
      AND _recent_flagged = 0 THEN
      _new_status := 'VERIFIED';
    END IF;

  ELSIF _current_status = 'VERIFIED' THEN
    IF _recent_flagged >= _downgrade_flag_threshold THEN
      _new_status := 'DOWNGRADED';
    END IF;

  ELSIF _current_status = 'DOWNGRADED' THEN
    IF _recent_flagged = 0
      AND _total_verified_sessions >= _verified_min_runs
      AND _new_score >= _verified_min_score THEN
      _new_status := 'MONITORED';
    ELSIF _recent_flagged = 0
      AND _total_verified_sessions >= 1 THEN
      _new_status := 'CALIBRATING';
    END IF;
  END IF;

  -- ── Persist ──────────────────────────────────────────────────────────
  UPDATE public.athlete_verification av
  SET
    verification_status   = _new_status,
    trust_score           = _new_score,
    verified_at           = CASE
                              WHEN _new_status = 'VERIFIED' AND _current_status != 'VERIFIED'
                              THEN _now
                              ELSE av.verified_at
                            END,
    last_eval_at          = _now,
    verification_flags    = _flags,
    calibration_valid_runs = _valid_runs,
    last_integrity_flag_at = CASE
                               WHEN _recent_flagged > 0 THEN _now
                               ELSE av.last_integrity_flag_at
                             END,
    updated_at            = _now
  WHERE av.user_id = p_user_id;

  new_status       := _new_status;
  new_trust_score  := _new_score;
  calibration_runs := _valid_runs;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. FIX get_verification_state — min distance 200 → 1000
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_verification_state()
RETURNS TABLE (
  verification_status     TEXT,
  trust_score             INTEGER,
  verified_at             TIMESTAMPTZ,
  last_eval_at            TIMESTAMPTZ,
  verification_flags      TEXT[],
  calibration_valid_runs  INTEGER,
  last_integrity_flag_at  TIMESTAMPTZ,
  identity_ok             BOOLEAN,
  permissions_ok          BOOLEAN,
  valid_runs_ok           BOOLEAN,
  integrity_ok            BOOLEAN,
  baseline_ok             BOOLEAN,
  trust_ok                BOOLEAN,
  valid_runs_count        INTEGER,
  flagged_runs_recent     INTEGER,
  total_distance_m        DOUBLE PRECISION,
  avg_distance_m          DOUBLE PRECISION,
  required_valid_runs     INTEGER,
  required_trust_score    INTEGER
) AS $$
DECLARE
  _uid                    UUID := auth.uid();
  _av                     public.athlete_verification%ROWTYPE;
  _verified_count         INTEGER;
  _recent_flagged         INTEGER;
  _total_dist             DOUBLE PRECISION;
  _avg_dist               DOUBLE PRECISION;

  _min_distance_m CONSTANT DOUBLE PRECISION := 1000;
  _required_runs  CONSTANT INTEGER := 7;
  _required_trust CONSTANT INTEGER := 80;
  _recent_window  CONSTANT INTERVAL := '30 days';
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: No authenticated user';
  END IF;

  SELECT * INTO _av
  FROM public.athlete_verification av
  WHERE av.user_id = _uid;

  IF NOT FOUND THEN
    INSERT INTO public.athlete_verification (user_id)
    VALUES (_uid)
    ON CONFLICT DO NOTHING;

    SELECT * INTO _av
    FROM public.athlete_verification av
    WHERE av.user_id = _uid;
  END IF;

  -- Count verified sessions (distance >= 1km)
  SELECT COUNT(*)
  INTO _verified_count
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = true
    AND s.total_distance_m >= _min_distance_m;

  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = false
    AND s.created_at >= (now() - _recent_window);

  SELECT COALESCE(SUM(s.total_distance_m), 0),
         CASE WHEN COUNT(*) > 0
              THEN COALESCE(SUM(s.total_distance_m), 0) / COUNT(*)
              ELSE 0
         END
  INTO _total_dist, _avg_dist
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = true
    AND s.total_distance_m >= _min_distance_m;

  verification_status    := _av.verification_status;
  trust_score            := _av.trust_score;
  verified_at            := _av.verified_at;
  last_eval_at           := _av.last_eval_at;
  verification_flags     := _av.verification_flags;
  calibration_valid_runs := _av.calibration_valid_runs;
  last_integrity_flag_at := _av.last_integrity_flag_at;

  identity_ok            := NULL;
  permissions_ok         := NULL;
  valid_runs_ok          := _verified_count >= _required_runs;
  integrity_ok           := _recent_flagged = 0;
  baseline_ok            := _avg_dist >= 1000 AND _verified_count >= 3;
  trust_ok               := _av.trust_score >= _required_trust;

  valid_runs_count       := _verified_count;
  flagged_runs_recent    := _recent_flagged;
  total_distance_m       := _total_dist;
  avg_distance_m         := _avg_dist;

  required_valid_runs    := _required_runs;
  required_trust_score   := _required_trust;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. NEW: backfill_strava_sessions — import history records as sessions
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Converts strava_activity_history rows into sessions so they count for
-- athlete verification. Only creates sessions for runs that:
--   - Don't already exist in sessions (by strava_activity_id)
--   - Have distance >= 1km
--   - Have plausible pace (2:30/km to 20:00/km)
--
-- Called from the mobile app after connecting Strava.
-- SECURITY DEFINER: uses p_user_id from the caller (Edge Function or client).

CREATE OR REPLACE FUNCTION public.backfill_strava_sessions(p_user_id UUID)
RETURNS INTEGER AS $$
DECLARE
  _inserted INTEGER := 0;
  _row      RECORD;
  _sid      UUID;
  _pace     DOUBLE PRECISION;
  _flags    TEXT[];
  _verified BOOLEAN;
  _start_ms BIGINT;
  _end_ms   BIGINT;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id is required';
  END IF;

  FOR _row IN
    SELECT h.*
    FROM public.strava_activity_history h
    WHERE h.user_id = p_user_id
      AND h.distance_m >= 1000
      AND h.moving_time_s > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.sessions s
        WHERE s.user_id = p_user_id
          AND s.strava_activity_id = h.strava_activity_id
      )
    ORDER BY h.start_date DESC
  LOOP
    _sid   := gen_random_uuid();
    _flags := '{}';
    _verified := true;

    -- Pace plausibility check (sec/km)
    _pace := _row.moving_time_s / (_row.distance_m / 1000.0);

    -- Too fast (< 2:30/km = 150 s/km) → flag
    IF _pace < 150 THEN
      _flags := array_append(_flags, 'SPEED_IMPOSSIBLE');
      _verified := false;
    END IF;

    -- Implausible pace (< 3:00/km or > 20:00/km)
    IF _pace < 180 OR _pace > 1200 THEN
      _flags := array_append(_flags, 'IMPLAUSIBLE_PACE');
      _verified := false;
    END IF;

    -- Duration too short (< 1 min)
    IF _row.moving_time_s < 60 THEN
      _flags := array_append(_flags, 'TOO_SHORT_DURATION');
      _verified := false;
    END IF;

    -- Parse start_date → ms
    BEGIN
      _start_ms := EXTRACT(EPOCH FROM (_row.start_date::timestamptz)) * 1000;
    EXCEPTION WHEN OTHERS THEN
      _start_ms := EXTRACT(EPOCH FROM _row.imported_at) * 1000;
    END;
    _end_ms := _start_ms + (_row.elapsed_time_s * 1000);

    INSERT INTO public.sessions (
      id, user_id, status, start_time_ms, end_time_ms,
      total_distance_m, moving_ms, avg_pace_sec_km,
      avg_bpm, max_bpm,
      is_verified, integrity_flags,
      is_synced, source, strava_activity_id
    ) VALUES (
      _sid, p_user_id, 2, _start_ms, _end_ms,
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
      _inserted := _inserted + 1;
    END IF;
  END LOOP;

  RETURN _inserted;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
