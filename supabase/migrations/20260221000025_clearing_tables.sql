-- ============================================================================
-- Omni Runner — Clearing system for cross-assessoria challenge prizes
-- Date: 2026-02-22
-- Sprint: 17.8.0
-- Origin: DECISAO 038 / Phase 18 — Module C (Cross-Institution Clearing)
-- ============================================================================
-- Flow:
--   1. settle-challenge creates pending prizes for cross-assessoria winners
--   2. A weekly cron aggregates pending items into clearing_cases (group-pair)
--   3. Losing group staff calls clearing-confirm-sent
--   4. Winning group staff calls clearing-confirm-received
--   5. Both confirmed → PAID_CONFIRMED → pending_coins released to balance
--   6. Deadline 7 days; after that → EXPIRED (manual resolution)
-- ============================================================================

BEGIN;

-- ── 1. clearing_weeks ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.clearing_weeks (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  start_date DATE NOT NULL,
  end_date   DATE NOT NULL,
  status     TEXT NOT NULL DEFAULT 'OPEN'
    CHECK (status IN ('OPEN', 'CLOSED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT clearing_weeks_date_order CHECK (end_date > start_date)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_clearing_weeks_dates
  ON public.clearing_weeks(start_date, end_date);

ALTER TABLE public.clearing_weeks ENABLE ROW LEVEL SECURITY;

CREATE POLICY clearing_weeks_select ON public.clearing_weeks
  FOR SELECT USING (true);

-- ── 2. clearing_cases ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.clearing_cases (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  week_id       UUID NOT NULL REFERENCES public.clearing_weeks(id) ON DELETE CASCADE,
  from_group_id UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  to_group_id   UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  tokens_total  INTEGER NOT NULL CHECK (tokens_total > 0),
  status        TEXT NOT NULL DEFAULT 'OPEN'
    CHECK (status IN ('OPEN', 'SENT_CONFIRMED', 'PAID_CONFIRMED', 'DISPUTED', 'EXPIRED')),
  deadline_at   TIMESTAMPTZ NOT NULL,
  sent_by       UUID REFERENCES auth.users(id),
  sent_at       TIMESTAMPTZ,
  received_by   UUID REFERENCES auth.users(id),
  received_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT clearing_cases_groups_differ CHECK (from_group_id != to_group_id)
);

CREATE INDEX IF NOT EXISTS idx_clearing_cases_week
  ON public.clearing_cases(week_id);

CREATE INDEX IF NOT EXISTS idx_clearing_cases_from_group
  ON public.clearing_cases(from_group_id);

CREATE INDEX IF NOT EXISTS idx_clearing_cases_to_group
  ON public.clearing_cases(to_group_id);

CREATE INDEX IF NOT EXISTS idx_clearing_cases_status
  ON public.clearing_cases(status)
  WHERE status IN ('OPEN', 'SENT_CONFIRMED');

ALTER TABLE public.clearing_cases ENABLE ROW LEVEL SECURITY;

-- Staff of either group can see their cases
CREATE POLICY clearing_cases_select ON public.clearing_cases
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND (cm.group_id = clearing_cases.from_group_id OR cm.group_id = clearing_cases.to_group_id)
    )
  );

-- ── 3. clearing_case_items ───────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.clearing_case_items (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id        UUID NOT NULL REFERENCES public.clearing_cases(id) ON DELETE CASCADE,
  challenge_id   UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  winner_user_id UUID NOT NULL REFERENCES auth.users(id),
  loser_user_id  UUID NOT NULL REFERENCES auth.users(id),
  amount         INTEGER NOT NULL CHECK (amount > 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clearing_case_items_case
  ON public.clearing_case_items(case_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_clearing_case_items_challenge_winner
  ON public.clearing_case_items(challenge_id, winner_user_id);

ALTER TABLE public.clearing_case_items ENABLE ROW LEVEL SECURITY;

-- Staff can see items for their cases
CREATE POLICY clearing_case_items_select ON public.clearing_case_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.clearing_cases cc
      JOIN public.coaching_members cm ON cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND (cm.group_id = cc.from_group_id OR cm.group_id = cc.to_group_id)
      WHERE cc.id = clearing_case_items.case_id
    )
  );

-- ── 4. clearing_case_events ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.clearing_case_events (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_id    UUID NOT NULL REFERENCES public.clearing_cases(id) ON DELETE CASCADE,
  actor_id   UUID NOT NULL REFERENCES auth.users(id),
  event_type TEXT NOT NULL
    CHECK (event_type IN ('CREATED', 'SENT_CONFIRMED', 'RECEIVED_CONFIRMED', 'DISPUTED', 'EXPIRED', 'CLEARED')),
  metadata   JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_clearing_case_events_case
  ON public.clearing_case_events(case_id);

ALTER TABLE public.clearing_case_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY clearing_case_events_select ON public.clearing_case_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.clearing_cases cc
      JOIN public.coaching_members cm ON cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND (cm.group_id = cc.from_group_id OR cm.group_id = cc.to_group_id)
      WHERE cc.id = clearing_case_events.case_id
    )
  );

COMMIT;
