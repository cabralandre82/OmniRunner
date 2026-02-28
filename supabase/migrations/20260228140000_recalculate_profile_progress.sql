-- ============================================================================
-- recalculate_profile_progress — Recompute profile_progress from sessions
-- Date: 2026-02-28
-- ============================================================================
-- Strava-imported sessions (webhook + backfill) never go through the
-- calculate-progression Edge Function, so profile_progress stays at zero.
-- This RPC:
--   1. Awards XP for verified sessions that never got progression_applied
--   2. Recalculates all profile_progress counters from sessions + xp_transactions
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.recalculate_profile_progress(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  _session   RECORD;
  _base_xp   INTEGER;
  _dist_bonus INTEGER;
  _dur_bonus  INTEGER;
  _session_xp INTEGER;
  _total_xp   INTEGER;
  _new_level  INTEGER;
  _lifetime_count  INTEGER;
  _lifetime_dist   DOUBLE PRECISION;
  _lifetime_moving BIGINT;
  _weekly_count    INTEGER;
  _monthly_count   INTEGER;
  _week_start_ms   BIGINT;
  _month_start_ms  BIGINT;
BEGIN
  -- Award XP for verified sessions >= 1km that never went through progression
  FOR _session IN
    SELECT id, total_distance_m, moving_ms, avg_bpm
    FROM public.sessions
    WHERE user_id = p_user_id
      AND is_verified = TRUE
      AND total_distance_m >= 1000
      AND progression_applied = FALSE
      AND status = 3
  LOOP
    _base_xp := 20;
    _dist_bonus := LEAST(FLOOR(_session.total_distance_m / 1000.0 * 10)::INTEGER, 500);
    _dur_bonus  := LEAST(FLOOR(COALESCE(_session.moving_ms, 0) / 1000.0 / 60.0 / 5.0)::INTEGER * 2, 120);
    _session_xp := _base_xp + _dist_bonus + _dur_bonus;
    IF _session.avg_bpm IS NOT NULL THEN
      _session_xp := _session_xp + 10;
    END IF;

    INSERT INTO public.xp_transactions (user_id, xp, source, ref_id, created_at_ms)
    VALUES (p_user_id, _session_xp, 'session', _session.id, EXTRACT(EPOCH FROM now())::BIGINT * 1000)
    ON CONFLICT DO NOTHING;

    UPDATE public.sessions
    SET progression_applied = TRUE
    WHERE id = _session.id;
  END LOOP;

  -- Compute total XP from all xp_transactions
  SELECT COALESCE(SUM(xp), 0)::INTEGER INTO _total_xp
  FROM public.xp_transactions
  WHERE user_id = p_user_id;

  -- Compute lifetime stats from verified sessions >= 1km
  SELECT
    COUNT(*)::INTEGER,
    COALESCE(SUM(total_distance_m), 0),
    COALESCE(SUM(moving_ms), 0)::BIGINT
  INTO _lifetime_count, _lifetime_dist, _lifetime_moving
  FROM public.sessions
  WHERE user_id = p_user_id
    AND is_verified = TRUE
    AND total_distance_m >= 1000
    AND status = 3;

  -- Weekly count (current ISO week)
  _week_start_ms := EXTRACT(EPOCH FROM date_trunc('week', now()))::BIGINT * 1000;
  SELECT COUNT(*)::INTEGER INTO _weekly_count
  FROM public.sessions
  WHERE user_id = p_user_id
    AND is_verified = TRUE
    AND total_distance_m >= 1000
    AND status = 3
    AND start_time_ms >= _week_start_ms;

  -- Monthly count (current calendar month)
  _month_start_ms := EXTRACT(EPOCH FROM date_trunc('month', now()))::BIGINT * 1000;
  SELECT COUNT(*)::INTEGER INTO _monthly_count
  FROM public.sessions
  WHERE user_id = p_user_id
    AND is_verified = TRUE
    AND total_distance_m >= 1000
    AND status = 3
    AND start_time_ms >= _month_start_ms;

  -- Recompute level: floor((xp / 100)^(2/3))
  _new_level := GREATEST(0, FLOOR(POWER(_total_xp::DOUBLE PRECISION / 100.0, 2.0 / 3.0))::INTEGER);

  -- Upsert profile_progress
  INSERT INTO public.profile_progress (
    user_id, total_xp, level, lifetime_session_count,
    lifetime_distance_m, lifetime_moving_ms,
    weekly_session_count, monthly_session_count
  ) VALUES (
    p_user_id, _total_xp, _new_level, _lifetime_count,
    _lifetime_dist, _lifetime_moving,
    _weekly_count, _monthly_count
  )
  ON CONFLICT (user_id) DO UPDATE SET
    total_xp              = EXCLUDED.total_xp,
    level                 = EXCLUDED.level,
    lifetime_session_count = EXCLUDED.lifetime_session_count,
    lifetime_distance_m   = EXCLUDED.lifetime_distance_m,
    lifetime_moving_ms    = EXCLUDED.lifetime_moving_ms,
    weekly_session_count  = EXCLUDED.weekly_session_count,
    monthly_session_count = EXCLUDED.monthly_session_count,
    updated_at            = now();
END;
$$;

GRANT EXECUTE ON FUNCTION public.recalculate_profile_progress(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recalculate_profile_progress(UUID) TO service_role;

COMMIT;
