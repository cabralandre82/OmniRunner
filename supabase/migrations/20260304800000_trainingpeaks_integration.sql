BEGIN;

-- 1. Add 'trainingpeaks' to coaching_device_links provider CHECK
ALTER TABLE public.coaching_device_links
  DROP CONSTRAINT IF EXISTS coaching_device_links_provider_check;
ALTER TABLE public.coaching_device_links
  ADD CONSTRAINT coaching_device_links_provider_check
  CHECK (provider IN ('garmin', 'apple', 'polar', 'suunto', 'trainingpeaks'));

-- 2. Add 'trainingpeaks' to coaching_workout_executions source CHECK  
ALTER TABLE public.coaching_workout_executions
  DROP CONSTRAINT IF EXISTS coaching_workout_executions_source_check;
ALTER TABLE public.coaching_workout_executions
  ADD CONSTRAINT coaching_workout_executions_source_check
  CHECK (source IN ('manual', 'garmin', 'apple', 'polar', 'suunto', 'trainingpeaks'));

-- 3. TrainingPeaks sync tracking table
CREATE TABLE IF NOT EXISTS public.coaching_tp_sync (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id             uuid NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  assignment_id        uuid NOT NULL REFERENCES public.coaching_workout_assignments(id) ON DELETE CASCADE,
  athlete_user_id      uuid NOT NULL REFERENCES auth.users(id),
  tp_workout_id        text,
  sync_status          text NOT NULL DEFAULT 'pending'
                       CHECK (sync_status IN ('pending', 'pushed', 'completed', 'failed', 'cancelled')),
  pushed_at            timestamptz,
  completed_at         timestamptz,
  error_message        text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  
  CONSTRAINT uq_tp_sync_assignment UNIQUE (assignment_id, athlete_user_id)
);

CREATE INDEX IF NOT EXISTS idx_tp_sync_group_status
  ON public.coaching_tp_sync (group_id, sync_status);
CREATE INDEX IF NOT EXISTS idx_tp_sync_athlete
  ON public.coaching_tp_sync (athlete_user_id, sync_status);

-- 4. RLS for coaching_tp_sync
ALTER TABLE public.coaching_tp_sync ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "athlete_tp_sync_select" ON public.coaching_tp_sync;
CREATE POLICY "athlete_tp_sync_select"
  ON public.coaching_tp_sync FOR SELECT USING (
    athlete_user_id = auth.uid()
  );

DROP POLICY IF EXISTS "staff_tp_sync_all" ON public.coaching_tp_sync;
CREATE POLICY "staff_tp_sync_all"
  ON public.coaching_tp_sync FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_tp_sync.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 5. RPC: Push workout to TrainingPeaks (creates sync record)
CREATE OR REPLACE FUNCTION public.fn_push_to_trainingpeaks(
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
  v_caller_role  text;
  v_device_link  record;
  v_sync_id      uuid;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  END IF;

  SELECT a.id, a.athlete_user_id, a.template_id, a.scheduled_date, a.group_id, a.status
    INTO v_assignment
    FROM coaching_workout_assignments a
    WHERE a.id = p_assignment_id;

  IF v_assignment IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ASSIGNMENT_NOT_FOUND');
  END IF;

  -- Validate caller is staff
  SELECT cm.role INTO v_caller_role
    FROM coaching_members cm
    WHERE cm.group_id = v_assignment.group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'FORBIDDEN');
  END IF;

  -- Verify athlete has TrainingPeaks linked
  SELECT dl.id INTO v_device_link
    FROM coaching_device_links dl
    WHERE dl.athlete_user_id = v_assignment.athlete_user_id
      AND dl.provider = 'trainingpeaks';

  IF v_device_link IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TP_NOT_LINKED', 
      'message', 'Atleta não tem TrainingPeaks vinculado');
  END IF;

  -- Create or update sync record
  INSERT INTO coaching_tp_sync (
    group_id, assignment_id, athlete_user_id, sync_status
  ) VALUES (
    v_assignment.group_id, p_assignment_id, v_assignment.athlete_user_id, 'pending'
  )
  ON CONFLICT (assignment_id, athlete_user_id)
  DO UPDATE SET sync_status = 'pending', updated_at = now(), error_message = NULL
  RETURNING id INTO v_sync_id;

  RETURN jsonb_build_object(
    'ok', true, 
    'code', 'SYNC_QUEUED',
    'data', jsonb_build_object('sync_id', v_sync_id)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_push_to_trainingpeaks(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_push_to_trainingpeaks(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_push_to_trainingpeaks(uuid) TO service_role;

-- 6. RPC: Get TP sync status for assignments
CREATE OR REPLACE FUNCTION public.fn_tp_sync_status(
  p_group_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_uid         uuid := auth.uid();
  v_role        text;
  v_result      jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_AUTHENTICATED');
  END IF;

  SELECT cm.role INTO v_role
    FROM coaching_members cm
    WHERE cm.group_id = p_group_id AND cm.user_id = v_uid;

  IF v_role IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_MEMBER');
  END IF;

  IF v_role IN ('admin_master', 'coach') THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'sync_id', s.id,
      'assignment_id', s.assignment_id,
      'athlete_user_id', s.athlete_user_id,
      'tp_workout_id', s.tp_workout_id,
      'sync_status', s.sync_status,
      'pushed_at', s.pushed_at,
      'completed_at', s.completed_at,
      'error_message', s.error_message
    ) ORDER BY s.updated_at DESC), '[]'::jsonb) INTO v_result
    FROM coaching_tp_sync s
    WHERE s.group_id = p_group_id;
  ELSE
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'sync_id', s.id,
      'assignment_id', s.assignment_id,
      'sync_status', s.sync_status,
      'pushed_at', s.pushed_at,
      'completed_at', s.completed_at
    ) ORDER BY s.updated_at DESC), '[]'::jsonb) INTO v_result
    FROM coaching_tp_sync s
    WHERE s.group_id = p_group_id AND s.athlete_user_id = v_uid;
  END IF;

  RETURN jsonb_build_object('ok', true, 'data', v_result);
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_tp_sync_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_tp_sync_status(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_tp_sync_status(uuid) TO service_role;

COMMIT;
