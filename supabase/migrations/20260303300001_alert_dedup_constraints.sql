-- ============================================================================
-- Migration: Ensure dedup constraints on all snapshot tables
-- Skips gracefully if tables don't exist yet.
-- ============================================================================

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_kpis_daily') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_kpis_group_day') THEN
      ALTER TABLE public.coaching_kpis_daily
        ADD CONSTRAINT uq_kpis_group_day UNIQUE (group_id, day);
    END IF;
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_athlete_kpis_daily') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_athlete_kpis_group_user_day') THEN
      ALTER TABLE public.coaching_athlete_kpis_daily
        ADD CONSTRAINT uq_athlete_kpis_group_user_day UNIQUE (group_id, user_id, day);
    END IF;
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_alerts') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uq_alert_dedup') THEN
      ALTER TABLE public.coaching_alerts
        ADD CONSTRAINT uq_alert_dedup UNIQUE (group_id, user_id, day, alert_type);
    END IF;
  END IF;
END $$;
