-- L22-05 — Grupos locais sem descoberta por proximidade
-- =====================================================================
-- Problem
-- -------
-- Amateur runners discover coaching groups strictly by word-of-mouth
-- because the portal/app expose no "groups near me" surface. The
-- finding explicitly calls for `coaching_groups.base_location
-- geography(POINT)` + an endpoint `GET /api/groups/nearby`, with
-- privacy-preserving opt-in on both sides (coach opts the group in,
-- amateur opts in to share approximate location).
--
-- Decision: avoid pulling in PostGIS just for a sub-10k-rows radius
-- search. Store `base_lat`/`base_lng` as numeric(8,5), snap to a
-- coach-chosen grid (500 m / 1 km / 5 km) at read time, and use
-- Haversine with a bounding-box prune. This keeps the extension
-- footprint zero and is more than fast enough for the expected
-- dataset (1k-10k groups today, 100k in 5 years).
--
-- Fix layers (all forward-only, additive)
-- ---------------------------------------
-- (a) `coaching_groups` gains 3 nullable columns:
--     - `base_lat numeric(8,5)` / `base_lng numeric(8,5)` — stored at
--       full 1m precision but never returned raw by any helper here.
--     - `allow_discovery boolean NOT NULL DEFAULT false` — opt-in
--       only. A group is NEVER surfaced in `/groups/nearby` until the
--       coach flips this AND sets coords.
--     - `location_precision_m smallint` with CHECK IN (500, 1000,
--       5000) — coach-chosen resolution. Default NULL until coach
--       provides coords; when opted in, defaults to 1000 m.
--
-- (b) Privacy helpers:
--     - `fn_groups_snap_coord(coord numeric, precision_m int)` — pure
--       function, rounds a WGS84 degree to the grid corresponding to
--       `precision_m`. Never exposes raw input.
--     - Every discovery RPC uses this snap; raw coords NEVER leave
--       the DB.
--
-- (c) Discovery RPC `fn_groups_nearby(p_lat, p_lng, p_radius_km)`:
--     SECURITY DEFINER STABLE. Inputs validated (±90/±180 bounds,
--     radius clamp ≤ 100 km, LIMIT 50). Bounding-box prune on
--     `base_lat` first (cheap), then Haversine refine. Returns
--     rows with {id, name, city, coach_display_name, member_count,
--     distance_km_approx (rounded to 1 km)}. Only approved +
--     discoverable groups surface. Coach identity and full coords
--     NEVER returned.
--
-- (d) Coach settings RPC `fn_group_set_base_location(p_group_id,
--     p_lat, p_lng, p_precision_m, p_allow_discovery)` —
--     SECURITY DEFINER, caller MUST be the coach_user_id of the
--     group (else NOT_GROUP_COACH). Updates the 4 columns
--     transactionally.
--
-- (e) Shape invariant:
--     `fn_coaching_groups_assert_discovery_shape()` raise P0010 if
--     the columns, CHECK, index, or helpers drift. CI guard runs
--     this.
--
-- Cross-refs
-- ----------
-- L04-07  PII redaction — coords are PII-sensitive, hence the snap
--         + opt-in + coach-only write path.
-- L10-07  Edge-fn JWT aud/iss — downstream `/api/groups/nearby`
--         route uses the same enforcement.
-- L22-04  Federação de grupos (future) — same opt-in lifecycle.
-- =====================================================================

BEGIN;

-- (a) Columns on coaching_groups ----------------------------------------------

ALTER TABLE public.coaching_groups
  ADD COLUMN IF NOT EXISTS base_lat numeric(8, 5),
  ADD COLUMN IF NOT EXISTS base_lng numeric(8, 5),
  ADD COLUMN IF NOT EXISTS allow_discovery boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS location_precision_m smallint;

-- Sanity CHECKs (kept on explicit constraint names for L19-08 compliance).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_base_lat_range'
  ) THEN
    ALTER TABLE public.coaching_groups
      ADD CONSTRAINT chk_coaching_groups_base_lat_range
        CHECK (base_lat IS NULL OR (base_lat >= -90 AND base_lat <= 90))
        NOT VALID;
    ALTER TABLE public.coaching_groups
      VALIDATE CONSTRAINT chk_coaching_groups_base_lat_range;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_base_lng_range'
  ) THEN
    ALTER TABLE public.coaching_groups
      ADD CONSTRAINT chk_coaching_groups_base_lng_range
        CHECK (base_lng IS NULL OR (base_lng >= -180 AND base_lng <= 180))
        NOT VALID;
    ALTER TABLE public.coaching_groups
      VALIDATE CONSTRAINT chk_coaching_groups_base_lng_range;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_location_precision'
  ) THEN
    ALTER TABLE public.coaching_groups
      ADD CONSTRAINT chk_coaching_groups_location_precision
        CHECK (location_precision_m IS NULL OR location_precision_m IN (500, 1000, 5000))
        NOT VALID;
    ALTER TABLE public.coaching_groups
      VALIDATE CONSTRAINT chk_coaching_groups_location_precision;
  END IF;

  -- Tie discovery flag to coord presence: enabling discovery requires
  -- coords + precision; flipping discovery off preserves coords (for
  -- re-enable) but they are never returned while flag is false.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_discovery_needs_coords'
  ) THEN
    ALTER TABLE public.coaching_groups
      ADD CONSTRAINT chk_coaching_groups_discovery_needs_coords
        CHECK (
          allow_discovery = false
          OR (
            base_lat IS NOT NULL
            AND base_lng IS NOT NULL
            AND location_precision_m IS NOT NULL
          )
        )
        NOT VALID;
    ALTER TABLE public.coaching_groups
      VALIDATE CONSTRAINT chk_coaching_groups_discovery_needs_coords;
  END IF;
END $$;

-- Partial index for the cheap bounding-box prune in fn_groups_nearby.
-- Includes only discoverable + approved + coord-present rows.
CREATE INDEX IF NOT EXISTS idx_coaching_groups_discovery_lat
  ON public.coaching_groups (base_lat)
  WHERE allow_discovery = true
    AND approval_status = 'approved'
    AND base_lat IS NOT NULL;

-- (b) Privacy helper: snap-to-grid --------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_groups_snap_coord(
  p_coord numeric,
  p_precision_m integer
) RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
  v_deg_per_m numeric;
  v_step       numeric;
BEGIN
  IF p_coord IS NULL OR p_precision_m IS NULL THEN
    RETURN NULL;
  END IF;

  IF p_precision_m NOT IN (500, 1000, 5000) THEN
    RAISE EXCEPTION 'INVALID_PRECISION: allowed values are 500, 1000, 5000'
      USING ERRCODE = '22023';
  END IF;

  -- WGS84 meters-per-degree at equator ≈ 111_320; latitude degrees
  -- cover roughly the same distance regardless of longitude, so the
  -- grid is slightly coarser east-west away from the equator (that
  -- is desired — the amateur gets an even less precise neighbourhood
  -- for groups in Rio vs. Reykjavík).
  v_deg_per_m := 1.0 / 111320.0;
  v_step := p_precision_m * v_deg_per_m;
  RETURN round(p_coord / v_step) * v_step;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_groups_snap_coord(numeric, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_groups_snap_coord(numeric, integer) FROM anon;
REVOKE ALL ON FUNCTION public.fn_groups_snap_coord(numeric, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_groups_snap_coord(numeric, integer) TO service_role;

-- (c) Nearby discovery RPC ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_groups_nearby(
  p_lat numeric,
  p_lng numeric,
  p_radius_km integer DEFAULT 10
) RETURNS TABLE (
  id uuid,
  name text,
  city text,
  coach_display_name text,
  member_count bigint,
  distance_km_approx integer,
  base_lat_snapped numeric,
  base_lng_snapped numeric,
  location_precision_m smallint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_radius_km integer;
  v_lat_deg_per_km numeric := 1.0 / 111.0;
  v_lng_deg_per_km numeric;
BEGIN
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: lat and lng are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_lat < -90 OR p_lat > 90 THEN
    RAISE EXCEPTION 'INVALID_LAT: must be between -90 and 90'
      USING ERRCODE = '22023';
  END IF;

  IF p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'INVALID_LNG: must be between -180 and 180'
      USING ERRCODE = '22023';
  END IF;

  -- Clamp radius to [1, 100]. Anything larger degrades into a full
  -- table scan and defeats the "nearby" UX — force narrower queries.
  v_radius_km := LEAST(GREATEST(COALESCE(p_radius_km, 10), 1), 100);

  -- Longitude degrees-per-km depends on latitude (cos-scale). We use
  -- the viewer's lat as a safe approximation; the bounding box is a
  -- prune, not a precise filter — final distance is Haversine.
  v_lng_deg_per_km := 1.0 / (111.0 * cos(radians(p_lat)));

  RETURN QUERY
  WITH candidates AS (
    SELECT
      g.id,
      g.name,
      g.city,
      g.coach_user_id,
      g.base_lat,
      g.base_lng,
      g.location_precision_m
    FROM public.coaching_groups g
    WHERE g.allow_discovery = true
      AND g.approval_status = 'approved'
      AND g.base_lat IS NOT NULL
      AND g.base_lng IS NOT NULL
      AND g.base_lat BETWEEN p_lat - (v_radius_km * v_lat_deg_per_km)
                         AND p_lat + (v_radius_km * v_lat_deg_per_km)
      AND g.base_lng BETWEEN p_lng - (v_radius_km * v_lng_deg_per_km)
                         AND p_lng + (v_radius_km * v_lng_deg_per_km)
  ),
  scored AS (
    SELECT
      c.*,
      -- Haversine in km. Numerically stable form using asin(sqrt(...)).
      2 * 6371.0 * asin(
        sqrt(
          power(sin(radians((c.base_lat - p_lat) / 2)), 2)
          + cos(radians(p_lat)) * cos(radians(c.base_lat))
            * power(sin(radians((c.base_lng - p_lng) / 2)), 2)
        )
      ) AS dist_km
    FROM candidates c
  )
  SELECT
    s.id,
    s.name,
    s.city,
    COALESCE(p.display_name, 'Coach') AS coach_display_name,
    (SELECT COUNT(*) FROM public.coaching_members cm WHERE cm.group_id = s.id) AS member_count,
    GREATEST(round(s.dist_km)::integer, 1) AS distance_km_approx,
    public.fn_groups_snap_coord(s.base_lat, s.location_precision_m::integer) AS base_lat_snapped,
    public.fn_groups_snap_coord(s.base_lng, s.location_precision_m::integer) AS base_lng_snapped,
    s.location_precision_m
  FROM scored s
  LEFT JOIN public.profiles p ON p.id = s.coach_user_id
  WHERE s.dist_km <= v_radius_km
  ORDER BY s.dist_km ASC
  LIMIT 50;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_groups_nearby(numeric, numeric, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_groups_nearby(numeric, numeric, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_groups_nearby(numeric, numeric, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_groups_nearby(numeric, numeric, integer) TO service_role;

-- (d) Coach-side setter -------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_group_set_base_location(
  p_group_id uuid,
  p_lat numeric,
  p_lng numeric,
  p_precision_m integer DEFAULT 1000,
  p_allow_discovery boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_uid uuid;
  v_coach_user_id uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT coach_user_id INTO v_coach_user_id
    FROM public.coaching_groups
    WHERE id = p_group_id
    FOR UPDATE;

  IF v_coach_user_id IS NULL THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF v_coach_user_id <> v_uid THEN
    RAISE EXCEPTION 'NOT_GROUP_COACH' USING ERRCODE = '42501';
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL THEN
    RAISE EXCEPTION 'INVALID_INPUT: lat and lng are required'
      USING ERRCODE = '22023';
  END IF;

  IF p_lat < -90 OR p_lat > 90 THEN
    RAISE EXCEPTION 'INVALID_LAT' USING ERRCODE = '22023';
  END IF;

  IF p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'INVALID_LNG' USING ERRCODE = '22023';
  END IF;

  IF p_precision_m NOT IN (500, 1000, 5000) THEN
    RAISE EXCEPTION 'INVALID_PRECISION' USING ERRCODE = '22023';
  END IF;

  UPDATE public.coaching_groups
    SET base_lat = p_lat,
        base_lng = p_lng,
        location_precision_m = p_precision_m::smallint,
        allow_discovery = p_allow_discovery
    WHERE id = p_group_id;

  RETURN jsonb_build_object(
    'status', 'ok',
    'group_id', p_group_id,
    'allow_discovery', p_allow_discovery,
    'location_precision_m', p_precision_m
  );
END;
$$;

REVOKE ALL ON FUNCTION public.fn_group_set_base_location(uuid, numeric, numeric, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_group_set_base_location(uuid, numeric, numeric, integer, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_group_set_base_location(uuid, numeric, numeric, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_group_set_base_location(uuid, numeric, numeric, integer, boolean) TO service_role;

-- (e) Shape invariants --------------------------------------------------------

CREATE OR REPLACE FUNCTION public.fn_coaching_groups_assert_discovery_shape()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_missing text[] := ARRAY[]::text[];
BEGIN
  -- Columns.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_groups'
      AND column_name = 'base_lat'
  ) THEN
    v_missing := array_append(v_missing, 'col:base_lat');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_groups'
      AND column_name = 'base_lng'
  ) THEN
    v_missing := array_append(v_missing, 'col:base_lng');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_groups'
      AND column_name = 'allow_discovery'
  ) THEN
    v_missing := array_append(v_missing, 'col:allow_discovery');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'coaching_groups'
      AND column_name = 'location_precision_m'
  ) THEN
    v_missing := array_append(v_missing, 'col:location_precision_m');
  END IF;

  -- CHECK constraints.
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_base_lat_range'
  ) THEN
    v_missing := array_append(v_missing, 'chk:base_lat_range');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_base_lng_range'
  ) THEN
    v_missing := array_append(v_missing, 'chk:base_lng_range');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_location_precision'
  ) THEN
    v_missing := array_append(v_missing, 'chk:location_precision');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_coaching_groups_discovery_needs_coords'
  ) THEN
    v_missing := array_append(v_missing, 'chk:discovery_needs_coords');
  END IF;

  -- Index.
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND indexname = 'idx_coaching_groups_discovery_lat'
  ) THEN
    v_missing := array_append(v_missing, 'idx:discovery_lat');
  END IF;

  -- Helpers.
  IF to_regprocedure('public.fn_groups_snap_coord(numeric,integer)') IS NULL THEN
    v_missing := array_append(v_missing, 'fn:fn_groups_snap_coord');
  END IF;

  IF to_regprocedure('public.fn_groups_nearby(numeric,numeric,integer)') IS NULL THEN
    v_missing := array_append(v_missing, 'fn:fn_groups_nearby');
  END IF;

  IF to_regprocedure('public.fn_group_set_base_location(uuid,numeric,numeric,integer,boolean)') IS NULL THEN
    v_missing := array_append(v_missing, 'fn:fn_group_set_base_location');
  END IF;

  -- Privilege surface: anon MUST NOT execute fn_groups_nearby or
  -- fn_group_set_base_location; authenticated MUST execute both.
  IF has_function_privilege('anon', 'public.fn_groups_nearby(numeric,numeric,integer)', 'EXECUTE') THEN
    v_missing := array_append(v_missing, 'priv:anon_can_execute_fn_groups_nearby');
  END IF;

  IF has_function_privilege('anon', 'public.fn_group_set_base_location(uuid,numeric,numeric,integer,boolean)', 'EXECUTE') THEN
    v_missing := array_append(v_missing, 'priv:anon_can_execute_fn_group_set_base_location');
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.fn_groups_nearby(numeric,numeric,integer)', 'EXECUTE') THEN
    v_missing := array_append(v_missing, 'priv:authenticated_missing_fn_groups_nearby');
  END IF;

  IF NOT has_function_privilege('authenticated', 'public.fn_group_set_base_location(uuid,numeric,numeric,integer,boolean)', 'EXECUTE') THEN
    v_missing := array_append(v_missing, 'priv:authenticated_missing_fn_group_set_base_location');
  END IF;

  IF array_length(v_missing, 1) > 0 THEN
    RAISE EXCEPTION
      'L22-05: coaching_groups discovery shape drift: %',
      array_to_string(v_missing, ', ')
      USING
        ERRCODE = 'P0010',
        HINT = 'See docs/runbooks/GROUPS_NEARBY_RUNBOOK.md and re-apply migration 20260421370000_l22_05_coaching_groups_nearby.sql';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_coaching_groups_assert_discovery_shape() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_coaching_groups_assert_discovery_shape() FROM anon;
REVOKE ALL ON FUNCTION public.fn_coaching_groups_assert_discovery_shape() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.fn_coaching_groups_assert_discovery_shape() TO service_role;

COMMIT;

-- Self-test (separate transaction so COMMIT has already happened).
DO $$
DECLARE
  v_test_coord numeric;
  v_snapped     numeric;
BEGIN
  -- Shape assertion must pass cleanly.
  PERFORM public.fn_coaching_groups_assert_discovery_shape();

  -- Snap helper: 500 m at São Paulo latitude should round ~4 decimal
  -- places. Anything smaller than 1 km at that latitude returns a
  -- number finer than 0.01°; anything at 5 km is coarser than 0.04°.
  v_test_coord := -23.55052;
  v_snapped := public.fn_groups_snap_coord(v_test_coord, 1000);
  IF v_snapped IS NULL OR abs(v_snapped - v_test_coord) > 0.01 THEN
    RAISE EXCEPTION 'L22-05 self-test failed: snap drift at 1km too large (input=% snapped=%)',
      v_test_coord, v_snapped;
  END IF;

  v_snapped := public.fn_groups_snap_coord(v_test_coord, 5000);
  IF v_snapped IS NULL OR abs(v_snapped - v_test_coord) > 0.05 THEN
    RAISE EXCEPTION 'L22-05 self-test failed: snap drift at 5km too large (input=% snapped=%)',
      v_test_coord, v_snapped;
  END IF;

  -- Input validation on fn_groups_nearby.
  BEGIN
    PERFORM public.fn_groups_nearby(NULL::numeric, NULL::numeric, 10);
    RAISE EXCEPTION 'L22-05 self-test failed: fn_groups_nearby accepted NULL coords';
  EXCEPTION
    WHEN sqlstate '22023' THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_groups_nearby(200::numeric, 0::numeric, 10);
    RAISE EXCEPTION 'L22-05 self-test failed: fn_groups_nearby accepted lat=200';
  EXCEPTION
    WHEN sqlstate '22023' THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_groups_nearby(0::numeric, -200::numeric, 10);
    RAISE EXCEPTION 'L22-05 self-test failed: fn_groups_nearby accepted lng=-200';
  EXCEPTION
    WHEN sqlstate '22023' THEN NULL;
  END;

  BEGIN
    PERFORM public.fn_groups_snap_coord(0, 123);
    RAISE EXCEPTION 'L22-05 self-test failed: snap accepted precision=123';
  EXCEPTION
    WHEN sqlstate '22023' THEN NULL;
  END;

  RAISE NOTICE 'L22-05 migration self-test passed';
END $$;
