import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-update-progress — Supabase Edge Function
 *
 * Aggregates verified sessions for a participant within the championship
 * window and updates their progress_value.
 *
 * Called by the client after a session sync, or by a cron job.
 *
 * POST /champ-update-progress
 * Body: { championship_id: string }
 */

const FN = "champ-update-progress";

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
  let userId: string | null = null;
  let httpStatus = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      httpStatus = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // deno-lint-ignore no-explicit-any
    let db: any;
    let user: { id: string; [key: string]: unknown };
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        httpStatus = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      httpStatus = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      httpStatus = rl.status!;
      if (httpStatus >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["championship_id"]);
    } catch (e) {
      httpStatus = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { championship_id } = body;

    // Fetch championship
    const { data: champ, error: champErr } = await db
      .from("championships")
      .select("id, status, metric, start_at, end_at")
      .eq("id", championship_id)
      .maybeSingle();

    if (champErr) {
      const classified = classifyError(champErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!champ) {
      httpStatus = 404;
      return jsonErr(404, "NOT_FOUND", "Campeonato não encontrado", requestId);
    }

    if (champ.status !== "active") {
      httpStatus = 409;
      return jsonErr(409, "NOT_ACTIVE",
        `Campeonato não está ativo (status: ${champ.status})`, requestId);
    }

    // Check participation
    const { data: participation } = await db
      .from("championship_participants")
      .select("id, status")
      .eq("championship_id", championship_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!participation || !["enrolled", "active"].includes(participation.status)) {
      httpStatus = 403;
      return jsonErr(403, "NOT_PARTICIPANT",
        "Você não está inscrito neste campeonato", requestId);
    }

    // Aggregate verified sessions within the championship window
    const startAtMs = new Date(champ.start_at).getTime();
    const endAtMs = new Date(champ.end_at).getTime();

    const { data: sessions, error: sessErr } = await db
      .from("sessions")
      .select("total_distance_m, moving_ms, avg_pace_sec_km")
      .eq("user_id", user.id)
      .eq("is_verified", true)
      .gte("start_time_ms", startAtMs)
      .lte("start_time_ms", endAtMs);

    if (sessErr) {
      const classified = classifyError(sessErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    const rows = sessions ?? [];
    let progressValue = 0;

    switch (champ.metric) {
      case "distance":
        progressValue = rows.reduce(
          (sum: number, s: { total_distance_m: number }) => sum + (s.total_distance_m ?? 0), 0);
        break;
      case "time":
        progressValue = rows.reduce(
          (sum: number, s: { moving_ms: number }) => sum + (s.moving_ms ?? 0), 0);
        break;
      case "pace": {
        const paces = rows
          .map((s: { avg_pace_sec_km: number | null }) => s.avg_pace_sec_km)
          .filter((p: number | null): p is number => p != null && p > 0);
        progressValue = paces.length > 0
          ? Math.min(...paces)
          : 0;
        break;
      }
      case "sessions":
        progressValue = rows.length;
        break;
      case "elevation":
        progressValue = rows.reduce(
          (sum: number, s: { total_distance_m: number }) => sum + (s.total_distance_m ?? 0), 0);
        break;
      default:
        progressValue = rows.reduce(
          (sum: number, s: { total_distance_m: number }) => sum + (s.total_distance_m ?? 0), 0);
    }

    // Update progress
    const { error: updateErr } = await db
      .from("championship_participants")
      .update({
        progress_value: progressValue,
        status: "active",
        updated_at: new Date().toISOString(),
      })
      .eq("id", participation.id);

    if (updateErr) {
      const classified = classifyError(updateErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      championship_id,
      progress_value: progressValue,
      sessions_counted: rows.length,
      metric: champ.metric,
    }, requestId);
  } catch (_err) {
    httpStatus = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status: httpStatus, duration_ms: elapsed() });
    }
  }
});
