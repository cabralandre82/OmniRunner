-- ============================================================================
-- BLOCO A: Workout Builder
-- Tables, indexes, RLS, and RPCs for workout templates, blocks, assignments.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_workout_templates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name        text NOT NULL CHECK (length(trim(name)) >= 2 AND length(trim(name)) <= 120),
  description text,
  created_by  uuid NOT NULL REFERENCES auth.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_workout_blocks (
  id                         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id                uuid NOT NULL REFERENCES public.coaching_workout_templates(id) ON DELETE CASCADE,
  order_index                int NOT NULL,
  block_type                 text NOT NULL
    CHECK (block_type IN ('warmup', 'interval', 'recovery', 'cooldown', 'steady')),
  duration_seconds           int,
  distance_meters            int,
  target_pace_seconds_per_km int,
  target_hr_zone             int CHECK (target_hr_zone IS NULL OR target_hr_zone BETWEEN 1 AND 5),
  rpe_target                 int CHECK (rpe_target IS NULL OR rpe_target BETWEEN 1 AND 10),
  notes                      text,
  created_at                 timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.coaching_workout_assignments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id        uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id uuid NOT NULL REFERENCES auth.users(id),
  template_id     uuid NOT NULL REFERENCES public.coaching_workout_templates(id) ON DELETE CASCADE,
  scheduled_date  date NOT NULL,
  status          text NOT NULL DEFAULT 'planned'
    CHECK (status IN ('planned', 'completed', 'missed')),
  version         int NOT NULL DEFAULT 1,
  notes           text,
  created_by      uuid NOT NULL REFERENCES auth.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_assignment_athlete_date UNIQUE (athlete_user_id, scheduled_date)
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_workout_templates_group
  ON public.coaching_workout_templates (group_id);

CREATE INDEX IF NOT EXISTS idx_workout_blocks_template
  ON public.coaching_workout_blocks (template_id, order_index);

CREATE INDEX IF NOT EXISTS idx_workout_assignments_group_date
  ON public.coaching_workout_assignments (group_id, scheduled_date DESC);

CREATE INDEX IF NOT EXISTS idx_workout_assignments_athlete
  ON public.coaching_workout_assignments (athlete_user_id, scheduled_date DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_workout_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_workout_assignments ENABLE ROW LEVEL SECURITY;

-- 3.1 Templates: staff can read
DROP POLICY IF EXISTS "staff_templates_select" ON public.coaching_workout_templates;
CREATE POLICY "staff_templates_select"
  ON public.coaching_workout_templates FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_templates.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.2 Templates: staff can insert
DROP POLICY IF EXISTS "staff_templates_insert" ON public.coaching_workout_templates;
CREATE POLICY "staff_templates_insert"
  ON public.coaching_workout_templates FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_templates.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.3 Templates: staff can update
DROP POLICY IF EXISTS "staff_templates_update" ON public.coaching_workout_templates;
CREATE POLICY "staff_templates_update"
  ON public.coaching_workout_templates FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_templates.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.4 Templates: staff can delete
DROP POLICY IF EXISTS "staff_templates_delete" ON public.coaching_workout_templates;
CREATE POLICY "staff_templates_delete"
  ON public.coaching_workout_templates FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_templates.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.5 Blocks: staff full access via template ownership
DROP POLICY IF EXISTS "staff_blocks_all" ON public.coaching_workout_blocks;
CREATE POLICY "staff_blocks_all"
  ON public.coaching_workout_blocks FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_workout_templates t
      JOIN public.coaching_members cm ON cm.group_id = t.group_id
      WHERE t.id = coaching_workout_blocks.template_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.6 Assignments: staff full access
DROP POLICY IF EXISTS "staff_assignments_all" ON public.coaching_workout_assignments;
CREATE POLICY "staff_assignments_all"
  ON public.coaching_workout_assignments FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_assignments.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 3.7 Assignments: athlete can read own assignments
DROP POLICY IF EXISTS "athlete_assignments_select" ON public.coaching_workout_assignments;
CREATE POLICY "athlete_assignments_select"
  ON public.coaching_workout_assignments FOR SELECT USING (
    athlete_user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_assignments.group_id
        AND cm.user_id = auth.uid()
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 fn_assign_workout: idempotent workout assignment with validation
CREATE OR REPLACE FUNCTION public.fn_assign_workout(
  p_template_id     uuid,
  p_athlete_user_id uuid,
  p_scheduled_date  date,
  p_notes           text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid           uuid := auth.uid();
  v_group_id      uuid;
  v_caller_role   text;
  v_athlete_role  text;
  v_assignment_id uuid;
BEGIN
  -- Get template group
  SELECT t.group_id INTO v_group_id
    FROM coaching_workout_templates t
    WHERE t.id = p_template_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPLATE_NOT_FOUND', 'message', 'Template não encontrado');
  END IF;

  -- Check caller is staff
  SELECT cm.role INTO v_caller_role
    FROM coaching_members cm
    WHERE cm.group_id = v_group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', 'message', 'Apenas coach/admin pode atribuir treinos');
  END IF;

  -- Check athlete is member
  SELECT cm.role INTO v_athlete_role
    FROM coaching_members cm
    WHERE cm.group_id = v_group_id AND cm.user_id = p_athlete_user_id;

  IF v_athlete_role IS NULL OR v_athlete_role != 'athlete' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ATHLETE_NOT_MEMBER', 'message', 'Atleta não é membro do grupo');
  END IF;

  -- Idempotent insert
  INSERT INTO coaching_workout_assignments
    (group_id, athlete_user_id, template_id, scheduled_date, notes, created_by)
  VALUES
    (v_group_id, p_athlete_user_id, p_template_id, p_scheduled_date, p_notes, v_uid)
  ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE SET
    template_id = EXCLUDED.template_id,
    notes       = EXCLUDED.notes,
    version     = coaching_workout_assignments.version + 1,
    updated_at  = now()
  RETURNING id INTO v_assignment_id;

  RETURN jsonb_build_object('ok', true, 'code', 'ASSIGNED', 'data', jsonb_build_object('assignment_id', v_assignment_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO service_role;

COMMIT;
