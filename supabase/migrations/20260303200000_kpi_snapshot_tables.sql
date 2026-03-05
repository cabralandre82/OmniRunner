-- ============================================================================
-- KPI snapshot tables for coaching analytics
-- These tables store daily aggregated metrics for assessoria dashboards.
-- ============================================================================

-- 1. Group-level daily KPIs
CREATE TABLE IF NOT EXISTS public.coaching_kpis_daily (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id               uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  day                    date NOT NULL,

  total_members          integer NOT NULL DEFAULT 0,
  total_athletes         integer NOT NULL DEFAULT 0,
  total_coaches          integer NOT NULL DEFAULT 0,
  new_members_today      integer NOT NULL DEFAULT 0,

  dau                    integer NOT NULL DEFAULT 0,
  wau                    integer NOT NULL DEFAULT 0,
  mau                    integer NOT NULL DEFAULT 0,

  sessions_today         integer NOT NULL DEFAULT 0,
  distance_today_m       numeric NOT NULL DEFAULT 0,
  unique_athletes_today  integer NOT NULL DEFAULT 0,

  retention_wow_pct      numeric(5,2),
  active_challenges      integer NOT NULL DEFAULT 0,

  attendance_sessions_7d integer NOT NULL DEFAULT 0,
  attendance_checkins_7d integer NOT NULL DEFAULT 0,
  attendance_rate_7d     numeric(5,2),

  adherence_percent_7d   numeric(5,2),
  workout_load_week      integer NOT NULL DEFAULT 0,
  performance_trend      numeric(5,2),
  revenue_month          numeric(12,2),
  active_subscriptions   integer NOT NULL DEFAULT 0,
  late_subscriptions     integer NOT NULL DEFAULT 0,

  total_sessions           integer,
  total_distance_m         numeric,
  total_duration_s         numeric,
  active_athletes          integer,
  avg_sessions_per_athlete numeric,

  engagement_score       numeric,
  churn_risk_count       integer,

  computed_at            timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_kpis_group_day UNIQUE (group_id, day)
);

ALTER TABLE public.coaching_kpis_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY "kpis_daily_staff_read" ON public.coaching_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_kpis_daily.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 2. Athlete-level daily KPIs
CREATE TABLE IF NOT EXISTS public.coaching_athlete_kpis_daily (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id           uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day                date NOT NULL,

  engagement_score   numeric NOT NULL DEFAULT 0,
  risk_level         text NOT NULL DEFAULT 'low'
                       CHECK (risk_level IN ('low', 'medium', 'high')),
  last_session_at_ms bigint,

  computed_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_athlete_kpis_group_user_day UNIQUE (group_id, user_id, day)
);

ALTER TABLE public.coaching_athlete_kpis_daily ENABLE ROW LEVEL SECURITY;

CREATE POLICY "athlete_kpis_daily_staff_read" ON public.coaching_athlete_kpis_daily
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_athlete_kpis_daily.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 3. Coaching alerts
CREATE TABLE IF NOT EXISTS public.coaching_alerts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id     uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day          date NOT NULL,
  alert_type   text NOT NULL,
  title        text NOT NULL,
  message      text,
  severity     text NOT NULL DEFAULT 'info'
                 CHECK (severity IN ('info', 'warning', 'critical')),
  resolved     boolean NOT NULL DEFAULT false,
  resolved_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_alert_dedup UNIQUE (group_id, user_id, day, alert_type)
);

ALTER TABLE public.coaching_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "alerts_staff_read" ON public.coaching_alerts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_alerts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

CREATE POLICY "alerts_staff_update" ON public.coaching_alerts
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_alerts.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- Grants
GRANT ALL ON TABLE public.coaching_kpis_daily TO authenticated;
GRANT ALL ON TABLE public.coaching_kpis_daily TO service_role;
GRANT ALL ON TABLE public.coaching_athlete_kpis_daily TO authenticated;
GRANT ALL ON TABLE public.coaching_athlete_kpis_daily TO service_role;
GRANT ALL ON TABLE public.coaching_alerts TO authenticated;
GRANT ALL ON TABLE public.coaching_alerts TO service_role;
