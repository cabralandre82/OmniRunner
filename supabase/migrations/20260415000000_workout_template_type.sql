-- Add workout_type to coaching_workout_templates.
-- Templates created before this migration will default to 'free'.

ALTER TABLE public.coaching_workout_templates
  ADD COLUMN IF NOT EXISTS workout_type text NOT NULL DEFAULT 'free'
    CHECK (workout_type IN (
      'continuous','interval','regenerative','long_run',
      'strength','technique','test','free','race','brick'
    ));
