-- ============================================================================
-- Omni Runner — Profile-aware anti-cheat thresholds (L21-01 + L21-02)
-- Date: 2026-04-21
-- Wave: 1 — supply chain (Lens 21 — Atleta Pro)
-- ============================================================================
--
-- Closes two criticals in Lens 21 (Atleta Pro) that share the same root
-- cause: hard-coded anti-cheat thresholds in
-- `supabase/functions/_shared/anti_cheat.ts` invalidated legitimate elite
-- sessions:
--
--   L21-01 — MAX_SPEED_MS = 12.5 m/s flagged Usain-Bolt-class sprinters
--            (peak 12.27 m/s, threshold 12.5, with SPEED_VIOLATION_THRESHOLD
--            = 0.1 marking the entire session SPEED_IMPOSSIBLE).
--
--   L21-02 — MAX_HR_BPM = 220 ignored measured-max-HR data; young athletes
--            in VO2max often hit 210-225 BPM on chest-strap data
--            (Robergs & Landwehr 2002, Tanaka 2001).
--
-- The fix turns thresholds into a function of (skill_bracket, age,
-- measured_max_hr). The bracket is already computed by
-- `fn_compute_skill_bracket(user_id)` introduced in
-- `20260224100000_challenge_queue.sql` (returns
-- 'beginner' | 'intermediate' | 'advanced' | 'elite' from average pace
-- of last 10 verified sessions). We add three columns to `profiles`:
--
--   • `birth_date`             — DATE, optional. If NULL the age-aware
--                                HR floor is skipped.
--   • `measured_max_hr_bpm`    — SMALLINT, optional, range [120,250].
--                                Highest value recorded by chest-strap
--                                in last 6 months.
--   • `measured_max_hr_at`     — TIMESTAMPTZ, optional. When the
--                                measurement was captured (used to
--                                expire stale data after 6 months).
--   • `skill_bracket_override` — TEXT, optional. Manual escape hatch
--                                for athletes whose pace history is
--                                not yet representative (e.g. an elite
--                                athlete who just signed up — the
--                                computed bracket would be 'beginner'
--                                until they log 10 sessions).
--
-- Plus a single canonical RPC `fn_get_anti_cheat_thresholds(user_id)`
-- that resolves the effective thresholds. The Edge Function callers
-- (`verify-session`, `strava-webhook`) call this RPC once per request
-- and pass the result to `runAntiCheatPipeline()` from
-- `_shared/anti_cheat.ts`.
--
-- Backwards compat:
--   • All new columns NULL-able with safe defaults.
--   • `fn_get_anti_cheat_thresholds()` always returns a row, never
--     errors, so legacy sessions still work.
--   • The TS pipeline keeps `DEFAULT_ANTI_CHEAT_THRESHOLDS` mirroring
--     the pre-fix constants — calling `runAntiCheatPipeline(input)`
--     without a thresholds arg behaves exactly like before.
--
-- ============================================================================

BEGIN;

-- ── 1. profiles columns ─────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS birth_date              DATE,
  ADD COLUMN IF NOT EXISTS measured_max_hr_bpm     SMALLINT,
  ADD COLUMN IF NOT EXISTS measured_max_hr_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS skill_bracket_override  TEXT;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_measured_max_hr_bpm;
ALTER TABLE public.profiles
  ADD CONSTRAINT chk_measured_max_hr_bpm
    CHECK (measured_max_hr_bpm IS NULL
           OR measured_max_hr_bpm BETWEEN 120 AND 250);

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_skill_bracket_override;
ALTER TABLE public.profiles
  ADD CONSTRAINT chk_skill_bracket_override
    CHECK (skill_bracket_override IS NULL
           OR skill_bracket_override IN
              ('beginner','intermediate','advanced','elite'));

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS chk_measured_max_hr_at_consistency;
ALTER TABLE public.profiles
  ADD CONSTRAINT chk_measured_max_hr_at_consistency
    CHECK ((measured_max_hr_bpm IS NULL) = (measured_max_hr_at IS NULL));

COMMENT ON COLUMN public.profiles.birth_date IS
  'L21-02: optional DOB used to derive age for the Tanaka 2001 max-HR floor (220 - age + 5). NULL skips the floor.';
COMMENT ON COLUMN public.profiles.measured_max_hr_bpm IS
  'L21-02: highest chest-strap HR in last 6 months. Lifts the IMPLAUSIBLE_HR_HIGH ceiling.';
COMMENT ON COLUMN public.profiles.measured_max_hr_at IS
  'L21-02: when measured_max_hr_bpm was captured. Values older than 6 months are ignored by fn_get_anti_cheat_thresholds.';
COMMENT ON COLUMN public.profiles.skill_bracket_override IS
  'L21-01: manual override of fn_compute_skill_bracket. Set by platform admin during onboarding for elites without session history yet.';

-- ── 2. fn_get_anti_cheat_thresholds ─────────────────────────────────────────
--
-- Returns ONE row per call. `source` documents the derivation in plain
-- text for forensics (Sentry tag `anti_cheat.threshold_source`).
--
-- Threshold ladder (per skill bracket, mirrored 1:1 in
-- `_shared/anti_cheat.ts` getThresholdsForBracket):
--
--   bracket       | max_speed | teleport | min_hr | max_hr (default)
--   beginner      | 12.5  m/s | 50 m/s   | 80     | 220
--   intermediate  | 12.5  m/s | 50 m/s   | 75     | 220
--   advanced      | 13.5  m/s | 55 m/s   | 70     | 225
--   elite         | 15.0  m/s | 60 m/s   | 60     | 230
--
-- Then max_hr is widened (never narrowed) by:
--   • measured_max_hr_bpm (+5 BPM headroom) IF measurement < 6 months old
--   • Tanaka floor (220 - age + 5) IF birth_date set
--
-- And finally clamped to [185, 250] to defeat absurd inputs.
--
-- ============================================================================

CREATE OR REPLACE FUNCTION public.fn_get_anti_cheat_thresholds(
  p_user_id UUID
)
RETURNS TABLE (
  skill_bracket      TEXT,
  max_speed_ms       NUMERIC,
  teleport_speed_ms  NUMERIC,
  min_hr_bpm         INTEGER,
  max_hr_bpm         INTEGER,
  source             TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog
AS $$
DECLARE
  v_override          TEXT;
  v_computed          TEXT;
  v_effective_bracket TEXT;
  v_birth_date        DATE;
  v_measured_hr       SMALLINT;
  v_measured_at       TIMESTAMPTZ;
  v_max_speed         NUMERIC;
  v_teleport_speed    NUMERIC;
  v_min_hr            INTEGER;
  v_max_hr            INTEGER;
  v_age_years         INTEGER;
  v_tanaka_floor      INTEGER;
  v_measured_floor    INTEGER;
  v_source_parts      TEXT[] := ARRAY[]::TEXT[];
BEGIN
  -- Read profile. Use FOR-loop pattern so missing rows return defaults.
  SELECT skill_bracket_override, birth_date,
         measured_max_hr_bpm, measured_max_hr_at
    INTO v_override, v_birth_date, v_measured_hr, v_measured_at
  FROM   public.profiles
  WHERE  id = p_user_id;

  -- Resolve bracket: override > computed > 'beginner' default.
  IF v_override IS NOT NULL THEN
    v_effective_bracket := v_override;
    v_source_parts := array_append(v_source_parts, 'override');
  ELSE
    BEGIN
      v_computed := public.fn_compute_skill_bracket(p_user_id);
    EXCEPTION WHEN OTHERS THEN
      v_computed := NULL;
    END;
    v_effective_bracket := COALESCE(v_computed, 'beginner');
    v_source_parts := array_append(v_source_parts,
      CASE WHEN v_computed IS NULL THEN 'default'
           ELSE 'computed' END);
  END IF;

  -- Base ladder
  CASE v_effective_bracket
    WHEN 'elite' THEN
      v_max_speed      := 15.0;
      v_teleport_speed := 60.0;
      v_min_hr         := 60;
      v_max_hr         := 230;
    WHEN 'advanced' THEN
      v_max_speed      := 13.5;
      v_teleport_speed := 55.0;
      v_min_hr         := 70;
      v_max_hr         := 225;
    WHEN 'intermediate' THEN
      v_max_speed      := 12.5;
      v_teleport_speed := 50.0;
      v_min_hr         := 75;
      v_max_hr         := 220;
    ELSE -- beginner OR unknown bracket value
      v_max_speed      := 12.5;
      v_teleport_speed := 50.0;
      v_min_hr         := 80;
      v_max_hr         := 220;
  END CASE;

  -- Tanaka 2001 floor: GREATEST(base_max_hr, 220 - age + 5).
  IF v_birth_date IS NOT NULL THEN
    v_age_years := EXTRACT(YEAR FROM age(current_date, v_birth_date))::INTEGER;
    IF v_age_years BETWEEN 10 AND 90 THEN
      v_tanaka_floor := 225 - v_age_years;
      IF v_tanaka_floor > v_max_hr THEN
        v_max_hr := v_tanaka_floor;
        v_source_parts := array_append(v_source_parts,
          'tanaka_floor=' || v_tanaka_floor::TEXT);
      END IF;
    END IF;
  END IF;

  -- Measured HR floor: GREATEST(current, measured + 5) IF measurement
  -- is at most 6 months old.
  IF v_measured_hr IS NOT NULL
     AND v_measured_at IS NOT NULL
     AND v_measured_at >= now() - interval '6 months'
  THEN
    v_measured_floor := v_measured_hr + 5;
    IF v_measured_floor > v_max_hr THEN
      v_max_hr := v_measured_floor;
      v_source_parts := array_append(v_source_parts,
        'measured_max_hr=' || v_measured_hr::TEXT);
    END IF;
  END IF;

  -- Final clamp [185, 250] to defeat absurd inputs.
  IF v_max_hr > 250 THEN v_max_hr := 250; END IF;
  IF v_max_hr < 185 THEN v_max_hr := 185; END IF;

  RETURN QUERY SELECT
    v_effective_bracket,
    v_max_speed,
    v_teleport_speed,
    v_min_hr,
    v_max_hr,
    array_to_string(v_source_parts, ',');
END;
$$;

COMMENT ON FUNCTION public.fn_get_anti_cheat_thresholds(UUID) IS
  'L21-01 + L21-02: derive profile-aware anti-cheat thresholds for a user. Mirrored 1:1 in supabase/functions/_shared/anti_cheat.ts getThresholdsForBracket(). Always returns one row.';

-- Allow service_role + authenticated to read (Edge Functions use
-- service_role; authenticated users may want to preview their own
-- thresholds via a future endpoint).
REVOKE ALL ON FUNCTION public.fn_get_anti_cheat_thresholds(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_get_anti_cheat_thresholds(UUID)
       TO service_role, authenticated;

-- ── 3. Self-check: assert threshold ladder for known brackets ───────────────
-- Catch silent regressions during migration apply.

DO $$
DECLARE
  v_row RECORD;
  v_test_user UUID := '00000000-0000-0000-0000-000000000000';
BEGIN
  -- Beginner default (no profile row → falls back to defaults)
  SELECT * INTO v_row FROM public.fn_get_anti_cheat_thresholds(v_test_user);
  IF v_row.max_speed_ms <> 12.5 OR v_row.max_hr_bpm <> 220 THEN
    RAISE EXCEPTION
      '[L21-01/02.self_check] beginner defaults regressed: max_speed=%, max_hr=%',
      v_row.max_speed_ms, v_row.max_hr_bpm;
  END IF;

  RAISE NOTICE '[L21-01/02] fn_get_anti_cheat_thresholds self-check passed for default user';
END;
$$;

COMMIT;
