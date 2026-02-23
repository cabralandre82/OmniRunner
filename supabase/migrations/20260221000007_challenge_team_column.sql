-- ============================================================================
-- Omni Runner — Add `team` column to challenge_participants
-- Date: 2026-02-21
-- Sprint: Phase 97.2.0
-- Origin: Fix intra-assessoria team_vs_team challenges
-- ============================================================================
-- Previously, team membership was determined by group_id matching
-- team_a_group_id / team_b_group_id. This breaks when both teams are
-- from the same assessoria (group_id is identical for all participants).
--
-- The `team` column explicitly assigns each participant to 'A' or 'B',
-- independent of their coaching group.
-- ============================================================================

ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS team TEXT
    CHECK (team IS NULL OR team IN ('A', 'B'));

COMMENT ON COLUMN public.challenge_participants.team IS
  'Explicit team assignment (A or B) for team_vs_team challenges. NULL for 1v1/group challenges.';

CREATE INDEX IF NOT EXISTS idx_challenge_parts_team
  ON public.challenge_participants(challenge_id, team)
  WHERE team IS NOT NULL;
