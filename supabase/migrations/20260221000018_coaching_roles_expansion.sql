-- ============================================================================
-- Omni Runner — Expand coaching_members roles for institutional model
-- Date: 2026-02-22
-- Origin: DECISAO 038 / Phase 18 (Assessoria Ecosystem Core)
-- ============================================================================
-- Migrates existing roles:
--   coach     -> admin_master
--   assistant -> assistente
--   athlete   -> atleta
--
-- New valid set: admin_master, professor, assistente, atleta
-- Backward-safe: old rows are updated in-place; no data loss.
-- ============================================================================

BEGIN;

-- ── 1. Drop the existing CHECK constraint ────────────────────────────────────

ALTER TABLE public.coaching_members
  DROP CONSTRAINT IF EXISTS coaching_members_role_check;

-- ── 2. Migrate existing data ─────────────────────────────────────────────────

UPDATE public.coaching_members SET role = 'admin_master' WHERE role = 'coach';
UPDATE public.coaching_members SET role = 'assistente'   WHERE role = 'assistant';
UPDATE public.coaching_members SET role = 'atleta'       WHERE role = 'athlete';

-- ── 3. Add new CHECK with expanded roles + update default ────────────────────

ALTER TABLE public.coaching_members
  ADD CONSTRAINT coaching_members_role_check
  CHECK (role IN ('admin_master', 'professor', 'assistente', 'atleta'));

ALTER TABLE public.coaching_members
  ALTER COLUMN role SET DEFAULT 'atleta';

-- ── 4. Update RLS policies that filter by role ───────────────────────────────

-- 4a. coaching_invites_read (from 20260218_full_schema.sql)
DROP POLICY IF EXISTS "coaching_invites_read" ON public.coaching_invites;
CREATE POLICY "coaching_invites_read" ON public.coaching_invites
  FOR SELECT USING (
    auth.uid() = invited_user_id
    OR EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_invites.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- 4b. baselines_read (from 20260219_analytics_tables.sql)
DROP POLICY IF EXISTS "baselines_read" ON public.athlete_baselines;
CREATE POLICY "baselines_read" ON public.athlete_baselines
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = athlete_baselines.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- 4c. trends_read (from 20260219_analytics_tables.sql)
DROP POLICY IF EXISTS "trends_read" ON public.athlete_trends;
CREATE POLICY "trends_read" ON public.athlete_trends
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = athlete_trends.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- 4d. coach_reads_insights (from 20260219_analytics_tables.sql)
DROP POLICY IF EXISTS "coach_reads_insights" ON public.coach_insights;
CREATE POLICY "coach_reads_insights" ON public.coach_insights
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'professor', 'assistente')
    )
  );

-- 4e. coach_updates_insights (from 20260219_analytics_tables.sql)
DROP POLICY IF EXISTS "coach_updates_insights" ON public.coach_insights;
CREATE POLICY "coach_updates_insights" ON public.coach_insights
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'professor', 'assistente')
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members
      WHERE coaching_members.group_id = coach_insights.group_id
        AND coaching_members.user_id = auth.uid()
        AND coaching_members.role IN ('admin_master', 'professor', 'assistente')
    )
  );

COMMIT;
