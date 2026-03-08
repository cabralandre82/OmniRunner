-- L-04: Add UNIQUE constraint on park_activities to prevent duplicate entries
DO $$ BEGIN
  ALTER TABLE public.park_activities
    ADD CONSTRAINT park_activities_user_park_time_uniq
    UNIQUE (user_id, park_id, start_time);
EXCEPTION WHEN undefined_table THEN NULL;
          WHEN duplicate_object THEN NULL;
END $$;
