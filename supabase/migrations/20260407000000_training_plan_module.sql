-- ============================================================================
-- Training Plan Module (Módulo de Passagem de Treino)
-- Prescrição → Liberação → Consumo → Feedback → Auditoria
--
-- COMPATIBILIDADE: totalmente aditivo. Não altera, não dropa, não conflita
-- com nenhuma tabela existente (coaching_workout_templates, coaching_workout_blocks,
-- coaching_workout_assignments, workout_delivery_batches, coaching_training_sessions).
-- ============================================================================

BEGIN;

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. TRAINING PLANS (Planilhas de Treino)
--    Uma planilha agrupa semanas de treino para um atleta dentro de um grupo.
--    Pode ser individual (athlete_user_id preenchido) ou modelo de grupo (NULL).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.training_plans (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id         uuid        NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id  uuid        REFERENCES auth.users(id) ON DELETE CASCADE,
  name             text        NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 120),
  description      text,
  sport_type       text        NOT NULL DEFAULT 'running'
    CHECK (sport_type IN ('running', 'cycling', 'triathlon', 'swimming', 'strength', 'multi')),
  status           text        NOT NULL DEFAULT 'active'
    CHECK (status IN ('active', 'paused', 'completed', 'archived')),
  starts_on        date,
  ends_on          date,
  created_by       uuid        NOT NULL REFERENCES auth.users(id),
  updated_by       uuid        REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_plan_dates CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on)
);

CREATE INDEX IF NOT EXISTS idx_training_plans_group
  ON public.training_plans (group_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_plans_athlete
  ON public.training_plans (athlete_user_id, status)
  WHERE athlete_user_id IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. TRAINING PLAN WEEKS (Semanas da Planilha)
--    Cada semana tem um número de ordem, datas, tipo de ciclo e status.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.training_plan_weeks (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id      uuid        NOT NULL REFERENCES public.training_plans(id) ON DELETE CASCADE,
  group_id     uuid        NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  week_number  int         NOT NULL CHECK (week_number >= 1),
  starts_on    date        NOT NULL,
  ends_on      date        NOT NULL GENERATED ALWAYS AS (starts_on + 6) STORED,
  label        text,
  coach_notes  text,
  cycle_type   text        NOT NULL DEFAULT 'base'
    CHECK (cycle_type IN ('base', 'build', 'peak', 'recovery', 'test', 'free', 'taper', 'transition')),
  status       text        NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'released', 'completed', 'archived')),
  total_load_points int,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT chk_week_starts_monday CHECK (EXTRACT(dow FROM starts_on) = 1),
  CONSTRAINT uq_plan_week_number     UNIQUE (plan_id, week_number),
  CONSTRAINT uq_plan_week_starts_on  UNIQUE (plan_id, starts_on)
);

CREATE INDEX IF NOT EXISTS idx_plan_weeks_plan
  ON public.training_plan_weeks (plan_id, week_number);
CREATE INDEX IF NOT EXISTS idx_plan_weeks_group_date
  ON public.training_plan_weeks (group_id, starts_on DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. PLAN WORKOUT RELEASES (Treinos Prescritos com Lifecycle de Liberação)
--    Entidade central: um treino específico numa data para um atleta,
--    com controle completo de rascunho → liberado → concluído.
--
--    NÃO tem UNIQUE (athlete_user_id, scheduled_date) — permite múltiplos
--    treinos no mesmo dia (ex: manhã e tarde). Isso é diferente de
--    coaching_workout_assignments que tem 1-por-dia.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.plan_workout_releases (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_week_id         uuid        REFERENCES public.training_plan_weeks(id) ON DELETE SET NULL,
  group_id             uuid        NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  athlete_user_id      uuid        NOT NULL REFERENCES auth.users(id),
  template_id          uuid        REFERENCES public.coaching_workout_templates(id) ON DELETE SET NULL,
  assignment_id        uuid        REFERENCES public.coaching_workout_assignments(id) ON DELETE SET NULL,

  -- Quando deve ser feito
  scheduled_date       date        NOT NULL,
  workout_order        int         NOT NULL DEFAULT 1,

  -- Lifecycle
  release_status       text        NOT NULL DEFAULT 'draft'
    CHECK (release_status IN (
      'draft', 'scheduled', 'released', 'in_progress',
      'completed', 'cancelled', 'replaced', 'archived'
    )),
  scheduled_release_at timestamptz,
  released_at          timestamptz,
  cancelled_at         timestamptz,
  replaced_by_id       uuid        REFERENCES public.plan_workout_releases(id),

  -- Metadados do treino
  workout_label        text,
  coach_notes          text,
  workout_type         text        DEFAULT 'continuous'
    CHECK (workout_type IN (
      'continuous', 'interval', 'regenerative', 'long_run', 'strength',
      'technique', 'test', 'free', 'race', 'brick'
    )),

  -- Snapshot do template na liberação (imutável após release)
  content_snapshot     jsonb,
  content_version      int         NOT NULL DEFAULT 1,

  -- Auditoria
  created_by           uuid        NOT NULL REFERENCES auth.users(id),
  updated_by           uuid        REFERENCES auth.users(id),
  released_by          uuid        REFERENCES auth.users(id),
  cancelled_by         uuid        REFERENCES auth.users(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pwr_athlete_date
  ON public.plan_workout_releases (athlete_user_id, scheduled_date DESC, release_status);
CREATE INDEX IF NOT EXISTS idx_pwr_group_date
  ON public.plan_workout_releases (group_id, scheduled_date DESC);
CREATE INDEX IF NOT EXISTS idx_pwr_week
  ON public.plan_workout_releases (plan_week_id)
  WHERE plan_week_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pwr_status
  ON public.plan_workout_releases (release_status, scheduled_release_at)
  WHERE release_status = 'scheduled';
CREATE INDEX IF NOT EXISTS idx_pwr_updated
  ON public.plan_workout_releases (updated_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. COMPLETED WORKOUTS (Execuções Reais do Atleta)
--    Separação rigorosa entre prescrição e execução.
--    Guarda o snapshot do que foi prescrito + o que foi realizado.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.completed_workouts (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  release_id            uuid        NOT NULL REFERENCES public.plan_workout_releases(id),
  athlete_user_id       uuid        NOT NULL REFERENCES auth.users(id),
  group_id              uuid        NOT NULL REFERENCES public.coaching_groups(id),

  -- Quando aconteceu
  started_at            timestamptz NOT NULL DEFAULT now(),
  finished_at           timestamptz,

  -- Snapshot prescrito (preserva o que foi planejado na hora do submit)
  planned_snapshot      jsonb,

  -- O que realmente aconteceu (métricas brutas)
  actual_distance_m     double precision,
  actual_duration_s     int,
  actual_avg_pace_s_km  double precision,
  actual_avg_hr         double precision,
  actual_max_hr         int,
  actual_avg_power_w    double precision,
  actual_avg_cadence    double precision,
  actual_elevation_m    double precision,

  -- Percepção subjetiva
  perceived_effort      int CHECK (perceived_effort IS NULL OR perceived_effort BETWEEN 1 AND 10),
  mood                  int CHECK (mood IS NULL OR mood BETWEEN 1 AND 5),

  -- Origem dos dados
  source                text        NOT NULL DEFAULT 'manual'
    CHECK (source IN ('manual', 'app_session', 'health_import', 'wearable_sync', 'strava_import')),
  session_id            uuid,

  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_completed_workouts_release
  ON public.completed_workouts (release_id);
CREATE INDEX IF NOT EXISTS idx_completed_workouts_athlete
  ON public.completed_workouts (athlete_user_id, started_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 5. ATHLETE WORKOUT FEEDBACK (Feedback Pós-Treino)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.athlete_workout_feedback (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  release_id           uuid        NOT NULL REFERENCES public.plan_workout_releases(id),
  completed_workout_id uuid        REFERENCES public.completed_workouts(id),
  athlete_user_id      uuid        NOT NULL REFERENCES auth.users(id),
  group_id             uuid        NOT NULL REFERENCES public.coaching_groups(id),

  rating               int         CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
  perceived_effort     int         CHECK (perceived_effort IS NULL OR perceived_effort BETWEEN 1 AND 10),
  mood                 int         CHECK (mood IS NULL OR mood BETWEEN 1 AND 5),
  how_was_it           text,
  what_was_hard        text,
  notes                text,

  submitted_at         timestamptz NOT NULL DEFAULT now(),

  UNIQUE (release_id, athlete_user_id)
);

CREATE INDEX IF NOT EXISTS idx_feedback_release
  ON public.athlete_workout_feedback (release_id);
CREATE INDEX IF NOT EXISTS idx_feedback_athlete
  ON public.athlete_workout_feedback (athlete_user_id, submitted_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 6. WORKOUT CHANGE LOG (Auditoria de Mutações)
--    Registra cada mutação relevante no lifecycle de um workout.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.workout_change_log (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  release_id  uuid        NOT NULL REFERENCES public.plan_workout_releases(id),
  group_id    uuid        NOT NULL REFERENCES public.coaching_groups(id),
  changed_by  uuid        REFERENCES auth.users(id),
  change_type text        NOT NULL
    CHECK (change_type IN (
      'created', 'template_updated', 'notes_updated', 'rescheduled',
      'released', 'scheduled_for_release', 'cancelled', 'replaced',
      'completed_by_athlete', 'feedback_submitted', 'snapshot_updated',
      'bulk_released', 'copied_from', 'moved_from'
    )),
  old_value   jsonb,
  new_value   jsonb,
  reason      text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_change_log_release
  ON public.workout_change_log (release_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_change_log_group
  ON public.workout_change_log (group_id, created_at DESC);

-- ═══════════════════════════════════════════════════════════════════════════
-- 7. WORKOUT SYNC CURSORS (Sync Incremental para o App)
--    Cada dispositivo tem um cursor que representa o último estado sincronizado.
--    O app usa esse cursor para buscar apenas o delta desde o último sync.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.workout_sync_cursors (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  athlete_user_id  uuid        NOT NULL REFERENCES auth.users(id),
  device_id        text        NOT NULL,
  last_sync_at     timestamptz NOT NULL DEFAULT now(),
  last_cursor_ts   timestamptz NOT NULL DEFAULT '1970-01-01 00:00:00+00',
  synced_count     int         NOT NULL DEFAULT 0,
  created_at       timestamptz NOT NULL DEFAULT now(),

  UNIQUE (athlete_user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_cursors_athlete
  ON public.workout_sync_cursors (athlete_user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- 8. UPDATED_AT TRIGGERS
-- ═══════════════════════════════════════════════════════════════════════════

-- Reuse fn_set_updated_at from workout_delivery migration (already exists)
-- but add IF NOT EXISTS guard

CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$;

DO $$ BEGIN
  CREATE TRIGGER trg_training_plans_updated
    BEFORE UPDATE ON public.training_plans
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_training_plan_weeks_updated
    BEFORE UPDATE ON public.training_plan_weeks
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_pwr_updated
    BEFORE UPDATE ON public.plan_workout_releases
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TRIGGER trg_completed_workouts_updated
    BEFORE UPDATE ON public.completed_workouts
    FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ═══════════════════════════════════════════════════════════════════════════
-- 9. RLS
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.training_plans         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.training_plan_weeks    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_workout_releases  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.completed_workouts     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.athlete_workout_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_change_log     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_sync_cursors   ENABLE ROW LEVEL SECURITY;

-- Helper: calcula o role do usuário corrente em um group_id
CREATE OR REPLACE FUNCTION public.fn_my_role_in_group(p_group_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM public.coaching_members
  WHERE group_id = p_group_id AND user_id = auth.uid()
  LIMIT 1;
$$;

-- ── training_plans ──────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "tp_staff_select"  ON public.training_plans;
DROP POLICY IF EXISTS "tp_staff_insert"  ON public.training_plans;
DROP POLICY IF EXISTS "tp_staff_update"  ON public.training_plans;
DROP POLICY IF EXISTS "tp_athlete_select" ON public.training_plans;

CREATE POLICY "tp_staff_select" ON public.training_plans FOR SELECT USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
);
CREATE POLICY "tp_staff_insert" ON public.training_plans FOR INSERT WITH CHECK (
  fn_my_role_in_group(group_id) IN ('admin_master','coach')
);
CREATE POLICY "tp_staff_update" ON public.training_plans FOR UPDATE USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach')
);
-- Atleta lê apenas sua própria planilha
CREATE POLICY "tp_athlete_select" ON public.training_plans FOR SELECT USING (
  athlete_user_id = auth.uid()
);

-- ── training_plan_weeks ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS "tpw_staff_all"    ON public.training_plan_weeks;
DROP POLICY IF EXISTS "tpw_athlete_select" ON public.training_plan_weeks;

CREATE POLICY "tpw_staff_all" ON public.training_plan_weeks FOR ALL USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
) WITH CHECK (
  fn_my_role_in_group(group_id) IN ('admin_master','coach')
);
CREATE POLICY "tpw_athlete_select" ON public.training_plan_weeks FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.training_plans tp
    WHERE tp.id = training_plan_weeks.plan_id
      AND tp.athlete_user_id = auth.uid()
  )
);

-- ── plan_workout_releases ───────────────────────────────────────────────────

DROP POLICY IF EXISTS "pwr_staff_all"    ON public.plan_workout_releases;
DROP POLICY IF EXISTS "pwr_athlete_select" ON public.plan_workout_releases;

CREATE POLICY "pwr_staff_all" ON public.plan_workout_releases FOR ALL USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
) WITH CHECK (
  fn_my_role_in_group(group_id) IN ('admin_master','coach')
);
-- Atleta vê apenas treinos liberados (released/in_progress/completed/cancelled)
CREATE POLICY "pwr_athlete_select" ON public.plan_workout_releases FOR SELECT USING (
  athlete_user_id = auth.uid()
  AND release_status IN ('released', 'in_progress', 'completed', 'cancelled', 'replaced')
);

-- ── completed_workouts ──────────────────────────────────────────────────────

DROP POLICY IF EXISTS "cw_staff_select"  ON public.completed_workouts;
DROP POLICY IF EXISTS "cw_athlete_all"   ON public.completed_workouts;

CREATE POLICY "cw_staff_select" ON public.completed_workouts FOR SELECT USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
);
CREATE POLICY "cw_athlete_all" ON public.completed_workouts FOR ALL USING (
  athlete_user_id = auth.uid()
) WITH CHECK (
  athlete_user_id = auth.uid()
);

-- ── athlete_workout_feedback ────────────────────────────────────────────────

DROP POLICY IF EXISTS "awf_staff_select"  ON public.athlete_workout_feedback;
DROP POLICY IF EXISTS "awf_athlete_all"   ON public.athlete_workout_feedback;

CREATE POLICY "awf_staff_select" ON public.athlete_workout_feedback FOR SELECT USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
);
CREATE POLICY "awf_athlete_all" ON public.athlete_workout_feedback FOR ALL USING (
  athlete_user_id = auth.uid()
) WITH CHECK (
  athlete_user_id = auth.uid()
);

-- ── workout_change_log ──────────────────────────────────────────────────────

DROP POLICY IF EXISTS "wcl_staff_select" ON public.workout_change_log;
DROP POLICY IF EXISTS "wcl_insert"       ON public.workout_change_log;

CREATE POLICY "wcl_staff_select" ON public.workout_change_log FOR SELECT USING (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
);
-- Apenas RPCs SECURITY DEFINER inserem (não RLS direto)
CREATE POLICY "wcl_insert" ON public.workout_change_log FOR INSERT WITH CHECK (
  fn_my_role_in_group(group_id) IN ('admin_master','coach','assistant')
  OR EXISTS (
    SELECT 1 FROM public.plan_workout_releases pwr
    WHERE pwr.id = workout_change_log.release_id
      AND pwr.athlete_user_id = auth.uid()
  )
);

-- ── workout_sync_cursors ────────────────────────────────────────────────────

DROP POLICY IF EXISTS "wsc_athlete_all" ON public.workout_sync_cursors;

CREATE POLICY "wsc_athlete_all" ON public.workout_sync_cursors FOR ALL USING (
  athlete_user_id = auth.uid()
) WITH CHECK (
  athlete_user_id = auth.uid()
);

-- ═══════════════════════════════════════════════════════════════════════════
-- 10. RPCs (SECURITY DEFINER — hardened, fail-fast)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 10a. Criar Training Plan ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_create_training_plan(
  p_group_id        uuid,
  p_athlete_user_id uuid,
  p_name            text,
  p_description     text DEFAULT NULL,
  p_sport_type      text DEFAULT 'running',
  p_starts_on       date DEFAULT NULL,
  p_ends_on         date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_role text;
  v_plan_id uuid;
BEGIN
  SELECT role INTO v_role
  FROM coaching_members
  WHERE group_id = p_group_id AND user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden' USING HINT = 'Only admin_master or coach can create plans';
  END IF;

  -- Athlete must be a member of the group
  IF p_athlete_user_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM coaching_members
      WHERE group_id = p_group_id AND user_id = p_athlete_user_id AND role = 'athlete'
    ) THEN
      RAISE EXCEPTION 'athlete_not_member' USING HINT = 'Athlete is not a member of this group';
    END IF;
  END IF;

  INSERT INTO training_plans (
    group_id, athlete_user_id, name, description, sport_type,
    starts_on, ends_on, created_by, updated_by
  ) VALUES (
    p_group_id, p_athlete_user_id, p_name, p_description, COALESCE(p_sport_type,'running'),
    p_starts_on, p_ends_on, auth.uid(), auth.uid()
  ) RETURNING id INTO v_plan_id;

  RETURN v_plan_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_create_training_plan FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_training_plan TO authenticated;

-- ─── 10b. Criar Semana na Planilha ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_create_plan_week(
  p_plan_id     uuid,
  p_starts_on   date,
  p_cycle_type  text DEFAULT 'base',
  p_label       text DEFAULT NULL,
  p_coach_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id  uuid;
  v_role      text;
  v_week_num  int;
  v_week_id   uuid;
  v_dow       int;
BEGIN
  SELECT group_id INTO v_group_id FROM training_plans WHERE id = p_plan_id;
  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'plan_not_found';
  END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Enforce Monday start
  v_dow := EXTRACT(dow FROM p_starts_on)::int;
  IF v_dow <> 1 THEN
    RAISE EXCEPTION 'week_must_start_on_monday'
      USING HINT = format('Provided date %s is a %s, not Monday', p_starts_on, to_char(p_starts_on,'Day'));
  END IF;

  SELECT COALESCE(MAX(week_number), 0) + 1 INTO v_week_num
  FROM training_plan_weeks WHERE plan_id = p_plan_id;

  INSERT INTO training_plan_weeks (
    plan_id, group_id, week_number, starts_on, cycle_type, label, coach_notes
  ) VALUES (
    p_plan_id, v_group_id, v_week_num, p_starts_on,
    COALESCE(p_cycle_type,'base'), p_label, p_coach_notes
  ) RETURNING id INTO v_week_id;

  RETURN v_week_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_create_plan_week FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_plan_week TO authenticated;

-- ─── 10c. Criar Treino na Semana (draft) ────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_create_plan_workout(
  p_plan_week_id   uuid,
  p_athlete_id     uuid,
  p_template_id    uuid,
  p_scheduled_date date,
  p_workout_type   text DEFAULT 'continuous',
  p_workout_label  text DEFAULT NULL,
  p_coach_notes    text DEFAULT NULL,
  p_workout_order  int  DEFAULT 1
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_role     text;
  v_release_id uuid;
  v_week_starts date;
  v_week_ends   date;
BEGIN
  SELECT w.group_id, w.starts_on, w.ends_on
  INTO v_group_id, v_week_starts, v_week_ends
  FROM training_plan_weeks w WHERE id = p_plan_week_id;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'week_not_found';
  END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_scheduled_date < v_week_starts OR p_scheduled_date > v_week_ends THEN
    RAISE EXCEPTION 'date_outside_week'
      USING HINT = format('Date %s is outside week %s–%s', p_scheduled_date, v_week_starts, v_week_ends);
  END IF;

  -- Validate athlete membership
  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = v_group_id AND user_id = p_athlete_id AND role = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  -- Build content snapshot from template
  INSERT INTO plan_workout_releases (
    plan_week_id, group_id, athlete_user_id, template_id,
    scheduled_date, workout_order, workout_type, workout_label, coach_notes,
    release_status, created_by, updated_by,
    content_snapshot
  )
  SELECT
    p_plan_week_id, v_group_id, p_athlete_id, p_template_id,
    p_scheduled_date, p_workout_order,
    COALESCE(p_workout_type,'continuous'), p_workout_label, p_coach_notes,
    'draft', auth.uid(), auth.uid(),
    jsonb_build_object(
      'template_id',   t.id,
      'template_name', t.name,
      'description',   t.description,
      'blocks', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'order_index',               b.order_index,
            'block_type',                b.block_type,
            'duration_seconds',          b.duration_seconds,
            'distance_meters',           b.distance_meters,
            'target_pace_seconds_per_km',b.target_pace_seconds_per_km,
            'target_pace_min_sec_per_km',b.target_pace_min_sec_per_km,
            'target_pace_max_sec_per_km',b.target_pace_max_sec_per_km,
            'target_hr_zone',            b.target_hr_zone,
            'target_hr_min',             b.target_hr_min,
            'target_hr_max',             b.target_hr_max,
            'rpe_target',                b.rpe_target,
            'repeat_count',              b.repeat_count,
            'notes',                     b.notes
          ) ORDER BY b.order_index
        )
        FROM coaching_workout_blocks b
        WHERE b.template_id = t.id
      ), '[]'::jsonb),
      'snapshot_at', now()
    )
  FROM coaching_workout_templates t
  WHERE t.id = p_template_id
  RETURNING id INTO v_release_id;

  IF v_release_id IS NULL THEN
    RAISE EXCEPTION 'template_not_found';
  END IF;

  -- Audit
  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (v_release_id, v_group_id, auth.uid(), 'created',
          jsonb_build_object('template_id', p_template_id, 'date', p_scheduled_date));

  RETURN v_release_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_create_plan_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_plan_workout TO authenticated;

-- ─── 10d. Liberar Treino Manualmente ────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_release_workout(
  p_release_id uuid,
  p_reason     text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id     uuid;
  v_role         text;
  v_status       text;
  v_athlete_id   uuid;
  v_snapshot     jsonb;
  v_template_id  uuid;
BEGIN
  SELECT group_id, release_status, athlete_user_id, content_snapshot, template_id
  INTO v_group_id, v_status, v_athlete_id, v_snapshot, v_template_id
  FROM plan_workout_releases WHERE id = p_release_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status NOT IN ('draft','scheduled') THEN
    RETURN 'already_' || v_status;
  END IF;

  -- Refresh snapshot on release to capture any template edits since draft
  UPDATE plan_workout_releases
  SET
    release_status   = 'released',
    released_at      = now(),
    released_by      = auth.uid(),
    updated_by       = auth.uid(),
    content_snapshot = COALESCE((
      SELECT jsonb_build_object(
        'template_id',   t.id,
        'template_name', t.name,
        'description',   t.description,
        'blocks', COALESCE((
          SELECT jsonb_agg(
            jsonb_build_object(
              'order_index',               b.order_index,
              'block_type',                b.block_type,
              'duration_seconds',          b.duration_seconds,
              'distance_meters',           b.distance_meters,
              'target_pace_seconds_per_km',b.target_pace_seconds_per_km,
              'target_pace_min_sec_per_km',b.target_pace_min_sec_per_km,
              'target_pace_max_sec_per_km',b.target_pace_max_sec_per_km,
              'target_hr_zone',            b.target_hr_zone,
              'target_hr_min',             b.target_hr_min,
              'target_hr_max',             b.target_hr_max,
              'rpe_target',                b.rpe_target,
              'repeat_count',              b.repeat_count,
              'notes',                     b.notes
            ) ORDER BY b.order_index
          )
          FROM coaching_workout_blocks b
          WHERE b.template_id = t.id
        ), '[]'::jsonb),
        'snapshot_at', now()
      )
      FROM coaching_workout_templates t WHERE t.id = v_template_id
    ), v_snapshot)
  WHERE id = p_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (p_release_id, v_group_id, auth.uid(), 'released',
          jsonb_build_object('reason', p_reason, 'released_at', now()));

  RETURN 'released';
END;
$$;
REVOKE ALL ON FUNCTION public.fn_release_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_release_workout TO authenticated;

-- ─── 10e. Agendar Liberação Automática ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_schedule_workout_release(
  p_release_id        uuid,
  p_scheduled_release_at timestamptz
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_role     text;
  v_status   text;
BEGIN
  SELECT group_id, release_status INTO v_group_id, v_status
  FROM plan_workout_releases WHERE id = p_release_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status = 'released' THEN RETURN 'already_released'; END IF;
  IF v_status IN ('cancelled','replaced','archived') THEN
    RAISE EXCEPTION 'invalid_status' USING HINT = 'Cannot schedule a cancelled/replaced/archived workout';
  END IF;

  IF p_scheduled_release_at <= now() THEN
    RAISE EXCEPTION 'scheduled_time_in_past'
      USING HINT = 'Scheduled release time must be in the future';
  END IF;

  UPDATE plan_workout_releases
  SET release_status = 'scheduled',
      scheduled_release_at = p_scheduled_release_at,
      updated_by = auth.uid()
  WHERE id = p_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (p_release_id, v_group_id, auth.uid(), 'scheduled_for_release',
          jsonb_build_object('scheduled_release_at', p_scheduled_release_at));

  RETURN 'scheduled';
END;
$$;
REVOKE ALL ON FUNCTION public.fn_schedule_workout_release FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_schedule_workout_release TO authenticated;

-- ─── 10f. Liberar Semana Inteira ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_bulk_release_week(
  p_plan_week_id uuid,
  p_reason       text DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_role     text;
  v_count    int := 0;
  v_rec      record;
BEGIN
  SELECT group_id INTO v_group_id
  FROM training_plan_weeks WHERE id = p_plan_week_id;
  IF v_group_id IS NULL THEN RAISE EXCEPTION 'week_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Release all draft/scheduled workouts in the week
  FOR v_rec IN
    SELECT id, template_id, content_snapshot
    FROM plan_workout_releases
    WHERE plan_week_id = p_plan_week_id
      AND release_status IN ('draft','scheduled')
  LOOP
    UPDATE plan_workout_releases
    SET
      release_status   = 'released',
      released_at      = now(),
      released_by      = auth.uid(),
      updated_by       = auth.uid(),
      content_snapshot = COALESCE((
        SELECT jsonb_build_object(
          'template_id', t.id, 'template_name', t.name, 'description', t.description,
          'blocks', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'order_index', b.order_index, 'block_type', b.block_type,
              'duration_seconds', b.duration_seconds, 'distance_meters', b.distance_meters,
              'target_pace_min_sec_per_km', b.target_pace_min_sec_per_km,
              'target_pace_max_sec_per_km', b.target_pace_max_sec_per_km,
              'target_hr_zone', b.target_hr_zone, 'rpe_target', b.rpe_target,
              'repeat_count', b.repeat_count, 'notes', b.notes
            ) ORDER BY b.order_index)
            FROM coaching_workout_blocks b WHERE b.template_id = t.id
          ), '[]'::jsonb),
          'snapshot_at', now()
        )
        FROM coaching_workout_templates t WHERE t.id = v_rec.template_id
      ), v_rec.content_snapshot)
    WHERE id = v_rec.id;

    INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
    VALUES (v_rec.id, v_group_id, auth.uid(), 'bulk_released',
            jsonb_build_object('plan_week_id', p_plan_week_id, 'reason', p_reason));

    v_count := v_count + 1;
  END LOOP;

  -- Update week status
  UPDATE training_plan_weeks
  SET status = 'released', updated_at = now()
  WHERE id = p_plan_week_id;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_bulk_release_week FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_bulk_release_week TO authenticated;

-- ─── 10g. Copiar Treino (para outro dia ou outro atleta) ─────────────────────

CREATE OR REPLACE FUNCTION public.fn_copy_workout(
  p_source_id       uuid,
  p_target_date     date,
  p_target_athlete  uuid DEFAULT NULL,
  p_target_week_id  uuid DEFAULT NULL,
  p_coach_notes     text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src         record;
  v_role        text;
  v_new_id      uuid;
  v_athlete     uuid;
  v_week_id     uuid;
BEGIN
  SELECT * INTO v_src FROM plan_workout_releases WHERE id = p_source_id;
  IF v_src IS NULL THEN RAISE EXCEPTION 'source_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_src.group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_athlete := COALESCE(p_target_athlete, v_src.athlete_user_id);
  v_week_id := COALESCE(p_target_week_id, v_src.plan_week_id);

  -- Target athlete must be a member
  IF NOT EXISTS (
    SELECT 1 FROM coaching_members
    WHERE group_id = v_src.group_id AND user_id = v_athlete AND role = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  INSERT INTO plan_workout_releases (
    plan_week_id, group_id, athlete_user_id, template_id,
    scheduled_date, workout_order, workout_type, workout_label, coach_notes,
    release_status, content_snapshot, content_version,
    created_by, updated_by
  ) VALUES (
    v_week_id, v_src.group_id, v_athlete, v_src.template_id,
    p_target_date, v_src.workout_order, v_src.workout_type,
    v_src.workout_label, COALESCE(p_coach_notes, v_src.coach_notes),
    'draft',
    jsonb_set(COALESCE(v_src.content_snapshot,'{}'), '{snapshot_at}', to_jsonb(now())),
    1,
    auth.uid(), auth.uid()
  ) RETURNING id INTO v_new_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (v_new_id, v_src.group_id, auth.uid(), 'copied_from',
          jsonb_build_object('source_id', p_source_id, 'target_date', p_target_date));

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_copy_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_copy_workout TO authenticated;

-- ─── 10h. Mover Treino ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_move_workout(
  p_release_id   uuid,
  p_target_date  date,
  p_target_week_id uuid DEFAULT NULL,
  p_reason       text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_role     text;
  v_status   text;
  v_old_date date;
BEGIN
  SELECT group_id, release_status, scheduled_date
  INTO v_group_id, v_status, v_old_date
  FROM plan_workout_releases WHERE id = p_release_id;
  IF v_group_id IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status IN ('completed','cancelled','replaced','archived') THEN
    RAISE EXCEPTION 'cannot_move_terminal_status';
  END IF;

  UPDATE plan_workout_releases
  SET scheduled_date = p_target_date,
      plan_week_id   = COALESCE(p_target_week_id, plan_week_id),
      updated_by     = auth.uid()
  WHERE id = p_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, old_value, new_value)
  VALUES (p_release_id, v_group_id, auth.uid(), 'moved_from',
          jsonb_build_object('date', v_old_date),
          jsonb_build_object('date', p_target_date, 'reason', p_reason));

  RETURN 'moved';
END;
$$;
REVOKE ALL ON FUNCTION public.fn_move_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_move_workout TO authenticated;

-- ─── 10i. Duplicar Semana ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_duplicate_week(
  p_source_week_id  uuid,
  p_target_starts_on date,
  p_target_plan_id  uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_src_week    record;
  v_role        text;
  v_new_week_id uuid;
  v_week_num    int;
  v_target_plan uuid;
  v_day_offset  int;
  v_dow         int;
  v_rec         record;
BEGIN
  SELECT * INTO v_src_week FROM training_plan_weeks WHERE id = p_source_week_id;
  IF v_src_week IS NULL THEN RAISE EXCEPTION 'source_week_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_src_week.group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  v_dow := EXTRACT(dow FROM p_target_starts_on)::int;
  IF v_dow <> 1 THEN
    RAISE EXCEPTION 'week_must_start_on_monday';
  END IF;

  v_target_plan := COALESCE(p_target_plan_id, v_src_week.plan_id);
  v_day_offset  := p_target_starts_on - v_src_week.starts_on;

  SELECT COALESCE(MAX(week_number),0)+1 INTO v_week_num
  FROM training_plan_weeks WHERE plan_id = v_target_plan;

  INSERT INTO training_plan_weeks (
    plan_id, group_id, week_number, starts_on, cycle_type, label, coach_notes
  ) VALUES (
    v_target_plan, v_src_week.group_id, v_week_num, p_target_starts_on,
    v_src_week.cycle_type,
    COALESCE(v_src_week.label, '') || ' (cópia)',
    v_src_week.coach_notes
  ) RETURNING id INTO v_new_week_id;

  -- Copy all workouts, shifting dates
  FOR v_rec IN
    SELECT * FROM plan_workout_releases
    WHERE plan_week_id = p_source_week_id
      AND release_status NOT IN ('cancelled','replaced','archived')
  LOOP
    INSERT INTO plan_workout_releases (
      plan_week_id, group_id, athlete_user_id, template_id,
      scheduled_date, workout_order, workout_type, workout_label, coach_notes,
      release_status, content_snapshot, content_version,
      created_by, updated_by
    ) VALUES (
      v_new_week_id, v_rec.group_id, v_rec.athlete_user_id, v_rec.template_id,
      v_rec.scheduled_date + v_day_offset, v_rec.workout_order, v_rec.workout_type,
      v_rec.workout_label, v_rec.coach_notes,
      'draft',
      jsonb_set(COALESCE(v_rec.content_snapshot,'{}'), '{snapshot_at}', to_jsonb(now())),
      1,
      auth.uid(), auth.uid()
    );
  END LOOP;

  RETURN v_new_week_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_duplicate_week FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_duplicate_week TO authenticated;

-- ─── 10j. Cancelar Treino ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_cancel_workout(
  p_release_id uuid,
  p_reason     text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id uuid;
  v_role     text;
  v_status   text;
BEGIN
  SELECT group_id, release_status INTO v_group_id, v_status
  FROM plan_workout_releases WHERE id = p_release_id;
  IF v_group_id IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status IN ('cancelled','replaced','archived','completed') THEN
    RETURN 'already_' || v_status;
  END IF;

  UPDATE plan_workout_releases
  SET release_status = 'cancelled',
      cancelled_at   = now(),
      cancelled_by   = auth.uid(),
      updated_by     = auth.uid()
  WHERE id = p_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (p_release_id, v_group_id, auth.uid(), 'cancelled',
          jsonb_build_object('reason', p_reason));

  RETURN 'cancelled';
END;
$$;
REVOKE ALL ON FUNCTION public.fn_cancel_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_cancel_workout TO authenticated;

-- ─── 10k. Substituir Treino Liberado (com rastreabilidade) ──────────────────

CREATE OR REPLACE FUNCTION public.fn_replace_workout(
  p_old_release_id uuid,
  p_new_template_id uuid,
  p_reason          text DEFAULT NULL,
  p_new_notes       text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old         record;
  v_role        text;
  v_new_id      uuid;
BEGIN
  SELECT * INTO v_old FROM plan_workout_releases WHERE id = p_old_release_id;
  IF v_old IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;
  IF v_old.release_status NOT IN ('released','in_progress') THEN
    RAISE EXCEPTION 'can_only_replace_released_or_in_progress';
  END IF;

  SELECT role INTO v_role
  FROM coaching_members WHERE group_id = v_old.group_id AND user_id = auth.uid() LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Create replacement (released immediately)
  INSERT INTO plan_workout_releases (
    plan_week_id, group_id, athlete_user_id, template_id,
    scheduled_date, workout_order, workout_type, workout_label,
    coach_notes, release_status, released_at, released_by,
    content_snapshot, content_version, created_by, updated_by
  )
  SELECT
    v_old.plan_week_id, v_old.group_id, v_old.athlete_user_id, p_new_template_id,
    v_old.scheduled_date, v_old.workout_order, v_old.workout_type, v_old.workout_label,
    COALESCE(p_new_notes, v_old.coach_notes), 'released', now(), auth.uid(),
    (SELECT jsonb_build_object(
      'template_id', t.id, 'template_name', t.name, 'description', t.description,
      'blocks', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'order_index', b.order_index, 'block_type', b.block_type,
          'duration_seconds', b.duration_seconds, 'distance_meters', b.distance_meters,
          'target_pace_min_sec_per_km', b.target_pace_min_sec_per_km,
          'target_pace_max_sec_per_km', b.target_pace_max_sec_per_km,
          'target_hr_zone', b.target_hr_zone, 'rpe_target', b.rpe_target,
          'repeat_count', b.repeat_count, 'notes', b.notes
        ) ORDER BY b.order_index)
        FROM coaching_workout_blocks b WHERE b.template_id = t.id
      ), '[]'::jsonb),
      'snapshot_at', now(), 'replaces_id', p_old_release_id
    ) FROM coaching_workout_templates t WHERE t.id = p_new_template_id),
    1, auth.uid(), auth.uid()
  RETURNING id INTO v_new_id;

  -- Mark old as replaced
  UPDATE plan_workout_releases
  SET release_status = 'replaced',
      replaced_by_id = v_new_id,
      updated_by     = auth.uid()
  WHERE id = p_old_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, old_value, new_value)
  VALUES (p_old_release_id, v_old.group_id, auth.uid(), 'replaced',
          jsonb_build_object('template_id', v_old.template_id),
          jsonb_build_object('new_release_id', v_new_id, 'reason', p_reason));

  RETURN v_new_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_replace_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_replace_workout TO authenticated;

-- ─── 10l. Atleta Marca Treino como Iniciado ──────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_athlete_start_workout(
  p_release_id uuid
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_athlete  uuid;
  v_group_id uuid;
  v_status   text;
BEGIN
  SELECT athlete_user_id, group_id, release_status
  INTO v_athlete, v_group_id, v_status
  FROM plan_workout_releases WHERE id = p_release_id;

  IF v_athlete IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;
  IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;
  IF v_status <> 'released' THEN RETURN 'status_is_' || v_status; END IF;

  UPDATE plan_workout_releases
  SET release_status = 'in_progress', updated_by = auth.uid()
  WHERE id = p_release_id;

  RETURN 'in_progress';
END;
$$;
REVOKE ALL ON FUNCTION public.fn_athlete_start_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_start_workout TO authenticated;

-- ─── 10m. Atleta Marca Treino como Concluído ────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_athlete_complete_workout(
  p_release_id         uuid,
  p_actual_distance_m  double precision DEFAULT NULL,
  p_actual_duration_s  int              DEFAULT NULL,
  p_actual_avg_hr      double precision DEFAULT NULL,
  p_perceived_effort   int              DEFAULT NULL,
  p_mood               int              DEFAULT NULL,
  p_source             text             DEFAULT 'manual'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_rec        record;
  v_completed_id uuid;
BEGIN
  SELECT athlete_user_id, group_id, release_status, content_snapshot
  INTO v_rec
  FROM plan_workout_releases WHERE id = p_release_id;

  IF v_rec.athlete_user_id IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;
  IF v_rec.athlete_user_id <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_rec.release_status NOT IN ('released','in_progress') THEN
    RAISE EXCEPTION 'workout_not_active'
      USING HINT = 'Workout must be released or in_progress to complete';
  END IF;

  IF p_perceived_effort IS NOT NULL AND p_perceived_effort NOT BETWEEN 1 AND 10 THEN
    RAISE EXCEPTION 'invalid_perceived_effort';
  END IF;

  IF p_mood IS NOT NULL AND p_mood NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'invalid_mood';
  END IF;

  INSERT INTO completed_workouts (
    release_id, athlete_user_id, group_id,
    started_at, finished_at,
    planned_snapshot,
    actual_distance_m, actual_duration_s, actual_avg_hr,
    perceived_effort, mood, source
  ) VALUES (
    p_release_id, auth.uid(), v_rec.group_id,
    now(), now(),
    v_rec.content_snapshot,
    p_actual_distance_m, p_actual_duration_s, p_actual_avg_hr,
    p_perceived_effort, p_mood,
    COALESCE(p_source, 'manual')
  ) RETURNING id INTO v_completed_id;

  UPDATE plan_workout_releases
  SET release_status = 'completed', updated_by = auth.uid()
  WHERE id = p_release_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
  VALUES (p_release_id, v_rec.group_id, auth.uid(), 'completed_by_athlete',
          jsonb_build_object(
            'completed_workout_id', v_completed_id,
            'distance_m', p_actual_distance_m,
            'duration_s', p_actual_duration_s,
            'source', p_source
          ));

  RETURN v_completed_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_athlete_complete_workout FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_complete_workout TO authenticated;

-- ─── 10n. Atleta Envia Feedback ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_submit_workout_feedback(
  p_release_id         uuid,
  p_rating             int     DEFAULT NULL,
  p_perceived_effort   int     DEFAULT NULL,
  p_mood               int     DEFAULT NULL,
  p_how_was_it         text    DEFAULT NULL,
  p_what_was_hard      text    DEFAULT NULL,
  p_notes              text    DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_athlete  uuid;
  v_group_id uuid;
  v_status   text;
  v_cw_id    uuid;
  v_fb_id    uuid;
BEGIN
  SELECT athlete_user_id, group_id, release_status
  INTO v_athlete, v_group_id, v_status
  FROM plan_workout_releases WHERE id = p_release_id;

  IF v_athlete IS NULL THEN RAISE EXCEPTION 'release_not_found'; END IF;
  IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_status NOT IN ('in_progress','completed','released') THEN
    RAISE EXCEPTION 'workout_not_active_for_feedback';
  END IF;

  SELECT id INTO v_cw_id
  FROM completed_workouts
  WHERE release_id = p_release_id AND athlete_user_id = auth.uid()
  ORDER BY created_at DESC LIMIT 1;

  INSERT INTO athlete_workout_feedback (
    release_id, completed_workout_id, athlete_user_id, group_id,
    rating, perceived_effort, mood, how_was_it, what_was_hard, notes
  ) VALUES (
    p_release_id, v_cw_id, auth.uid(), v_group_id,
    p_rating, p_perceived_effort, p_mood, p_how_was_it, p_what_was_hard, p_notes
  )
  ON CONFLICT (release_id, athlete_user_id)
  DO UPDATE SET
    rating = EXCLUDED.rating,
    perceived_effort = EXCLUDED.perceived_effort,
    mood = EXCLUDED.mood,
    how_was_it = EXCLUDED.how_was_it,
    what_was_hard = EXCLUDED.what_was_hard,
    notes = EXCLUDED.notes,
    submitted_at = now()
  RETURNING id INTO v_fb_id;

  INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type)
  VALUES (p_release_id, v_group_id, auth.uid(), 'feedback_submitted');

  RETURN v_fb_id;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_submit_workout_feedback FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_submit_workout_feedback TO authenticated;

-- ─── 10o. Sync Delta para o App (cursor incremental) ────────────────────────

CREATE OR REPLACE FUNCTION public.fn_get_training_sync_delta(
  p_device_id    text,
  p_since        timestamptz DEFAULT '1970-01-01 00:00:00+00'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_athlete uuid := auth.uid();
  v_workouts jsonb;
  v_new_cursor timestamptz;
BEGIN
  SELECT COALESCE(jsonb_agg(row_to_json(r.*) ORDER BY r.updated_at), '[]'::jsonb)
  INTO v_workouts
  FROM (
    SELECT
      pwr.id,
      pwr.scheduled_date,
      pwr.workout_order,
      pwr.release_status,
      pwr.workout_type,
      pwr.workout_label,
      pwr.coach_notes,
      pwr.content_snapshot,
      pwr.content_version,
      pwr.released_at,
      pwr.cancelled_at,
      pwr.replaced_by_id,
      pwr.updated_at,
      (SELECT row_to_json(cw.*) FROM completed_workouts cw
       WHERE cw.release_id = pwr.id AND cw.athlete_user_id = v_athlete
       ORDER BY cw.created_at DESC LIMIT 1) AS completed_workout,
      (SELECT row_to_json(fb.*) FROM athlete_workout_feedback fb
       WHERE fb.release_id = pwr.id AND fb.athlete_user_id = v_athlete
       LIMIT 1) AS feedback
    FROM plan_workout_releases pwr
    WHERE pwr.athlete_user_id = v_athlete
      AND pwr.release_status IN ('released','in_progress','completed','cancelled','replaced')
      AND pwr.updated_at > p_since
    ORDER BY pwr.updated_at
    LIMIT 200
  ) r;

  v_new_cursor := COALESCE(
    (SELECT MAX(updated_at) FROM plan_workout_releases
     WHERE athlete_user_id = v_athlete AND updated_at > p_since),
    p_since
  );

  -- Upsert cursor
  INSERT INTO workout_sync_cursors (athlete_user_id, device_id, last_sync_at, last_cursor_ts, synced_count)
  VALUES (v_athlete, p_device_id, now(), v_new_cursor, jsonb_array_length(v_workouts))
  ON CONFLICT (athlete_user_id, device_id) DO UPDATE
  SET last_sync_at = now(),
      last_cursor_ts = EXCLUDED.last_cursor_ts,
      synced_count = workout_sync_cursors.synced_count + EXCLUDED.synced_count;

  RETURN jsonb_build_object(
    'workouts', v_workouts,
    'cursor',   v_new_cursor,
    'count',    jsonb_array_length(v_workouts)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.fn_get_training_sync_delta FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_get_training_sync_delta TO authenticated;

-- ─── 10p. Job: processar liberações agendadas (chamado por pg_cron ou Edge Fn) ─

CREATE OR REPLACE FUNCTION public.fn_process_scheduled_releases()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count int := 0;
  v_rec   record;
BEGIN
  FOR v_rec IN
    SELECT id, group_id, template_id, content_snapshot
    FROM plan_workout_releases
    WHERE release_status = 'scheduled'
      AND scheduled_release_at <= now()
    LIMIT 500
  LOOP
    UPDATE plan_workout_releases
    SET
      release_status   = 'released',
      released_at      = now(),
      released_by      = NULL, -- system release
      updated_by       = NULL,
      content_snapshot = COALESCE((
        SELECT jsonb_build_object(
          'template_id', t.id, 'template_name', t.name, 'description', t.description,
          'blocks', COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
              'order_index', b.order_index, 'block_type', b.block_type,
              'duration_seconds', b.duration_seconds, 'distance_meters', b.distance_meters,
              'target_pace_min_sec_per_km', b.target_pace_min_sec_per_km,
              'target_pace_max_sec_per_km', b.target_pace_max_sec_per_km,
              'target_hr_zone', b.target_hr_zone, 'rpe_target', b.rpe_target,
              'repeat_count', b.repeat_count, 'notes', b.notes
            ) ORDER BY b.order_index)
            FROM coaching_workout_blocks b WHERE b.template_id = t.id
          ), '[]'::jsonb),
          'snapshot_at', now()
        )
        FROM coaching_workout_templates t WHERE t.id = v_rec.template_id
      ), v_rec.content_snapshot)
    WHERE id = v_rec.id;

    INSERT INTO workout_change_log (release_id, group_id, changed_by, change_type, new_value)
    VALUES (v_rec.id, v_rec.group_id, NULL, 'released',
            jsonb_build_object('trigger', 'scheduled_job', 'released_at', now()));

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public.fn_process_scheduled_releases FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_process_scheduled_releases TO service_role;

-- ═══════════════════════════════════════════════════════════════════════════
-- 11. Planned vs Completed VIEW (para o portal)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW public.v_planned_vs_completed AS
SELECT
  pwr.id                                            AS release_id,
  pwr.group_id,
  pwr.athlete_user_id,
  pwr.scheduled_date,
  pwr.workout_type,
  pwr.workout_label,
  pwr.release_status,
  pwr.content_version,
  pwr.coach_notes,
  -- Planned targets from snapshot
  (pwr.content_snapshot->>'template_name')          AS planned_template_name,
  (SELECT SUM(
    CASE
      WHEN (b->>'block_type') = 'repeat' THEN 0
      ELSE COALESCE((b->>'distance_meters')::float, 0)
    END
  ) FROM jsonb_array_elements(COALESCE(pwr.content_snapshot->'blocks','[]')) b
  )                                                 AS planned_distance_m,
  -- Actual
  cw.actual_distance_m,
  cw.actual_duration_s,
  cw.actual_avg_pace_s_km,
  cw.actual_avg_hr,
  cw.perceived_effort                               AS completed_effort,
  cw.finished_at                                    AS completed_at,
  -- Feedback
  fb.rating                                         AS feedback_rating,
  fb.mood                                           AS feedback_mood,
  fb.how_was_it                                     AS feedback_text,
  -- Compliance
  CASE
    WHEN pwr.release_status = 'completed'
         AND cw.actual_distance_m IS NOT NULL
         AND (pwr.content_snapshot->'blocks') IS NOT NULL
         AND (SELECT SUM(COALESCE((b->>'distance_meters')::float,0))
              FROM jsonb_array_elements(COALESCE(pwr.content_snapshot->'blocks','[]')) b) > 0
    THEN ROUND(
      (cw.actual_distance_m /
       (SELECT SUM(COALESCE((b->>'distance_meters')::float,0))
        FROM jsonb_array_elements(COALESCE(pwr.content_snapshot->'blocks','[]')) b)
      * 100)::numeric, 1)
    ELSE NULL
  END                                               AS compliance_pct
FROM public.plan_workout_releases pwr
LEFT JOIN public.completed_workouts cw
  ON cw.release_id = pwr.id
LEFT JOIN public.athlete_workout_feedback fb
  ON fb.release_id = pwr.id AND fb.athlete_user_id = pwr.athlete_user_id;

-- ═══════════════════════════════════════════════════════════════════════════
-- 12. pg_cron: agendar processamento automático de releases (a cada 5 min)
--    Só roda se pg_cron estiver disponível (Supabase Pro+)
-- ═══════════════════════════════════════════════════════════════════════════

DO $cron_setup$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'cron' AND table_name = 'job'
  ) THEN
    PERFORM cron.schedule(
      'process-scheduled-workout-releases',
      '*/5 * * * *',
      $job$SELECT public.fn_process_scheduled_releases()$job$
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- pg_cron not available — releases will be processed by Edge Function instead
  NULL;
END;
$cron_setup$;

COMMIT;
