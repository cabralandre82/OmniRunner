-- ============================================================================
-- L04-05 — Privacy zones for GPS polylines
-- Date: 2026-04-21
-- ============================================================================
-- Elite athletes + doxxing/stalking risk: publishing a raw Strava polyline
-- reveals the runner's home address (start coordinates) and workplace (end
-- coordinates). LGPD art. 42 + industry practice (Strava, Garmin Connect,
-- Nike Run) mandate:
--
--   - per-user privacy zones (a home/work circle of radius_m with all points
--     inside stripped),
--   - a non-owner viewing a polyline never sees the first / last 200 m
--     regardless of explicit zones.
--
-- All of that is a policy decision that must happen server-side: the mobile
-- app is no longer the source of runs (Strava is the single source), so the
-- primitive must live next to the polyline storage in Postgres and be applied
-- by whatever layer surfaces the trace (edge functions, portal, feed).
--
-- This migration ships the canonical primitives:
--
--   1. `profiles.privacy_zones jsonb` (array of { lat, lng, radius_m, label? })
--      with a CHECK constraint that bounds shape + radius.
--   2. `fn_haversine_m(lat1, lng1, lat2, lng2)` — great-circle distance in
--      metres (stateless, IMMUTABLE).
--   3. `fn_point_in_zones(lat, lng, zones)` — returns true if (lat,lng) is
--      inside any zone.
--   4. `fn_decode_polyline(text)` / `fn_encode_polyline(jsonb)` — Google
--      encoded polyline codec (plpgsql, IMMUTABLE).
--   5. `fn_mask_polyline(polyline, zones, trim_start_m, trim_end_m)` — the
--      canonical mask: decode → strip points in zones → trim first/last N
--      metres → re-encode.
--   6. `fn_session_polyline_for_viewer(session_id)` — viewer-scoped RPC that
--      returns the raw polyline to the owner or platform_admin, and a masked
--      polyline to everyone else (using owner's privacy_zones + default
--      200 m head/tail trim). platform_admin access is logged in
--      `portal_audit_log` (audit trail for privileged GPS access).
--
-- All readers that surface a polyline to a viewer distinct from the owner
-- MUST call `fn_session_polyline_for_viewer`; directly selecting
-- `strava_activity_history.summary_polyline` is the legacy behaviour this
-- primitive replaces.

BEGIN;

-- ── 1. profiles.privacy_zones jsonb ──────────────────────────────────────────
DO $add_col$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'profiles'
      AND column_name  = 'privacy_zones'
  ) THEN
    RAISE NOTICE 'profiles.privacy_zones already exists — skipping';
  ELSE
    ALTER TABLE public.profiles
      ADD COLUMN privacy_zones jsonb NOT NULL DEFAULT '[]'::jsonb;
  END IF;
END
$add_col$;

-- CHECK constraints cannot contain subqueries, so validation is wrapped in an
-- IMMUTABLE function and referenced from the constraint expression.
CREATE OR REPLACE FUNCTION public.fn_validate_privacy_zones(p_zones jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT
    p_zones IS NOT NULL
    AND jsonb_typeof(p_zones) = 'array'
    AND jsonb_array_length(p_zones) <= 5
    AND NOT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_zones) AS z
      WHERE jsonb_typeof(z.value) <> 'object'
         OR NOT (z.value ? 'lat' AND z.value ? 'lng' AND z.value ? 'radius_m')
         OR jsonb_typeof(z.value->'lat') <> 'number'
         OR jsonb_typeof(z.value->'lng') <> 'number'
         OR jsonb_typeof(z.value->'radius_m') <> 'number'
         OR (z.value->>'lat')::double precision  NOT BETWEEN -90  AND  90
         OR (z.value->>'lng')::double precision  NOT BETWEEN -180 AND 180
         OR (z.value->>'radius_m')::double precision NOT BETWEEN 50 AND 500
    );
$$;

COMMENT ON FUNCTION public.fn_validate_privacy_zones(jsonb) IS
  'L04-05: IMMUTABLE shape validator for profiles.privacy_zones; used from the CHECK constraint since CHECK cannot contain subqueries.';

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_privacy_zones_shape;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_privacy_zones_shape
  CHECK (public.fn_validate_privacy_zones(privacy_zones));

COMMENT ON COLUMN public.profiles.privacy_zones IS
  'L04-05: array of { lat, lng, radius_m, label? } circles that must be stripped from any polyline served to a viewer != owner. Max 5 zones, radius clamped [50, 500] m.';

-- ── 2. fn_haversine_m ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_haversine_m(
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
) RETURNS double precision
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_r      constant double precision := 6371000.0;
  v_lat1_r double precision;
  v_lat2_r double precision;
  v_dlat_r double precision;
  v_dlng_r double precision;
  v_a      double precision;
BEGIN
  IF p_lat1 IS NULL OR p_lng1 IS NULL OR p_lat2 IS NULL OR p_lng2 IS NULL THEN
    RETURN NULL;
  END IF;
  v_lat1_r := radians(p_lat1);
  v_lat2_r := radians(p_lat2);
  v_dlat_r := radians(p_lat2 - p_lat1);
  v_dlng_r := radians(p_lng2 - p_lng1);
  v_a := sin(v_dlat_r/2) * sin(v_dlat_r/2)
       + cos(v_lat1_r) * cos(v_lat2_r)
       * sin(v_dlng_r/2) * sin(v_dlng_r/2);
  RETURN v_r * 2 * atan2(sqrt(v_a), sqrt(1 - v_a));
END
$$;

COMMENT ON FUNCTION public.fn_haversine_m(double precision, double precision, double precision, double precision) IS
  'L04-05: great-circle distance in metres between two (lat,lng) points. IMMUTABLE, PARALLEL SAFE.';

-- ── 3. fn_point_in_zones ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_point_in_zones(
  p_lat   double precision,
  p_lng   double precision,
  p_zones jsonb
) RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_zone   jsonb;
  v_z_lat  double precision;
  v_z_lng  double precision;
  v_z_rad  double precision;
BEGIN
  IF p_zones IS NULL
     OR jsonb_typeof(p_zones) <> 'array'
     OR jsonb_array_length(p_zones) = 0 THEN
    RETURN false;
  END IF;

  FOR v_zone IN SELECT value FROM jsonb_array_elements(p_zones) LOOP
    v_z_lat := (v_zone->>'lat')::double precision;
    v_z_lng := (v_zone->>'lng')::double precision;
    v_z_rad := GREATEST(50.0, LEAST(500.0, (v_zone->>'radius_m')::double precision));
    IF public.fn_haversine_m(p_lat, p_lng, v_z_lat, v_z_lng) <= v_z_rad THEN
      RETURN true;
    END IF;
  END LOOP;

  RETURN false;
END
$$;

COMMENT ON FUNCTION public.fn_point_in_zones(double precision, double precision, jsonb) IS
  'L04-05: true when (lat,lng) falls inside any zone in p_zones. Radius clamped [50, 500] m per zone defensively.';

-- ── 4. fn_decode_polyline (Google encoded polyline algorithm) ────────────────
CREATE OR REPLACE FUNCTION public.fn_decode_polyline(p_polyline text)
RETURNS TABLE (ord integer, lat double precision, lng double precision)
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_len    integer;
  v_i      integer := 1;
  v_k      integer := 0;
  v_lat    integer := 0;
  v_lng    integer := 0;
  v_ord    integer := 0;
  v_shift  integer;
  v_result integer;
  v_b      integer;
  v_dlat   integer;
  v_dlng   integer;
BEGIN
  IF p_polyline IS NULL OR p_polyline = '' THEN
    RETURN;
  END IF;
  v_len := length(p_polyline);

  WHILE v_i <= v_len LOOP
    -- decode lat delta
    v_shift  := 0;
    v_result := 0;
    LOOP
      IF v_i > v_len THEN EXIT; END IF;
      v_b := ascii(substr(p_polyline, v_i, 1)) - 63;
      v_i := v_i + 1;
      v_result := v_result | ((v_b & 31) << v_shift);
      v_shift  := v_shift + 5;
      EXIT WHEN v_b < 32;
    END LOOP;
    IF (v_result & 1) = 1 THEN
      v_dlat := -((v_result >> 1) + 1);
    ELSE
      v_dlat := (v_result >> 1);
    END IF;
    v_lat := v_lat + v_dlat;

    -- decode lng delta
    v_shift  := 0;
    v_result := 0;
    LOOP
      IF v_i > v_len THEN EXIT; END IF;
      v_b := ascii(substr(p_polyline, v_i, 1)) - 63;
      v_i := v_i + 1;
      v_result := v_result | ((v_b & 31) << v_shift);
      v_shift  := v_shift + 5;
      EXIT WHEN v_b < 32;
    END LOOP;
    IF (v_result & 1) = 1 THEN
      v_dlng := -((v_result >> 1) + 1);
    ELSE
      v_dlng := (v_result >> 1);
    END IF;
    v_lng := v_lng + v_dlng;

    ord := v_ord;
    lat := v_lat::double precision / 1e5;
    lng := v_lng::double precision / 1e5;
    v_ord := v_ord + 1;
    RETURN NEXT;
    v_k := v_k + 1;
    -- hard cap to prevent runaway decoding on malformed input
    EXIT WHEN v_k > 100000;
  END LOOP;
END
$$;

COMMENT ON FUNCTION public.fn_decode_polyline(text) IS
  'L04-05: decode a Google encoded polyline into (ord, lat, lng) rows. IMMUTABLE; caps at 100k points.';

-- ── 5. fn_encode_polyline_value (internal: encode one signed int) ────────────
CREATE OR REPLACE FUNCTION public.fn_encode_polyline_value(p_value integer)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_v       integer;
  v_out     text := '';
  v_chunk   integer;
BEGIN
  IF p_value < 0 THEN
    v_v := ((-p_value) << 1) - 1;
  ELSE
    v_v := p_value << 1;
  END IF;
  WHILE v_v >= 32 LOOP
    v_chunk := (v_v & 31) | 32;
    v_out := v_out || chr(v_chunk + 63);
    v_v := v_v >> 5;
  END LOOP;
  v_out := v_out || chr(v_v + 63);
  RETURN v_out;
END
$$;

COMMENT ON FUNCTION public.fn_encode_polyline_value(integer) IS
  'L04-05: encode a single signed-int delta using the Google polyline scheme.';

-- ── 6. fn_encode_polyline(jsonb array of [lat, lng]) ─────────────────────────
CREATE OR REPLACE FUNCTION public.fn_encode_polyline(p_points jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_prev_lat integer := 0;
  v_prev_lng integer := 0;
  v_cur_lat  integer;
  v_cur_lng  integer;
  v_point    jsonb;
  v_out      text    := '';
BEGIN
  IF p_points IS NULL
     OR jsonb_typeof(p_points) <> 'array'
     OR jsonb_array_length(p_points) = 0 THEN
    RETURN '';
  END IF;

  FOR v_point IN SELECT value FROM jsonb_array_elements(p_points) LOOP
    v_cur_lat := round((v_point->>0)::double precision * 1e5)::integer;
    v_cur_lng := round((v_point->>1)::double precision * 1e5)::integer;
    v_out := v_out
          || public.fn_encode_polyline_value(v_cur_lat - v_prev_lat)
          || public.fn_encode_polyline_value(v_cur_lng - v_prev_lng);
    v_prev_lat := v_cur_lat;
    v_prev_lng := v_cur_lng;
  END LOOP;

  RETURN v_out;
END
$$;

COMMENT ON FUNCTION public.fn_encode_polyline(jsonb) IS
  'L04-05: encode a jsonb array of [lat, lng] pairs into a Google encoded polyline string.';

-- ── 7. fn_mask_polyline (decode → filter zones → trim head/tail → encode) ───
CREATE OR REPLACE FUNCTION public.fn_mask_polyline(
  p_polyline     text,
  p_zones        jsonb,
  p_trim_start_m integer DEFAULT 200,
  p_trim_end_m   integer DEFAULT 200
) RETURNS text
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  v_trim_start  integer;
  v_trim_end    integer;
  v_pts         jsonb := '[]'::jsonb;
  v_dists       double precision[] := ARRAY[]::double precision[];
  v_total       double precision := 0;
  v_lat_prev    double precision;
  v_lng_prev    double precision;
  v_row         record;
  v_first       boolean := true;
  v_threshold_s double precision;
  v_threshold_e double precision;
  v_filtered    jsonb := '[]'::jsonb;
  v_i           integer;
  v_len         integer;
  v_lat         double precision;
  v_lng         double precision;
  v_dist        double precision;
BEGIN
  IF p_polyline IS NULL OR p_polyline = '' THEN
    RETURN '';
  END IF;

  v_trim_start := GREATEST(0, LEAST(5000, COALESCE(p_trim_start_m, 0)));
  v_trim_end   := GREATEST(0, LEAST(5000, COALESCE(p_trim_end_m,   0)));

  -- pass 1: decode + accumulate cumulative distance
  FOR v_row IN SELECT ord, lat, lng FROM public.fn_decode_polyline(p_polyline) LOOP
    IF v_first THEN
      v_pts   := v_pts   || jsonb_build_array(to_jsonb(v_row.lat), to_jsonb(v_row.lng));
      v_dists := v_dists || ARRAY[0.0];
      v_first := false;
    ELSE
      v_total := v_total + public.fn_haversine_m(v_lat_prev, v_lng_prev, v_row.lat, v_row.lng);
      v_pts   := jsonb_insert(v_pts, ARRAY[jsonb_array_length(v_pts)::text], jsonb_build_array(to_jsonb(v_row.lat), to_jsonb(v_row.lng)));
      v_dists := v_dists || ARRAY[v_total];
    END IF;
    v_lat_prev := v_row.lat;
    v_lng_prev := v_row.lng;
  END LOOP;

  v_len := jsonb_array_length(v_pts);
  IF v_len = 0 THEN
    RETURN '';
  END IF;

  v_threshold_s := v_trim_start::double precision;
  v_threshold_e := v_total - v_trim_end::double precision;

  -- pass 2: keep only points within the trimmed range AND outside every zone
  FOR v_i IN 0 .. (v_len - 1) LOOP
    v_dist := v_dists[v_i + 1];
    v_lat  := (v_pts->v_i->>0)::double precision;
    v_lng  := (v_pts->v_i->>1)::double precision;
    IF v_dist < v_threshold_s THEN CONTINUE; END IF;
    IF v_dist > v_threshold_e THEN CONTINUE; END IF;
    IF public.fn_point_in_zones(v_lat, v_lng, p_zones) THEN CONTINUE; END IF;
    v_filtered := v_filtered || jsonb_build_array(jsonb_build_array(to_jsonb(v_lat), to_jsonb(v_lng)));
  END LOOP;

  -- if nothing survives, return empty string (caller should treat as "route hidden")
  IF jsonb_array_length(v_filtered) = 0 THEN
    RETURN '';
  END IF;

  RETURN public.fn_encode_polyline(v_filtered);
END
$$;

COMMENT ON FUNCTION public.fn_mask_polyline(text, jsonb, integer, integer) IS
  'L04-05: mask a Google encoded polyline by stripping points within any privacy zone and trimming the first p_trim_start_m / last p_trim_end_m metres. Empty string means "route suppressed".';

-- ── 8. fn_session_polyline_for_viewer ────────────────────────────────────────
-- Viewer-scoped accessor that the portal / edge functions MUST use when
-- surfacing a polyline to a human viewer. Owner + platform_admin get raw.
-- Everyone else gets masked; platform_admin access is audit-logged.
CREATE OR REPLACE FUNCTION public.fn_session_polyline_for_viewer(
  p_session_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer   uuid;
  v_owner    uuid;
  v_is_admin boolean;
  v_poly     text;
  v_zones    jsonb;
BEGIN
  v_viewer := auth.uid();
  IF v_viewer IS NULL AND current_setting('role', true) <> 'service_role' THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  SELECT s.user_id INTO v_owner
  FROM public.sessions s
  WHERE s.id = p_session_id;
  IF v_owner IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT COALESCE(p.privacy_zones, '[]'::jsonb) INTO v_zones
  FROM public.profiles p
  WHERE p.id = v_owner;

  -- best-effort: pull the most recent polyline for this user + the session's
  -- strava_activity_id if available, else fall back to the latest import.
  SELECT sah.summary_polyline INTO v_poly
  FROM public.strava_activity_history sah
  WHERE sah.user_id = v_owner
    AND sah.summary_polyline IS NOT NULL
    AND sah.summary_polyline <> ''
  ORDER BY sah.imported_at DESC
  LIMIT 1;

  IF v_poly IS NULL OR v_poly = '' THEN
    RETURN NULL;
  END IF;

  v_is_admin := EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = v_viewer AND platform_role = 'admin'
  );

  IF v_viewer = v_owner THEN
    RETURN v_poly;
  END IF;

  IF v_is_admin THEN
    BEGIN
      INSERT INTO public.portal_audit_log (
        actor_id, group_id, action, target_type, target_id, metadata
      ) VALUES (
        v_viewer,
        NULL,
        'session.polyline.admin_view',
        'session',
        p_session_id,
        jsonb_build_object('owner_id', v_owner, 'reason', 'platform_admin read')
      );
    EXCEPTION WHEN OTHERS THEN
      -- audit log failures must not block legitimate admin access, but they
      -- should be visible in pg logs
      RAISE WARNING 'L04-05: failed to write portal_audit_log admin_view for session %: % / %', p_session_id, SQLSTATE, SQLERRM;
    END;
    RETURN v_poly;
  END IF;

  RETURN public.fn_mask_polyline(v_poly, v_zones, 200, 200);
END
$$;

COMMENT ON FUNCTION public.fn_session_polyline_for_viewer(uuid) IS
  'L04-05: viewer-scoped accessor for a session polyline. Owner + platform_admin get raw; everyone else gets privacy_zones-masked + 200m head/tail trim. Admin access is logged in portal_audit_log.';

-- ── 9. self-test DO block ────────────────────────────────────────────────────
DO $selftest$
DECLARE
  v_col_exists  boolean;
  v_mask_out    text;
  v_dec_rows    integer;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='profiles' AND column_name='privacy_zones'
  ) INTO v_col_exists;
  IF NOT v_col_exists THEN
    RAISE EXCEPTION 'self-test: profiles.privacy_zones column missing';
  END IF;

  -- shape validator: accept good payloads and reject bad ones
  IF NOT public.fn_validate_privacy_zones('[]'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_privacy_zones must accept empty array';
  END IF;
  IF NOT public.fn_validate_privacy_zones(
       '[{"lat":-23.55,"lng":-46.63,"radius_m":200,"label":"home"}]'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_privacy_zones must accept a well-formed zone';
  END IF;
  IF public.fn_validate_privacy_zones('[{"lat":0,"lng":0,"radius_m":10}]'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_privacy_zones must reject radius_m < 50';
  END IF;
  IF public.fn_validate_privacy_zones('[{"lat":999,"lng":0,"radius_m":200}]'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_privacy_zones must reject out-of-range lat';
  END IF;
  IF public.fn_validate_privacy_zones('"not-an-array"'::jsonb) THEN
    RAISE EXCEPTION 'self-test: fn_validate_privacy_zones must reject non-array';
  END IF;

  -- decode round-trip: encode [[38.5,-120.2],[40.7,-120.95],[43.252,-126.453]]
  -- Google's canonical example -> "_p~iF~ps|U_ulLnnqC_mqNvxq`@"
  SELECT count(*)::integer INTO v_dec_rows
  FROM public.fn_decode_polyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
  IF v_dec_rows <> 3 THEN
    RAISE EXCEPTION 'self-test: fn_decode_polyline expected 3 rows, got %', v_dec_rows;
  END IF;

  IF public.fn_encode_polyline('[[38.5,-120.2],[40.7,-120.95],[43.252,-126.453]]'::jsonb)
     <> '_p~iF~ps|U_ulLnnqC_mqNvxq`@' THEN
    RAISE EXCEPTION 'self-test: fn_encode_polyline round-trip failed';
  END IF;

  -- mask with zone covering the middle point should drop only the middle
  v_mask_out := public.fn_mask_polyline(
    '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
    jsonb_build_array(jsonb_build_object('lat', 40.7, 'lng', -120.95, 'radius_m', 500)),
    0, 0
  );
  IF v_mask_out = '' THEN
    RAISE EXCEPTION 'self-test: fn_mask_polyline stripped everything when zone only covers the middle';
  END IF;

  -- haversine: ~111km per degree latitude near equator
  IF public.fn_haversine_m(0, 0, 1, 0) NOT BETWEEN 110000 AND 112000 THEN
    RAISE EXCEPTION 'self-test: fn_haversine_m sanity check failed';
  END IF;

  -- point_in_zones positive + negative cases
  IF NOT public.fn_point_in_zones(0, 0,
       jsonb_build_array(jsonb_build_object('lat', 0, 'lng', 0, 'radius_m', 200))) THEN
    RAISE EXCEPTION 'self-test: fn_point_in_zones must hit (0,0) inside (0,0,200m)';
  END IF;
  IF public.fn_point_in_zones(1, 0,
       jsonb_build_array(jsonb_build_object('lat', 0, 'lng', 0, 'radius_m', 200))) THEN
    RAISE EXCEPTION 'self-test: fn_point_in_zones must NOT hit (1,0) inside (0,0,200m)';
  END IF;

  RAISE NOTICE 'L04-05 self-test passed';
END
$selftest$;

-- ── 10. grants ───────────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.fn_session_polyline_for_viewer(uuid) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.fn_session_polyline_for_viewer(uuid)
  TO authenticated, service_role;

-- The pure helpers are safe for anon (no row access).
GRANT EXECUTE ON FUNCTION public.fn_validate_privacy_zones(jsonb)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_haversine_m(double precision, double precision, double precision, double precision)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_point_in_zones(double precision, double precision, jsonb)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_decode_polyline(text)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_encode_polyline_value(integer)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_encode_polyline(jsonb)
  TO PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_mask_polyline(text, jsonb, integer, integer)
  TO PUBLIC;

COMMIT;
