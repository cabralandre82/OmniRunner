-- ============================================================================
-- Analytics tables for Coaching Intelligence Engine (Phase 16)
-- Reference: contracts/analytics_api.md
-- ============================================================================

-- 1. analytics_submissions — idempotency guard for submitAnalyticsData
CREATE TABLE IF NOT EXISTS public.analytics_submissions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID NOT NULL UNIQUE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL,
  distance_m      DOUBLE PRECISION NOT NULL,
  moving_ms       BIGINT NOT NULL,
  avg_pace_sec_per_km DOUBLE PRECISION,
  avg_bpm         INTEGER,
  start_time_ms   BIGINT NOT NULL,
  end_time_ms     BIGINT NOT NULL,
  processed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_submissions_user_group
  ON public.analytics_submissions(user_id, group_id);
CREATE INDEX IF NOT EXISTS idx_submissions_group_time
  ON public.analytics_submissions(group_id, start_time_ms DESC);

ALTER TABLE public.analytics_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_inserts_own_submissions"
  ON public.analytics_submissions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "user_reads_own_submissions"
  ON public.analytics_submissions FOR SELECT
  USING (auth.uid() = user_id);

-- 2. athlete_baselines
CREATE TABLE IF NOT EXISTS public.athlete_baselines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL,
  metric          TEXT NOT NULL,
  value           DOUBLE PRECISION NOT NULL,
  sample_size     INTEGER NOT NULL,
  window_start_ms BIGINT NOT NULL,
  window_end_ms   BIGINT NOT NULL,
  computed_at_ms  BIGINT NOT NULL,

  UNIQUE(user_id, group_id, metric)
);

CREATE INDEX IF NOT EXISTS idx_baselines_group
  ON public.athlete_baselines(group_id);
CREATE INDEX IF NOT EXISTS idx_baselines_user_group
  ON public.athlete_baselines(user_id, group_id);

ALTER TABLE public.athlete_baselines ENABLE ROW LEVEL SECURITY;

CREATE POLICY "baselines_read" ON public.athlete_baselines
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = athlete_baselines.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );

-- Edge Function uses service_role key which bypasses RLS automatically.
-- No additional policy needed for server-side writes.

-- 3. athlete_trends
CREATE TABLE IF NOT EXISTS public.athlete_trends (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL,
  metric          TEXT NOT NULL,
  period          TEXT NOT NULL,
  direction       TEXT NOT NULL,
  current_value   DOUBLE PRECISION NOT NULL,
  baseline_value  DOUBLE PRECISION NOT NULL,
  change_percent  DOUBLE PRECISION NOT NULL,
  data_points     INTEGER NOT NULL,
  latest_period_key TEXT NOT NULL,
  analyzed_at_ms  BIGINT NOT NULL,

  UNIQUE(user_id, group_id, metric, period)
);

CREATE INDEX IF NOT EXISTS idx_trends_group
  ON public.athlete_trends(group_id);
CREATE INDEX IF NOT EXISTS idx_trends_user_group
  ON public.athlete_trends(user_id, group_id);
CREATE INDEX IF NOT EXISTS idx_trends_direction
  ON public.athlete_trends(group_id, direction);

ALTER TABLE public.athlete_trends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "trends_read" ON public.athlete_trends
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = athlete_trends.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );

-- Edge Function uses service_role key which bypasses RLS automatically.

-- 4. coach_insights
CREATE TABLE IF NOT EXISTS public.coach_insights (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            UUID NOT NULL,
  target_user_id      UUID,
  target_display_name TEXT,
  type                TEXT NOT NULL,
  priority            TEXT NOT NULL,
  title               TEXT NOT NULL,
  message             TEXT NOT NULL,
  metric              TEXT,
  reference_value     DOUBLE PRECISION,
  change_percent      DOUBLE PRECISION,
  related_entity_id   UUID,
  created_at_ms       BIGINT NOT NULL,
  read_at_ms          BIGINT,
  dismissed           BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS idx_insights_group
  ON public.coach_insights(group_id, created_at_ms DESC);
CREATE INDEX IF NOT EXISTS idx_insights_unread
  ON public.coach_insights(group_id) WHERE read_at_ms IS NULL AND dismissed = false;
CREATE INDEX IF NOT EXISTS idx_insights_type
  ON public.coach_insights(group_id, type);

ALTER TABLE public.coach_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "coach_reads_insights" ON public.coach_insights
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );

CREATE POLICY "coach_updates_insights" ON public.coach_insights
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('coach', 'assistant')
    )
  );

-- Edge Function uses service_role key which bypasses RLS automatically.
