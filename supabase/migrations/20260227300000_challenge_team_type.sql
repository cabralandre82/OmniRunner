-- Add 'team' challenge type for group-vs-group (Team A vs Team B).
-- Not tied to assessorias — creator freely assigns participants to teams.
-- Reference: DECISAO 088

BEGIN;

-- 1. Update type CHECK to include 'team'
ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_type_check;
ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_type_check CHECK (type IN ('one_vs_one', 'group', 'team'));

-- 2. Ensure challenge_participants has a 'team' column
ALTER TABLE public.challenge_participants
  ADD COLUMN IF NOT EXISTS team TEXT;

-- 3. CHECK constraint on team values
ALTER TABLE public.challenge_participants
  ADD CONSTRAINT chk_participant_team CHECK (team IS NULL OR team IN ('A', 'B'));

COMMIT;
