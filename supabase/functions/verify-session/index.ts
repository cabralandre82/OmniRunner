import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";
import {
  runAntiCheatPipeline,
  normalizeAppSession,
  loadAntiCheatThresholds,
} from "../_shared/anti_cheat.ts";

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
 * Anti-cheat pipeline: see _shared/anti_cheat.ts
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

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

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

    // ── 4. Run unified anti-cheat pipeline (L21-01/02: profile-aware) ─
    const p = body as VerifyPayload;
    const input = normalizeAppSession(p);
    const thresholds = await loadAntiCheatThresholds(db, user.id);
    const result = runAntiCheatPipeline(input, thresholds);

    // ── 5. Persist (service_role bypasses RLS) ───────────────────────
    const { error } = await db
      .from("sessions")
      .update({
        is_verified: result.is_verified,
        integrity_flags: result.flags,
      })
      .eq("id", p.session_id)
      .eq("user_id", user.id);

    if (error) {
      const classified = classifyError(error);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 6. Trigger athlete verification re-evaluation (fire-and-forget) ──
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
      is_verified: result.is_verified,
      integrity_flags: result.flags,
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
