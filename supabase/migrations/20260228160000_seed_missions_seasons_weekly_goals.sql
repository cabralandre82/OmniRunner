-- ============================================================================
-- Seed missions, seasons, and auto-generate weekly goals
-- Date: 2026-02-28
-- ============================================================================

BEGIN;

-- ── Season seed ─────────────────────────────────────────────────────────────
INSERT INTO public.seasons (id, name, status, starts_at_ms, ends_at_ms)
VALUES (
  'a1b2c3d4-0001-4000-8000-000000000001',
  'Temporada de Verão 2026',
  'active',
  1735689600000,
  1743465600000
) ON CONFLICT (id) DO NOTHING;

-- ── Mission Definitions (20 missions) ───────────────────────────────────────
-- Daily missions (easy, slot=daily)
INSERT INTO public.missions (id, title, description, difficulty, slot, xp_reward, coins_reward, criteria_type, criteria_json, max_completions) VALUES
-- Daily easy
(gen_random_uuid(), 'Corrida do Dia', 'Complete 1 corrida verificada hoje', 'easy', 'daily', 30, 5, 'complete_sessions', '{"target_count": 1}', 999),
(gen_random_uuid(), '3 km Hoje', 'Corra pelo menos 3 km hoje', 'easy', 'daily', 40, 5, 'accumulate_distance', '{"target_m": 3000}', 999),
(gen_random_uuid(), '5 km Hoje', 'Corra pelo menos 5 km hoje', 'easy', 'daily', 50, 10, 'accumulate_distance', '{"target_m": 5000}', 999),
(gen_random_uuid(), '30 min Correndo', 'Corra por pelo menos 30 minutos', 'easy', 'daily', 40, 5, 'single_session_duration', '{"target_ms": 1800000}', 999),
-- Weekly medium
(gen_random_uuid(), '3 Corridas na Semana', 'Complete 3 corridas verificadas esta semana', 'medium', 'weekly', 80, 15, 'complete_sessions', '{"target_count": 3}', 999),
(gen_random_uuid(), '15 km Semanais', 'Acumule 15 km de corrida esta semana', 'medium', 'weekly', 100, 20, 'accumulate_distance', '{"target_m": 15000}', 999),
(gen_random_uuid(), '25 km Semanais', 'Acumule 25 km de corrida esta semana', 'medium', 'weekly', 120, 25, 'accumulate_distance', '{"target_m": 25000}', 999),
(gen_random_uuid(), '5 Corridas na Semana', 'Complete 5 corridas verificadas esta semana', 'medium', 'weekly', 100, 20, 'complete_sessions', '{"target_count": 5}', 999),
(gen_random_uuid(), 'Manter Sequência de 3 Dias', 'Corra 3 dias consecutivos', 'medium', 'weekly', 80, 15, 'maintain_streak', '{"days": 3}', 999),
(gen_random_uuid(), 'Abaixo de 6:00/km', 'Complete uma sessão com pace médio < 6:00/km em ≥ 5 km', 'medium', 'weekly', 100, 15, 'achieve_pace', '{"max_pace_sec_per_km": 360, "min_distance_m": 5000}', 999),
(gen_random_uuid(), '1 Hora de Corrida', 'Complete uma sessão de pelo menos 1 hora', 'medium', 'weekly', 80, 15, 'single_session_duration', '{"target_ms": 3600000}', 999),
-- Season hard
(gen_random_uuid(), '100 km na Temporada', 'Acumule 100 km durante a temporada', 'hard', 'season', 200, 50, 'accumulate_distance', '{"target_m": 100000}', 1),
(gen_random_uuid(), '250 km na Temporada', 'Acumule 250 km durante a temporada', 'hard', 'season', 300, 75, 'accumulate_distance', '{"target_m": 250000}', 1),
(gen_random_uuid(), '30 Corridas na Temporada', 'Complete 30 corridas verificadas na temporada', 'hard', 'season', 250, 60, 'complete_sessions', '{"target_count": 30}', 1),
(gen_random_uuid(), 'Sequência de 7 Dias', 'Corra 7 dias consecutivos', 'hard', 'season', 200, 50, 'maintain_streak', '{"days": 7}', 1),
(gen_random_uuid(), 'Sequência de 14 Dias', 'Corra 14 dias consecutivos', 'hard', 'season', 350, 80, 'maintain_streak', '{"days": 14}', 1),
(gen_random_uuid(), 'Abaixo de 5:00/km', 'Complete uma sessão com pace médio < 5:00/km em ≥ 5 km', 'hard', 'season', 250, 50, 'achieve_pace', '{"max_pace_sec_per_km": 300, "min_distance_m": 5000}', 1),
(gen_random_uuid(), '3 Desafios Completados', 'Complete 3 desafios durante a temporada', 'hard', 'season', 200, 50, 'complete_challenges', '{"count": 3}', 1),
(gen_random_uuid(), '500 km na Temporada', 'Acumule 500 km durante a temporada', 'hard', 'season', 400, 100, 'accumulate_distance', '{"target_m": 500000}', 1),
(gen_random_uuid(), '10 Corridas Longas', 'Complete 10 sessões de pelo menos 10 km', 'hard', 'season', 300, 60, 'accumulate_distance', '{"target_m": 100000}', 1)
ON CONFLICT DO NOTHING;

-- ── Auto-generate weekly goals RPC ──────────────────────────────────────────
-- Creates a weekly distance goal based on the user's recent activity.
-- If the user ran last week, the target is 110% of that distance.
-- If not, the target is a minimum of 10 km.

CREATE OR REPLACE FUNCTION public.generate_weekly_goal(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  _week_start  DATE;
  _prev_start  BIGINT;
  _prev_end    BIGINT;
  _prev_dist   DOUBLE PRECISION;
  _target      DOUBLE PRECISION;
  _existing    UUID;
BEGIN
  _week_start := date_trunc('week', now())::DATE;

  -- Check if goal already exists for this week
  SELECT id INTO _existing
  FROM public.weekly_goals
  WHERE user_id = p_user_id AND week_start = _week_start;

  IF _existing IS NOT NULL THEN
    RETURN;
  END IF;

  -- Calculate previous week's distance
  _prev_start := EXTRACT(EPOCH FROM (_week_start - INTERVAL '7 days'))::BIGINT * 1000;
  _prev_end   := EXTRACT(EPOCH FROM _week_start)::BIGINT * 1000;

  SELECT COALESCE(SUM(total_distance_m), 0) INTO _prev_dist
  FROM public.sessions
  WHERE user_id = p_user_id
    AND is_verified = TRUE
    AND status = 3
    AND total_distance_m >= 1000
    AND start_time_ms >= _prev_start
    AND start_time_ms < _prev_end;

  -- Target: 110% of last week, minimum 10 km
  _target := GREATEST(_prev_dist * 1.1, 10000);
  -- Round to nearest km
  _target := ROUND(_target / 1000) * 1000;

  INSERT INTO public.weekly_goals (user_id, week_start, metric, target_value, current_value, status)
  VALUES (p_user_id, _week_start, 'distance', _target, 0, 'active');

  -- Update current_value with this week's actual progress
  UPDATE public.weekly_goals
  SET current_value = (
    SELECT COALESCE(SUM(total_distance_m), 0)
    FROM public.sessions
    WHERE user_id = p_user_id
      AND is_verified = TRUE
      AND status = 3
      AND total_distance_m >= 1000
      AND start_time_ms >= EXTRACT(EPOCH FROM _week_start)::BIGINT * 1000
  )
  WHERE user_id = p_user_id AND week_start = _week_start;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_weekly_goal(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_weekly_goal(UUID) TO service_role;

COMMIT;
