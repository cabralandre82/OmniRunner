-- ============================================================================
-- Migration: Ensure dedup constraints on all snapshot tables
--
-- The CREATE TABLE statements in 20260303200000 already define:
--   coaching_kpis_daily:          UNIQUE (group_id, day)
--   coaching_athlete_kpis_daily:  UNIQUE (group_id, user_id, day)
--   coaching_alerts:              UNIQUE (group_id, user_id, day, alert_type)
--
-- This migration is a safety net: add IF NOT EXISTS and verify the
-- PATCH_SET_BASED functions use ON CONFLICT correctly.
-- ============================================================================

-- 1. Snapshot group KPIs — one row per group per day
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_kpis_group_day'
  ) THEN
    ALTER TABLE public.coaching_kpis_daily
      ADD CONSTRAINT uq_kpis_group_day UNIQUE (group_id, day);
  END IF;
END $$;

-- 2. Snapshot athlete KPIs — one row per athlete per group per day
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_athlete_kpis_group_user_day'
  ) THEN
    ALTER TABLE public.coaching_athlete_kpis_daily
      ADD CONSTRAINT uq_athlete_kpis_group_user_day UNIQUE (group_id, user_id, day);
  END IF;
END $$;

-- 3. Alerts — one alert per type per athlete per group per day
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'uq_alert_dedup'
  ) THEN
    ALTER TABLE public.coaching_alerts
      ADD CONSTRAINT uq_alert_dedup UNIQUE (group_id, user_id, day, alert_type);
  END IF;
END $$;

-- ============================================================================
-- Verification: ON CONFLICT usage in compute functions
--
-- compute_coaching_kpis_daily:
--   INSERT ... ON CONFLICT (group_id, day) DO UPDATE SET ...    ✓ idempotent
--
-- compute_coaching_athlete_kpis_daily:
--   INSERT ... ON CONFLICT (group_id, user_id, day) DO UPDATE SET ...  ✓ idempotent
--
-- compute_coaching_alerts_daily:
--   INSERT ... ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING  ✓ no duplication
-- ============================================================================
