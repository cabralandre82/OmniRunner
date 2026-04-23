-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L23-05 — Workout template catalogue (Daniels / Pfitzinger / Hudson seeds) ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   A coach who just joined Omni Runner lands on an empty                   ║
-- ║   `coaching_workout_templates` list. The existing flow forces them        ║
-- ║   to author every fartlek, tempo, interval, and long run from scratch.   ║
-- ║   Every endurance coaching textbook (Daniels' Running Formula,           ║
-- ║   Pfitzinger's Advanced Marathoning, Hudson's Run Faster) publishes a    ║
-- ║   canonical library — reproducing these as a catalogue means coaches    ║
-- ║   clone in one click and adjust, instead of starting blank.              ║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. public.workout_template_catalog — global library (no group_id).      ║
-- ║      slug UNIQUE, category CHECK enum, difficulty CHECK [1,5],            ║
-- ║      source CHECK enum (daniels|pfitzinger|hudson|custom),                ║
-- ║      is_active flag so a template can be deprecated without               ║
-- ║      breaking clones.                                                     ║
-- ║   2. public.workout_template_catalog_blocks — per-block spec              ║
-- ║      mirroring coaching_workout_blocks (so clone is a 1:1 copy).          ║
-- ║      Aggregate CHECK ensures order_index is unique per catalog row.      ║
-- ║   3. Seed of 12 canonical templates spanning all 4 sources.               ║
-- ║   4. fn_clone_catalog_template(catalog_id, target_group_id,               ║
-- ║      override_name?) — SECURITY DEFINER; only coach/admin_master of      ║
-- ║      target group can call; returns new template id.                     ║
-- ║      Idempotent: if clone already exists (slug + group), returns         ║
-- ║      existing id.                                                         ║
-- ║   5. fn_list_catalog_templates(category?, source?, difficulty_max?) —    ║
-- ║      STABLE SECURITY INVOKER; returns active templates only.              ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. Catalogue header ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.workout_template_catalog (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  slug           TEXT NOT NULL UNIQUE,
  name           TEXT NOT NULL,
  description    TEXT,
  category       TEXT NOT NULL,
  workout_type   TEXT NOT NULL,
  source         TEXT NOT NULL,
  difficulty     INT NOT NULL DEFAULT 3,
  typical_duration_minutes INT,
  typical_distance_meters  INT,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT workout_template_catalog_slug_shape
    CHECK (slug ~ '^[a-z][a-z0-9_-]{2,62}$'),
  CONSTRAINT workout_template_catalog_category_check
    CHECK (category IN (
      'base', 'tempo', 'threshold', 'interval',
      'long_run', 'recovery', 'fartlek', 'hills',
      'race_pace', 'vo2max', 'strength', 'test'
    )),
  CONSTRAINT workout_template_catalog_workout_type_check
    CHECK (workout_type IN (
      'continuous', 'interval', 'regenerative', 'long_run',
      'strength', 'technique', 'test', 'free', 'race', 'brick'
    )),
  CONSTRAINT workout_template_catalog_source_check
    CHECK (source IN ('daniels', 'pfitzinger', 'hudson', 'custom')),
  CONSTRAINT workout_template_catalog_difficulty_range
    CHECK (difficulty BETWEEN 1 AND 5),
  CONSTRAINT workout_template_catalog_name_len
    CHECK (length(trim(name)) BETWEEN 2 AND 120)
);

COMMENT ON TABLE public.workout_template_catalog IS
  'Global library of canonical workouts (Daniels / Pfitzinger / Hudson). Not tenant-scoped.';

CREATE INDEX IF NOT EXISTS workout_template_catalog_category_idx
  ON public.workout_template_catalog(category)
  WHERE is_active;

CREATE INDEX IF NOT EXISTS workout_template_catalog_source_idx
  ON public.workout_template_catalog(source)
  WHERE is_active;

ALTER TABLE public.workout_template_catalog ENABLE ROW LEVEL SECURITY;

CREATE POLICY workout_template_catalog_public_read ON public.workout_template_catalog
  FOR SELECT USING (is_active = TRUE);

CREATE POLICY workout_template_catalog_platform_admin ON public.workout_template_catalog
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
        AND pa.platform_role = 'admin'
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
        AND pa.platform_role = 'admin'
    )
  );

-- ─── 2. Catalogue blocks ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.workout_template_catalog_blocks (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  catalog_id                 UUID NOT NULL
                                REFERENCES public.workout_template_catalog(id) ON DELETE CASCADE,
  order_index                INT NOT NULL,
  block_type                 TEXT NOT NULL,
  duration_seconds           INT,
  distance_meters            INT,
  target_pace_seconds_per_km INT,
  target_hr_zone             INT,
  rpe_target                 INT,
  notes                      TEXT,
  created_at                 TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT workout_template_catalog_blocks_type_check
    CHECK (block_type IN ('warmup', 'interval', 'recovery', 'cooldown', 'steady')),
  CONSTRAINT workout_template_catalog_blocks_hr_range
    CHECK (target_hr_zone IS NULL OR target_hr_zone BETWEEN 1 AND 5),
  CONSTRAINT workout_template_catalog_blocks_rpe_range
    CHECK (rpe_target IS NULL OR rpe_target BETWEEN 1 AND 10),
  CONSTRAINT workout_template_catalog_blocks_order_non_negative
    CHECK (order_index >= 0),
  CONSTRAINT workout_template_catalog_blocks_has_prescription
    CHECK (duration_seconds IS NOT NULL OR distance_meters IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS workout_template_catalog_blocks_order_uniq
  ON public.workout_template_catalog_blocks(catalog_id, order_index);

ALTER TABLE public.workout_template_catalog_blocks ENABLE ROW LEVEL SECURITY;

CREATE POLICY workout_template_catalog_blocks_public_read ON public.workout_template_catalog_blocks
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.workout_template_catalog cat
      WHERE cat.id = workout_template_catalog_blocks.catalog_id
        AND cat.is_active = TRUE
    )
  );

CREATE POLICY workout_template_catalog_blocks_platform_admin
  ON public.workout_template_catalog_blocks
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
        AND pa.platform_role = 'admin'
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.platform_admins pa
      WHERE pa.user_id = auth.uid()
        AND pa.platform_role = 'admin'
    )
  );

-- ─── 3. Seed: 12 canonical workouts ──────────────────────────────────────────

INSERT INTO public.workout_template_catalog
  (slug, name, description, category, workout_type, source, difficulty,
   typical_duration_minutes, typical_distance_meters)
VALUES
  ('daniels-e-run-60', 'Easy Run 60 min (Daniels E-pace)',
   'Pure aerobic base run at E-pace. 60 minutes conversational effort. Daniels VDOT book.',
   'base', 'continuous', 'daniels', 2, 60, 12000),
  ('daniels-tempo-20', 'Tempo Run 20 min (Daniels T-pace)',
   '15 min warmup, 20 min at Threshold pace, 15 min cooldown. The classic lactate threshold session.',
   'threshold', 'continuous', 'daniels', 3, 50, NULL),
  ('daniels-i-4x1000', 'Intervals 4x1000m (Daniels I-pace)',
   '15 min warmup, 4 x 1000m at Interval pace with 3 min jog recovery, 10 min cooldown. VO2max work.',
   'interval', 'interval', 'daniels', 4, 55, NULL),
  ('daniels-r-8x400', 'Reps 8x400m (Daniels R-pace)',
   '15 min warmup, 8 x 400m at Rep pace with full 400m jog recovery, 10 min cooldown. Speed and form.',
   'vo2max', 'interval', 'daniels', 4, 45, NULL),
  ('pfitzinger-long-24km-gmp', 'Long Run 24km w/ GMP',
   '24km total, final 10km at Goal Marathon Pace. Pfitzinger marathon block staple.',
   'long_run', 'long_run', 'pfitzinger', 4, 135, 24000),
  ('pfitzinger-medium-long-18km', 'Medium-Long Run 18km',
   'Steady aerobic 18km. Pfitzinger recovery-week staple between workouts.',
   'base', 'long_run', 'pfitzinger', 3, 100, 18000),
  ('pfitzinger-lactate-4x1600', 'Lactate Intervals 4x1600m',
   '3km warmup, 4 x 1600m at 5K pace with 400m jog, 2km cooldown. Pfitzinger classic.',
   'threshold', 'interval', 'pfitzinger', 4, 75, NULL),
  ('hudson-fartlek-classic', 'Hudson Fartlek Classic',
   '15 min warmup, 8 x (2 min hard / 1 min easy), 15 min cooldown. Brad Hudson Run Faster.',
   'fartlek', 'interval', 'hudson', 3, 55, NULL),
  ('hudson-hill-strides', 'Hudson Hill Strides',
   '20 min easy warmup, 8 x 10-sec hill strides uphill with walk-down recovery, 15 min easy cooldown.',
   'hills', 'interval', 'hudson', 3, 45, NULL),
  ('hudson-cutdown-long-run', 'Hudson Cutdown Long Run',
   '18km with progressive pace: first 9km easy, next 6km marathon pace, last 3km half-marathon pace.',
   'race_pace', 'long_run', 'hudson', 4, 100, 18000),
  ('recovery-30-jog', 'Recovery Jog 30 min',
   '30 min very easy. Zone 1 only. Day after hard sessions.',
   'recovery', 'regenerative', 'custom', 1, 30, 5000),
  ('test-5k-tt', '5K Time Trial',
   '2km warmup, 5km all-out on flat route, 2km cooldown. Quarterly fitness benchmark.',
   'test', 'test', 'custom', 5, 45, 9000)
ON CONFLICT (slug) DO NOTHING;

-- Block-level seeds for a subset (demonstrating the pattern — coaches can
-- clone and reshape). The remaining catalogue entries render as single-block
-- free-form cards in the mobile until a platform_admin fills the schedule.

INSERT INTO public.workout_template_catalog_blocks
  (catalog_id, order_index, block_type, duration_seconds,
   target_hr_zone, rpe_target, notes)
SELECT cat.id, 0, 'steady', 60*60, 2, 3,
  'Conversational pace, Daniels E-zone. Zero stops.'
FROM public.workout_template_catalog cat
WHERE cat.slug = 'daniels-e-run-60'
ON CONFLICT DO NOTHING;

INSERT INTO public.workout_template_catalog_blocks
  (catalog_id, order_index, block_type, duration_seconds, target_hr_zone, rpe_target, notes)
SELECT cat.id, 0, 'warmup', 15*60, 2, 3, 'Easy warmup, 15 min.'
FROM public.workout_template_catalog cat WHERE cat.slug = 'daniels-tempo-20'
ON CONFLICT DO NOTHING;

INSERT INTO public.workout_template_catalog_blocks
  (catalog_id, order_index, block_type, duration_seconds, target_hr_zone, rpe_target, notes)
SELECT cat.id, 1, 'interval', 20*60, 4, 7,
  'Threshold / T-pace. Comfortably hard, sustainable ~1h race.'
FROM public.workout_template_catalog cat WHERE cat.slug = 'daniels-tempo-20'
ON CONFLICT DO NOTHING;

INSERT INTO public.workout_template_catalog_blocks
  (catalog_id, order_index, block_type, duration_seconds, target_hr_zone, rpe_target, notes)
SELECT cat.id, 2, 'cooldown', 15*60, 1, 2, 'Easy cooldown, 15 min.'
FROM public.workout_template_catalog cat WHERE cat.slug = 'daniels-tempo-20'
ON CONFLICT DO NOTHING;

-- ─── 4. RPC: clone into coaching_workout_templates ────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_clone_catalog_template(
  p_catalog_id UUID,
  p_target_group_id UUID,
  p_override_name TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cat     public.workout_template_catalog%ROWTYPE;
  v_is_auth BOOLEAN;
  v_tpl_id  UUID;
  v_existing_id UUID;
  v_clone_name TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_cat
  FROM public.workout_template_catalog
  WHERE id = p_catalog_id
    AND is_active = TRUE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'catalog template not found or inactive' USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.coaching_members cm
    WHERE cm.group_id = p_target_group_id
      AND cm.user_id = auth.uid()
      AND cm.role IN ('admin_master', 'coach')
  ) INTO v_is_auth;

  IF NOT v_is_auth THEN
    RAISE EXCEPTION 'only coach or admin_master of target group can clone'
      USING ERRCODE = '42501';
  END IF;

  v_clone_name := COALESCE(p_override_name, v_cat.name);

  -- Idempotency: a coach clicking "clone" twice in a row would otherwise
  -- create two identical templates. We fingerprint by (group, slug) via
  -- the description anchor (catalog_slug:<slug>) so a subsequent call
  -- returns the existing id.
  SELECT id INTO v_existing_id
  FROM public.coaching_workout_templates
  WHERE group_id = p_target_group_id
    AND description LIKE '%catalog_slug:' || v_cat.slug || '%'
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN v_existing_id;
  END IF;

  INSERT INTO public.coaching_workout_templates
    (group_id, name, description, workout_type, created_by)
  VALUES
    (p_target_group_id, v_clone_name,
     COALESCE(v_cat.description, '')
       || E'\n\n[catalog_slug:' || v_cat.slug || ']',
     v_cat.workout_type, auth.uid())
  RETURNING id INTO v_tpl_id;

  INSERT INTO public.coaching_workout_blocks
    (template_id, order_index, block_type, duration_seconds, distance_meters,
     target_pace_seconds_per_km, target_hr_zone, rpe_target, notes)
  SELECT v_tpl_id, b.order_index, b.block_type, b.duration_seconds,
         b.distance_meters, b.target_pace_seconds_per_km,
         b.target_hr_zone, b.rpe_target, b.notes
  FROM public.workout_template_catalog_blocks b
  WHERE b.catalog_id = p_catalog_id
  ORDER BY b.order_index;

  RETURN v_tpl_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_clone_catalog_template(UUID, UUID, TEXT) TO authenticated;

-- ─── 5. RPC: list active catalogue ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_list_catalog_templates(
  p_category TEXT DEFAULT NULL,
  p_source TEXT DEFAULT NULL,
  p_difficulty_max INT DEFAULT NULL
) RETURNS TABLE (
  id UUID,
  slug TEXT,
  name TEXT,
  category TEXT,
  workout_type TEXT,
  source TEXT,
  difficulty INT,
  typical_duration_minutes INT,
  typical_distance_meters INT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT cat.id, cat.slug, cat.name, cat.category, cat.workout_type,
         cat.source, cat.difficulty, cat.typical_duration_minutes,
         cat.typical_distance_meters
  FROM public.workout_template_catalog cat
  WHERE cat.is_active = TRUE
    AND (p_category IS NULL OR cat.category = p_category)
    AND (p_source IS NULL OR cat.source = p_source)
    AND (p_difficulty_max IS NULL OR cat.difficulty <= p_difficulty_max)
  ORDER BY cat.source, cat.difficulty, cat.name;
$$;

GRANT EXECUTE ON FUNCTION public.fn_list_catalog_templates(TEXT, TEXT, INT)
  TO authenticated;

-- ─── 6. Self-tests ────────────────────────────────────────────────────────────

DO $selftest$
DECLARE
  v_seed_count INT;
  v_source_count INT;
BEGIN
  SELECT COUNT(*) INTO v_seed_count FROM public.workout_template_catalog;
  IF v_seed_count < 12 THEN
    RAISE EXCEPTION 'self-test: expected at least 12 catalogue seeds, got %', v_seed_count;
  END IF;

  SELECT COUNT(DISTINCT source) INTO v_source_count
  FROM public.workout_template_catalog;
  IF v_source_count < 4 THEN
    RAISE EXCEPTION 'self-test: expected all 4 sources represented, got %', v_source_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.workout_template_catalog
    WHERE slug = 'daniels-tempo-20'
  ) THEN
    RAISE EXCEPTION 'self-test: daniels-tempo-20 seed missing';
  END IF;

  IF (
    SELECT COUNT(*) FROM public.workout_template_catalog_blocks b
    JOIN public.workout_template_catalog c ON c.id = b.catalog_id
    WHERE c.slug = 'daniels-tempo-20'
  ) < 3 THEN
    RAISE EXCEPTION 'self-test: daniels-tempo-20 must have 3 blocks';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_template_catalog_slug_shape'
  ) THEN
    RAISE EXCEPTION 'self-test: catalog slug shape CHECK missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'workout_template_catalog_blocks_order_uniq'
  ) THEN
    RAISE EXCEPTION 'self-test: catalogue blocks order unique index missing';
  END IF;
END;
$selftest$;

COMMIT;
