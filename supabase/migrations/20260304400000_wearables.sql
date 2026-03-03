-- ============================================================================
-- BLOCO D: Wearables — Device Links + Workout Executions
-- Tables, indexes, RLS, and RPCs for wearable device integration.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TABLES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.coaching_device_links (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id   uuid NOT NULL REFERENCES auth.users(id),
  provider          text NOT NULL CHECK (provider IN ('garmin', 'apple', 'polar', 'suunto')),
  access_token      text,
  refresh_token     text,
  provider_user_id  text,
  expires_at        timestamptz,
  linked_at         timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT uq_device_link_athlete_provider UNIQUE (athlete_user_id, provider)
);

CREATE TABLE IF NOT EXISTS public.coaching_workout_executions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id                 uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  assignment_id            uuid REFERENCES public.coaching_workout_assignments(id) ON DELETE SET NULL,
  athlete_user_id          uuid NOT NULL REFERENCES auth.users(id),
  actual_duration_seconds  int,
  actual_distance_meters   int,
  avg_pace_seconds_per_km  int,
  avg_hr                   int,
  max_hr                   int,
  calories                 int,
  source                   text NOT NULL CHECK (source IN ('manual', 'garmin', 'apple', 'polar', 'suunto')),
  provider_activity_id     text,
  completed_at             timestamptz NOT NULL DEFAULT now(),
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_execution_athlete_provider_activity
  ON public.coaching_workout_executions (athlete_user_id, provider_activity_id)
  WHERE provider_activity_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. INDEXES
-- ═══════════════════════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_device_links_athlete
  ON public.coaching_device_links (athlete_user_id);

CREATE INDEX IF NOT EXISTS idx_executions_group_athlete
  ON public.coaching_workout_executions (group_id, athlete_user_id, completed_at DESC);

CREATE INDEX IF NOT EXISTS idx_executions_assignment
  ON public.coaching_workout_executions (assignment_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.coaching_device_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_workout_executions ENABLE ROW LEVEL SECURITY;

-- 3.1 Device links: athlete can manage own links
CREATE POLICY "athlete_self_all"
  ON public.coaching_device_links FOR ALL USING (
    athlete_user_id = auth.uid()
  );

-- 3.2 Device links: staff can read links for their group
CREATE POLICY "staff_device_links_select"
  ON public.coaching_device_links FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_device_links.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- 3.3 Executions: athlete can insert own executions
CREATE POLICY "athlete_insert_self"
  ON public.coaching_workout_executions FOR INSERT WITH CHECK (
    athlete_user_id = auth.uid()
  );

-- 3.4 Executions: athlete can read own executions
CREATE POLICY "athlete_select_self"
  ON public.coaching_workout_executions FOR SELECT USING (
    athlete_user_id = auth.uid()
  );

-- 3.5 Executions: staff can read executions for their group
CREATE POLICY "staff_executions_select"
  ON public.coaching_workout_executions FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_workout_executions.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach', 'assistant')
    )
  );

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. RPCs
-- ═══════════════════════════════════════════════════════════════════════════

-- 4.1 fn_generate_workout_payload: builds structured workout data for wearable export
CREATE OR REPLACE FUNCTION public.fn_generate_workout_payload(
  p_assignment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid          uuid := auth.uid();
  v_assignment   record;
  v_template     record;
  v_caller_role  text;
  v_blocks       jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED', 'message', 'Usuário não autenticado');
  END IF;

  SELECT a.id, a.athlete_user_id, a.template_id, a.scheduled_date, a.group_id
    INTO v_assignment
    FROM coaching_workout_assignments a
    WHERE a.id = p_assignment_id;

  IF v_assignment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ASSIGNMENT_NOT_FOUND', 'message', 'Atribuição não encontrada');
  END IF;

  -- Validate caller is the athlete or staff of the group
  IF v_uid != v_assignment.athlete_user_id THEN
    SELECT cm.role INTO v_caller_role
      FROM coaching_members cm
      WHERE cm.group_id = v_assignment.group_id AND cm.user_id = v_uid;

    IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
      RETURN jsonb_build_object('ok', false, 'code', 'FORBIDDEN', 'message', 'Sem permissão para acessar este treino');
    END IF;
  END IF;

  SELECT t.id, t.name INTO v_template
    FROM coaching_workout_templates t
    WHERE t.id = v_assignment.template_id;

  IF v_template IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPLATE_NOT_FOUND', 'message', 'Template não encontrado');
  END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'order_index', b.order_index,
      'block_type', b.block_type,
      'duration_seconds', b.duration_seconds,
      'distance_meters', b.distance_meters,
      'target_pace_seconds_per_km', b.target_pace_seconds_per_km,
      'target_hr_zone', b.target_hr_zone,
      'rpe_target', b.rpe_target,
      'notes', b.notes
    ) ORDER BY b.order_index
  ), '[]'::jsonb) INTO v_blocks
  FROM coaching_workout_blocks b
  WHERE b.template_id = v_template.id;

  RETURN jsonb_build_object(
    'ok', true,
    'data', jsonb_build_object(
      'assignment_id', v_assignment.id,
      'template_name', v_template.name,
      'scheduled_date', v_assignment.scheduled_date,
      'blocks', v_blocks
    )
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_generate_workout_payload(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_generate_workout_payload(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_generate_workout_payload(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_generate_workout_payload(uuid) TO service_role;

-- 4.2 fn_import_execution: imports a workout execution (manual or from wearable)
CREATE OR REPLACE FUNCTION public.fn_import_execution(
  p_assignment_id          uuid    DEFAULT NULL,
  p_duration_seconds       int     DEFAULT NULL,
  p_distance_meters        int     DEFAULT NULL,
  p_avg_pace               int     DEFAULT NULL,
  p_avg_hr                 int     DEFAULT NULL,
  p_max_hr                 int     DEFAULT NULL,
  p_calories               int     DEFAULT NULL,
  p_source                 text    DEFAULT 'manual',
  p_provider_activity_id   text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid          uuid := auth.uid();
  v_group_id     uuid;
  v_exec_id      uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED', 'message', 'Usuário não autenticado');
  END IF;

  -- Resolve group_id from assignment or from membership
  IF p_assignment_id IS NOT NULL THEN
    SELECT a.group_id INTO v_group_id
      FROM coaching_workout_assignments a
      WHERE a.id = p_assignment_id AND a.athlete_user_id = v_uid;

    IF v_group_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'ASSIGNMENT_NOT_FOUND', 'message', 'Atribuição não encontrada ou não pertence ao usuário');
    END IF;
  ELSE
    SELECT cm.group_id INTO v_group_id
      FROM coaching_members cm
      WHERE cm.user_id = v_uid AND cm.role = 'athlete'
      LIMIT 1;

    IF v_group_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'code', 'NO_GROUP', 'message', 'Usuário não está em nenhum grupo como atleta');
    END IF;
  END IF;

  INSERT INTO coaching_workout_executions (
    group_id, assignment_id, athlete_user_id,
    actual_duration_seconds, actual_distance_meters,
    avg_pace_seconds_per_km, avg_hr, max_hr, calories,
    source, provider_activity_id
  ) VALUES (
    v_group_id, p_assignment_id, v_uid,
    p_duration_seconds, p_distance_meters,
    p_avg_pace, p_avg_hr, p_max_hr, p_calories,
    p_source, p_provider_activity_id
  )
  ON CONFLICT (athlete_user_id, provider_activity_id)
    WHERE provider_activity_id IS NOT NULL
    DO NOTHING
  RETURNING id INTO v_exec_id;

  -- If ON CONFLICT hit, v_exec_id will be NULL → return duplicate info
  IF v_exec_id IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'code', 'DUPLICATE', 'message', 'Execução já importada anteriormente');
  END IF;

  -- If assignment_id provided, mark assignment as completed
  IF p_assignment_id IS NOT NULL THEN
    UPDATE coaching_workout_assignments
       SET status = 'completed', updated_at = now()
     WHERE id = p_assignment_id AND athlete_user_id = v_uid;
  END IF;

  RETURN jsonb_build_object('ok', true, 'code', 'IMPORTED', 'data', jsonb_build_object('execution_id', v_exec_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_import_execution(uuid, int, int, int, int, int, int, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_import_execution(uuid, int, int, int, int, int, int, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_import_execution(uuid, int, int, int, int, int, int, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_import_execution(uuid, int, int, int, int, int, int, text, text) TO service_role;

COMMIT;
