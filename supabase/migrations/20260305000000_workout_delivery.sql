-- ================================================================
-- FASE 1: Feature flag for TrainingPeaks (OFF by default)
-- FASE 3: Workout Delivery tables, RLS, RPCs
-- ================================================================
BEGIN;

-- ────────────────────────────────────────────────────────────────
-- 1. Feature flag: trainingpeaks_enabled (OFF / 0%)
-- ────────────────────────────────────────────────────────────────
INSERT INTO public.feature_flags (key, enabled, rollout_pct)
VALUES ('trainingpeaks_enabled', false, 0)
ON CONFLICT (key) DO UPDATE SET enabled = false, rollout_pct = 0;

-- ────────────────────────────────────────────────────────────────
-- 2. Tables
-- ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.workout_delivery_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.coaching_groups(id),
  created_by uuid NOT NULL REFERENCES auth.users(id),
  period_start date,
  period_end date,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','publishing','published','closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_batches_group
  ON public.workout_delivery_batches (group_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.workout_delivery_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.coaching_groups(id),
  batch_id uuid NOT NULL REFERENCES public.workout_delivery_batches(id),
  athlete_user_id uuid NOT NULL REFERENCES auth.users(id),
  assignment_id uuid REFERENCES public.coaching_workout_assignments(id),
  export_payload jsonb NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','published','confirmed','failed')),
  published_at timestamptz,
  confirmed_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (batch_id, athlete_user_id, assignment_id)
);

CREATE INDEX IF NOT EXISTS idx_delivery_items_group_batch
  ON public.workout_delivery_items (group_id, batch_id);
CREATE INDEX IF NOT EXISTS idx_delivery_items_athlete
  ON public.workout_delivery_items (athlete_user_id, status);

CREATE TABLE IF NOT EXISTS public.workout_delivery_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id uuid NOT NULL REFERENCES public.coaching_groups(id),
  item_id uuid NOT NULL REFERENCES public.workout_delivery_items(id),
  actor_user_id uuid,
  type text NOT NULL,
  meta jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_delivery_events_item
  ON public.workout_delivery_events (item_id, created_at DESC);

-- updated_at triggers
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

DROP TRIGGER IF EXISTS trg_delivery_batches_updated ON public.workout_delivery_batches;
CREATE TRIGGER trg_delivery_batches_updated
  BEFORE UPDATE ON public.workout_delivery_batches
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

DROP TRIGGER IF EXISTS trg_delivery_items_updated ON public.workout_delivery_items;
CREATE TRIGGER trg_delivery_items_updated
  BEFORE UPDATE ON public.workout_delivery_items
  FOR EACH ROW EXECUTE FUNCTION public.fn_set_updated_at();

-- ────────────────────────────────────────────────────────────────
-- 3. RLS
-- ────────────────────────────────────────────────────────────────
ALTER TABLE public.workout_delivery_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_delivery_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workout_delivery_events  ENABLE ROW LEVEL SECURITY;

-- Batches: staff of group can CRUD
CREATE POLICY batches_staff_select ON public.workout_delivery_batches
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_batches.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant')
    )
  );

CREATE POLICY batches_staff_insert ON public.workout_delivery_batches
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_batches.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach')
    )
  );

CREATE POLICY batches_staff_update ON public.workout_delivery_batches
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_batches.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach')
    )
  );

-- Items: staff full access, athlete reads own
CREATE POLICY items_staff_all ON public.workout_delivery_items
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_items.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant')
    )
  );

CREATE POLICY items_athlete_select ON public.workout_delivery_items
  FOR SELECT USING (
    athlete_user_id = auth.uid()
  );

-- Events: staff full read, staff insert, athlete insert own
CREATE POLICY events_staff_select ON public.workout_delivery_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_events.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant')
    )
  );

CREATE POLICY events_staff_insert ON public.workout_delivery_events
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = workout_delivery_events.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master','coach','assistant')
    )
  );

CREATE POLICY events_athlete_select ON public.workout_delivery_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workout_delivery_items di
      WHERE di.id = workout_delivery_events.item_id
        AND di.athlete_user_id = auth.uid()
    )
  );

CREATE POLICY events_athlete_insert ON public.workout_delivery_events
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.workout_delivery_items di
      WHERE di.id = workout_delivery_events.item_id
        AND di.athlete_user_id = auth.uid()
    )
  );

-- ────────────────────────────────────────────────────────────────
-- 4. RPCs (SECURITY DEFINER, hardened)
-- ────────────────────────────────────────────────────────────────

-- 4a. Create batch
CREATE OR REPLACE FUNCTION public.fn_create_delivery_batch(
  p_group_id uuid,
  p_period_start date DEFAULT NULL,
  p_period_end date DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id uuid;
  v_role text;
BEGIN
  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = p_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO workout_delivery_batches (group_id, created_by, period_start, period_end)
  VALUES (p_group_id, auth.uid(), p_period_start, p_period_end)
  RETURNING id INTO v_batch_id;

  RETURN v_batch_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_create_delivery_batch FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_create_delivery_batch TO authenticated;

-- 4b. Generate delivery items (set-based)
CREATE OR REPLACE FUNCTION public.fn_generate_delivery_items(
  p_batch_id uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_period_start date;
  v_period_end date;
  v_role text;
  v_count int;
BEGIN
  SELECT b.group_id, b.period_start, b.period_end
  INTO v_group_id, v_period_start, v_period_end
  FROM workout_delivery_batches b
  WHERE b.id = p_batch_id;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'batch_not_found';
  END IF;

  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO workout_delivery_items (group_id, batch_id, athlete_user_id, assignment_id, export_payload)
  SELECT
    wa.group_id,
    p_batch_id,
    wa.athlete_user_id,
    wa.id,
    jsonb_build_object(
      'assignment_id', wa.id,
      'template_name', wt.name,
      'template_description', wt.description,
      'scheduled_date', wa.scheduled_date,
      'notes', wa.notes,
      'blocks', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'order', wb.order_index,
            'type', wb.block_type,
            'duration_s', wb.duration_seconds,
            'distance_m', wb.distance_meters,
            'pace_s_km', wb.target_pace_seconds_per_km,
            'hr_zone', wb.target_hr_zone,
            'rpe', wb.rpe_target,
            'notes', wb.notes
          ) ORDER BY wb.order_index
        )
        FROM coaching_workout_blocks wb
        WHERE wb.template_id = wa.template_id
      ), '[]'::jsonb)
    )
  FROM coaching_workout_assignments wa
  JOIN coaching_workout_templates wt ON wt.id = wa.template_id
  WHERE wa.group_id = v_group_id
    AND wa.status = 'planned'
    AND (v_period_start IS NULL OR wa.scheduled_date >= v_period_start)
    AND (v_period_end   IS NULL OR wa.scheduled_date <= v_period_end)
  ON CONFLICT (batch_id, athlete_user_id, assignment_id) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;

  UPDATE workout_delivery_batches
  SET status = 'publishing'
  WHERE id = p_batch_id AND status = 'draft';

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_generate_delivery_items FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_generate_delivery_items TO authenticated;

-- 4c. Mark item published
CREATE OR REPLACE FUNCTION public.fn_mark_item_published(
  p_item_id uuid,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_role text;
  v_status text;
BEGIN
  SELECT di.group_id, di.status INTO v_group_id, v_status
  FROM workout_delivery_items di WHERE di.id = p_item_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;

  SELECT cm.role INTO v_role
  FROM coaching_members cm
  WHERE cm.group_id = v_group_id AND cm.user_id = auth.uid()
  LIMIT 1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master','coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_status = 'published' THEN RETURN 'already_published'; END IF;

  UPDATE workout_delivery_items
  SET status = 'published', published_at = now()
  WHERE id = p_item_id AND status = 'pending';

  INSERT INTO workout_delivery_events (group_id, item_id, actor_user_id, type, meta)
  VALUES (v_group_id, p_item_id, auth.uid(), 'MARK_PUBLISHED',
          CASE WHEN p_note IS NOT NULL THEN jsonb_build_object('note', p_note) END);

  RETURN 'published';
END;
$$;

REVOKE ALL ON FUNCTION public.fn_mark_item_published FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mark_item_published TO authenticated;

-- 4d. Athlete confirm item
CREATE OR REPLACE FUNCTION public.fn_athlete_confirm_item(
  p_item_id uuid,
  p_result text,
  p_reason text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id uuid;
  v_athlete uuid;
  v_status text;
BEGIN
  IF p_result NOT IN ('confirmed','failed') THEN
    RAISE EXCEPTION 'invalid_result';
  END IF;

  SELECT di.group_id, di.athlete_user_id, di.status
  INTO v_group_id, v_athlete, v_status
  FROM workout_delivery_items di WHERE di.id = p_item_id;

  IF v_group_id IS NULL THEN RAISE EXCEPTION 'item_not_found'; END IF;
  IF v_athlete <> auth.uid() THEN RAISE EXCEPTION 'forbidden'; END IF;

  IF v_status IN ('confirmed','failed') THEN RETURN 'already_' || v_status; END IF;

  UPDATE workout_delivery_items
  SET status = p_result,
      confirmed_at = CASE WHEN p_result = 'confirmed' THEN now() ELSE confirmed_at END,
      last_error = CASE WHEN p_result = 'failed' THEN COALESCE(p_reason, 'unknown') ELSE last_error END
  WHERE id = p_item_id AND status = 'published';

  INSERT INTO workout_delivery_events (group_id, item_id, actor_user_id, type, meta)
  VALUES (v_group_id, p_item_id, auth.uid(),
          CASE WHEN p_result = 'confirmed' THEN 'ATHLETE_CONFIRMED' ELSE 'ATHLETE_FAILED' END,
          jsonb_build_object('reason', p_reason, 'note', p_note));

  RETURN p_result;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_athlete_confirm_item FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_athlete_confirm_item TO authenticated;

COMMIT;
