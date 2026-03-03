BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO E: Analytics Avançado
-- Adds workout adherence, training load, performance trend, and financial
-- metrics to the KPI compute pipeline.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. New columns on coaching_kpis_daily
ALTER TABLE public.coaching_kpis_daily
  ADD COLUMN IF NOT EXISTS adherence_percent_7d numeric(5,2),
  ADD COLUMN IF NOT EXISTS workout_load_week int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS performance_trend numeric(5,2),
  ADD COLUMN IF NOT EXISTS revenue_month numeric(12,2),
  ADD COLUMN IF NOT EXISTS active_subscriptions int NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS late_subscriptions int NOT NULL DEFAULT 0;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. REWRITE compute_coaching_kpis_daily — add BLOCO E metrics
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
  v_day_start_ts  timestamptz;
  v_7d_start_ts   timestamptz;
  v_count integer;
BEGIN
  v_day_start_ms  := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_day_end_ms    := v_day_start_ms + 86400000;
  v_week_start_ms := v_day_start_ms - 6 * 86400000;
  v_month_start_ms := v_day_start_ms - 29 * 86400000;
  v_prev_week_start_ms := v_week_start_ms - 7 * 86400000;
  v_prev_week_end_ms   := v_week_start_ms;

  v_day_start_ts := p_day::timestamptz;
  v_7d_start_ts  := (p_day - 6)::timestamptz;

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

  INSERT INTO coaching_kpis_daily (
    group_id, day,
    total_members, total_athletes, total_coaches, new_members_today,
    dau, wau, mau,
    sessions_today, distance_today_m, unique_athletes_today,
    retention_wow_pct, active_challenges,
    attendance_sessions_7d, attendance_checkins_7d, attendance_rate_7d,
    adherence_percent_7d, workout_load_week, performance_trend,
    revenue_month, active_subscriptions, late_subscriptions,
    computed_at
  )
  SELECT
    g.id AS group_id,
    p_day,

    -- Membership
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

    0,

    -- Attendance metrics (OS-01 integration)
    coalesce(att.training_sessions_7d, 0),
    coalesce(att.checkins_7d, 0),
    CASE WHEN coalesce(att.training_sessions_7d, 0) = 0 OR coalesce(mem.total_athletes, 0) = 0
         THEN NULL
         ELSE round(
           (att.checkins_7d::numeric / (att.training_sessions_7d * mem.total_athletes)) * 100, 2
         )
    END,

    -- BLOCO E: Adherence (7d)
    CASE WHEN adh.total_7d > 0
         THEN round(adh.completed_7d * 100.0 / adh.total_7d, 2)
         ELSE NULL
    END,

    -- BLOCO E: Workout load (seconds, 7d)
    coalesce(wl.load_seconds, 0),

    -- BLOCO E: Performance trend (positive = improvement)
    CASE WHEN pt.pace_last_week > 0
         THEN round((pt.pace_last_week - pt.pace_this_week) * 100.0 / pt.pace_last_week, 2)
         ELSE NULL
    END,

    -- BLOCO E: Financial
    coalesce(fin.revenue_month, 0),
    coalesce(subs.active_subs, 0),
    coalesce(subs.late_subs, 0),

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
        WHERE ks.start_time_ms >= v_day_start_ms AND ks.total_distance_m >= 1000
      ) AS dau,
      count(DISTINCT ks.user_id) FILTER (
        WHERE ks.start_time_ms >= v_week_start_ms AND ks.total_distance_m >= 1000
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

  -- WoW retention
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

  -- Attendance from OS-01 training sessions (last 7 days)
  LEFT JOIN LATERAL (
    SELECT
      count(DISTINCT ts.id) AS training_sessions_7d,
      count(DISTINCT ta.id) AS checkins_7d
    FROM coaching_training_sessions ts
    LEFT JOIN coaching_training_attendance ta ON ta.session_id = ts.id
    WHERE ts.group_id = g.id
      AND ts.starts_at >= v_7d_start_ts
      AND ts.starts_at < v_day_start_ts + interval '1 day'
      AND ts.status != 'cancelled'
  ) att ON true

  -- BLOCO E: Workout adherence (7d)
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE a.status = 'completed') AS completed_7d,
      count(*) AS total_7d
    FROM coaching_workout_assignments a
    WHERE a.group_id = g.id
      AND a.scheduled_date >= (p_day - 6)
      AND a.scheduled_date <= p_day
  ) adh ON true

  -- BLOCO E: Workout load (seconds, 7d)
  LEFT JOIN LATERAL (
    SELECT coalesce(sum(e.actual_duration_seconds), 0) AS load_seconds
    FROM coaching_workout_executions e
    WHERE e.group_id = g.id
      AND e.completed_at >= v_7d_start_ts
      AND e.completed_at < v_day_start_ts + interval '1 day'
  ) wl ON true

  -- BLOCO E: Performance trend (this week vs last week avg pace)
  LEFT JOIN LATERAL (
    SELECT
      avg(e.avg_pace_seconds_per_km) FILTER (WHERE e.completed_at >= v_7d_start_ts) AS pace_this_week,
      avg(e.avg_pace_seconds_per_km) FILTER (WHERE e.completed_at >= v_7d_start_ts - interval '7 days' AND e.completed_at < v_7d_start_ts) AS pace_last_week
    FROM coaching_workout_executions e
    WHERE e.group_id = g.id
      AND e.completed_at >= v_7d_start_ts - interval '7 days'
      AND e.completed_at < v_day_start_ts + interval '1 day'
      AND e.avg_pace_seconds_per_km IS NOT NULL
  ) pt ON true

  -- BLOCO E: Revenue this month
  LEFT JOIN LATERAL (
    SELECT
      coalesce(sum(l.amount) FILTER (WHERE l.type = 'revenue'), 0) AS revenue_month
    FROM coaching_financial_ledger l
    WHERE l.group_id = g.id
      AND l.date >= date_trunc('month', p_day)::date
      AND l.date <= p_day
  ) fin ON true

  -- BLOCO E: Subscription counts
  LEFT JOIN LATERAL (
    SELECT
      count(*) FILTER (WHERE s.status = 'active') AS active_subs,
      count(*) FILTER (WHERE s.status = 'late') AS late_subs
    FROM coaching_subscriptions s
    WHERE s.group_id = g.id
  ) subs ON true

  ON CONFLICT (group_id, day) DO UPDATE SET
    total_members          = EXCLUDED.total_members,
    total_athletes         = EXCLUDED.total_athletes,
    total_coaches          = EXCLUDED.total_coaches,
    new_members_today      = EXCLUDED.new_members_today,
    dau                    = EXCLUDED.dau,
    wau                    = EXCLUDED.wau,
    mau                    = EXCLUDED.mau,
    sessions_today         = EXCLUDED.sessions_today,
    distance_today_m       = EXCLUDED.distance_today_m,
    unique_athletes_today  = EXCLUDED.unique_athletes_today,
    retention_wow_pct      = EXCLUDED.retention_wow_pct,
    active_challenges      = EXCLUDED.active_challenges,
    attendance_sessions_7d = EXCLUDED.attendance_sessions_7d,
    attendance_checkins_7d = EXCLUDED.attendance_checkins_7d,
    attendance_rate_7d     = EXCLUDED.attendance_rate_7d,
    adherence_percent_7d   = EXCLUDED.adherence_percent_7d,
    workout_load_week      = EXCLUDED.workout_load_week,
    performance_trend      = EXCLUDED.performance_trend,
    revenue_month          = EXCLUDED.revenue_month,
    active_subscriptions   = EXCLUDED.active_subscriptions,
    late_subscriptions     = EXCLUDED.late_subscriptions,
    computed_at            = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. UPDATE compute_coaching_alerts_daily — add FINANCIAL_LATE
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.compute_coaching_alerts_daily(p_day date)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_day_start_ms bigint;
  v_14d_start_ts timestamptz;
  v_day_ts       timestamptz;
  v_count integer := 0;
  v_partial integer;
BEGIN
  v_day_start_ms := extract(epoch from p_day::timestamp at time zone 'UTC')::bigint * 1000;
  v_day_ts       := p_day::timestamptz;
  v_14d_start_ts := (p_day - 13)::timestamptz;

  -- High risk alerts (from athlete KPIs)
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

  -- Inactive 30d+
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

  -- Inactive 14d (exclude 30d)
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

  -- Inactive 7d (exclude 14d/30d)
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

  -- MISSED_TRAININGS_14D (from OS-05)
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    cm.group_id,
    cm.user_id,
    p_day,
    'missed_trainings_14d',
    cm.display_name || ' sem presença em treinos (14d)',
    'Grupo teve ' || gs.session_count || ' treinos nos últimos 14 dias, mas este atleta não registrou presença em nenhum.',
    CASE
      WHEN ak.risk_level = 'high' THEN 'critical'
      ELSE 'warning'
    END
  FROM coaching_members cm

  JOIN LATERAL (
    SELECT count(*) AS session_count
    FROM coaching_training_sessions ts
    WHERE ts.group_id = cm.group_id
      AND ts.starts_at >= v_14d_start_ts
      AND ts.starts_at < v_day_ts + interval '1 day'
      AND ts.status != 'cancelled'
  ) gs ON gs.session_count >= 2

  LEFT JOIN LATERAL (
    SELECT count(*) AS att_count
    FROM coaching_training_attendance ta
    JOIN coaching_training_sessions ts ON ts.id = ta.session_id
    WHERE ta.athlete_user_id = cm.user_id
      AND ta.group_id = cm.group_id
      AND ts.starts_at >= v_14d_start_ts
      AND ts.starts_at < v_day_ts + interval '1 day'
  ) att ON true

  LEFT JOIN coaching_athlete_kpis_daily ak
    ON ak.user_id = cm.user_id AND ak.group_id = cm.group_id AND ak.day = p_day

  WHERE cm.role = 'athlete'
    AND coalesce(att.att_count, 0) = 0

  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  -- ═══════════════════════════════════════════════════════════════════════
  -- BLOCO E: FINANCIAL_LATE — athletes with late subscriptions
  -- ═══════════════════════════════════════════════════════════════════════
  INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
  SELECT
    cm.group_id, cm.user_id, p_day, 'financial_late',
    cm.display_name || ' com assinatura em atraso',
    'Atleta está com a assinatura em atraso desde ' || s.next_due_date,
    'warning'
  FROM coaching_members cm
  JOIN coaching_subscriptions s ON s.athlete_user_id = cm.user_id AND s.group_id = cm.group_id
  WHERE cm.role = 'athlete' AND s.status = 'late'
  ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
  GET DIAGNOSTICS v_partial = ROW_COUNT;
  v_count := v_count + v_partial;

  RETURN v_count;
END;
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. Grants
-- ═══════════════════════════════════════════════════════════════════════════

REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_kpis_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_kpis_daily(date) TO service_role;

REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM anon;
REVOKE ALL ON FUNCTION public.compute_coaching_alerts_daily(date) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.compute_coaching_alerts_daily(date) TO service_role;

COMMIT;
