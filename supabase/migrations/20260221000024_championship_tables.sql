-- ============================================================================
-- Omni Runner — Championship system (inter-assessoria competitions)
-- Date: 2026-02-22
-- Sprint: 17.9.0
-- Origin: DECISAO 038 / Phase 18 — Module H (Championship Context)
-- ============================================================================
-- Assessoria host creates a championship, invites other groups,
-- athletes join via badge (optional) or direct enrollment.
-- Badges always expire at championship end_at.
-- ============================================================================

BEGIN;

-- ── 1. championship_templates ────────────────────────────────────────────────
-- Reusable templates for recurring championships

CREATE TABLE IF NOT EXISTS public.championship_templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_group_id  UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  metric          TEXT NOT NULL CHECK (metric IN ('distance','time','pace','sessions','elevation')),
  duration_days   INTEGER NOT NULL CHECK (duration_days > 0),
  requires_badge  BOOLEAN NOT NULL DEFAULT false,
  max_participants INTEGER,
  rules_json      JSONB NOT NULL DEFAULT '{}',
  created_by      UUID NOT NULL REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_championship_templates_owner
  ON public.championship_templates(owner_group_id);

ALTER TABLE public.championship_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY championship_templates_select ON public.championship_templates
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = championship_templates.owner_group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

-- ── 2. championships ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.championships (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id     UUID REFERENCES public.championship_templates(id) ON DELETE SET NULL,
  host_group_id   UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  metric          TEXT NOT NULL CHECK (metric IN ('distance','time','pace','sessions','elevation')),
  requires_badge  BOOLEAN NOT NULL DEFAULT false,
  max_participants INTEGER,
  start_at        TIMESTAMPTZ NOT NULL,
  end_at          TIMESTAMPTZ NOT NULL,
  status          TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'open', 'active', 'completed', 'cancelled')),
  rules_json      JSONB NOT NULL DEFAULT '{}',
  created_by      UUID NOT NULL REFERENCES auth.users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT championships_date_order CHECK (end_at > start_at)
);

CREATE INDEX IF NOT EXISTS idx_championships_host
  ON public.championships(host_group_id, status);

CREATE INDEX IF NOT EXISTS idx_championships_status
  ON public.championships(status)
  WHERE status IN ('open', 'active');

ALTER TABLE public.championships ENABLE ROW LEVEL SECURITY;

-- All authenticated users can see open/active championships
CREATE POLICY championships_select ON public.championships
  FOR SELECT USING (
    status IN ('open', 'active', 'completed')
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = championships.host_group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

-- ── 3. championship_invites ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.championship_invites (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  championship_id UUID NOT NULL REFERENCES public.championships(id) ON DELETE CASCADE,
  to_group_id     UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined', 'revoked')),
  invited_by      UUID NOT NULL REFERENCES auth.users(id),
  responded_by    UUID REFERENCES auth.users(id),
  responded_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT championship_invites_unique UNIQUE (championship_id, to_group_id)
);

CREATE INDEX IF NOT EXISTS idx_championship_invites_champ
  ON public.championship_invites(championship_id, status);

CREATE INDEX IF NOT EXISTS idx_championship_invites_group
  ON public.championship_invites(to_group_id, status);

ALTER TABLE public.championship_invites ENABLE ROW LEVEL SECURITY;

-- Staff of host or invited group can see invites
CREATE POLICY championship_invites_select ON public.championship_invites
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
        AND (
          cm.group_id = championship_invites.to_group_id
          OR cm.group_id = (
            SELECT c.host_group_id FROM public.championships c
            WHERE c.id = championship_invites.championship_id
          )
        )
    )
  );

-- ── 4. championship_participants ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.championship_participants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  championship_id UUID NOT NULL REFERENCES public.championships(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  group_id        UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  status          TEXT NOT NULL DEFAULT 'enrolled'
    CHECK (status IN ('enrolled', 'active', 'completed', 'withdrawn', 'disqualified')),
  progress_value  DOUBLE PRECISION NOT NULL DEFAULT 0,
  final_rank      INTEGER,
  joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT championship_participants_unique UNIQUE (championship_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_championship_participants_champ
  ON public.championship_participants(championship_id, status);

CREATE INDEX IF NOT EXISTS idx_championship_participants_user
  ON public.championship_participants(user_id);

ALTER TABLE public.championship_participants ENABLE ROW LEVEL SECURITY;

-- Participants of open/active/completed championships are visible to all authenticated
CREATE POLICY championship_participants_select ON public.championship_participants
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.championships c
      WHERE c.id = championship_participants.championship_id
        AND c.status IN ('open', 'active', 'completed')
    )
  );

-- ── 5. championship_badges ───────────────────────────────────────────────────
-- Temporary participation pass; always expires at championship end_at

CREATE TABLE IF NOT EXISTS public.championship_badges (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  championship_id UUID NOT NULL REFERENCES public.championships(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES auth.users(id),
  intent_id       UUID REFERENCES public.token_intents(id),
  granted_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,
  CONSTRAINT championship_badges_unique UNIQUE (championship_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_championship_badges_user
  ON public.championship_badges(user_id, expires_at);

ALTER TABLE public.championship_badges ENABLE ROW LEVEL SECURITY;

CREATE POLICY championship_badges_own ON public.championship_badges
  FOR SELECT USING (user_id = auth.uid());

-- Staff of the host group can also see all badges for their championships
CREATE POLICY championship_badges_staff ON public.championship_badges
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.championships c
      JOIN public.coaching_members cm ON cm.group_id = c.host_group_id
      WHERE c.id = championship_badges.championship_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor')
    )
  );

COMMIT;
