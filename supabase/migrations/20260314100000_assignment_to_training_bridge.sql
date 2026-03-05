-- ============================================================================
-- Bridge: workout assignments → training sessions for auto-attendance
-- When a structured workout is assigned, auto-create a training_session
-- with distance_target_m and pace range calculated from blocks.
-- DECISAO 136
-- ============================================================================

BEGIN;

-- Link column: which assignment originated this training session
ALTER TABLE public.coaching_training_sessions
  ADD COLUMN IF NOT EXISTS source_assignment_id uuid
    REFERENCES public.coaching_workout_assignments(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_training_sessions_assignment
  ON public.coaching_training_sessions (source_assignment_id)
  WHERE source_assignment_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- Trigger function: on workout assignment insert/update, sync to training_session
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_assignment_to_training()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_total_distance   double precision := 0;
  v_pace_min         double precision;
  v_pace_max         double precision;
  v_repeat_mult      int := 1;
  v_block            record;
  v_in_repeat        boolean := false;
  v_template_name    text;
BEGIN
  -- Get template name
  SELECT name INTO v_template_name
    FROM coaching_workout_templates
    WHERE id = NEW.template_id;

  -- Calculate totals from blocks
  FOR v_block IN
    SELECT block_type, distance_meters, duration_seconds,
           target_pace_min_sec_per_km, target_pace_max_sec_per_km,
           repeat_count
      FROM coaching_workout_blocks
      WHERE template_id = NEW.template_id
      ORDER BY order_index
  LOOP
    IF v_block.block_type = 'repeat' THEN
      v_repeat_mult := COALESCE(v_block.repeat_count, 1);
      v_in_repeat := true;
      CONTINUE;
    END IF;

    IF v_block.block_type NOT IN ('rest') AND v_block.distance_meters IS NOT NULL THEN
      IF v_in_repeat THEN
        v_total_distance := v_total_distance + (v_block.distance_meters * v_repeat_mult);
      ELSE
        v_total_distance := v_total_distance + v_block.distance_meters;
      END IF;
    END IF;

    -- Track pace range from active blocks (interval, steady)
    IF v_block.block_type IN ('interval', 'steady') THEN
      IF v_block.target_pace_min_sec_per_km IS NOT NULL THEN
        IF v_pace_min IS NULL OR v_block.target_pace_min_sec_per_km < v_pace_min THEN
          v_pace_min := v_block.target_pace_min_sec_per_km;
        END IF;
      END IF;
      IF v_block.target_pace_max_sec_per_km IS NOT NULL THEN
        IF v_pace_max IS NULL OR v_block.target_pace_max_sec_per_km > v_pace_max THEN
          v_pace_max := v_block.target_pace_max_sec_per_km;
        END IF;
      END IF;
    END IF;

    -- Reset repeat multiplier after a non-repeat block following repeat
    IF v_block.block_type = 'recovery' AND v_in_repeat THEN
      -- Still in repeat group (interval + recovery pattern)
      NULL;
    ELSIF v_block.block_type NOT IN ('interval', 'recovery') THEN
      v_in_repeat := false;
      v_repeat_mult := 1;
    END IF;
  END LOOP;

  -- Only create training session if we have distance data
  IF v_total_distance > 0 THEN
    INSERT INTO coaching_training_sessions (
      group_id, created_by, title, starts_at,
      distance_target_m, pace_min_sec_km, pace_max_sec_km,
      source_assignment_id, status
    ) VALUES (
      NEW.group_id,
      NEW.created_by,
      COALESCE(v_template_name, 'Treino'),
      NEW.scheduled_date::timestamptz,
      v_total_distance,
      v_pace_min,
      v_pace_max,
      NEW.id,
      'scheduled'
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$fn$;

-- Trigger on assignment insert
DROP TRIGGER IF EXISTS trg_workout_assignment_to_training ON public.coaching_workout_assignments;
CREATE TRIGGER trg_workout_assignment_to_training
  AFTER INSERT ON public.coaching_workout_assignments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_assignment_to_training();

COMMIT;
