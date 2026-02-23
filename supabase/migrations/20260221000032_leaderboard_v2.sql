-- ============================================================================
-- Omni Runner — Leaderboard v2: Global / Assessoria / Campeonato
-- Date: 2026-02-27
-- Sprint: 20.3.0
-- ============================================================================
-- Expands the leaderboard system to support 3 scopes:
--   global       — all users with verified sessions
--   assessoria   — members of a coaching_group
--   championship — enrolled/active participants in a championship
--
-- Adds composite scoring (distance points + challenge wins).
-- ============================================================================

BEGIN;

-- ── 1. Expand leaderboards.scope CHECK ──────────────────────────────────────

ALTER TABLE public.leaderboards
  DROP CONSTRAINT IF EXISTS leaderboards_scope_check;

ALTER TABLE public.leaderboards
  ADD CONSTRAINT leaderboards_scope_check
    CHECK (scope IN ('global','friends','group','season','assessoria','championship'));

-- ── 2. Add FK columns for assessoria and championship scopes ────────────────

ALTER TABLE public.leaderboards
  ADD COLUMN IF NOT EXISTS coaching_group_id UUID
    REFERENCES public.coaching_groups(id) ON DELETE CASCADE;

ALTER TABLE public.leaderboards
  ADD COLUMN IF NOT EXISTS championship_id UUID
    REFERENCES public.championships(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_leaderboards_coaching_group
  ON public.leaderboards(coaching_group_id)
  WHERE coaching_group_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_leaderboards_championship
  ON public.leaderboards(championship_id)
  WHERE championship_id IS NOT NULL;

-- ── 3. Update RLS for leaderboards ──────────────────────────────────────────
-- Drop the old read policy and recreate with assessoria + championship support.

DROP POLICY IF EXISTS "leaderboards_read_all" ON public.leaderboards;

CREATE POLICY "leaderboards_read_v2" ON public.leaderboards
  FOR SELECT USING (
    scope IN ('global', 'season')
    OR (scope = 'group' AND EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = leaderboards.group_id
        AND gm.user_id = auth.uid()
        AND gm.status = 'active'
    ))
    OR (scope = 'assessoria' AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = leaderboards.coaching_group_id
        AND cm.user_id = auth.uid()
    ))
    OR (scope = 'championship' AND EXISTS (
      SELECT 1 FROM public.championship_participants cp
      WHERE cp.championship_id = leaderboards.championship_id
        AND cp.user_id = auth.uid()
        AND cp.status IN ('enrolled', 'active', 'completed')
    ))
    OR (scope = 'friends' AND true)
  );

-- ── 4. Service-role INSERT/UPDATE/DELETE for leaderboards ───────────────────
-- Edge Functions run as service_role so they bypass RLS.
-- These policies let the compute function write leaderboard data.

DROP POLICY IF EXISTS "leaderboards_service_write" ON public.leaderboards;

CREATE POLICY "leaderboards_service_write" ON public.leaderboards
  FOR ALL USING (
    auth.role() = 'service_role'
  );

DROP POLICY IF EXISTS "lb_entries_service_write" ON public.leaderboard_entries;

CREATE POLICY "lb_entries_service_write" ON public.leaderboard_entries
  FOR ALL USING (
    auth.role() = 'service_role'
  );

-- ── 5. RPC: compute_leaderboard_assessoria ──────────────────────────────────
-- Materializes a leaderboard for a specific coaching group.
-- Metric: composite score = floor(distance_km) + (challenge_wins * 5)
-- Only includes members of the coaching group with verified sessions in range.

CREATE OR REPLACE FUNCTION public.compute_leaderboard_assessoria(
  p_coaching_group_id UUID,
  p_period       TEXT,
  p_period_key   TEXT,
  p_start_ms     BIGINT,
  p_end_ms       BIGINT
)
RETURNS INTEGER AS $$
DECLARE
  lb_id TEXT;
  row_count INTEGER;
  now_ms BIGINT;
BEGIN
  now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;
  lb_id := 'assessoria_' || p_period || '_composite_' || p_coaching_group_id::TEXT || '_' || p_period_key;

  INSERT INTO public.leaderboards (id, scope, period, metric, period_key, computed_at_ms, is_final, coaching_group_id)
  VALUES (lb_id, 'assessoria', p_period, 'composite', p_period_key, now_ms, false, p_coaching_group_id)
  ON CONFLICT (id) DO UPDATE SET computed_at_ms = now_ms;

  DELETE FROM public.leaderboard_entries WHERE leaderboard_id = lb_id;

  INSERT INTO public.leaderboard_entries (leaderboard_id, user_id, display_name, avatar_url, level, value, rank, period_key)
  SELECT
    lb_id,
    cm.user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(FLOOR(POWER(pp.total_xp::DOUBLE PRECISION / 100, 2.0/3.0))::INTEGER, 0),
    COALESCE(FLOOR(agg.total_dist / 1000.0), 0) + COALESCE(wins.win_count * 5, 0),
    ROW_NUMBER() OVER (
      ORDER BY (COALESCE(FLOOR(agg.total_dist / 1000.0), 0) + COALESCE(wins.win_count * 5, 0)) DESC
    ),
    p_period_key
  FROM public.coaching_members cm
  JOIN public.profiles p ON p.id = cm.user_id
  LEFT JOIN public.profile_progress pp ON pp.user_id = cm.user_id
  LEFT JOIN (
    SELECT s.user_id, SUM(s.total_distance_m) AS total_dist
    FROM public.sessions s
    WHERE s.is_verified = true
      AND s.start_time_ms BETWEEN p_start_ms AND p_end_ms
      AND s.total_distance_m > 0
    GROUP BY s.user_id
  ) agg ON agg.user_id = cm.user_id
  LEFT JOIN (
    SELECT cr.user_id, COUNT(*) AS win_count
    FROM public.challenge_results cr
    WHERE cr.outcome = 'won'
      AND cr.calculated_at_ms BETWEEN p_start_ms AND p_end_ms
    GROUP BY cr.user_id
  ) wins ON wins.user_id = cm.user_id
  WHERE cm.group_id = p_coaching_group_id
    AND (agg.total_dist IS NOT NULL OR wins.win_count IS NOT NULL)
  ORDER BY (COALESCE(FLOOR(agg.total_dist / 1000.0), 0) + COALESCE(wins.win_count * 5, 0)) DESC
  LIMIT 200;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 6. RPC: compute_leaderboard_championship ────────────────────────────────
-- Materializes a leaderboard for championship participants.
-- Uses the championship's own metric for ranking.
-- Only includes participants with status enrolled/active/completed
-- AND who have an active championship badge.

CREATE OR REPLACE FUNCTION public.compute_leaderboard_championship(
  p_championship_id UUID,
  p_period_key      TEXT,
  p_start_ms        BIGINT,
  p_end_ms          BIGINT
)
RETURNS INTEGER AS $$
DECLARE
  lb_id TEXT;
  row_count INTEGER;
  now_ms BIGINT;
  v_metric TEXT;
  v_is_lower_better BOOLEAN;
BEGIN
  now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;

  SELECT metric INTO v_metric
  FROM public.championships
  WHERE id = p_championship_id;

  IF v_metric IS NULL THEN
    RETURN 0;
  END IF;

  v_is_lower_better := v_metric IN ('pace', 'time');

  lb_id := 'championship_' || v_metric || '_' || p_championship_id::TEXT || '_' || p_period_key;

  INSERT INTO public.leaderboards (id, scope, period, metric, period_key, computed_at_ms, is_final, championship_id)
  VALUES (lb_id, 'championship', 'weekly', v_metric, p_period_key, now_ms, false, p_championship_id)
  ON CONFLICT (id) DO UPDATE SET computed_at_ms = now_ms;

  DELETE FROM public.leaderboard_entries WHERE leaderboard_id = lb_id;

  INSERT INTO public.leaderboard_entries (leaderboard_id, user_id, display_name, avatar_url, level, value, rank, period_key)
  SELECT
    lb_id,
    cp.user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(FLOOR(POWER(pp.total_xp::DOUBLE PRECISION / 100, 2.0/3.0))::INTEGER, 0),
    CASE v_metric
      WHEN 'distance'  THEN COALESCE(agg.total_dist, 0)
      WHEN 'sessions'  THEN COALESCE(agg.session_count, 0)
      WHEN 'time'      THEN COALESCE(agg.total_moving, 0)
      WHEN 'pace'      THEN COALESCE(agg.avg_pace, 9999)
      WHEN 'elevation' THEN COALESCE(agg.total_dist, 0)
    END,
    ROW_NUMBER() OVER (
      ORDER BY
        CASE WHEN v_is_lower_better THEN
          CASE v_metric
            WHEN 'pace' THEN COALESCE(agg.avg_pace, 9999)
            WHEN 'time' THEN COALESCE(agg.total_moving, 999999999)
          END
        END ASC NULLS LAST,
        CASE WHEN NOT v_is_lower_better THEN
          CASE v_metric
            WHEN 'distance'  THEN COALESCE(agg.total_dist, 0)
            WHEN 'sessions'  THEN COALESCE(agg.session_count, 0)
            WHEN 'elevation' THEN COALESCE(agg.total_dist, 0)
          END
        END DESC NULLS LAST
    ),
    p_period_key
  FROM public.championship_participants cp
  JOIN public.profiles p ON p.id = cp.user_id
  LEFT JOIN public.profile_progress pp ON pp.user_id = cp.user_id
  INNER JOIN LATERAL (
    SELECT 1 AS ok
    FROM public.championship_badges cb
    WHERE cb.championship_id = p_championship_id
      AND cb.user_id = cp.user_id
      AND cb.expires_at > now()
    LIMIT 1
  ) badge_check ON true
  LEFT JOIN LATERAL (
    SELECT
      SUM(s.total_distance_m) AS total_dist,
      COUNT(*)::DOUBLE PRECISION AS session_count,
      SUM(s.moving_ms) AS total_moving,
      CASE WHEN COUNT(*) FILTER (WHERE s.avg_pace_sec_km > 0) > 0
        THEN AVG(s.avg_pace_sec_km) FILTER (WHERE s.avg_pace_sec_km > 0)
        ELSE 9999
      END AS avg_pace
    FROM public.sessions s
    WHERE s.user_id = cp.user_id
      AND s.is_verified = true
      AND s.start_time_ms BETWEEN p_start_ms AND p_end_ms
      AND s.total_distance_m > 0
  ) agg ON true
  WHERE cp.championship_id = p_championship_id
    AND cp.status IN ('enrolled', 'active', 'completed')
  ORDER BY
    CASE WHEN v_is_lower_better THEN
      CASE v_metric
        WHEN 'pace' THEN COALESCE(agg.avg_pace, 9999)
        WHEN 'time' THEN COALESCE(agg.total_moving, 999999999)
      END
    END ASC NULLS LAST,
    CASE WHEN NOT v_is_lower_better THEN
      CASE v_metric
        WHEN 'distance'  THEN COALESCE(agg.total_dist, 0)
        WHEN 'sessions'  THEN COALESCE(agg.session_count, 0)
        WHEN 'elevation' THEN COALESCE(agg.total_dist, 0)
      END
    END DESC NULLS LAST
  LIMIT 200;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 7. Update global weekly RPC to also support monthly + composite ─────────

CREATE OR REPLACE FUNCTION public.compute_leaderboard_global(
  p_period     TEXT,
  p_period_key TEXT,
  p_start_ms   BIGINT,
  p_end_ms     BIGINT
)
RETURNS INTEGER AS $$
DECLARE
  lb_id TEXT;
  row_count INTEGER;
  now_ms BIGINT;
BEGIN
  now_ms := EXTRACT(EPOCH FROM now())::BIGINT * 1000;
  lb_id := 'global_' || p_period || '_composite_' || p_period_key;

  INSERT INTO public.leaderboards (id, scope, period, metric, period_key, computed_at_ms, is_final)
  VALUES (lb_id, 'global', p_period, 'composite', p_period_key, now_ms, false)
  ON CONFLICT (id) DO UPDATE SET computed_at_ms = now_ms;

  DELETE FROM public.leaderboard_entries WHERE leaderboard_id = lb_id;

  INSERT INTO public.leaderboard_entries (leaderboard_id, user_id, display_name, avatar_url, level, value, rank, period_key)
  SELECT
    lb_id,
    s.user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(FLOOR(POWER(pp.total_xp::DOUBLE PRECISION / 100, 2.0/3.0))::INTEGER, 0),
    FLOOR(SUM(s.total_distance_m) / 1000.0) + COALESCE(wins.win_count * 5, 0),
    ROW_NUMBER() OVER (
      ORDER BY (FLOOR(SUM(s.total_distance_m) / 1000.0) + COALESCE(wins.win_count * 5, 0)) DESC
    ),
    p_period_key
  FROM public.sessions s
  JOIN public.profiles p ON p.id = s.user_id
  LEFT JOIN public.profile_progress pp ON pp.user_id = s.user_id
  LEFT JOIN (
    SELECT cr.user_id, COUNT(*) AS win_count
    FROM public.challenge_results cr
    WHERE cr.outcome = 'won'
      AND cr.calculated_at_ms BETWEEN p_start_ms AND p_end_ms
    GROUP BY cr.user_id
  ) wins ON wins.user_id = s.user_id
  WHERE s.is_verified = true
    AND s.start_time_ms BETWEEN p_start_ms AND p_end_ms
    AND s.total_distance_m > 0
  GROUP BY s.user_id, p.display_name, p.avatar_url, pp.total_xp, wins.win_count
  ORDER BY (FLOOR(SUM(s.total_distance_m) / 1000.0) + COALESCE(wins.win_count * 5, 0)) DESC
  LIMIT 200;

  GET DIAGNOSTICS row_count = ROW_COUNT;
  RETURN row_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 8. Expand leaderboards.metric CHECK ─────────────────────────────────────

ALTER TABLE public.leaderboards
  DROP CONSTRAINT IF EXISTS leaderboards_metric_check;

ALTER TABLE public.leaderboards
  ADD CONSTRAINT leaderboards_metric_check
    CHECK (metric IN ('distance','sessions','moving_time','avg_pace','season_xp','composite','pace','time','elevation'));

COMMIT;
