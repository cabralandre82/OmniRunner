-- Challenge goal redesign: replace metric with goal, remove team_vs_team
-- Reference: DECISAO 087

BEGIN;

-- 1. Add goal column
ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS goal TEXT;

-- 2. Migrate existing data
UPDATE public.challenges SET goal = 'most_distance' WHERE metric = 'distance' AND goal IS NULL;
UPDATE public.challenges SET goal = 'best_pace_at_distance' WHERE metric = 'pace' AND goal IS NULL;
UPDATE public.challenges SET goal = 'most_distance' WHERE metric = 'time' AND goal IS NULL;
UPDATE public.challenges SET goal = 'most_distance' WHERE goal IS NULL;

-- 3. Make goal NOT NULL with CHECK
ALTER TABLE public.challenges
  ALTER COLUMN goal SET NOT NULL;

ALTER TABLE public.challenges
  ADD CONSTRAINT chk_challenges_goal
  CHECK (goal IN ('fastest_at_distance', 'most_distance', 'best_pace_at_distance', 'collective_distance'));

-- 4. Update type constraint to remove team_vs_team
-- Convert any existing team_vs_team to group
UPDATE public.challenges SET type = 'group' WHERE type = 'team_vs_team';

ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_type_check;
ALTER TABLE public.challenges
  ADD CONSTRAINT challenges_type_check CHECK (type IN ('one_vs_one', 'group'));

-- 5. Drop old metric CHECK (keep column for backward compat during transition)
ALTER TABLE public.challenges DROP CONSTRAINT IF EXISTS challenges_metric_check;

-- 6. Remove team columns from challenge_participants (nullable, safe to keep)
-- We keep the columns to avoid breaking existing data, just stop using them.

-- 7. Remove team columns from challenges (keep for data preservation)
-- team_a_group_id, team_b_group_id are nullable, safe to leave.

COMMIT;
