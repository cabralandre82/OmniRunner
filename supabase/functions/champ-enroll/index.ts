import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-enroll — Supabase Edge Function
 *
 * Athlete self-enrolls in an open championship.
 *
 * POST /champ-enroll
 * Body: { championship_id: string }
 *
 * Guards:
 *   - Championship must be status='open'
 *   - Athlete must have active_coaching_group_id set
 *   - If requires_badge, athlete must hold a valid championship_badge
 *   - If max_participants set, count must be under limit
 *   - Idempotent: re-enrolling returns existing participation
 */

const FN = "champ-enroll";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

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

    // ── 1. Auth ──────────────────────────────────────────────────────────
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

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 20, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      httpStatus = rl.status!;
      if (httpStatus >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
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

    // ── 3. Fetch championship ───────────────────────────────────────────
    const { data: champ, error: champErr } = await db
      .from("championships")
      .select("id, status, requires_badge, max_participants, host_group_id")
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
      return jsonErr(404, "NOT_FOUND", "Championship not found", requestId);
    }

    if (champ.status !== "open") {
      httpStatus = 409;
      return jsonErr(409, "NOT_OPEN", `Championship is ${champ.status}, enrollment requires status=open`, requestId);
    }

    // ── 4. Get athlete's coaching group ─────────────────────────────────
    const { data: profile } = await db
      .from("profiles")
      .select("active_coaching_group_id")
      .eq("id", user.id)
      .maybeSingle();

    const groupId = profile?.active_coaching_group_id;
    if (!groupId) {
      httpStatus = 400;
      return jsonErr(400, "NO_GROUP", "You must belong to a coaching group to join a championship", requestId);
    }

    // ── 4b. Verify athlete's group is allowed to participate ───────────
    // Allowed if: athlete's group IS the host, OR there's an accepted invite
    if (groupId !== champ.host_group_id) {
      const { data: invite } = await db
        .from("championship_invites")
        .select("id, status")
        .eq("championship_id", championship_id)
        .eq("to_group_id", groupId)
        .eq("status", "accepted")
        .maybeSingle();

      if (!invite) {
        httpStatus = 403;
        return jsonErr(403, "GROUP_NOT_INVITED",
          "Sua assessoria não foi convidada para este campeonato ou o convite ainda não foi aceito.",
          requestId);
      }
    }

    // ── 5. Idempotent: check existing participation ─────────────────────
    const { data: existing } = await db
      .from("championship_participants")
      .select("id, status")
      .eq("championship_id", championship_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (existing) {
      return jsonOk({
        participant_id: existing.id,
        status: existing.status,
        already_enrolled: true,
      }, requestId);
    }

    // ── 6. Badge check ──────────────────────────────────────────────────
    if (champ.requires_badge) {
      const { data: badge } = await db
        .from("championship_badges")
        .select("id, expires_at")
        .eq("championship_id", championship_id)
        .eq("user_id", user.id)
        .gt("expires_at", new Date().toISOString())
        .maybeSingle();

      if (!badge) {
        httpStatus = 403;
        return jsonErr(403, "BADGE_REQUIRED", "This championship requires an active participation badge", requestId);
      }
    }

    // ── 7. Max participants check ───────────────────────────────────────
    if (champ.max_participants) {
      const { count, error: countErr } = await db
        .from("championship_participants")
        .select("id", { count: "exact", head: true })
        .eq("championship_id", championship_id)
        .in("status", ["enrolled", "active", "completed"]);

      if (!countErr && typeof count === "number" && count >= champ.max_participants) {
        httpStatus = 409;
        return jsonErr(409, "FULL", "Championship has reached maximum participants", requestId);
      }
    }

    // ── 8. Enroll ───────────────────────────────────────────────────────
    const { data: participant, error: insertErr } = await db
      .from("championship_participants")
      .insert({
        championship_id,
        user_id: user.id,
        group_id: groupId,
        status: "enrolled",
      })
      .select("id, status")
      .single();

    if (insertErr) {
      const classified = classifyError(insertErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      participant_id: participant.id,
      status: participant.status,
      already_enrolled: false,
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
