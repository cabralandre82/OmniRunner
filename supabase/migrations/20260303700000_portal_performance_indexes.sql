-- ============================================================================
-- OS-04: Performance indexes for portal queries (paginação + filtros)
-- Idempotent (IF NOT EXISTS).
-- ============================================================================

BEGIN;

-- ── Sessions (engagement queries) ──
CREATE INDEX IF NOT EXISTS idx_sessions_user_start
  ON public.sessions (user_id, start_time_ms DESC);

-- ── KPI Snapshots (engagement/retention trends) ──
CREATE INDEX IF NOT EXISTS idx_kpis_daily_group_day
  ON public.coaching_kpis_daily (group_id, day DESC);

CREATE INDEX IF NOT EXISTS idx_athlete_kpis_daily_group_day
  ON public.coaching_athlete_kpis_daily (group_id, day DESC);

CREATE INDEX IF NOT EXISTS idx_athlete_kpis_daily_group_user_day
  ON public.coaching_athlete_kpis_daily (group_id, user_id, day DESC);

-- ── Alerts (risk panel queries) ──
CREATE INDEX IF NOT EXISTS idx_alerts_group_resolved
  ON public.coaching_alerts (group_id, resolved, day DESC);

CREATE INDEX IF NOT EXISTS idx_alerts_group_user
  ON public.coaching_alerts (group_id, user_id, day DESC);

-- ── Attendance (attendance analytics) ──
CREATE INDEX IF NOT EXISTS idx_attendance_group_checked
  ON public.coaching_training_attendance (group_id, checked_at DESC);

CREATE INDEX IF NOT EXISTS idx_attendance_session_status
  ON public.coaching_training_attendance (session_id, status);

-- ── Announcements (read rate queries) ──
CREATE INDEX IF NOT EXISTS idx_announcement_reads_ann_user
  ON public.coaching_announcement_reads (announcement_id, user_id);

-- ── Member status (CRM filters) ──
CREATE INDEX IF NOT EXISTS idx_member_status_group_status
  ON public.coaching_member_status (group_id, status);

COMMIT;
