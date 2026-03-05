-- ============================================================================
-- OS-04: Performance indexes for portal queries (paginação + filtros)
-- Skips gracefully if tables don't exist yet.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_sessions_user_start
  ON public.sessions (user_id, start_time_ms DESC);

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_kpis_daily') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_kpis_daily_group_day ON public.coaching_kpis_daily (group_id, day DESC)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_athlete_kpis_daily') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_athlete_kpis_daily_group_day ON public.coaching_athlete_kpis_daily (group_id, day DESC)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_athlete_kpis_daily_group_user_day ON public.coaching_athlete_kpis_daily (group_id, user_id, day DESC)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_alerts') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_alerts_group_resolved ON public.coaching_alerts (group_id, resolved, day DESC)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_alerts_group_user ON public.coaching_alerts (group_id, user_id, day DESC)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_training_attendance') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_attendance_group_checked ON public.coaching_training_attendance (group_id, checked_at DESC)';
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_attendance_session_status ON public.coaching_training_attendance (session_id, status)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_announcement_reads') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_announcement_reads_ann_user ON public.coaching_announcement_reads (announcement_id, user_id)';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='coaching_member_status') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_member_status_group_status ON public.coaching_member_status (group_id, status)';
  END IF;
END $$;
