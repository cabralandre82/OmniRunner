-- Liga de Assessorias — inter-group seasonal competition
-- Reference: ROADMAP_NEXT.md §2 Liga de Assessorias

BEGIN;

-- ── 1. league_seasons ──────────────────────────────────────────────────────
-- A season runs for a quarter (or custom period). Only one active at a time.

CREATE TABLE IF NOT EXISTS public.league_seasons (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  start_at_ms   BIGINT NOT NULL,
  end_at_ms     BIGINT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'upcoming'
    CHECK (status IN ('upcoming', 'active', 'completed')),
  created_at_ms BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT,

  CONSTRAINT league_seasons_date_order CHECK (end_at_ms > start_at_ms)
);

ALTER TABLE public.league_seasons ENABLE ROW LEVEL SECURITY;

CREATE POLICY league_seasons_read ON public.league_seasons
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── 2. league_enrollments ──────────────────────────────────────────────────
-- An assessoria enrolls in a season. Auto-enroll or staff-triggered.

CREATE TABLE IF NOT EXISTS public.league_enrollments (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id     UUID NOT NULL REFERENCES public.league_seasons(id) ON DELETE CASCADE,
  group_id      UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  enrolled_at_ms BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT,

  UNIQUE(season_id, group_id)
);

CREATE INDEX idx_league_enrollments_season ON public.league_enrollments(season_id);

ALTER TABLE public.league_enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY league_enrollments_read ON public.league_enrollments
  FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY league_enrollments_staff_insert ON public.league_enrollments
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = league_enrollments.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

-- ── 3. league_snapshots ────────────────────────────────────────────────────
-- Weekly snapshot per group: score, rank, sub-metrics.

CREATE TABLE IF NOT EXISTS public.league_snapshots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id       UUID NOT NULL REFERENCES public.league_seasons(id) ON DELETE CASCADE,
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  week_key        TEXT NOT NULL,
  total_km        DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_sessions  INTEGER NOT NULL DEFAULT 0,
  active_members  INTEGER NOT NULL DEFAULT 0,
  total_members   INTEGER NOT NULL DEFAULT 0,
  challenge_wins  INTEGER NOT NULL DEFAULT 0,
  week_score      DOUBLE PRECISION NOT NULL DEFAULT 0,
  cumulative_score DOUBLE PRECISION NOT NULL DEFAULT 0,
  rank            INTEGER NOT NULL DEFAULT 0,
  prev_rank       INTEGER,
  created_at_ms   BIGINT NOT NULL DEFAULT (EXTRACT(EPOCH FROM now()) * 1000)::BIGINT,

  UNIQUE(season_id, group_id, week_key)
);

CREATE INDEX idx_league_snapshots_season_week ON public.league_snapshots(season_id, week_key);
CREATE INDEX idx_league_snapshots_group ON public.league_snapshots(group_id);

ALTER TABLE public.league_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY league_snapshots_read ON public.league_snapshots
  FOR SELECT USING (auth.uid() IS NOT NULL);

-- Service role writes via Edge Functions
CREATE POLICY league_snapshots_service_write ON public.league_snapshots
  FOR INSERT WITH CHECK (true);

CREATE POLICY league_snapshots_service_update ON public.league_snapshots
  FOR UPDATE USING (true);

COMMIT;
