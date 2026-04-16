-- ============================================================================
-- Training Plan — Features de distribuição em massa e biblioteca de semanas
--
-- CHANGES:
--   1. ADD COLUMNS  training_plan_weeks.is_week_template, template_name
--      Permite marcar qualquer semana como "modelo de semana" reutilizável.
--
--   2. CREATE FUNCTION fn_bulk_assign_week
--      Versiona a função que já existia apenas no banco de produção (sem
--      migration). Copia uma semana inteira para um atleta específico,
--      criando o plano e a semana do atleta se necessário.
--      Parâmetro p_auto_release (default false) libera os treinos copiados
--      imediatamente — Feature 4.
--
--   3. CREATE FUNCTION fn_distribute_workout
--      Copia um único treino para N atletas em uma data específica,
--      encontrando ou criando a semana de destino de cada atleta.
--      Corrige o bug do fn_copy_workout que usava o plan_week_id do atleta
--      origem quando p_target_week_id era NULL — Feature 1.
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. Colunas de template de semana em training_plan_weeks
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.training_plan_weeks
  ADD COLUMN IF NOT EXISTS is_week_template boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS template_name     text;

-- Índice para listagem rápida de templates por grupo
CREATE INDEX IF NOT EXISTS idx_tpw_week_template
  ON public.training_plan_weeks (plan_id)
  WHERE is_week_template = true;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. fn_bulk_assign_week
--    Copia uma semana inteira (todos os treinos não-cancelados) para um
--    atleta, criando plano e semana de destino quando necessário.
--    p_auto_release: se true, libera os treinos imediatamente após copiar.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_bulk_assign_week(
  p_source_week_id    uuid,
  p_target_athlete_id uuid,
  p_target_start_date date,
  p_group_id          uuid,
  p_actor_id          uuid,
  p_auto_release      boolean DEFAULT false
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role         text;
  v_source_week  record;
  v_source_plan  record;
  v_target_plan  record;
  v_target_week  record;
  v_new_week_id  uuid;
  v_new_rel_id   uuid;
  v_offset_days  int;
  v_target_date  date;
  v_rel          record;
BEGIN
  -- ── Autorização ────────────────────────────────────────────────────────
  SELECT role INTO v_role
  FROM coaching_members
  WHERE group_id = p_group_id AND user_id = p_actor_id
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    RAISE EXCEPTION 'forbidden' USING HINT = 'Only admin_master or coach can bulk-assign weeks';
  END IF;

  -- Atleta deve ser membro
  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = p_target_athlete_id AND role = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  -- ── Carregar semana e plano de origem ──────────────────────────────────
  SELECT * INTO v_source_week
  FROM training_plan_weeks WHERE id = p_source_week_id;
  IF v_source_week IS NULL THEN RAISE EXCEPTION 'source_week_not_found'; END IF;

  SELECT * INTO v_source_plan
  FROM training_plans WHERE id = v_source_week.plan_id;
  IF v_source_plan IS NULL OR v_source_plan.group_id <> p_group_id THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- ── Garantir plano de destino (cria se não existir) ───────────────────
  SELECT * INTO v_target_plan
  FROM training_plans
  WHERE group_id = p_group_id
    AND athlete_user_id = p_target_athlete_id
    AND status IN ('active', 'paused')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_target_plan IS NULL THEN
    INSERT INTO training_plans (
      group_id, athlete_user_id, name, sport_type,
      status, starts_on, created_by, updated_by
    ) VALUES (
      p_group_id, p_target_athlete_id,
      'Planilha — ' || to_char(now(), 'Mon/YYYY'),
      COALESCE(v_source_plan.sport_type, 'running'),
      'active',
      p_target_start_date,
      p_actor_id, p_actor_id
    ) RETURNING * INTO v_target_plan;
  END IF;

  -- ── Garantir semana de destino (cria se não existir) ──────────────────
  SELECT * INTO v_target_week
  FROM training_plan_weeks
  WHERE plan_id = v_target_plan.id
    AND starts_on = p_target_start_date;

  IF v_target_week IS NULL THEN
    INSERT INTO training_plan_weeks (
      plan_id, week_number, starts_on, ends_on,
      cycle_type, label, coach_notes,
      created_by, updated_by
    ) VALUES (
      v_target_plan.id,
      COALESCE(
        (SELECT MAX(week_number) + 1 FROM training_plan_weeks WHERE plan_id = v_target_plan.id),
        1
      ),
      p_target_start_date,
      p_target_start_date + INTERVAL '6 days',
      COALESCE(v_source_week.cycle_type, 'base'),
      v_source_week.label,
      v_source_week.coach_notes,
      p_actor_id, p_actor_id
    ) RETURNING * INTO v_target_week;
  END IF;

  v_new_week_id := v_target_week.id;

  -- ── Copiar treinos ativos ─────────────────────────────────────────────
  FOR v_rel IN
    SELECT *
    FROM plan_workout_releases
    WHERE plan_week_id = p_source_week_id
      AND release_status NOT IN ('cancelled', 'replaced', 'archived')
  LOOP
    -- Calcular data de destino preservando o dia da semana
    v_offset_days := v_rel.scheduled_date - v_source_week.starts_on;
    v_target_date := p_target_start_date + v_offset_days;

    INSERT INTO plan_workout_releases (
      plan_week_id, group_id, athlete_user_id, template_id,
      scheduled_date, workout_order, workout_type, workout_label,
      coach_notes, release_status, content_snapshot, content_version,
      video_url, created_by, updated_by
    ) VALUES (
      v_new_week_id,
      p_group_id,
      p_target_athlete_id,
      v_rel.template_id,
      v_target_date,
      v_rel.workout_order,
      v_rel.workout_type,
      v_rel.workout_label,
      v_rel.coach_notes,
      CASE WHEN p_auto_release THEN 'released' ELSE 'draft' END,
      jsonb_set(COALESCE(v_rel.content_snapshot, '{}'), '{snapshot_at}', to_jsonb(now())),
      1,
      v_rel.video_url,
      p_actor_id,
      p_actor_id
    ) RETURNING id INTO v_new_rel_id;

    INSERT INTO workout_change_log (
      release_id, group_id, changed_by, change_type, new_value
    ) VALUES (
      v_new_rel_id, p_group_id, p_actor_id,
      CASE WHEN p_auto_release THEN 'bulk_assigned_released' ELSE 'bulk_assigned' END,
      jsonb_build_object('source_week_id', p_source_week_id, 'auto_release', p_auto_release)
    );
  END LOOP;

  -- Atualizar status da semana destino se liberada
  IF p_auto_release THEN
    UPDATE training_plan_weeks
    SET status = 'released', updated_at = now()
    WHERE id = v_new_week_id;
  END IF;

  RETURN v_new_week_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_bulk_assign_week FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bulk_assign_week TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. fn_distribute_workout
--    Copia um único treino para um atleta em uma data específica.
--    Diferente de fn_copy_workout: encontra/cria automaticamente a semana
--    de destino do atleta (fn_copy_workout usava o plan_week_id da origem).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_distribute_workout(
  p_source_id         uuid,
  p_target_athlete_id uuid,
  p_target_date       date,
  p_group_id          uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role        text;
  v_src         record;
  v_target_plan record;
  v_week_start  date;
  v_week_end    date;
  v_target_week record;
  v_new_id      uuid;
BEGIN
  -- ── Autorização ────────────────────────────────────────────────────────
  SELECT role INTO v_role
  FROM coaching_members
  WHERE group_id = p_group_id AND user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = p_group_id AND user_id = p_target_athlete_id AND role = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  -- ── Treino origem ──────────────────────────────────────────────────────
  SELECT * INTO v_src FROM plan_workout_releases WHERE id = p_source_id;
  IF v_src IS NULL THEN RAISE EXCEPTION 'source_not_found'; END IF;
  IF v_src.group_id <> p_group_id THEN RAISE EXCEPTION 'forbidden'; END IF;

  -- ── Semana de destino (segunda-feira que contém p_target_date) ────────
  v_week_start := p_target_date - EXTRACT(DOW FROM p_target_date)::int
                  + CASE WHEN EXTRACT(DOW FROM p_target_date) = 0 THEN -6 ELSE 1 END;
  v_week_end   := v_week_start + 6;

  -- ── Plano ativo do atleta destino ─────────────────────────────────────
  SELECT * INTO v_target_plan
  FROM training_plans
  WHERE group_id = p_group_id
    AND athlete_user_id = p_target_athlete_id
    AND status IN ('active', 'paused')
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_target_plan IS NULL THEN
    INSERT INTO training_plans (
      group_id, athlete_user_id, name, sport_type,
      status, starts_on, created_by, updated_by
    ) VALUES (
      p_group_id, p_target_athlete_id,
      'Planilha — ' || to_char(now(), 'Mon/YYYY'),
      'running', 'active', v_week_start,
      auth.uid(), auth.uid()
    ) RETURNING * INTO v_target_plan;
  END IF;

  -- ── Semana ────────────────────────────────────────────────────────────
  SELECT * INTO v_target_week
  FROM training_plan_weeks
  WHERE plan_id = v_target_plan.id AND starts_on = v_week_start;

  IF v_target_week IS NULL THEN
    INSERT INTO training_plan_weeks (
      plan_id, week_number, starts_on, ends_on,
      cycle_type, created_by, updated_by
    ) VALUES (
      v_target_plan.id,
      COALESCE(
        (SELECT MAX(week_number) + 1 FROM training_plan_weeks WHERE plan_id = v_target_plan.id),
        1
      ),
      v_week_start, v_week_end,
      'base',
      auth.uid(), auth.uid()
    ) RETURNING * INTO v_target_week;
  END IF;

  -- ── Inserir treino ────────────────────────────────────────────────────
  INSERT INTO plan_workout_releases (
    plan_week_id, group_id, athlete_user_id, template_id,
    scheduled_date, workout_order, workout_type, workout_label,
    coach_notes, release_status, content_snapshot, content_version,
    video_url, created_by, updated_by
  ) VALUES (
    v_target_week.id,
    p_group_id,
    p_target_athlete_id,
    v_src.template_id,
    p_target_date,
    v_src.workout_order,
    v_src.workout_type,
    v_src.workout_label,
    v_src.coach_notes,
    'draft',
    jsonb_set(COALESCE(v_src.content_snapshot, '{}'), '{snapshot_at}', to_jsonb(now())),
    1,
    v_src.video_url,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_new_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (v_new_id, p_group_id, auth.uid(), 'distributed_from',
          jsonb_build_object('source_id', p_source_id, 'target_athlete', p_target_athlete_id));

  RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_distribute_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_distribute_workout TO authenticated;

COMMIT;
