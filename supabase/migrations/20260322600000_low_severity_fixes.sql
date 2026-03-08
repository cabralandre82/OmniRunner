-- ============================================================================
-- LOW severity fixes — P3
-- ============================================================================

-- L-01: Add CHECK constraint on workout_delivery_events.type
-- Known types: MARK_PUBLISHED, ATHLETE_CONFIRMED, ATHLETE_FAILED
DO $$ BEGIN
  ALTER TABLE public.workout_delivery_events
    ADD CONSTRAINT delivery_events_type_check
    CHECK (type IN ('MARK_PUBLISHED','ATHLETE_CONFIRMED','ATHLETE_FAILED'));
EXCEPTION WHEN undefined_table THEN NULL;
          WHEN duplicate_object THEN NULL;
END $$;

-- L-02: Add max-length CHECK on coaching_announcements.body (10 000 chars)
DO $$ BEGIN
  ALTER TABLE public.coaching_announcements
    ADD CONSTRAINT announcements_body_max_length
    CHECK (length(body) <= 10000);
EXCEPTION WHEN undefined_table THEN NULL;
          WHEN duplicate_object THEN NULL;
END $$;

-- L-03: Tighten missions RLS — replace USING(true) with authenticated-only
DO $$ BEGIN
  DROP POLICY IF EXISTS "missions_read_all" ON public.missions;
  DROP POLICY IF EXISTS "missions_read_authenticated" ON public.missions;
  CREATE POLICY "missions_read_authenticated" ON public.missions
    FOR SELECT USING (auth.role() = 'authenticated');
EXCEPTION WHEN undefined_table THEN NULL;
END $$;