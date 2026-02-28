-- ============================================================================
-- Client-safe wrapper for eval_athlete_verification
-- Date: 2026-02-26
-- DECISÃO 116
-- ============================================================================
-- The parameterized eval_athlete_verification(UUID) fails when called from
-- the client via PostgREST due to permission/parameter issues. This creates
-- a parameterless wrapper that uses auth.uid() — safer and simpler for client.
-- Also adds explicit GRANT EXECUTE for all verification RPCs.

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Client wrapper: eval_my_verification() — no params, uses auth.uid()
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.eval_my_verification()
RETURNS TABLE (
  new_status            TEXT,
  new_trust_score       INTEGER,
  calibration_runs      INTEGER
) AS $$
BEGIN
  RETURN QUERY
    SELECT * FROM public.eval_athlete_verification(auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. GRANT EXECUTE on all verification functions
-- ═══════════════════════════════════════════════════════════════════════════

GRANT EXECUTE ON FUNCTION public.eval_my_verification()
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.eval_athlete_verification(UUID)
  TO authenticated, service_role;

GRANT EXECUTE ON FUNCTION public.get_verification_state()
  TO authenticated;

GRANT EXECUTE ON FUNCTION public.backfill_strava_sessions(UUID)
  TO authenticated, service_role;

COMMIT;
