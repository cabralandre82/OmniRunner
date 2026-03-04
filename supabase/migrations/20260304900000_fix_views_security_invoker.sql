-- ============================================================================
-- Fix SECURITY DEFINER views → SECURITY INVOKER
-- Date: 2026-03-03
-- Issue: Supabase lint warns that v_user_progression and v_weekly_progress
--        run with creator privileges, bypassing RLS for the querying user.
-- Fix: Recreate both views with security_invoker = on so RLS of the
--      underlying tables (profiles, profile_progress, sessions) is enforced
--      per-user at query time.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW public.v_user_progression
WITH (security_invoker = on)
AS
SELECT
  p.id                                                AS user_id,
  p.display_name,
  p.avatar_url,
  pp.total_xp,
  pp.level,
  GREATEST(0,
    FLOOR(100.0 * POWER((pp.level + 1)::DOUBLE PRECISION, 1.5))::INTEGER - pp.total_xp
  )                                                   AS xp_to_next_level,
  pp.season_xp,
  pp.daily_streak_count                               AS streak_current,
  pp.streak_best,
  pp.has_freeze_available,
  pp.weekly_session_count,
  pp.monthly_session_count,
  pp.lifetime_session_count,
  pp.lifetime_distance_m,
  pp.lifetime_moving_ms,
  pp.updated_at
FROM public.profiles p
LEFT JOIN public.profile_progress pp ON pp.user_id = p.id;

CREATE OR REPLACE VIEW public.v_weekly_progress
WITH (security_invoker = on)
AS
SELECT
  s.user_id,
  DATE_TRUNC('week', TO_TIMESTAMP(s.start_time_ms / 1000.0) AT TIME ZONE 'UTC')::DATE
                                                      AS week_start,
  COUNT(*)::INTEGER                                   AS session_count,
  COALESCE(SUM(s.total_distance_m), 0)                AS total_distance_m,
  COALESCE(SUM(s.moving_ms), 0)                       AS total_moving_ms,
  ROUND(COALESCE(SUM(s.moving_ms), 0) / 1000.0 / 60.0, 1)
                                                      AS total_moving_min,
  MIN(s.start_time_ms)                                AS first_session_ms,
  MAX(s.start_time_ms)                                AS last_session_ms
FROM public.sessions s
WHERE s.is_verified = true
  AND s.total_distance_m >= 200
GROUP BY s.user_id, DATE_TRUNC('week', TO_TIMESTAMP(s.start_time_ms / 1000.0) AT TIME ZONE 'UTC')::DATE;

COMMIT;
