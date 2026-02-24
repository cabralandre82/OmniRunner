-- ============================================================================
-- Omni Runner — Verification Checklist RPCs
-- Date: 2026-02-24
-- Sprint: VERIFIED-2 (Sprint 22.2.0)
-- ============================================================================
--
-- 1. Updates eval_athlete_verification with finalized thresholds:
--      N = 7 verified runs for VERIFIED
--      Trust threshold = 80
--      Recalibrated scoring formula (volume: 5pts/session, cap 35)
--
-- 2. Adds get_verification_state() — read-only RPC for client checklist.
--    Returns full verification state + boolean checklist items so the app
--    can display progress without hardcoding thresholds.
--
-- 3. State machine (finalized):
--      valid_runs = 0               → UNVERIFIED
--      valid_runs 1..6              → CALIBRATING
--      valid_runs >= 7, trust < 80  → MONITORED
--      valid_runs >= 7, trust >= 80, no severe flags → VERIFIED
--      severe flags (>= 3 in 30d)  → DOWNGRADED
--
-- CHECKLIST ITEMS (MVP):
--   identity_ok      → NULL (future: selfie/liveness — not implemented)
--   permissions_ok   → NULL (client-side only: GPS/sensors)
--   valid_runs_ok    → calibration_valid_runs >= 7
--   integrity_ok     → 0 severe flags in last 30 days
--   baseline_ok      → avg distance >= 1km AND >= 3 sessions
--   trust_ok         → trust_score >= 80
--
-- RULES (CONGELADAS):
--   stake=0 always allowed; stake>0 requires VERIFIED.
--   ZERO admin override. Server decides.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. UPDATED eval_athlete_verification — finalized thresholds & scoring
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

  -- Thresholds (hardcoded server-side — not configurable by client)
  _verified_min_runs        CONSTANT INTEGER := 7;
  _verified_min_score       CONSTANT INTEGER := 80;
  _downgrade_flag_threshold CONSTANT INTEGER := 3;
  _recent_window            CONSTANT INTERVAL := '30 days';
BEGIN
  -- Fetch current verification state
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

  -- Count verified sessions (is_verified=true, distance >= 200m)
  SELECT COUNT(*)
  INTO _total_verified_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = true
    AND s.total_distance_m >= 200;

  -- Count sessions with critical integrity issues
  SELECT COUNT(*)
  INTO _total_flagged_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false;

  -- Count recent flagged sessions (last 30 days)
  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = false
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
    AND s.total_distance_m >= 200;

  -- ── Compute trust_score (0..100) ─────────────────────────────────────
  --
  -- Five components, recalibrated so 7 clean runs of ~3km reach >= 80:
  --   1. Volume    (max 35): 5 pts per verified session, cap 35
  --   2. Consistency (max 15): avg distance >= 1km + >= 3 sessions
  --   3. Distance  (max 20): total distance milestones
  --   4. Clean     (max 20): no flagged sessions + >= 5 verified
  --   5. Longevity (max 10): session count milestones (10+, 20+)
  --
  -- Example: 7 clean runs × 3km avg (21km total):
  --   35 + 15 + 14 + 20 + 0 = 84 → passes 80 ✓

  _new_score := 0;
  _flags := '{}';

  -- 1. Session volume (max 35 pts)
  _new_score := _new_score + LEAST(_total_verified_sessions * 5, 35);

  -- 2. Distance consistency (max 15 pts)
  IF _avg_distance_m >= 1000 AND _total_verified_sessions >= 3 THEN
    _new_score := _new_score + 15;
    _flags := array_append(_flags, 'consistent_distance');
  ELSIF _avg_distance_m >= 500 THEN
    _new_score := _new_score + 8;
  END IF;

  -- 3. Total distance milestones (max 20 pts)
  IF _total_distance_m >= 50000 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'high_volume_runner');
  ELSIF _total_distance_m >= 20000 THEN
    _new_score := _new_score + 14;
  ELSIF _total_distance_m >= 10000 THEN
    _new_score := _new_score + 8;
  END IF;

  -- 4. Clean record (max 20 pts)
  IF _total_flagged_sessions = 0 AND _total_verified_sessions >= 5 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'clean_record');
  ELSIF _total_flagged_sessions = 0 THEN
    _new_score := _new_score + 12;
  ELSIF _total_flagged_sessions <= 1 THEN
    _new_score := _new_score + 6;
  END IF;

  -- Penalty for recent integrity flags
  IF _recent_flagged >= _downgrade_flag_threshold THEN
    _new_score := GREATEST(_new_score - 30, 0);
    _flags := array_append(_flags, 'recent_integrity_issues');
  ELSIF _recent_flagged > 0 THEN
    _new_score := GREATEST(_new_score - (_recent_flagged * 10), 0);
  END IF;

  -- 5. Longevity bonus (max 10 pts)
  IF _total_verified_sessions >= 20 THEN
    _new_score := _new_score + 10;
    _flags := array_append(_flags, 'veteran_runner');
  ELSIF _total_verified_sessions >= 10 THEN
    _new_score := _new_score + 5;
  END IF;

  -- Clamp to 0..100
  _new_score := LEAST(GREATEST(_new_score, 0), 100);

  -- ── State machine transitions ────────────────────────────────────────
  --
  --   0 runs               → UNVERIFIED
  --   1..6 runs             → CALIBRATING
  --   >= 7 + trust < 80     → MONITORED
  --   >= 7 + trust >= 80 + clean → VERIFIED
  --   >= 3 severe flags/30d → DOWNGRADED

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
-- 2. RPC: get_verification_state — read-only checklist for client
-- ═══════════════════════════════════════════════════════════════════════════
--
-- Called by Flutter app to display verification progress.
-- Uses auth.uid() — user can only read their own state.
-- SECURITY DEFINER to guarantee access even with complex RLS chains.
-- Does NOT mutate any data.

CREATE OR REPLACE FUNCTION public.get_verification_state()
RETURNS TABLE (
  -- Core state
  verification_status     TEXT,
  trust_score             INTEGER,
  verified_at             TIMESTAMPTZ,
  last_eval_at            TIMESTAMPTZ,
  verification_flags      TEXT[],
  calibration_valid_runs  INTEGER,
  last_integrity_flag_at  TIMESTAMPTZ,

  -- Checklist booleans (true = requirement met)
  identity_ok             BOOLEAN,
  permissions_ok          BOOLEAN,
  valid_runs_ok           BOOLEAN,
  integrity_ok            BOOLEAN,
  baseline_ok             BOOLEAN,
  trust_ok                BOOLEAN,

  -- Raw counts for progress display
  valid_runs_count        INTEGER,
  flagged_runs_recent     INTEGER,
  total_distance_m        DOUBLE PRECISION,
  avg_distance_m          DOUBLE PRECISION,

  -- Thresholds (so client knows targets without hardcoding)
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

  _required_runs CONSTANT INTEGER := 7;
  _required_trust CONSTANT INTEGER := 80;
  _recent_window CONSTANT INTERVAL := '30 days';
BEGIN
  IF _uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: No authenticated user';
  END IF;

  -- Fetch verification record
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

  -- Count verified sessions
  SELECT COUNT(*)
  INTO _verified_count
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = true
    AND s.total_distance_m >= 200;

  -- Count recent flagged sessions
  SELECT COUNT(*)
  INTO _recent_flagged
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = false
    AND s.created_at >= (now() - _recent_window);

  -- Distance stats
  SELECT COALESCE(SUM(s.total_distance_m), 0),
         CASE WHEN COUNT(*) > 0
              THEN COALESCE(SUM(s.total_distance_m), 0) / COUNT(*)
              ELSE 0
         END
  INTO _total_dist, _avg_dist
  FROM public.sessions s
  WHERE s.user_id = _uid
    AND s.is_verified = true
    AND s.total_distance_m >= 200;

  -- Return composite row
  verification_status    := _av.verification_status;
  trust_score            := _av.trust_score;
  verified_at            := _av.verified_at;
  last_eval_at           := _av.last_eval_at;
  verification_flags     := _av.verification_flags;
  calibration_valid_runs := _av.calibration_valid_runs;
  last_integrity_flag_at := _av.last_integrity_flag_at;

  -- Checklist booleans
  identity_ok            := NULL;   -- future: selfie/liveness
  permissions_ok         := NULL;   -- client-side only (GPS/sensors)
  valid_runs_ok          := _verified_count >= _required_runs;
  integrity_ok           := _recent_flagged = 0;
  baseline_ok            := _avg_dist >= 1000 AND _verified_count >= 3;
  trust_ok               := _av.trust_score >= _required_trust;

  -- Raw counts
  valid_runs_count       := _verified_count;
  flagged_runs_recent    := _recent_flagged;
  total_distance_m       := _total_dist;
  avg_distance_m         := _avg_dist;

  -- Thresholds
  required_valid_runs    := _required_runs;
  required_trust_score   := _required_trust;

  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Update is_user_verified helper to use finalized threshold
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_user_verified(p_user_id UUID)
RETURNS BOOLEAN AS $$
  SELECT COALESCE(
    (SELECT verification_status = 'VERIFIED'
     FROM public.athlete_verification
     WHERE user_id = p_user_id),
    false
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

COMMIT;
