-- ─────────────────────────────────────────────────────────────────────────────
-- coaching_week_templates: abstract reusable week models (not tied to any athlete)
-- coaching_week_template_workouts: workouts inside a template, keyed by day_of_week
-- fn_apply_week_template: applies a template to an athlete's plan week
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Template header table
CREATE TABLE IF NOT EXISTS public.coaching_week_templates (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid        NOT NULL REFERENCES public.coaching_groups(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (length(trim(name)) > 0),
  description text,
  created_by  uuid        NOT NULL REFERENCES public.profiles(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- 2. Workouts inside a template (no scheduled_date — uses day_of_week 0=Mon…6=Sun)
CREATE TABLE IF NOT EXISTS public.coaching_week_template_workouts (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id   uuid        NOT NULL REFERENCES public.coaching_week_templates(id) ON DELETE CASCADE,
  day_of_week   smallint    NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  workout_order smallint    NOT NULL DEFAULT 1,
  workout_type  text        NOT NULL DEFAULT 'continuous',
  workout_label text        NOT NULL CHECK (length(trim(workout_label)) > 0),
  description   text,
  coach_notes   text,
  blocks        jsonb       NOT NULL DEFAULT '[]',
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_cwt_group ON public.coaching_week_templates (group_id);
CREATE INDEX IF NOT EXISTS idx_cwtw_template ON public.coaching_week_template_workouts (template_id);

-- 4. RLS
ALTER TABLE public.coaching_week_templates          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coaching_week_template_workouts  ENABLE ROW LEVEL SECURITY;

-- Group staff (admin_master / coach) can read and write their own group's templates
DROP POLICY IF EXISTS "group_staff_manage_templates" ON public.coaching_week_templates;
CREATE POLICY "group_staff_manage_templates"
  ON public.coaching_week_templates
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.coaching_members cm
      WHERE cm.group_id = coaching_week_templates.group_id
        AND cm.user_id  = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

DROP POLICY IF EXISTS "group_staff_manage_template_workouts" ON public.coaching_week_template_workouts;
CREATE POLICY "group_staff_manage_template_workouts"
  ON public.coaching_week_template_workouts
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.coaching_week_templates t
      JOIN public.coaching_members cm ON cm.group_id = t.group_id
      WHERE t.id         = coaching_week_template_workouts.template_id
        AND cm.user_id   = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );

-- 5. Grants
GRANT ALL ON TABLE public.coaching_week_templates         TO authenticated;
GRANT ALL ON TABLE public.coaching_week_template_workouts TO authenticated;

-- 6. fn_apply_week_template
--    Copies template workouts into an athlete's plan week.
--    day_of_week (0=Mon) + p_week_start_date = scheduled_date.
--    p_overrides: jsonb array of {template_workout_id, workout_label?, coach_notes?,
--                                  workout_type?, description?, blocks?, remove?}
CREATE OR REPLACE FUNCTION public.fn_apply_week_template(
  p_template_id     uuid,
  p_plan_week_id    uuid,
  p_athlete_id      uuid,
  p_week_start_date date,
  p_auto_release    boolean DEFAULT false,
  p_overrides       jsonb   DEFAULT '[]'::jsonb
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_group_id    uuid;
  v_role        text;
  v_release_status text;
  v_created     int := 0;
  v_tw          record;
  v_override    jsonb;
  v_label       text;
  v_notes       text;
  v_blocks      jsonb;
  v_type        text;
  v_desc        text;
  v_remove      boolean;
  v_date        date;
  v_tpl_name    text;
BEGIN
  -- Validate template exists and belongs to a group
  SELECT t.group_id, t.name
  INTO   v_group_id, v_tpl_name
  FROM   public.coaching_week_templates t
  WHERE  t.id = p_template_id;

  IF v_group_id IS NULL THEN
    RAISE EXCEPTION 'template_not_found';
  END IF;

  -- Caller must be staff of that group
  SELECT role INTO v_role
  FROM   public.coaching_members
  WHERE  group_id = v_group_id AND user_id = auth.uid()
  LIMIT  1;

  IF v_role IS NULL OR v_role NOT IN ('admin_master', 'coach') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  -- Athlete must be a member of the same group
  IF NOT EXISTS (
    SELECT 1 FROM public.coaching_members
    WHERE  group_id = v_group_id
      AND  user_id  = p_athlete_id
      AND  role     = 'athlete'
  ) THEN
    RAISE EXCEPTION 'athlete_not_member';
  END IF;

  v_release_status := CASE WHEN p_auto_release THEN 'released' ELSE 'draft' END;

  FOR v_tw IN
    SELECT * FROM public.coaching_week_template_workouts
    WHERE  template_id = p_template_id
    ORDER  BY day_of_week, workout_order
  LOOP
    -- Find per-workout override (if any)
    SELECT elem INTO v_override
    FROM   jsonb_array_elements(COALESCE(p_overrides, '[]'::jsonb)) elem
    WHERE  (elem->>'template_workout_id') = v_tw.id::text
    LIMIT  1;

    v_remove := COALESCE((v_override->>'remove')::boolean, false);
    IF v_remove THEN CONTINUE; END IF;

    v_label  := COALESCE(NULLIF(v_override->>'workout_label', ''), v_tw.workout_label);
    v_notes  := COALESCE(v_override->>'coach_notes',  v_tw.coach_notes);
    v_type   := COALESCE(NULLIF(v_override->>'workout_type', ''), v_tw.workout_type);
    v_desc   := COALESCE(v_override->>'description',  v_tw.description);
    v_blocks := COALESCE(v_override->'blocks',         v_tw.blocks);
    v_date   := p_week_start_date + v_tw.day_of_week;

    INSERT INTO public.plan_workout_releases (
      plan_week_id, group_id, athlete_user_id, template_id,
      scheduled_date, workout_order, workout_type,
      workout_label, coach_notes, release_status,
      created_by, updated_by,
      content_snapshot
    ) VALUES (
      p_plan_week_id, v_group_id, p_athlete_id, NULL,
      v_date, v_tw.workout_order, v_type,
      v_label, v_notes, v_release_status,
      auth.uid(), auth.uid(),
      jsonb_build_object(
        'template_id',   p_template_id,
        'template_name', v_tpl_name,
        'description',   v_desc,
        'blocks',        v_blocks,
        'snapshot_at',   now()
      )
    );

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_apply_week_template FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_apply_week_template TO authenticated;
