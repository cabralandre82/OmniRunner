-- Adds p_blocks jsonb parameter to fn_create_descriptive_workout so that
-- workouts created via "Descrever" or AI parse can carry structured blocks
-- (pace zones, HR targets, distance/duration triggers) that GPS watches need.
--
-- 20260414001000_training_plan_v2.sql criou a versão de 9 args. Como o
-- 10º parâmetro (p_blocks) tem DEFAULT, PostgreSQL trata como overload
-- distinto — `CREATE OR REPLACE` só substituiria se a assinatura bater.
-- Drop explícito da versão anterior evita ambiguidade no REVOKE/GRANT abaixo.
DROP FUNCTION IF EXISTS public.fn_create_descriptive_workout(
  uuid, uuid, date, text, text, text, text, text, int
);

CREATE OR REPLACE FUNCTION public.fn_create_descriptive_workout(
  p_plan_week_id   uuid,
  p_athlete_id     uuid,
  p_scheduled_date date,
  p_workout_label  text,
  p_description    text  DEFAULT NULL,
  p_workout_type   text  DEFAULT 'continuous',
  p_coach_notes    text  DEFAULT NULL,
  p_video_url      text  DEFAULT NULL,
  p_workout_order  int   DEFAULT 1,
  p_blocks         jsonb DEFAULT '[]'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id    uuid;
  v_role        text;
  v_release_id  uuid;
  v_week_starts date;
  v_week_ends   date;
BEGIN
  SELECT w.group_id, w.starts_on, w.ends_on
  INTO v_group_id, v_week_starts, v_week_ends
  FROM training_plan_weeks w
  WHERE id = p_plan_week_id;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'week_not_found';
  END IF;

  SELECT role INTO v_role
  FROM coaching_members
  WHERE group_id = v_group_id AND user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_scheduled_date < v_week_starts OR p_scheduled_date > v_week_ends THEN
    RAISE EXCEPTION 'date_outside_week'
      USING HINT = format('Date %s is outside week %s–%s',
                          p_scheduled_date, v_week_starts, v_week_ends);
  END IF;

  IF p_workout_label IS NULL OR length(trim(p_workout_label)) = 0 THEN
    RAISE EXCEPTION 'workout_label_required'
      USING HINT = 'Descriptive workouts must have a label';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = v_group_id
      AND user_id = p_athlete_id
      AND role = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  INSERT INTO plan_workout_releases (
    plan_week_id, group_id, athlete_user_id, template_id,
    scheduled_date, workout_order, workout_type,
    workout_label, coach_notes, video_url,
    release_status, created_by, updated_by,
    content_snapshot
  ) VALUES (
    p_plan_week_id, v_group_id, p_athlete_id, NULL,
    p_scheduled_date, p_workout_order,
    COALESCE(p_workout_type, 'continuous'),
    p_workout_label, p_coach_notes, p_video_url,
    'draft', auth.uid(), auth.uid(),
    jsonb_build_object(
      'template_id',   NULL,
      'template_name', p_workout_label,
      'description',   p_description,
      'blocks',        COALESCE(p_blocks, '[]'::jsonb),
      'snapshot_at',   now()
    )
  ) RETURNING id INTO v_release_id;

  INSERT INTO workout_change_log (
    release_id, group_id, changed_by, change_type, new_value
  ) VALUES (
    v_release_id, v_group_id, auth.uid(), 'created',
    jsonb_build_object(
      'descriptive', true,
      'label', p_workout_label,
      'date', p_scheduled_date,
      'block_count', jsonb_array_length(COALESCE(p_blocks, '[]'::jsonb))
    )
  );

  RETURN v_release_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_create_descriptive_workout(
  uuid, uuid, date, text, text, text, text, text, int, jsonb
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_descriptive_workout(
  uuid, uuid, date, text, text, text, text, text, int, jsonb
) TO authenticated;
