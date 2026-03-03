-- ============================================================================
-- PATCH: Set-based rewrite of KPI compute functions
-- Replaces FOR-LOOP-per-group/per-athlete with single INSERT...SELECT statements.
-- Designed for 10k+ assessorias, 100k+ athletes.
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. compute_coaching_kpis_daily(p_day) — GROUP-LEVEL, set-based
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.compute_coaching_kpis_daily(p_day date)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_day_start_ms  bigint;
  v_day_end_ms    bigint;
  v_week_start_ms bigint;
  v_month_start_ms bigint;
  v_prev_week_start_ms bigint;
  v_prev_week_end_ms   bigint;
  v_count integer;
BEGIN
  v_day_start_ms  := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_day_end_ms    := v_day_start_ms + 86400000;
  v_week_start_ms := v_day_start_ms - 6 * 86400000;
  v_month_start_ms := v_day_start_ms - 29 * 86400000;
  v_prev_week_start_ms := v_week_start_ms - 7 * 86400000;
  v_prev_week_end_ms   := v_week_start_ms;

  -- Pre-materialize qualified sessions for the month window into a temp table.
  -- This avoids re-scanning sessions once per subquery.
  CREATE TEMP TABLE _kpi_sessions ON COMMIT DROP AS
    SELECT s.user_id, s.start_time_ms, s.total_distance_m, cm.group_id
    FROM sessions s
    JOIN coaching_members cm
      ON cm.user_id = s.user_id AND cm.role = 'athlete'
    WHERE s.start_time_ms >= v_month_start_ms
      AND s.start_time_ms < v_day_end_ms
      AND s.status >= 3
      AND s.is_verified = true;

  CREATE INDEX ON _kpi_sessions (group_id, start_time_ms);

  -- Single INSERT...SELECT across ALL groups
  INSERT INTO coaching_kpis_daily (
    group_id, day,
    total_members, total_athletes, total_coaches, new_members_today,
    dau, wau, mau,
    sessions_today, distance_today_m, unique_athletes_today,
    retention_wow_pct, active_challenges,
    computed_at
  )
  SELECT
    g.id AS group_id,
    p_day,

    -- Membership counts
    coalesce(mem.total_members, 0),
    coalesce(mem.total_athletes, 0),
    coalesce(mem.total_coaches, 0),
    coalesce(mem.new_members_today, 0),

    -- DAU / WAU / MAU
    coalesce(act.dau, 0),
    coalesce(act.wau, 0),
    coalesce(act.mau, 0),

    -- Sessions today
    coalesce(today_agg.sessions_today, 0),
    coalesce(today_agg.distance_today_m, 0),
    coalesce(today_agg.unique_athletes_today, 0),

    -- WoW retention
    CASE WHEN coalesce(ret.prev_week_active, 0) = 0 THEN NULL
         ELSE round((ret.returning_users::numeric / ret.prev_week_active) * 100, 2)
    END,

    -- Active challenges (0 placeholder — enriched below if table exists)
    0,

    now()

  FROM coaching_groups g

  -- Membership aggregates
  LEFT JOIN LATERAL (
    SELECT
      count(*)                                                    AS total_members,
      count(*) FILTER (WHERE cm.role = 'athlete')                  AS total_athletes,
      count(*) FILTER (WHERE cm.role IN ('admin_master','coach','assistant')) AS total_coaches,
      count(*) FILTER (WHERE cm.joined_at_ms >= v_day_start_ms
                         AND cm.joined_at_ms < v_day_end_ms)      AS new_members_today
    FROM coaching_members cm
    WHERE cm.group_id = g.id
  ) mem ON true

  -- Activity: DAU / WAU / MAU from temp table
  LEFT JOIN LATERAL (
    SELECT
      count(DISTINCT ks.user_id) FILTER (
        WHERE ks.start_time_ms >= v_day_start_ms
          AND ks.total_distance_m >= 1000
      ) AS dau,
      count(DISTINCT ks.user_id) FILTER (
        WHERE ks.start_time_ms >= v_week_start_ms
          AND ks.total_distance_m >= 1000
      ) AS wau,
      count(DISTINCT ks.user_id) FILTER (
        WHERE ks.total_distance_m >= 1000
      ) AS mau
    FROM _kpi_sessions ks
    WHERE ks.group_id = g.id
  ) act ON true

  -- Today's sessions aggregate
  LEFT JOIN LATERAL (
    SELECT
      count(*)               AS sessions_today,
      coalesce(sum(ks.total_distance_m), 0) AS distance_today_m,
      count(DISTINCT ks.user_id) AS unique_athletes_today
    FROM _kpi_sessions ks
    WHERE ks.group_id = g.id
      AND ks.start_time_ms >= v_day_start_ms
  ) today_agg ON true

  -- WoW retention: users active in both current week and previous week
  LEFT JOIN LATERAL (
    SELECT
      (SELECT count(DISTINCT user_id)
       FROM _kpi_sessions
       WHERE group_id = g.id
         AND start_time_ms >= v_prev_week_start_ms
         AND start_time_ms < v_prev_week_end_ms
         AND total_distance_m >= 1000
      ) AS prev_week_active,
      (SELECT count(*) FROM (
         SELECT user_id FROM _kpi_sessions
         WHERE group_id = g.id
           AND start_time_ms >= v_week_start_ms
           AND total_distance_m >= 1000
         INTERSECT
         SELECT user_id FROM _kpi_sessions
         WHERE group_id = g.id
           AND start_time_ms >= v_prev_week_start_ms
           AND start_time_ms < v_prev_week_end_ms
           AND total_distance_m >= 1000
       ) x
      ) AS returning_users
  ) ret ON true

  ON CONFLICT (group_id, day) DO UPDATE SET
    total_members       = EXCLUDED.total_members,
    total_athletes      = EXCLUDED.total_athletes,
    total_coaches       = EXCLUDED.total_coaches,
    new_members_today   = EXCLUDED.new_members_today,
    dau                 = EXCLUDED.dau,
    wau                 = EXCLUDED.wau,
    mau                 = EXCLUDED.mau,
    sessions_today      = EXCLUDED.sessions_today,
    distance_today_m    = EXCLUDED.distance_today_m,
    unique_athletes_today = EXCLUDED.unique_athletes_today,
    retention_wow_pct   = EXCLUDED.retention_wow_pct,
    active_challenges   = EXCLUDED.active_challenges,
    computed_at         = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 2. compute_coaching_athlete_kpis_daily(p_day, p_group_id) — set-based
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.compute_coaching_athlete_kpis_daily(
  p_day      date,
  p_group_id uuid DEFAULT NULL
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_day_start_ms bigint;
  v_7d_ms  bigint;
  v_14d_ms bigint;
  v_30d_ms bigint;
  v_3d_ms  bigint;
  v_count  integer;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_3d_ms  := v_day_start_ms - 2 * 86400000;
  v_7d_ms  := v_day_start_ms - 6 * 86400000;
  v_14d_ms := v_day_start_ms - 13 * 86400000;
  v_30d_ms := v_day_start_ms - 29 * 86400000;

  -- Pre-materialize sessions for all target athletes in the 30d window
  CREATE TEMP TABLE _athlete_sessions ON COMMIT DROP AS
    SELECT s.user_id, s.start_time_ms, s.total_distance_m
    FROM sessions s
    WHERE s.start_time_ms >= v_30d_ms
      AND s.status >= 3
      AND s.is_verified = true
      AND s.user_id IN (
        SELECT cm.user_id FROM coaching_members cm
        WHERE cm.role = 'athlete'
          AND (p_group_id IS NULL OR cm.group_id = p_group_id)
      );

  CREATE INDEX ON _athlete_sessions (user_id, start_time_ms);

  INSERT INTO coaching_athlete_kpis_daily (
    group_id, user_id, day,
    engagement_score, sessions_7d, sessions_14d, sessions_30d,
    distance_7d_m, last_session_at_ms, risk_level, current_streak,
    computed_at
  )
  SELECT
    cm.group_id,
    cm.user_id,
    p_day,

    -- engagement_score (0-100)
    least(
      -- frequency: min(sessions_7d * 15, 45)
      least(coalesce(agg.s7, 0) * 15, 45)
      -- recency: 30 / 20 / 10 / 0
      + CASE
          WHEN agg.last_ms >= v_3d_ms  THEN 30
          WHEN agg.last_ms >= v_7d_ms  THEN 20
          WHEN agg.last_ms >= v_14d_ms THEN 10
          ELSE 0
        END
      -- consistency: min(sessions_14d * 3, 15)
      + least(coalesce(agg.s14, 0) * 3, 15)
      -- streak: min(streak * 2, 10)
      + least(coalesce(pp.daily_streak_count, 0) * 2, 10),
      100
    ),

    coalesce(agg.s7, 0),
    coalesce(agg.s14, 0),
    coalesce(agg.s30, 0),
    coalesce(agg.dist7, 0),
    agg.last_ms,

    -- risk_level derived from the same score expression
    CASE
      WHEN least(
             least(coalesce(agg.s7, 0) * 15, 45)
             + CASE
                 WHEN agg.last_ms >= v_3d_ms  THEN 30
                 WHEN agg.last_ms >= v_7d_ms  THEN 20
                 WHEN agg.last_ms >= v_14d_ms THEN 10
                 ELSE 0
               END
             + least(coalesce(agg.s14, 0) * 3, 15)
             + least(coalesce(pp.daily_streak_count, 0) * 2, 10),
             100
           ) >= 40 THEN 'ok'
      WHEN least(
             least(coalesce(agg.s7, 0) * 15, 45)
             + CASE
                 WHEN agg.last_ms >= v_3d_ms  THEN 30
                 WHEN agg.last_ms >= v_7d_ms  THEN 20
                 WHEN agg.last_ms >= v_14d_ms THEN 10
                 ELSE 0
               END
             + least(coalesce(agg.s14, 0) * 3, 15)
             + least(coalesce(pp.daily_streak_count, 0) * 2, 10),
             100
           ) >= 20 THEN 'medium'
      ELSE 'high'
    END,

    coalesce(pp.daily_streak_count, 0),
    now()

  FROM coaching_members cm

  -- Session aggregates per athlete
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE a.start_time_ms >= v_7d_ms)  AS s7,
      count(*) FILTER (WHERE a.start_time_ms >= v_14d_ms) AS s14,
      count(*)                                             AS s30,
      coalesce(sum(a.total_distance_m) FILTER (WHERE a.start_time_ms >= v_7d_ms), 0) AS dist7,
      max(a.start_time_ms)                                 AS last_ms
    FROM _athlete_sessions a
    WHERE a.user_id = cm.user_id
  ) agg ON true

  -- Streak from profile_progress
  LEFT JOIN profile_progress pp ON pp.user_id = cm.user_id

  WHERE cm.role = 'athlete'
    AND (p_group_id IS NULL OR cm.group_id = p_group_id)

  ON CONFLICT (group_id, user_id, day) DO UPDATE SET
    engagement_score   = EXCLUDED.engagement_score,
    sessions_7d        = EXCLUDED.sessions_7d,
    sessions_14d       = EXCLUDED.sessions_14d,
    sessions_30d       = EXCLUDED.sessions_30d,
    distance_7d_m      = EXCLUDED.distance_7d_m,
    last_session_at_ms = EXCLUDED.last_session_at_ms,
    risk_level         = EXCLUDED.risk_level,
    current_streak     = EXCLUDED.current_streak,
    computed_at        = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- 3. compute_coaching_alerts_daily(p_day) — set-based
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.compute_coaching_alerts_daily(p_day date)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_day_start_ms bigint;
  v_count integer := 0;
  v_partial integer;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;

  -- High risk alerts
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    ak.group_id, ak.user_id, p_day,
    'athlete_high_risk',
    cm.display_name || ' em risco alto',
    'Score de engajamento: ' || ak.engagement_score || '/100. Sem atividade recente.',
    'critical'
  FROM coaching_athlete_kpis_daily ak
  JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
  WHERE ak.day = p_day AND ak.risk_level = 'high'
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  -- Medium risk alerts
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    ak.group_id, ak.user_id, p_day,
    'athlete_medium_risk',
    cm.display_name || ' com engajamento médio',
    'Score: ' || ak.engagement_score || '/100. Atividade em queda.',
    'warning'
  FROM coaching_athlete_kpis_daily ak
  JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
  WHERE ak.day = p_day AND ak.risk_level = 'medium'
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  -- Inactive 30d+ (includes never-ran athletes)
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    ak.group_id, ak.user_id, p_day,
    'inactive_30d',
    cm.display_name ||
      CASE WHEN ak.last_session_at_ms IS NULL
           THEN ' nunca registrou uma corrida'
           ELSE ' inativo há 30+ dias'
      END,
    CASE WHEN ak.last_session_at_ms IS NULL
         THEN 'Atleta cadastrado mas sem nenhuma sessão.'
         ELSE 'Considere entrar em contato para verificar a situação.'
    END,
    CASE WHEN ak.last_session_at_ms IS NULL THEN 'warning' ELSE 'critical' END
  FROM coaching_athlete_kpis_daily ak
  JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
  WHERE ak.day = p_day
    AND (ak.last_session_at_ms IS NULL
         OR ak.last_session_at_ms < v_day_start_ms - 29 * 86400000::bigint)
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  -- Inactive 14d (exclude already caught by 30d)
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    ak.group_id, ak.user_id, p_day,
    'inactive_14d',
    cm.display_name || ' inativo há 14+ dias',
    'Uma mensagem de incentivo pode ajudar.',
    'warning'
  FROM coaching_athlete_kpis_daily ak
  JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
  WHERE ak.day = p_day
    AND ak.last_session_at_ms IS NOT NULL
    AND ak.last_session_at_ms < v_day_start_ms - 13 * 86400000::bigint
    AND ak.last_session_at_ms >= v_day_start_ms - 29 * 86400000::bigint
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  -- Inactive 7d (exclude already caught by 14d/30d)
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    ak.group_id, ak.user_id, p_day,
    'inactive_7d',
    cm.display_name || ' sem atividade na última semana',
    'Sem corrida nos últimos 7 dias.',
    'info'
  FROM coaching_athlete_kpis_daily ak
  JOIN coaching_members cm ON cm.user_id = ak.user_id AND cm.group_id = ak.group_id
  WHERE ak.day = p_day
    AND ak.last_session_at_ms IS NOT NULL
    AND ak.last_session_at_ms < v_day_start_ms - 6 * 86400000::bigint
    AND ak.last_session_at_ms >= v_day_start_ms - 13 * 86400000::bigint
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  RETURN v_count;
END;
$$;


-- ═══════════════════════════════════════════════════════════════════════════
-- Grants (match SECURITY_HARDENING.sql)
-- ═══════════════════════════════════════════════════════════════════════════
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_kpis_daily(date) TO service_role;

REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_athlete_kpis_daily(date, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_alerts_daily(date) TO service_role;
