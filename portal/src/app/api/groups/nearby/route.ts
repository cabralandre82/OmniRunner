import { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";
import {
  apiError,
  apiUnauthorized,
  apiValidationFailed,
  apiOk,
} from "@/lib/api/errors";

/**
 * GET /api/groups/nearby — L22-05 discovery endpoint.
 *
 * Surfaces coaching groups that (a) are approved by the platform,
 * (b) have opted into discovery, and (c) sit within `radius_km`
 * of the caller's supplied coordinates.
 *
 * Privacy posture (see docs/runbooks/GROUPS_NEARBY_RUNBOOK.md):
 *
 * - The caller MUST be an authenticated user. We deliberately do
 *   NOT expose this route to anon — the opt-in lives implicitly in
 *   the mobile UI asking for location permission; the server never
 *   stores the caller's coords.
 * - The raw `base_lat`/`base_lng` stored on `coaching_groups` are
 *   NEVER returned. The RPC `fn_groups_nearby` snaps coords to the
 *   coach's chosen grid (500 m / 1 km / 5 km) before returning them.
 * - `distance_km_approx` is rounded to the nearest km (min 1) so an
 *   attacker cannot triangulate by calling the endpoint from three
 *   positions.
 * - Radius is clamped to [1, 100] km server-side; `limit` is fixed
 *   to 50 inside the RPC. No pagination (nearby search intentionally
 *   bounded — amateur users looking for "groups near me" do not need
 *   page 2).
 *
 * Query params:
 *   - lat        required, numeric in [-90, 90]
 *   - lng        required, numeric in [-180, 180]
 *   - radius_km  optional, integer in [1, 100], default 10
 *
 * Response: `{ ok: true, data: { items: NearbyGroup[] } }`.
 */
function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

interface NearbyGroupRow {
  id: string;
  name: string;
  city: string;
  coach_display_name: string;
  member_count: number;
  distance_km_approx: number;
  base_lat_snapped: number;
  base_lng_snapped: number;
  location_precision_m: number;
}

function parseNumeric(raw: string | null, label: string): number | null {
  if (raw === null || raw === "") return null;
  const n = Number(raw);
  if (!Number.isFinite(n)) {
    throw new Error(`INVALID_${label.toUpperCase()}`);
  }
  return n;
}

export async function GET(req: NextRequest) {
  try {
    const params = req.nextUrl.searchParams;

    let lat: number | null;
    let lng: number | null;
    let radiusKm: number | null;

    try {
      lat = parseNumeric(params.get("lat"), "lat");
      lng = parseNumeric(params.get("lng"), "lng");
      radiusKm = parseNumeric(params.get("radius_km"), "radius_km");
    } catch (err) {
      return apiValidationFailed(req, (err as Error).message);
    }

    if (lat === null || lng === null) {
      return apiValidationFailed(req, "lat and lng are required");
    }

    if (lat < -90 || lat > 90) {
      return apiValidationFailed(req, "lat must be between -90 and 90");
    }

    if (lng < -180 || lng > 180) {
      return apiValidationFailed(req, "lng must be between -180 and 180");
    }

    const clampedRadius = radiusKm === null
      ? 10
      : Math.min(Math.max(Math.round(radiusKm), 1), 100);

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();

    if (authErr || !user) return apiUnauthorized(req);

    const { data, error } = await supabase.rpc("fn_groups_nearby", {
      p_lat: lat,
      p_lng: lng,
      p_radius_km: clampedRadius,
    });

    if (error) {
      logger.error("GET /api/groups/nearby — RPC error", error);
      return apiError(req, "DB_ERROR", error.message, 500);
    }

    const items = (data ?? []) as NearbyGroupRow[];
    return apiOk({ items });
  } catch (err) {
    logger.error("GET /api/groups/nearby", err);
    return apiError(req, "INTERNAL_ERROR", "unexpected error", 500);
  }
}
