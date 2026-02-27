import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";
import {
  SPEED_IMPOSSIBLE,
  GPS_JUMP,
  TELEPORT,
  VEHICLE_SUSPECTED,
  NO_MOTION_PATTERN,
  BACKGROUND_GPS_GAP,
  TIME_SKEW,
  TOO_FEW_POINTS,
  TOO_SHORT_DURATION,
  TOO_SHORT_DISTANCE,
  IMPLAUSIBLE_PACE,
  IMPLAUSIBLE_HR_LOW,
  IMPLAUSIBLE_HR_HIGH,
} from "../_shared/integrity_flags.ts";

/**
 * verify-session — Supabase Edge Function
 *
 * Server-side anti-cheat validation for workout sessions.
 * Called after a session is synced. This is the SINGLE PIPELINE that
 * sets is_verified and integrity_flags authoritatively.
 *
 * The server's verdict OVERWRITES any client-side flags.
 * The app may pre-check and show warnings, but the server decides.
 *
 * Flag dictionary: see _shared/integrity_flags.ts
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
  avg_cadence_spm?: number;
}

// ── Thresholds ────────────────────────────────────────────────────────────

const MAX_SPEED_MS = 12.5;           // ~45 km/h — faster than any human runner
const TELEPORT_SPEED_MS = 50.0;      // ~180 km/h — impossible for running
const GPS_JUMP_THRESHOLD_M = 500;    // 500m raw jump
const MAX_ACCURACY_M = 15.0;         // points with accuracy > this are low-quality
const MIN_POINTS = 5;
const MIN_DURATION_MS = 60_000;      // 1 minute
const MAX_PACE_SEC_KM = 90;          // 1:30/km — world record sprint pace
const MIN_DISTANCE_M = 50;
const GPS_GAP_THRESHOLD_MS = 60_000; // 60s gap = background GPS loss
const MOTION_RADIUS_M = 150;         // all points within 150m = no real motion (allows 200m/400m tracks)
const MIN_HR_RUNNING_BPM = 80;      // avg HR below this while running > 1km = suspicious
const MAX_HR_BPM = 220;             // above 220 = physiologically impossible
const HR_CHECK_MIN_DISTANCE_M = 1000; // only check HR if session > 1km
const VEHICLE_MIN_SPEED_KMH = 15;    // avg speed above this is suspicious with low cadence
const VEHICLE_MAX_CADENCE_SPM = 100;  // avg cadence below this at high speed = likely vehicle
const VEHICLE_MIN_DISTANCE_M = 1000;  // only check cadence correlation if session > 1km

// ── Helpers ───────────────────────────────────────────────────────────────

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

function hasGoodAccuracy(p: LocationPoint): boolean {
  return p.accuracy != null && p.accuracy <= MAX_ACCURACY_M;
}

// ── Handler ───────────────────────────────────────────────────────────────

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

    // ── 4. Full verification pipeline ────────────────────────────────
    const p = body as VerifyPayload;
    const flags: string[] = [];
    const durationMs = p.end_time_ms - p.start_time_ms;

    // ─ Quality checks ────────────────────────────────────────────────

    if (p.route.length < MIN_POINTS) {
      flags.push(TOO_FEW_POINTS);
    }

    if (durationMs < MIN_DURATION_MS) {
      flags.push(TOO_SHORT_DURATION);
    }

    if (p.total_distance_m < MIN_DISTANCE_M) {
      flags.push(TOO_SHORT_DISTANCE);
    }

    if (p.total_distance_m > 0 && durationMs > 0) {
      const paceSecKm = (durationMs / 1000) / (p.total_distance_m / 1000);
      if (paceSecKm < MAX_PACE_SEC_KM && p.total_distance_m > 1000) {
        flags.push(IMPLAUSIBLE_PACE);
      }
    }

    // ─ TIME_SKEW: timestamps internally inconsistent ─────────────────

    if (p.end_time_ms <= p.start_time_ms) {
      flags.push(TIME_SKEW);
    } else if (p.route.length >= 2) {
      let negativeDeltas = 0;
      for (let i = 1; i < p.route.length; i++) {
        if (p.route[i].timestamp_ms < p.route[i - 1].timestamp_ms) {
          negativeDeltas++;
        }
      }
      if (negativeDeltas > p.route.length * 0.1) {
        flags.push(TIME_SKEW);
      }
    }

    // ─ Route-based checks (need >= 2 points) ─────────────────────────

    if (p.route.length >= 2) {
      let speedViolations = 0;
      let gpsJumps = 0;
      let teleportViolations = 0;
      let maxGapMs = 0;
      const totalSegments = p.route.length - 1;

      for (let i = 1; i < p.route.length; i++) {
        const prev = p.route[i - 1];
        const curr = p.route[i];
        const dt = (curr.timestamp_ms - prev.timestamp_ms) / 1000;
        const dtMs = curr.timestamp_ms - prev.timestamp_ms;

        if (dtMs > maxGapMs) maxGapMs = dtMs;

        if (dt <= 0) continue;

        const dist = haversine(prev.lat, prev.lng, curr.lat, curr.lng);
        const speed = dist / dt;

        // SPEED_IMPOSSIBLE: sustained high speed (> 10% of segments)
        if (speed > MAX_SPEED_MS) {
          speedViolations++;
        }

        // GPS_JUMP: raw distance jump > 500m
        if (dist > GPS_JUMP_THRESHOLD_M) {
          gpsJumps++;
        }

        // TELEPORT: impossible speed with good accuracy on both points
        if (
          hasGoodAccuracy(prev) &&
          hasGoodAccuracy(curr) &&
          speed > TELEPORT_SPEED_MS
        ) {
          teleportViolations++;
        }
      }

      if (speedViolations > totalSegments * 0.1) {
        flags.push(SPEED_IMPOSSIBLE);
      }
      if (gpsJumps > 0) {
        flags.push(GPS_JUMP);
      }
      if (teleportViolations > 0) {
        flags.push(TELEPORT);
      }

      // BACKGROUND_GPS_GAP: > 60s between consecutive points
      if (maxGapMs > GPS_GAP_THRESHOLD_MS) {
        flags.push(BACKGROUND_GPS_GAP);
      }
    }

    // ─ NO_MOTION_PATTERN: all points within a tiny radius ────────────

    if (p.route.length >= MIN_POINTS && p.total_distance_m >= MIN_DISTANCE_M) {
      const cLat = p.route.reduce((s, pt) => s + pt.lat, 0) / p.route.length;
      const cLng = p.route.reduce((s, pt) => s + pt.lng, 0) / p.route.length;
      let maxDist = 0;
      for (const pt of p.route) {
        const d = haversine(cLat, cLng, pt.lat, pt.lng);
        if (d > maxDist) maxDist = d;
      }
      if (maxDist < MOTION_RADIUS_M) {
        flags.push(NO_MOTION_PATTERN);
      }
    }

    // ─ HR plausibility (when avg_bpm is provided) ──────────────────

    if (p.avg_bpm != null && p.avg_bpm > 0) {
      if (p.avg_bpm > MAX_HR_BPM) {
        flags.push(IMPLAUSIBLE_HR_HIGH);
      } else if (
        p.avg_bpm < MIN_HR_RUNNING_BPM &&
        p.total_distance_m >= HR_CHECK_MIN_DISTANCE_M
      ) {
        flags.push(IMPLAUSIBLE_HR_LOW);
      }
    }

    // ─ Cadence vs speed correlation (vehicle detection) ─────────────

    if (
      p.avg_cadence_spm != null &&
      p.avg_cadence_spm >= 0 &&
      p.total_distance_m >= VEHICLE_MIN_DISTANCE_M &&
      durationMs > 0
    ) {
      const avgSpeedKmh = (p.total_distance_m / 1000) / (durationMs / 3_600_000);
      if (avgSpeedKmh > VEHICLE_MIN_SPEED_KMH && p.avg_cadence_spm < VEHICLE_MAX_CADENCE_SPM) {
        flags.push(VEHICLE_SUSPECTED);
      }
    }

    // ── 5. Verdict ───────────────────────────────────────────────────
    const isVerified = flags.length === 0;

    // ── 6. Persist (service_role bypasses RLS) ───────────────────────
    const { error } = await db
      .from("sessions")
      .update({
        is_verified: isVerified,
        integrity_flags: flags,
      })
      .eq("id", p.session_id)
      .eq("user_id", user.id);

    if (error) {
      const classified = classifyError(error);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 7. Trigger athlete verification re-evaluation (fire-and-forget) ──
    // Idempotent: the RPC recomputes trust_score and state machine from
    // scratch every time, so running it N times is safe.
    db.rpc("eval_athlete_verification", { p_user_id: user.id })
      .single()
      .then(() => {
        console.log(JSON.stringify({
          request_id: requestId, fn: FN,
          event: "eval_triggered", user_id: user.id,
        }));
      })
      .catch((err: Error) => {
        console.error(JSON.stringify({
          request_id: requestId, fn: FN,
          event: "eval_trigger_failed", user_id: user.id,
          detail: err?.message,
        }));
      });

    return jsonOk({
      status: "ok",
      session_id: p.session_id,
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
