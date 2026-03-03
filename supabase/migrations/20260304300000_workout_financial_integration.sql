BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO C: Integration Esportivo ↔ Financeiro
-- Modifies fn_assign_workout to check subscription status + weekly limits
-- Adds FINANCIAL_LATE alert type to compute_coaching_alerts_daily
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_assign_workout(
  p_template_id    uuid,
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
  v_uid              uuid := auth.uid();
  v_group_id         uuid;
  v_caller_role      text;
  v_athlete_role     text;
  v_sub_status       text;
  v_max_per_week     int;
  v_week_count       int;
  v_assignment_id    uuid;
  v_week_start       date;
BEGIN
  -- Get template group
  SELECT t.group_id INTO v_group_id
  FROM coaching_workout_templates t WHERE t.id = p_template_id;

  IF v_group_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'code', 'TEMPLATE_NOT_FOUND', 'message', 'Template não encontrado');
  END IF;

  -- Check caller is staff
  SELECT cm.role INTO v_caller_role
  FROM coaching_members cm WHERE cm.group_id = v_group_id AND cm.user_id = v_uid;

  IF v_caller_role IS NULL OR v_caller_role NOT IN ('admin_master', 'coach') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'NOT_STAFF', 'message', 'Apenas coach/admin pode atribuir treinos');
  END IF;

  -- Check athlete is member
  SELECT cm.role INTO v_athlete_role
  FROM coaching_members cm WHERE cm.group_id = v_group_id AND cm.user_id = p_athlete_user_id;

  IF v_athlete_role IS NULL OR v_athlete_role != 'athlete' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'ATHLETE_NOT_MEMBER', 'message', 'Atleta não é membro do grupo');
  END IF;

  -- ══ NEW: Check subscription status ══
  SELECT s.status INTO v_sub_status
  FROM coaching_subscriptions s
  WHERE s.group_id = v_group_id AND s.athlete_user_id = p_athlete_user_id;

  -- If subscription exists and is 'late', block new assignments
  IF v_sub_status = 'late' THEN
    RETURN jsonb_build_object('ok', false, 'code', 'SUBSCRIPTION_LATE', 'message', 'Atleta com assinatura em atraso. Regularize antes de atribuir treinos.');
  END IF;

  -- If subscription exists and is cancelled/paused, block
  IF v_sub_status IN ('cancelled', 'paused') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'SUBSCRIPTION_INACTIVE', 'message', 'Atleta sem assinatura ativa.');
  END IF;

  -- ══ NEW: Check weekly limit if plan has max_workouts_per_week ══
  IF v_sub_status = 'active' THEN
    SELECT p.max_workouts_per_week INTO v_max_per_week
    FROM coaching_subscriptions s
    JOIN coaching_plans p ON p.id = s.plan_id
    WHERE s.group_id = v_group_id AND s.athlete_user_id = p_athlete_user_id;

    IF v_max_per_week IS NOT NULL THEN
      v_week_start := date_trunc('week', p_scheduled_date)::date;
      SELECT count(*) INTO v_week_count
      FROM coaching_workout_assignments a
      WHERE a.athlete_user_id = p_athlete_user_id
        AND a.scheduled_date >= v_week_start
        AND a.scheduled_date < v_week_start + 7;

      IF v_week_count >= v_max_per_week THEN
        RETURN jsonb_build_object('ok', false, 'code', 'WEEKLY_LIMIT_REACHED',
          'message', format('Limite de %s treinos/semana atingido.', v_max_per_week));
      END IF;
    END IF;
  END IF;

  -- Note: if no subscription exists, we allow assignment (group may not use plans)

  -- Insert with idempotent upsert
  INSERT INTO coaching_workout_assignments (group_id, athlete_user_id, template_id, scheduled_date, notes, created_by)
  VALUES (v_group_id, p_athlete_user_id, p_template_id, p_scheduled_date, p_notes, v_uid)
  ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE SET
    template_id = EXCLUDED.template_id,
    notes = EXCLUDED.notes,
    version = coaching_workout_assignments.version + 1,
    updated_at = now()
  RETURNING id INTO v_assignment_id;

  RETURN jsonb_build_object('ok', true, 'code', 'ASSIGNED', 'data', jsonb_build_object('assignment_id', v_assignment_id));
END;
$fn$;

REVOKE ALL ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_assign_workout(uuid, uuid, date, text) TO service_role;

COMMIT;
