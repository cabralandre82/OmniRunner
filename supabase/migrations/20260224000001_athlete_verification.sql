-- ============================================================================
-- Omni Runner — Athlete Verification State Machine
-- Date: 2026-02-24
-- Sprint: VERIFIED-1
-- Origin: SPRINT 1 — "Atleta Verificado" & Monetization Gate
-- ============================================================================
--
-- Creates dedicated table for athlete verification state.
--
-- WHY A NEW TABLE (not profile_progress):
--   profile_progress has RLS "progress_public_read USING (true)" — anyone
--   can read anyone's progression. Verification data (trust_score, flags)
--   must be readable ONLY by the owning user. Changing profile_progress
--   RLS would break leaderboards. Separate bounded context per ARCHITECTURE §12.
--
-- STATE MACHINE:
--   UNVERIFIED → CALIBRATING → MONITORED → VERIFIED
--                                            ↓
--                                        DOWNGRADED
--
--   UNVERIFIED  : New user, no verified runs yet
--   CALIBRATING : Has started running; accumulating valid sessions
--   MONITORED   : Met calibration threshold; under observation window
--   VERIFIED    : Proven trustworthy — may create/join stake>0 challenges
--   DOWNGRADED  : Was VERIFIED but integrity violations detected; must re-earn
--
-- RULES (CONGELADAS):
--   • stake=0 always allowed for any user
--   • stake>0 requires verification_status = 'VERIFIED'
--   • NO admin override, NO manual set, NO backdoor — ZERO "force VERIFIED"
--   • Status transitions ONLY via SECURITY DEFINER RPC (server-side logic)
--   • App shows UX hints; server decides eligibility
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLE: athlete_verification
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.athlete_verification (
  -- PK = user_id, 1:1 with auth.users
  user_id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Current state in the verification state machine
  verification_status   TEXT NOT NULL DEFAULT 'UNVERIFIED'
    CHECK (verification_status IN (
      'UNVERIFIED', 'CALIBRATING', 'MONITORED', 'VERIFIED', 'DOWNGRADED'
    )),

  -- Composite trust score (0..100). Computed server-side from:
  --   session count, integrity flags, consistency, distance patterns.
  -- Higher = more trustworthy. Threshold for VERIFIED defined in EF logic.
  trust_score           INTEGER NOT NULL DEFAULT 0
    CHECK (trust_score >= 0 AND trust_score <= 100),

  -- When the user was promoted to VERIFIED (NULL if never)
  verified_at           TIMESTAMPTZ,

  -- Last time the evaluation RPC ran for this user
  last_eval_at          TIMESTAMPTZ,

  -- Accumulated integrity signals from evaluation runs.
  -- Examples: 'speed_anomaly', 'teleport_detected', 'vehicle_suspected',
  --           'consistent_runner', 'hr_correlated', 'multi_device'
  verification_flags    TEXT[] NOT NULL DEFAULT '{}',

  -- Number of valid (is_verified=true, no critical integrity_flags) sessions
  -- completed during CALIBRATING phase. Resets on DOWNGRADED.
  calibration_valid_runs INTEGER NOT NULL DEFAULT 0
    CHECK (calibration_valid_runs >= 0),

  -- Last time a negative integrity flag was recorded (speed/teleport/vehicle)
  last_integrity_flag_at TIMESTAMPTZ,

  -- Audit timestamps
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for EF/RPC lookups by status (e.g., batch evaluation of CALIBRATING users)
CREATE INDEX IF NOT EXISTS idx_athlete_verification_status
  ON public.athlete_verification(verification_status);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.athlete_verification ENABLE ROW LEVEL SECURITY;

-- Users can only read their OWN verification record
CREATE POLICY "verification_own_read"
  ON public.athlete_verification
  FOR SELECT
  USING (auth.uid() = user_id);

-- NO INSERT/UPDATE/DELETE policies for authenticated users.
-- All mutations happen via SECURITY DEFINER RPCs (server-side only).
-- This means: a user calling supabase.from('athlete_verification').update(...)
-- will be rejected by RLS — there is no UPDATE policy.

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. SECURITY DEFINER RPC: eval_athlete_verification
-- ═══════════════════════════════════════════════════════════════════════════
-- Evaluates a user's verification status based on their session history.
-- Called by Edge Functions (service_role) or pg_cron, NEVER directly by client.
--
-- This is the ONLY path to change verification_status or trust_score.
-- There is NO override, NO manual set, NO admin backdoor.

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
  _calibration_min_runs     CONSTANT INTEGER := 5;
  _monitored_min_runs       CONSTANT INTEGER := 10;
  _verified_min_runs        CONSTANT INTEGER := 15;
  _verified_min_score       CONSTANT INTEGER := 70;
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

  -- Count verified sessions (is_verified=true, status=completed or similar)
  SELECT COUNT(*)
  INTO _total_verified_sessions
  FROM public.sessions s
  WHERE s.user_id = p_user_id
    AND s.is_verified = true
    AND s.total_distance_m >= 200;

  -- Count sessions with critical integrity flags
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

  -- Total and average distance
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
  _new_score := 0;
  _flags := '{}';

  -- Session volume component (max 30 pts)
  _new_score := _new_score + LEAST(_total_verified_sessions * 2, 30);

  -- Distance consistency component (max 20 pts)
  IF _avg_distance_m >= 1000 AND _total_verified_sessions >= 3 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'consistent_distance');
  ELSIF _avg_distance_m >= 500 THEN
    _new_score := _new_score + 10;
  END IF;

  -- Total distance component (max 20 pts)
  IF _total_distance_m >= 50000 THEN      -- 50km+
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'high_volume_runner');
  ELSIF _total_distance_m >= 20000 THEN   -- 20km+
    _new_score := _new_score + 15;
  ELSIF _total_distance_m >= 5000 THEN    -- 5km+
    _new_score := _new_score + 10;
  END IF;

  -- Clean record bonus (max 20 pts)
  IF _total_flagged_sessions = 0 AND _total_verified_sessions >= 5 THEN
    _new_score := _new_score + 20;
    _flags := array_append(_flags, 'clean_record');
  ELSIF _total_flagged_sessions <= 1 THEN
    _new_score := _new_score + 10;
  END IF;

  -- Penalty for recent integrity flags
  IF _recent_flagged >= _downgrade_flag_threshold THEN
    _new_score := GREATEST(_new_score - 30, 0);
    _flags := array_append(_flags, 'recent_integrity_issues');
  ELSIF _recent_flagged > 0 THEN
    _new_score := GREATEST(_new_score - (_recent_flagged * 10), 0);
  END IF;

  -- Longevity bonus (max 10 pts)
  IF _total_verified_sessions >= 30 THEN
    _new_score := _new_score + 10;
    _flags := array_append(_flags, 'veteran_runner');
  ELSIF _total_verified_sessions >= 15 THEN
    _new_score := _new_score + 5;
  END IF;

  -- Clamp to 0..100
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
    ELSIF _total_verified_sessions >= _monitored_min_runs THEN
      _new_status := 'MONITORED';
    END IF;

  ELSIF _current_status = 'MONITORED' THEN
    IF _recent_flagged >= _downgrade_flag_threshold THEN
      _new_status := 'CALIBRATING';
      _valid_runs := GREATEST(_total_verified_sessions - _recent_flagged, 0);
    ELSIF _total_verified_sessions >= _verified_min_runs
      AND _new_score >= _verified_min_score THEN
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

  -- Return computed values
  new_status       := _new_status;
  new_trust_score  := _new_score;
  calibration_runs := _valid_runs;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. HELPER RPC: get_verification_gate
-- ═══════════════════════════════════════════════════════════════════════════
-- Lightweight check used by Edge Functions (challenge-create, challenge-join)
-- to enforce the monetization gate. Returns true only if VERIFIED.

CREATE OR REPLACE FUNCTION public.is_user_verified(p_user_id UUID)
RETURNS BOOLEAN AS $$
  SELECT COALESCE(
    (SELECT verification_status = 'VERIFIED'
     FROM public.athlete_verification
     WHERE user_id = p_user_id),
    false
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. UPDATE TRIGGER: auto-create athlete_verification on user signup
-- ═══════════════════════════════════════════════════════════════════════════
-- Extends the existing handle_new_user_gamification() trigger to also
-- create the athlete_verification row (UNVERIFIED, trust_score=0).

CREATE OR REPLACE FUNCTION public.handle_new_user_gamification()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.profile_progress (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  INSERT INTO public.athlete_verification (user_id) VALUES (NEW.id) ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger already exists (on_auth_user_gamification), no need to recreate.
-- The CREATE OR REPLACE above updates the function body in place.

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. BACKFILL: create rows for all existing users who don't have one
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.athlete_verification (user_id)
SELECT id FROM auth.users
WHERE id NOT IN (SELECT user_id FROM public.athlete_verification)
ON CONFLICT DO NOTHING;

COMMIT;
