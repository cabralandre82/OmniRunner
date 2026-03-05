-- ============================================================================
-- Workout Blocks V2: pace range, HR range, repeat blocks, rest type
-- DECISAO 136 — Structured Workout + .FIT Export
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. New columns on coaching_workout_blocks
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_workout_blocks
  ADD COLUMN IF NOT EXISTS target_pace_min_sec_per_km int,
  ADD COLUMN IF NOT EXISTS target_pace_max_sec_per_km int,
  ADD COLUMN IF NOT EXISTS target_hr_min int,
  ADD COLUMN IF NOT EXISTS target_hr_max int,
  ADD COLUMN IF NOT EXISTS repeat_count int;

-- HR range validation
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT chk_hr_min CHECK (target_hr_min IS NULL OR target_hr_min BETWEEN 40 AND 220);
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT chk_hr_max CHECK (target_hr_max IS NULL OR target_hr_max BETWEEN 40 AND 220);
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT chk_hr_range CHECK (
    target_hr_min IS NULL OR target_hr_max IS NULL OR target_hr_max >= target_hr_min
  );

-- Pace range validation (pace_min = faster = lower number, pace_max = slower = higher number)
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT chk_pace_range CHECK (
    target_pace_min_sec_per_km IS NULL
    OR target_pace_max_sec_per_km IS NULL
    OR target_pace_max_sec_per_km >= target_pace_min_sec_per_km
  );

-- Repeat count validation
ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT chk_repeat_count CHECK (repeat_count IS NULL OR repeat_count BETWEEN 1 AND 100);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. Expand block_type CHECK to include 'rest' and 'repeat'
-- ═══════════════════════════════════════════════════════════════════════════

-- Drop old constraint (auto-generated name from CREATE TABLE)
DO $$ BEGIN
  ALTER TABLE public.coaching_workout_blocks
    DROP CONSTRAINT IF EXISTS coaching_workout_blocks_block_type_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.coaching_workout_blocks
  ADD CONSTRAINT coaching_workout_blocks_block_type_check
  CHECK (block_type IN ('warmup', 'interval', 'recovery', 'cooldown', 'steady', 'rest', 'repeat'));

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. Backfill: copy legacy single-pace to pace range
-- ═══════════════════════════════════════════════════════════════════════════

UPDATE public.coaching_workout_blocks
SET
  target_pace_min_sec_per_km = target_pace_seconds_per_km,
  target_pace_max_sec_per_km = target_pace_seconds_per_km
WHERE target_pace_seconds_per_km IS NOT NULL
  AND target_pace_min_sec_per_km IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RLS: athlete can read blocks of their assigned templates
-- ═══════════════════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "athlete_blocks_select" ON public.coaching_workout_blocks;
CREATE POLICY "athlete_blocks_select"
  ON public.coaching_workout_blocks FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_workout_assignments a
      WHERE a.template_id = coaching_workout_blocks.template_id
        AND a.athlete_user_id = auth.uid()
    )
  );

-- Athletes can also read templates they have assignments for
DROP POLICY IF EXISTS "athlete_templates_select" ON public.coaching_workout_templates;
CREATE POLICY "athlete_templates_select"
  ON public.coaching_workout_templates FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_workout_assignments a
      WHERE a.template_id = coaching_workout_templates.id
        AND a.athlete_user_id = auth.uid()
    )
  );

COMMIT;
