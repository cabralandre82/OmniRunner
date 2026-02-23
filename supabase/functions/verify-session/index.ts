import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * verify-session — Supabase Edge Function
 *
 * Server-side anti-cheat validation for workout sessions.
 * Called after a session is synced. Applies speed, teleport, and plausibility
 * checks that complement the client-side IntegrityDetect* modules.
 *
 * JWT is validated manually (verify_jwt = false in config.toml) because the
 * Supabase gateway rejects ES256 anonymous tokens. We call requireUser()
 * from _shared/auth.ts to validate the token server-side.
 *
 * Ping mode: if the body is empty or missing required fields, returns 200
 * with { status: "ok", note: "auth_ok_no_payload", auth_user_id } after
 * successful JWT validation — useful for connectivity/auth auditing.
 *
 * POST /verify-session
 * Headers: Authorization: Bearer <jwt>
 * Body: { session_id, user_id, route, total_distance_m, start_time_ms, end_time_ms }
 */

interface LocationPoint {
  lat: number;
  lng: number;
  alt?: number;
  accuracy?: number;
  speed?: number;
  timestamp_ms: number;
}

interface VerifyPayload {
  session_id: string;
  user_id: string;
  route: LocationPoint[];
  total_distance_m: number;
  start_time_ms: number;
  end_time_ms: number;
  avg_bpm?: number;
}

const MAX_SPEED_MS = 12.5; // ~45 km/h — faster than any human runner
const TELEPORT_THRESHOLD_M = 500; // 500m jump between consecutive points
const MIN_POINTS = 5;
const MIN_DURATION_MS = 60_000; // 1 minute
const MAX_PACE_SEC_KM = 90; // 1:30/km — world record sprint pace
const MIN_DISTANCE_M = 50;

// ── Helpers ──────────────────────────────────────────────────────────────

function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ── Handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  const FN = "verify-session";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Authenticate ──────────────────────────────────────────────
    let user: { id: string; [key: string]: unknown };
    // deno-lint-ignore no-explicit-any
    let db: any;
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 60, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body (allow empty for ping mode) ────────────────────
    let body: Partial<VerifyPayload> = {};
    try {
      body = await requireJson(req) as Partial<VerifyPayload>;
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    // ── 3. Ping mode: body missing required fields ───────────────────
    if (!body.session_id || !body.user_id || !Array.isArray(body.route)) {
      return jsonOk({
        status: "ok",
        note: "auth_ok_no_payload",
        auth_user_id: user.id,
      }, requestId);
    }

    // ── 4. Full verification (existing logic) ────────────────────────
    const fullBody = body as VerifyPayload;
    const flags: string[] = [];

    if (fullBody.route.length < MIN_POINTS) {
      flags.push("TOO_FEW_POINTS");
    }

    const durationMs = fullBody.end_time_ms - fullBody.start_time_ms;
    if (durationMs < MIN_DURATION_MS) {
      flags.push("TOO_SHORT_DURATION");
    }

    if (fullBody.total_distance_m < MIN_DISTANCE_M) {
      flags.push("TOO_SHORT_DISTANCE");
    }

    if (fullBody.route.length >= 2) {
      let speedViolations = 0;
      let teleportViolations = 0;

      for (let i = 1; i < fullBody.route.length; i++) {
        const prev = fullBody.route[i - 1];
        const curr = fullBody.route[i];
        const dt = (curr.timestamp_ms - prev.timestamp_ms) / 1000;

        if (dt <= 0) continue;

        const dist = haversine(prev.lat, prev.lng, curr.lat, curr.lng);
        const speed = dist / dt;

        if (speed > MAX_SPEED_MS) {
          speedViolations++;
        }

        if (dist > TELEPORT_THRESHOLD_M) {
          teleportViolations++;
        }
      }

      const totalSegments = fullBody.route.length - 1;
      if (speedViolations > totalSegments * 0.1) {
        flags.push("SPEED_EXCEEDED");
      }
      if (teleportViolations > 0) {
        flags.push("TELEPORT_DETECTED");
      }
    }

    if (fullBody.total_distance_m > 0 && durationMs > 0) {
      const paceSecKm = (durationMs / 1000) / (fullBody.total_distance_m / 1000);
      if (paceSecKm < MAX_PACE_SEC_KM && fullBody.total_distance_m > 1000) {
        flags.push("IMPLAUSIBLE_PACE");
      }
    }

    const isVerified = flags.length === 0;

    // ── 5. Persist result (service_role bypasses RLS) ────────────────
    const { error } = await db
      .from("sessions")
      .update({
        is_verified: isVerified,
        integrity_flags: flags,
      })
      .eq("id", fullBody.session_id)
      .eq("user_id", fullBody.user_id);

    if (error) {
      const classified = classifyError(error);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      status: "ok",
      session_id: fullBody.session_id,
      is_verified: isVerified,
      integrity_flags: flags,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});
