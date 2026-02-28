-- ============================================================================
-- evaluate_badges_retroactive — Award badges based on current aggregate stats
-- Date: 2026-02-28
-- ============================================================================
-- The evaluate-badges Edge Function requires a session_id and is only called
-- for in-app sessions. Strava-imported sessions never trigger badge evaluation.
-- This RPC evaluates all badge criteria based on aggregate profile stats
-- and awards any eligible badges that haven't been awarded yet.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.evaluate_badges_retroactive(p_user_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  _badge        RECORD;
  _awarded_ids  TEXT[];
  _count        INTEGER := 0;
  _progress     RECORD;
  _eligible     BOOLEAN;
  _best_pace    DOUBLE PRECISION;
  _weekly_dist  DOUBLE PRECISION;
  _max_dist     DOUBLE PRECISION;
  _max_moving   BIGINT;
  _chall_done   INTEGER;
  _chall_won    INTEGER;
  _champ_done   INTEGER;
  _has_early    BOOLEAN;
  _has_night    BOOLEAN;
BEGIN
  -- Get already awarded badge IDs
  SELECT ARRAY_AGG(badge_id) INTO _awarded_ids
  FROM public.badge_awards
  WHERE user_id = p_user_id;
  _awarded_ids := COALESCE(_awarded_ids, ARRAY[]::TEXT[]);

  -- Get profile progress
  SELECT * INTO _progress
  FROM public.profile_progress
  WHERE user_id = p_user_id;

  IF _progress IS NULL THEN
    RETURN 0;
  END IF;

  -- Compute additional stats
  SELECT COALESCE(MAX(total_distance_m), 0), COALESCE(MAX(moving_ms), 0)
  INTO _max_dist, _max_moving
  FROM public.sessions
  WHERE user_id = p_user_id AND is_verified = TRUE AND status = 3 AND total_distance_m >= 1000;

  SELECT MIN(avg_pace_sec_km) INTO _best_pace
  FROM public.sessions
  WHERE user_id = p_user_id AND is_verified = TRUE AND status = 3
    AND total_distance_m >= 1000 AND avg_pace_sec_km IS NOT NULL AND avg_pace_sec_km > 0;

  -- Weekly distance
  SELECT COALESCE(SUM(total_distance_m), 0) INTO _weekly_dist
  FROM public.sessions
  WHERE user_id = p_user_id AND is_verified = TRUE AND status = 3
    AND start_time_ms >= EXTRACT(EPOCH FROM date_trunc('week', now()))::BIGINT * 1000;

  -- Challenge stats
  SELECT COUNT(*) INTO _chall_done
  FROM public.challenge_results
  WHERE user_id = p_user_id AND outcome IN ('won', 'completed_target', 'participated');

  SELECT COUNT(*) INTO _chall_won
  FROM public.challenge_results
  WHERE user_id = p_user_id AND outcome = 'won';

  SELECT COUNT(*) INTO _champ_done
  FROM public.championship_participants
  WHERE user_id = p_user_id AND status = 'completed';

  -- Time-of-day checks
  SELECT EXISTS(
    SELECT 1 FROM public.sessions
    WHERE user_id = p_user_id AND is_verified = TRUE AND status = 3
      AND EXTRACT(HOUR FROM TO_TIMESTAMP(start_time_ms / 1000.0)) < 6
  ) INTO _has_early;

  SELECT EXISTS(
    SELECT 1 FROM public.sessions
    WHERE user_id = p_user_id AND is_verified = TRUE AND status = 3
      AND EXTRACT(HOUR FROM TO_TIMESTAMP(start_time_ms / 1000.0)) >= 22
  ) INTO _has_night;

  -- Evaluate each badge
  FOR _badge IN
    SELECT * FROM public.badges WHERE NOT (id = ANY(_awarded_ids))
  LOOP
    _eligible := FALSE;

    CASE _badge.criteria_type
      WHEN 'single_session_distance' THEN
        _eligible := _max_dist >= (_badge.criteria_json->>'threshold_m')::DOUBLE PRECISION;

      WHEN 'lifetime_distance' THEN
        _eligible := _progress.lifetime_distance_m >= (_badge.criteria_json->>'threshold_m')::DOUBLE PRECISION;

      WHEN 'session_count' THEN
        _eligible := _progress.lifetime_session_count >= (_badge.criteria_json->>'count')::INTEGER;

      WHEN 'daily_streak' THEN
        _eligible := GREATEST(_progress.daily_streak_count, _progress.streak_best) >= (_badge.criteria_json->>'days')::INTEGER;

      WHEN 'weekly_distance' THEN
        _eligible := _weekly_dist >= (_badge.criteria_json->>'threshold_m')::DOUBLE PRECISION;

      WHEN 'pace_below' THEN
        IF _best_pace IS NOT NULL THEN
          _eligible := _best_pace < (_badge.criteria_json->>'max_pace_sec_per_km')::DOUBLE PRECISION
            AND _max_dist >= COALESCE((_badge.criteria_json->>'min_distance_m')::DOUBLE PRECISION, 5000);
        END IF;

      WHEN 'single_session_duration' THEN
        _eligible := _max_moving >= (_badge.criteria_json->>'threshold_ms')::BIGINT;

      WHEN 'lifetime_duration' THEN
        _eligible := _progress.lifetime_moving_ms >= (_badge.criteria_json->>'threshold_ms')::BIGINT;

      WHEN 'challenges_completed' THEN
        _eligible := _chall_done >= (_badge.criteria_json->>'count')::INTEGER;

      WHEN 'challenge_won' THEN
        _eligible := _chall_won >= (_badge.criteria_json->>'count')::INTEGER;

      WHEN 'championship_completed' THEN
        _eligible := _champ_done >= (_badge.criteria_json->>'count')::INTEGER;

      WHEN 'session_before_hour' THEN
        _eligible := _has_early;

      WHEN 'session_after_hour' THEN
        _eligible := _has_night;

      ELSE
        _eligible := FALSE;
    END CASE;

    IF _eligible THEN
      INSERT INTO public.badge_awards (user_id, badge_id, unlocked_at_ms, xp_awarded, coins_awarded)
      VALUES (
        p_user_id,
        _badge.id,
        EXTRACT(EPOCH FROM now())::BIGINT * 1000,
        _badge.xp_reward,
        _badge.coins_reward
      )
      ON CONFLICT DO NOTHING;

      IF FOUND THEN
        _count := _count + 1;

        -- Award badge XP
        IF _badge.xp_reward > 0 THEN
          INSERT INTO public.xp_transactions (user_id, xp, source, ref_id, created_at_ms)
          VALUES (p_user_id, _badge.xp_reward, 'badge', _badge.id, EXTRACT(EPOCH FROM now())::BIGINT * 1000);

          UPDATE public.profile_progress
          SET total_xp = total_xp + _badge.xp_reward,
              level = GREATEST(0, FLOOR(POWER((total_xp + _badge.xp_reward)::DOUBLE PRECISION / 100.0, 2.0 / 3.0))::INTEGER)
          WHERE user_id = p_user_id;
        END IF;

        -- Award badge coins
        IF _badge.coins_reward > 0 THEN
          INSERT INTO public.coin_ledger (user_id, amount, reason, ref_id)
          VALUES (p_user_id, _badge.coins_reward, 'badge_reward', _badge.id);
        END IF;
      END IF;
    END IF;
  END LOOP;

  RETURN _count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.evaluate_badges_retroactive(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_badges_retroactive(UUID) TO service_role;

COMMIT;
