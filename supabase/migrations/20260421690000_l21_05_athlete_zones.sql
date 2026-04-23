-- ╔════════════════════════════════════════════════════════════════════════════╗
-- ║ L21-05 — Athlete training zones (pace + HR)                                ║
-- ║                                                                            ║
-- ║ Context:                                                                   ║
-- ║   Elite athletes currently get `skill_bracket` (beginner → elite) as the  ║
-- ║   only prescription handle. That's useless for a coach writing "40 min   ║
-- ║   em Z2 aeróbico" because there's no source of truth for where Z2 lives ║
-- ║   for that specific athlete — it depends on LTHR, threshold pace, HRmax.║
-- ║                                                                            ║
-- ║ Delivers:                                                                  ║
-- ║   1. public.athlete_zones — per-user pace + HR zones, plus anchor         ║
-- ║      metrics (LTHR, threshold pace, VO2max). JSONB payloads validated    ║
-- ║      by IMMUTABLE helper functions so the CHECK constraint doesn't       ║
-- ║      explode on subqueries.                                              ║
-- ║   2. public.athlete_zone_history — append-only audit trail so coaches    ║
-- ║      can see who changed zones and when (critical for training-load      ║
-- ║      attribution and compliance with athlete-facing disclosure).        ║
-- ║   3. fn_validate_pace_zones / fn_validate_hr_zones — IMMUTABLE shape    ║
-- ║      validators.                                                         ║
-- ║   4. fn_zones_compute_from_anchors — derives 5-zone pace + HR            ║
-- ║      distributions from LTHR / threshold pace using canonical            ║
-- ║      Friel (HR) and Daniels (pace) bands.                               ║
-- ║   5. fn_zones_set / fn_zones_classify_pace / fn_zones_classify_hr —      ║
-- ║      SECURITY DEFINER RPCs for write / query.                           ║
-- ║   6. AFTER INSERT/UPDATE trigger that snapshots the full jsonb payload  ║
-- ║      into athlete_zone_history keyed by version.                        ║
-- ╚════════════════════════════════════════════════════════════════════════════╝

BEGIN;

-- ─── 1. validators (IMMUTABLE so they can back CHECK constraints) ───────────

CREATE OR REPLACE FUNCTION public.fn_validate_pace_zones(p_zones jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_count int;
  v_zone jsonb;
  v_prev_max int;
  v_min int;
  v_max int;
  v_number int;
BEGIN
  IF p_zones IS NULL OR jsonb_typeof(p_zones) <> 'array' THEN
    RETURN false;
  END IF;
  v_count := jsonb_array_length(p_zones);
  IF v_count NOT BETWEEN 3 AND 7 THEN
    RETURN false;
  END IF;
  v_prev_max := NULL;
  FOR i IN 0 .. v_count - 1 LOOP
    v_zone := p_zones -> i;
    IF jsonb_typeof(v_zone) <> 'object' THEN RETURN false; END IF;
    IF NOT (v_zone ? 'zone' AND v_zone ? 'min_sec_km' AND v_zone ? 'max_sec_km') THEN
      RETURN false;
    END IF;
    v_number := (v_zone ->> 'zone')::int;
    v_min    := (v_zone ->> 'min_sec_km')::int;
    v_max    := (v_zone ->> 'max_sec_km')::int;
    IF v_number <> i + 1 THEN RETURN false; END IF;
    IF v_min NOT BETWEEN 120 AND 1200 THEN RETURN false; END IF;
    IF v_max NOT BETWEEN 120 AND 1200 THEN RETURN false; END IF;
    IF v_min >= v_max THEN RETURN false; END IF;
    IF v_prev_max IS NOT NULL AND v_min < v_prev_max THEN
      RETURN false;
    END IF;
    v_prev_max := v_max;
  END LOOP;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_pace_zones(jsonb) IS
  'L21-05: validates pace zone jsonb payload. 3-7 zones, ascending by sec/km, bounds 120-1200 sec/km (02:00/km to 20:00/km).';

CREATE OR REPLACE FUNCTION public.fn_validate_hr_zones(p_zones jsonb)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_count int;
  v_zone jsonb;
  v_prev_max int;
  v_min int;
  v_max int;
  v_number int;
BEGIN
  IF p_zones IS NULL OR jsonb_typeof(p_zones) <> 'array' THEN
    RETURN false;
  END IF;
  v_count := jsonb_array_length(p_zones);
  IF v_count NOT BETWEEN 3 AND 7 THEN
    RETURN false;
  END IF;
  v_prev_max := NULL;
  FOR i IN 0 .. v_count - 1 LOOP
    v_zone := p_zones -> i;
    IF jsonb_typeof(v_zone) <> 'object' THEN RETURN false; END IF;
    IF NOT (v_zone ? 'zone' AND v_zone ? 'min_bpm' AND v_zone ? 'max_bpm') THEN
      RETURN false;
    END IF;
    v_number := (v_zone ->> 'zone')::int;
    v_min    := (v_zone ->> 'min_bpm')::int;
    v_max    := (v_zone ->> 'max_bpm')::int;
    IF v_number <> i + 1 THEN RETURN false; END IF;
    IF v_min NOT BETWEEN 40 AND 230 THEN RETURN false; END IF;
    IF v_max NOT BETWEEN 40 AND 230 THEN RETURN false; END IF;
    IF v_min >= v_max THEN RETURN false; END IF;
    IF v_prev_max IS NOT NULL AND v_min < v_prev_max THEN
      RETURN false;
    END IF;
    v_prev_max := v_max;
  END LOOP;
  RETURN true;
END;
$$;

COMMENT ON FUNCTION public.fn_validate_hr_zones(jsonb) IS
  'L21-05: validates HR zone jsonb payload. 3-7 zones, ascending by bpm, bounds 40-230 bpm.';

GRANT EXECUTE ON FUNCTION public.fn_validate_pace_zones(jsonb) TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_validate_hr_zones(jsonb) TO PUBLIC;

-- ─── 2. athlete_zones table ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.athlete_zones (
  user_id                uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pace_zones             jsonb NOT NULL,
  hr_zones               jsonb NOT NULL,
  lthr_bpm               int,
  hr_max_bpm             int,
  hr_rest_bpm            int,
  threshold_pace_sec_km  int,
  vo2max                 numeric(4,1),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             text NOT NULL DEFAULT 'athlete_manual',
  version                int NOT NULL DEFAULT 1,
  CONSTRAINT athlete_zones_pace_zones_shape
    CHECK (public.fn_validate_pace_zones(pace_zones)),
  CONSTRAINT athlete_zones_hr_zones_shape
    CHECK (public.fn_validate_hr_zones(hr_zones)),
  CONSTRAINT athlete_zones_lthr_range
    CHECK (lthr_bpm IS NULL OR lthr_bpm BETWEEN 80 AND 220),
  CONSTRAINT athlete_zones_hr_max_range
    CHECK (hr_max_bpm IS NULL OR hr_max_bpm BETWEEN 120 AND 230),
  CONSTRAINT athlete_zones_hr_rest_range
    CHECK (hr_rest_bpm IS NULL OR hr_rest_bpm BETWEEN 30 AND 110),
  CONSTRAINT athlete_zones_threshold_pace_range
    CHECK (threshold_pace_sec_km IS NULL OR threshold_pace_sec_km BETWEEN 150 AND 900),
  CONSTRAINT athlete_zones_vo2max_range
    CHECK (vo2max IS NULL OR vo2max BETWEEN 15.0 AND 95.0),
  CONSTRAINT athlete_zones_updated_by_enum
    CHECK (updated_by IN ('athlete_manual', 'auto_calculated', 'coach_assigned')),
  CONSTRAINT athlete_zones_hr_order
    CHECK (hr_rest_bpm IS NULL OR hr_max_bpm IS NULL OR hr_rest_bpm < hr_max_bpm)
);

COMMENT ON TABLE public.athlete_zones IS
  'L21-05: per-athlete pace/HR zones and anchor metrics. One row per user.';

CREATE INDEX IF NOT EXISTS athlete_zones_updated_at_idx
  ON public.athlete_zones(updated_at DESC);

ALTER TABLE public.athlete_zones ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_zones_self_read ON public.athlete_zones
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY athlete_zones_coach_read ON public.athlete_zones
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.coaching_members me
      JOIN public.coaching_members athlete
        ON athlete.group_id = me.group_id
      WHERE me.user_id = auth.uid()
        AND me.role IN ('admin_master', 'coach')
        AND athlete.user_id = athlete_zones.user_id
    )
  );

-- Writes go through RPCs; direct INSERT/UPDATE blocked for non-service roles.

-- ─── 3. athlete_zone_history (append-only audit) ────────────────────────────

CREATE TABLE IF NOT EXISTS public.athlete_zone_history (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  version                int NOT NULL,
  pace_zones             jsonb NOT NULL,
  hr_zones               jsonb NOT NULL,
  lthr_bpm               int,
  threshold_pace_sec_km  int,
  vo2max                 numeric(4,1),
  updated_by             text NOT NULL,
  updated_by_user_id     uuid REFERENCES auth.users(id),
  recorded_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT athlete_zone_history_version_positive
    CHECK (version >= 1),
  CONSTRAINT athlete_zone_history_unique_version
    UNIQUE (user_id, version)
);

COMMENT ON TABLE public.athlete_zone_history IS
  'L21-05: append-only audit trail of zone edits. No UPDATE/DELETE allowed.';

CREATE INDEX IF NOT EXISTS athlete_zone_history_user_recorded_idx
  ON public.athlete_zone_history(user_id, recorded_at DESC);

ALTER TABLE public.athlete_zone_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY athlete_zone_history_self_read ON public.athlete_zone_history
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY athlete_zone_history_coach_read ON public.athlete_zone_history
  FOR SELECT USING (
    EXISTS (
      SELECT 1
      FROM public.coaching_members me
      JOIN public.coaching_members athlete
        ON athlete.group_id = me.group_id
      WHERE me.user_id = auth.uid()
        AND me.role IN ('admin_master', 'coach')
        AND athlete.user_id = athlete_zone_history.user_id
    )
  );

CREATE OR REPLACE FUNCTION public.fn_athlete_zone_history_block_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_setting('role', true) = 'service_role' THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'athlete_zone_history is append-only'
    USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS athlete_zone_history_no_update ON public.athlete_zone_history;
CREATE TRIGGER athlete_zone_history_no_update
  BEFORE UPDATE OR DELETE ON public.athlete_zone_history
  FOR EACH ROW EXECUTE FUNCTION public.fn_athlete_zone_history_block_mutation();

-- ─── 4. snapshot trigger ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_athlete_zones_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.athlete_zone_history (
    user_id, version, pace_zones, hr_zones,
    lthr_bpm, threshold_pace_sec_km, vo2max,
    updated_by, updated_by_user_id
  ) VALUES (
    NEW.user_id, NEW.version, NEW.pace_zones, NEW.hr_zones,
    NEW.lthr_bpm, NEW.threshold_pace_sec_km, NEW.vo2max,
    NEW.updated_by, auth.uid()
  );
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_athlete_zones_snapshot() FROM PUBLIC;

DROP TRIGGER IF EXISTS athlete_zones_snapshot_insert ON public.athlete_zones;
CREATE TRIGGER athlete_zones_snapshot_insert
  AFTER INSERT ON public.athlete_zones
  FOR EACH ROW EXECUTE FUNCTION public.fn_athlete_zones_snapshot();

DROP TRIGGER IF EXISTS athlete_zones_snapshot_update ON public.athlete_zones;
CREATE TRIGGER athlete_zones_snapshot_update
  AFTER UPDATE ON public.athlete_zones
  FOR EACH ROW
  WHEN (
    OLD.pace_zones IS DISTINCT FROM NEW.pace_zones
    OR OLD.hr_zones IS DISTINCT FROM NEW.hr_zones
    OR OLD.lthr_bpm IS DISTINCT FROM NEW.lthr_bpm
    OR OLD.threshold_pace_sec_km IS DISTINCT FROM NEW.threshold_pace_sec_km
    OR OLD.vo2max IS DISTINCT FROM NEW.vo2max
  )
  EXECUTE FUNCTION public.fn_athlete_zones_snapshot();

-- ─── 5. fn_zones_compute_from_anchors ───────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_zones_compute_from_anchors(
  p_lthr_bpm int,
  p_threshold_pace_sec_km int
)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_pace jsonb;
  v_hr jsonb;
BEGIN
  IF p_lthr_bpm IS NULL OR p_lthr_bpm NOT BETWEEN 80 AND 220 THEN
    RAISE EXCEPTION 'lthr_bpm out of range [80, 220]' USING ERRCODE = 'P0001';
  END IF;
  IF p_threshold_pace_sec_km IS NULL OR p_threshold_pace_sec_km NOT BETWEEN 150 AND 900 THEN
    RAISE EXCEPTION 'threshold_pace_sec_km out of range [150, 900]' USING ERRCODE = 'P0001';
  END IF;

  -- Daniels VDOT-inspired pace bands, expressed as multipliers of LT pace.
  -- Slower pace = higher sec/km. Z1 is easy (1.25x slower), Z5 is VO2max (0.88x).
  v_pace := jsonb_build_array(
    jsonb_build_object('zone', 1,
      'min_sec_km', round(p_threshold_pace_sec_km * 1.25)::int,
      'max_sec_km', round(p_threshold_pace_sec_km * 1.50)::int),
    jsonb_build_object('zone', 2,
      'min_sec_km', round(p_threshold_pace_sec_km * 1.12)::int,
      'max_sec_km', round(p_threshold_pace_sec_km * 1.25)::int),
    jsonb_build_object('zone', 3,
      'min_sec_km', round(p_threshold_pace_sec_km * 1.03)::int,
      'max_sec_km', round(p_threshold_pace_sec_km * 1.12)::int),
    jsonb_build_object('zone', 4,
      'min_sec_km', round(p_threshold_pace_sec_km * 0.95)::int,
      'max_sec_km', round(p_threshold_pace_sec_km * 1.03)::int),
    jsonb_build_object('zone', 5,
      'min_sec_km', round(p_threshold_pace_sec_km * 0.85)::int,
      'max_sec_km', round(p_threshold_pace_sec_km * 0.95)::int)
  );

  -- Joe Friel 5-zone HR model anchored on LTHR.
  -- Z1 < 85% LTHR, Z2 85-89%, Z3 90-94%, Z4 95-99%, Z5 100-106%.
  v_hr := jsonb_build_array(
    jsonb_build_object('zone', 1,
      'min_bpm', round(p_lthr_bpm * 0.60)::int,
      'max_bpm', round(p_lthr_bpm * 0.85)::int),
    jsonb_build_object('zone', 2,
      'min_bpm', round(p_lthr_bpm * 0.85)::int,
      'max_bpm', round(p_lthr_bpm * 0.89)::int),
    jsonb_build_object('zone', 3,
      'min_bpm', round(p_lthr_bpm * 0.89)::int,
      'max_bpm', round(p_lthr_bpm * 0.94)::int),
    jsonb_build_object('zone', 4,
      'min_bpm', round(p_lthr_bpm * 0.94)::int,
      'max_bpm', round(p_lthr_bpm * 0.99)::int),
    jsonb_build_object('zone', 5,
      'min_bpm', round(p_lthr_bpm * 0.99)::int,
      'max_bpm', round(p_lthr_bpm * 1.06)::int)
  );

  RETURN jsonb_build_object('pace_zones', v_pace, 'hr_zones', v_hr);
END;
$$;

COMMENT ON FUNCTION public.fn_zones_compute_from_anchors(int, int) IS
  'L21-05: derives 5-zone pace (Daniels-style) + HR (Friel-style) distributions from LTHR and threshold pace. Deterministic, callable by UI previews.';

GRANT EXECUTE ON FUNCTION public.fn_zones_compute_from_anchors(int, int) TO authenticated;

-- ─── 6. fn_zones_set ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_zones_set(
  p_user_id uuid,
  p_pace_zones jsonb,
  p_hr_zones jsonb,
  p_lthr_bpm int DEFAULT NULL,
  p_hr_max_bpm int DEFAULT NULL,
  p_hr_rest_bpm int DEFAULT NULL,
  p_threshold_pace_sec_km int DEFAULT NULL,
  p_vo2max numeric DEFAULT NULL,
  p_updated_by text DEFAULT 'athlete_manual'
)
RETURNS public.athlete_zones
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_is_coach boolean := false;
  v_existing public.athlete_zones%ROWTYPE;
  v_next_version int;
  v_result public.athlete_zones%ROWTYPE;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0002';
  END IF;
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id required' USING ERRCODE = 'P0001';
  END IF;

  IF p_updated_by NOT IN ('athlete_manual', 'auto_calculated', 'coach_assigned') THEN
    RAISE EXCEPTION 'invalid updated_by %', p_updated_by USING ERRCODE = 'P0001';
  END IF;

  IF v_caller <> p_user_id THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.coaching_members me
      JOIN public.coaching_members athlete
        ON athlete.group_id = me.group_id
      WHERE me.user_id = v_caller
        AND me.role IN ('admin_master', 'coach')
        AND athlete.user_id = p_user_id
    ) INTO v_is_coach;
    IF NOT v_is_coach THEN
      RAISE EXCEPTION 'only the athlete or a group coach may set zones'
        USING ERRCODE = 'P0003';
    END IF;
    IF p_updated_by = 'athlete_manual' THEN
      RAISE EXCEPTION 'coach cannot set updated_by=athlete_manual'
        USING ERRCODE = 'P0003';
    END IF;
  END IF;

  IF NOT public.fn_validate_pace_zones(p_pace_zones) THEN
    RAISE EXCEPTION 'invalid pace_zones payload' USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.fn_validate_hr_zones(p_hr_zones) THEN
    RAISE EXCEPTION 'invalid hr_zones payload' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO v_existing FROM public.athlete_zones
  WHERE user_id = p_user_id FOR UPDATE;

  v_next_version := COALESCE(v_existing.version, 0) + 1;

  INSERT INTO public.athlete_zones (
    user_id, pace_zones, hr_zones,
    lthr_bpm, hr_max_bpm, hr_rest_bpm,
    threshold_pace_sec_km, vo2max,
    updated_at, updated_by, version
  ) VALUES (
    p_user_id, p_pace_zones, p_hr_zones,
    p_lthr_bpm, p_hr_max_bpm, p_hr_rest_bpm,
    p_threshold_pace_sec_km, p_vo2max,
    now(), p_updated_by, v_next_version
  )
  ON CONFLICT (user_id) DO UPDATE SET
    pace_zones            = EXCLUDED.pace_zones,
    hr_zones              = EXCLUDED.hr_zones,
    lthr_bpm              = EXCLUDED.lthr_bpm,
    hr_max_bpm            = EXCLUDED.hr_max_bpm,
    hr_rest_bpm           = EXCLUDED.hr_rest_bpm,
    threshold_pace_sec_km = EXCLUDED.threshold_pace_sec_km,
    vo2max                = EXCLUDED.vo2max,
    updated_at            = EXCLUDED.updated_at,
    updated_by            = EXCLUDED.updated_by,
    version               = EXCLUDED.version
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_zones_set(
  uuid, jsonb, jsonb, int, int, int, int, numeric, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_zones_set(
  uuid, jsonb, jsonb, int, int, int, int, numeric, text) TO authenticated;

COMMENT ON FUNCTION public.fn_zones_set(
  uuid, jsonb, jsonb, int, int, int, int, numeric, text) IS
  'L21-05: upserts athlete zones. Callable by the athlete themselves or any coach of a group the athlete belongs to. Coaches must not claim athlete_manual.';

-- ─── 7. classify RPCs ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.fn_zones_classify_pace(
  p_user_id uuid,
  p_pace_sec_km int
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_allowed boolean := false;
  v_zones jsonb;
  v_zone jsonb;
  v_zone_num int;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0002';
  END IF;
  IF p_user_id IS NULL OR p_pace_sec_km IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_caller = p_user_id THEN
    v_allowed := true;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.coaching_members me
      JOIN public.coaching_members athlete
        ON athlete.group_id = me.group_id
      WHERE me.user_id = v_caller
        AND me.role IN ('admin_master', 'coach')
        AND athlete.user_id = p_user_id
    ) INTO v_allowed;
  END IF;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'not authorised to classify this athlete'
      USING ERRCODE = 'P0003';
  END IF;

  SELECT pace_zones INTO v_zones FROM public.athlete_zones
   WHERE user_id = p_user_id;
  IF v_zones IS NULL THEN RETURN NULL; END IF;

  FOR i IN 0 .. jsonb_array_length(v_zones) - 1 LOOP
    v_zone := v_zones -> i;
    IF p_pace_sec_km <= (v_zone ->> 'max_sec_km')::int
       AND p_pace_sec_km >= (v_zone ->> 'min_sec_km')::int THEN
      RETURN (v_zone ->> 'zone')::int;
    END IF;
  END LOOP;

  -- Below the fastest zone → return top zone; above slowest → return bottom.
  v_zone := v_zones -> 0;
  IF p_pace_sec_km > (v_zone ->> 'max_sec_km')::int THEN
    RETURN (v_zone ->> 'zone')::int;
  END IF;
  v_zone := v_zones -> (jsonb_array_length(v_zones) - 1);
  RETURN (v_zone ->> 'zone')::int;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_zones_classify_pace(uuid, int) TO authenticated;

CREATE OR REPLACE FUNCTION public.fn_zones_classify_hr(
  p_user_id uuid,
  p_hr_bpm int
)
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_allowed boolean := false;
  v_zones jsonb;
  v_zone jsonb;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = 'P0002';
  END IF;
  IF p_user_id IS NULL OR p_hr_bpm IS NULL THEN
    RETURN NULL;
  END IF;

  IF v_caller = p_user_id THEN
    v_allowed := true;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.coaching_members me
      JOIN public.coaching_members athlete
        ON athlete.group_id = me.group_id
      WHERE me.user_id = v_caller
        AND me.role IN ('admin_master', 'coach')
        AND athlete.user_id = p_user_id
    ) INTO v_allowed;
  END IF;
  IF NOT v_allowed THEN
    RAISE EXCEPTION 'not authorised to classify this athlete'
      USING ERRCODE = 'P0003';
  END IF;

  SELECT hr_zones INTO v_zones FROM public.athlete_zones
   WHERE user_id = p_user_id;
  IF v_zones IS NULL THEN RETURN NULL; END IF;

  FOR i IN 0 .. jsonb_array_length(v_zones) - 1 LOOP
    v_zone := v_zones -> i;
    IF p_hr_bpm >= (v_zone ->> 'min_bpm')::int
       AND p_hr_bpm <= (v_zone ->> 'max_bpm')::int THEN
      RETURN (v_zone ->> 'zone')::int;
    END IF;
  END LOOP;

  v_zone := v_zones -> 0;
  IF p_hr_bpm < (v_zone ->> 'min_bpm')::int THEN
    RETURN (v_zone ->> 'zone')::int;
  END IF;
  v_zone := v_zones -> (jsonb_array_length(v_zones) - 1);
  RETURN (v_zone ->> 'zone')::int;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_zones_classify_hr(uuid, int) TO authenticated;

-- ─── 8. self-tests ──────────────────────────────────────────────────────────

DO $tests$
DECLARE
  v_bool boolean;
  v_preview jsonb;
  v_pace jsonb;
  v_hr jsonb;
BEGIN
  -- pace validator happy path
  v_bool := public.fn_validate_pace_zones(jsonb_build_array(
    jsonb_build_object('zone', 1, 'min_sec_km', 360, 'max_sec_km', 420),
    jsonb_build_object('zone', 2, 'min_sec_km', 330, 'max_sec_km', 360),
    jsonb_build_object('zone', 3, 'min_sec_km', 300, 'max_sec_km', 330)
  ));
  IF NOT v_bool THEN
    RAISE EXCEPTION 'pace validator should have accepted ascending input (actually did not — note: ascending means higher sec/km means slower, so Z1 slowest)';
  END IF;

  -- pace validator rejects zone=0
  v_bool := public.fn_validate_pace_zones(jsonb_build_array(
    jsonb_build_object('zone', 0, 'min_sec_km', 360, 'max_sec_km', 420)
  ));
  IF v_bool THEN RAISE EXCEPTION 'pace validator should have rejected zone=0 or count=1'; END IF;

  -- hr validator happy path
  v_bool := public.fn_validate_hr_zones(jsonb_build_array(
    jsonb_build_object('zone', 1, 'min_bpm',  90, 'max_bpm', 130),
    jsonb_build_object('zone', 2, 'min_bpm', 130, 'max_bpm', 150),
    jsonb_build_object('zone', 3, 'min_bpm', 150, 'max_bpm', 170)
  ));
  IF NOT v_bool THEN RAISE EXCEPTION 'hr validator should have accepted input'; END IF;

  -- hr validator rejects overlap (Z2.max > Z3.min)
  v_bool := public.fn_validate_hr_zones(jsonb_build_array(
    jsonb_build_object('zone', 1, 'min_bpm',  90, 'max_bpm', 130),
    jsonb_build_object('zone', 2, 'min_bpm', 130, 'max_bpm', 160),
    jsonb_build_object('zone', 3, 'min_bpm', 150, 'max_bpm', 170)
  ));
  IF v_bool THEN RAISE EXCEPTION 'hr validator should have rejected overlapping zones'; END IF;

  -- compute anchor — accepts realistic elite-runner values
  v_preview := public.fn_zones_compute_from_anchors(170, 220);
  v_pace := v_preview -> 'pace_zones';
  v_hr   := v_preview -> 'hr_zones';
  IF NOT public.fn_validate_pace_zones(v_pace) THEN
    RAISE EXCEPTION 'computed pace zones failed validation';
  END IF;
  IF NOT public.fn_validate_hr_zones(v_hr) THEN
    RAISE EXCEPTION 'computed hr zones failed validation';
  END IF;

  -- constraint wiring
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'athlete_zones_pace_zones_shape'
       AND conrelid = 'public.athlete_zones'::regclass
  ) THEN
    RAISE EXCEPTION 'athlete_zones_pace_zones_shape missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'athlete_zones_hr_zones_shape'
       AND conrelid = 'public.athlete_zones'::regclass
  ) THEN
    RAISE EXCEPTION 'athlete_zones_hr_zones_shape missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'athlete_zones_updated_by_enum'
       AND conrelid = 'public.athlete_zones'::regclass
  ) THEN
    RAISE EXCEPTION 'athlete_zones_updated_by_enum missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'athlete_zone_history_unique_version'
       AND conrelid = 'public.athlete_zone_history'::regclass
  ) THEN
    RAISE EXCEPTION 'athlete_zone_history_unique_version missing';
  END IF;
END;
$tests$;

COMMIT;
