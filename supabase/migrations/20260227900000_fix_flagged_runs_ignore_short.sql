-- ============================================================================
-- Fix: flagged runs query should ignore sessions < 1km
-- Date: 2026-02-26
-- DECISÃO 115
-- ============================================================================
-- Sessions with distance < 1km (e.g. 300m test runs) were counting as
-- "flagged" in integrity checks, penalizing the trust score by -10 pts
-- and blocking VERIFIED status. Only sessions >= 1km should affect integrity.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. FIX eval_athlete_verification — ignore short sessions in flag counts
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

  -- Count flagged sessions >= 1km (short runs don't affect integrity)
  SELECT COUNT(*)
  INTO _total_flagged_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false
    AND s.total_distance_m >= _min_distance_m;

  -- Count recent flagged sessions >= 1km (last 30 days)
  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false
    AND s.total_distance_m >= _min_distance_m
    AND s.created_at >= (_now - _recent_window);

  -- Total and average distance for verified sessions
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

  -- ── Compute trust_score (0..100)
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

  -- ── State machine transitions
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

  -- ── Persist
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
-- 2. FIX get_verification_state — ignore short sessions in flag counts
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

  -- Count recent flagged sessions >= 1km (short runs don't affect integrity)
  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = false
    AND s.total_distance_m >= _min_distance_m
    AND s.created_at >= (now() - _recent_window);

  -- Distance stats for verified sessions >= 1km
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

COMMIT;
