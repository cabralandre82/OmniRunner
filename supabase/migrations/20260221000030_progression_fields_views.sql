-- ============================================================================
-- Omni Runner — Progression fields + views
-- Date: 2026-02-26
-- Sprint: 20.1.1
-- Origin: DECISAO 044 (Modelo Final de Progressão)
-- ============================================================================
-- A) profile_progress: add level, streak_best, freeze_earned_at_streak
-- B) weekly_goals: new table for auto-generated weekly goals
-- C) v_user_progression: view joining profiles + profile_progress + level
-- D) v_weekly_progress: view aggregating verified sessions per user per week
-- E) Update increment_profile_progress RPC to recompute level
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- A) profile_progress — new columns
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.profile_progress
  ADD COLUMN IF NOT EXISTS level              INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS streak_best        INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS freeze_earned_at_streak INTEGER NOT NULL DEFAULT 0;

ALTER TABLE public.profile_progress
  ADD CONSTRAINT chk_level_gte_zero          CHECK (level >= 0),
  ADD CONSTRAINT chk_streak_best_gte_zero    CHECK (streak_best >= 0),
  ADD CONSTRAINT chk_streak_count_gte_zero   CHECK (daily_streak_count >= 0);

-- Backfill level for existing rows using N^1.5 formula:
--   levelFromXp(totalXp) = floor((totalXp / 100)^(2/3))
UPDATE public.profile_progress
SET level = GREATEST(0, FLOOR(POWER(total_xp::DOUBLE PRECISION / 100.0, 2.0 / 3.0))::INTEGER)
WHERE total_xp > 0 AND level = 0;

-- Backfill streak_best = MAX(daily_streak_count, streak_best)
UPDATE public.profile_progress
SET streak_best = GREATEST(streak_best, daily_streak_count)
WHERE daily_streak_count > streak_best;

-- ═══════════════════════════════════════════════════════════════════════════
-- B) weekly_goals — auto-generated weekly goals per user
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.weekly_goals (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  week_start        DATE NOT NULL,
  metric            TEXT NOT NULL DEFAULT 'distance',
  target_value      DOUBLE PRECISION NOT NULL,
  current_value     DOUBLE PRECISION NOT NULL DEFAULT 0,
  status            TEXT NOT NULL DEFAULT 'active',
  xp_awarded        INTEGER NOT NULL DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at      TIMESTAMPTZ,

  CONSTRAINT chk_wg_metric     CHECK (metric IN ('distance', 'time')),
  CONSTRAINT chk_wg_status     CHECK (status IN ('active', 'completed', 'missed')),
  CONSTRAINT chk_wg_target_pos CHECK (target_value > 0),
  CONSTRAINT chk_wg_current_nn CHECK (current_value >= 0),
  CONSTRAINT chk_wg_xp_nn      CHECK (xp_awarded >= 0),
  CONSTRAINT uq_wg_user_week   UNIQUE (user_id, week_start)
);

CREATE INDEX idx_weekly_goals_user_active
  ON public.weekly_goals(user_id, status)
  WHERE status = 'active';

CREATE INDEX idx_weekly_goals_week
  ON public.weekly_goals(week_start DESC);

ALTER TABLE public.weekly_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wg_own_read" ON public.weekly_goals
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "wg_own_insert" ON public.weekly_goals
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "wg_own_update" ON public.weekly_goals
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Staff can view their athletes' goals
CREATE POLICY "wg_staff_read" ON public.weekly_goals
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND cm.group_id IN (
          SELECT cm2.group_id FROM public.coaching_members cm2
          WHERE cm2.user_id = weekly_goals.user_id
        )
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- C) v_user_progression — read-only view of progression state
-- ═══════════════════════════════════════════════════════════════════════════
-- Combines profiles + profile_progress into a single queryable surface.
-- Level is read from the stored column (kept in sync by RPC).
-- xp_to_next_level is computed on the fly (cheap for single-row reads).

CREATE OR REPLACE VIEW public.v_user_progression AS
SELECT
  p.id                                                AS user_id,
  p.display_name,
  p.avatar_url,
  pp.total_xp,
  pp.level,
  -- XP needed for next level: floor(100 * (level+1)^1.5) - total_xp
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

-- RLS on views: Postgres views inherit the RLS of underlying tables.
-- Since profiles has SELECT USING (true) and profile_progress has
-- SELECT USING (true), this view is readable by any authenticated user.

-- ═══════════════════════════════════════════════════════════════════════════
-- D) v_weekly_progress — aggregated verified sessions per ISO week
-- ═══════════════════════════════════════════════════════════════════════════
-- Aggregates sessions by user and ISO week for goal checking.
-- week_start is the Monday of the ISO week (UTC).

CREATE OR REPLACE VIEW public.v_weekly_progress AS
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

-- ═══════════════════════════════════════════════════════════════════════════
-- E) Update increment_profile_progress to recompute level
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.increment_profile_progress(
  p_user_id       UUID,
  p_xp            INTEGER,
  p_distance_m    DOUBLE PRECISION,
  p_moving_ms     BIGINT
)
RETURNS VOID AS $$
DECLARE
  _new_xp   INTEGER;
  _new_level INTEGER;
BEGIN
  UPDATE public.profile_progress
  SET
    total_xp              = total_xp + p_xp,
    season_xp             = season_xp + p_xp,
    lifetime_session_count = lifetime_session_count + 1,
    lifetime_distance_m   = lifetime_distance_m + p_distance_m,
    lifetime_moving_ms    = lifetime_moving_ms + p_moving_ms,
    updated_at            = now()
  WHERE user_id = p_user_id
  RETURNING total_xp INTO _new_xp;

  IF _new_xp IS NOT NULL THEN
    _new_level := GREATEST(0, FLOOR(POWER(_new_xp::DOUBLE PRECISION / 100.0, 2.0 / 3.0))::INTEGER);
    UPDATE public.profile_progress
    SET level = _new_level
    WHERE user_id = p_user_id AND level <> _new_level;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- F) RPC: fn_update_streak — atomically update streak + best + freeze
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_update_streak(
  p_user_id       UUID,
  p_session_day_ms BIGINT
)
RETURNS TABLE (
  streak_current INTEGER,
  streak_best    INTEGER,
  freeze_used    BOOLEAN
) AS $$
DECLARE
  _current    INTEGER;
  _best       INTEGER;
  _last_ms    BIGINT;
  _has_freeze BOOLEAN;
  _today_ms   BIGINT;
  _yesterday_ms BIGINT;
  _freeze_used BOOLEAN := FALSE;
  _earned_at  INTEGER;
BEGIN
  SELECT pp.daily_streak_count, pp.streak_best, pp.last_streak_day_ms,
         pp.has_freeze_available, pp.freeze_earned_at_streak
  INTO _current, _best, _last_ms, _has_freeze, _earned_at
  FROM public.profile_progress pp
  WHERE pp.user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Normalize to day boundary (ms since epoch, truncated to UTC day)
  _today_ms := (p_session_day_ms / 86400000) * 86400000;

  -- Already counted today
  IF _last_ms IS NOT NULL AND (_last_ms / 86400000) = (_today_ms / 86400000) THEN
    streak_current := _current;
    streak_best    := _best;
    freeze_used    := FALSE;
    RETURN NEXT;
    RETURN;
  END IF;

  _yesterday_ms := _today_ms - 86400000;

  IF _last_ms IS NULL THEN
    -- First ever session
    _current := 1;
  ELSIF (_last_ms / 86400000) = (_yesterday_ms / 86400000) THEN
    -- Consecutive day
    _current := _current + 1;
  ELSIF (_last_ms / 86400000) = ((_yesterday_ms - 86400000) / 86400000) AND _has_freeze THEN
    -- Missed 1 day but freeze available
    _current := _current + 1;
    _has_freeze := FALSE;
    _freeze_used := TRUE;
  ELSE
    -- Streak broken
    _current := 1;
  END IF;

  -- Update best
  IF _current > _best THEN
    _best := _current;
  END IF;

  -- Earn freeze every 7 days (if not already earned at this threshold)
  IF _current >= 7 AND (_current / 7) > (_earned_at / 7) AND NOT _has_freeze THEN
    _has_freeze := TRUE;
    _earned_at  := (_current / 7) * 7;
  END IF;

  UPDATE public.profile_progress
  SET daily_streak_count    = _current,
      streak_best           = _best,
      last_streak_day_ms    = _today_ms,
      has_freeze_available  = _has_freeze,
      freeze_earned_at_streak = _earned_at,
      updated_at            = now()
  WHERE profile_progress.user_id = p_user_id;

  streak_current := _current;
  streak_best    := _best;
  freeze_used    := _freeze_used;
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- G) RPC: fn_generate_weekly_goal — create goal for current week
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_generate_weekly_goal(
  p_user_id UUID,
  p_metric  TEXT DEFAULT 'distance'
)
RETURNS JSONB AS $$
DECLARE
  _week_start     DATE;
  _baseline       DOUBLE PRECISION;
  _week_num       INTEGER;
  _factor         DOUBLE PRECISION;
  _target         DOUBLE PRECISION;
  _default_dist   DOUBLE PRECISION := 10000.0;  -- 10 km in meters
  _default_time   DOUBLE PRECISION := 3600.0;   -- 60 min in seconds
  _existing       UUID;
  _goal_id        UUID;
BEGIN
  IF p_metric NOT IN ('distance', 'time') THEN
    RAISE EXCEPTION 'Invalid metric: %. Use distance or time.', p_metric;
  END IF;

  -- Current ISO week Monday
  _week_start := DATE_TRUNC('week', NOW() AT TIME ZONE 'UTC')::DATE;

  -- Check idempotency
  SELECT id INTO _existing
  FROM public.weekly_goals
  WHERE user_id = p_user_id AND week_start = _week_start;

  IF _existing IS NOT NULL THEN
    RETURN jsonb_build_object(
      'goal_id', _existing,
      'week_start', _week_start,
      'already_exists', true
    );
  END IF;

  -- Compute baseline from last 4 weeks
  IF p_metric = 'distance' THEN
    SELECT COALESCE(AVG(vw.total_distance_m), _default_dist)
    INTO _baseline
    FROM public.v_weekly_progress vw
    WHERE vw.user_id = p_user_id
      AND vw.week_start >= (_week_start - INTERVAL '28 days')::DATE
      AND vw.week_start < _week_start;
  ELSE
    SELECT COALESCE(AVG(vw.total_moving_ms / 1000.0), _default_time)
    INTO _baseline
    FROM public.v_weekly_progress vw
    WHERE vw.user_id = p_user_id
      AND vw.week_start >= (_week_start - INTERVAL '28 days')::DATE
      AND vw.week_start < _week_start;
  END IF;

  -- Alternating factor: even ISO weeks = 1.0 (maintain), odd = 1.1 (push)
  _week_num := EXTRACT(WEEK FROM _week_start)::INTEGER;
  _factor := CASE WHEN _week_num % 2 = 0 THEN 1.0 ELSE 1.1 END;

  _target := ROUND((_baseline * _factor)::NUMERIC, 1);

  -- Minimum thresholds
  IF p_metric = 'distance' AND _target < 1000 THEN
    _target := 1000;  -- At least 1 km
  ELSIF p_metric = 'time' AND _target < 600 THEN
    _target := 600;    -- At least 10 min
  END IF;

  INSERT INTO public.weekly_goals (user_id, week_start, metric, target_value)
  VALUES (p_user_id, _week_start, p_metric, _target)
  RETURNING id INTO _goal_id;

  RETURN jsonb_build_object(
    'goal_id', _goal_id,
    'week_start', _week_start,
    'metric', p_metric,
    'target_value', _target,
    'baseline', ROUND(_baseline::NUMERIC, 1),
    'factor', _factor,
    'already_exists', false
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- H) RPC: fn_check_weekly_goal — update progress, auto-complete if met
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_check_weekly_goal(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  _goal    RECORD;
  _actual  DOUBLE PRECISION;
  _week    DATE;
BEGIN
  _week := DATE_TRUNC('week', NOW() AT TIME ZONE 'UTC')::DATE;

  SELECT * INTO _goal
  FROM public.weekly_goals
  WHERE user_id = p_user_id
    AND week_start = _week
    AND status = 'active';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'no_active_goal');
  END IF;

  -- Get current week actual
  IF _goal.metric = 'distance' THEN
    SELECT COALESCE(vw.total_distance_m, 0) INTO _actual
    FROM public.v_weekly_progress vw
    WHERE vw.user_id = p_user_id AND vw.week_start = _week;
  ELSE
    SELECT COALESCE(vw.total_moving_ms / 1000.0, 0) INTO _actual
    FROM public.v_weekly_progress vw
    WHERE vw.user_id = p_user_id AND vw.week_start = _week;
  END IF;

  _actual := COALESCE(_actual, 0);

  IF _actual >= _goal.target_value AND _goal.status = 'active' THEN
    UPDATE public.weekly_goals
    SET current_value = _actual,
        status = 'completed',
        xp_awarded = 40,
        completed_at = now()
    WHERE id = _goal.id;

    RETURN jsonb_build_object(
      'status', 'completed',
      'goal_id', _goal.id,
      'target', _goal.target_value,
      'actual', _actual,
      'xp_awarded', 40
    );
  ELSE
    UPDATE public.weekly_goals
    SET current_value = _actual
    WHERE id = _goal.id;

    RETURN jsonb_build_object(
      'status', 'in_progress',
      'goal_id', _goal.id,
      'target', _goal.target_value,
      'actual', _actual,
      'pct', ROUND(LEAST(100, (_actual / _goal.target_value) * 100)::NUMERIC, 1)
    );
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMIT;
