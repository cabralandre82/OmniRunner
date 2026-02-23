-- ── Team vs Team Challenges ──────────────────────────────────────────────────
-- Adds support for assessoria-vs-assessoria team challenges.
-- Each participant pays the same entry_fee_coins (enforced at challenge level).
-- Winning team splits the pool equally among its members.

-- 1. Expand challenge type to include team_vs_team
ALTER TABLE public.challenges
  DROP CONSTRAINT IF EXISTS challenges_type_check;

ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_type_check
    CHECK (type IN ('one_vs_one', 'group', 'team_vs_team'));

-- 2. Add team group references to challenges
ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS team_a_group_id UUID REFERENCES public.coaching_groups(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS team_b_group_id UUID REFERENCES public.coaching_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_challenges_team_a ON public.challenges(team_a_group_id)
  WHERE team_a_group_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_challenges_team_b ON public.challenges(team_b_group_id)
  WHERE team_b_group_id IS NOT NULL;

-- 3. Add group_id to challenge_participants so we know which team each athlete is on
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS group_id UUID REFERENCES public.coaching_groups(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_challenge_parts_group ON public.challenge_participants(group_id)
  WHERE group_id IS NOT NULL;

-- 4. Challenge team invites table (assessoria invites for team challenges)
CREATE TABLE IF NOT EXISTS public.challenge_team_invites (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id    UUID NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  to_group_id     UUID NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  invited_by      UUID NOT NULL REFERENCES auth.users(id),
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'accepted', 'declined')),
  responded_by    UUID REFERENCES auth.users(id),
  responded_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT challenge_team_invites_unique UNIQUE (challenge_id, to_group_id)
);

CREATE INDEX IF NOT EXISTS idx_challenge_team_invites_challenge
  ON public.challenge_team_invites(challenge_id, status);

CREATE INDEX IF NOT EXISTS idx_challenge_team_invites_group
  ON public.challenge_team_invites(to_group_id, status);

ALTER TABLE public.challenge_team_invites ENABLE ROW LEVEL SECURITY;

CREATE POLICY challenge_team_invites_select ON public.challenge_team_invites
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.user_id = auth.uid()
        AND (
          cm.group_id = challenge_team_invites.to_group_id
          OR cm.group_id = (
            SELECT c.team_a_group_id FROM public.challenges c
            WHERE c.id = challenge_team_invites.challenge_id
          )
        )
    )
  );
