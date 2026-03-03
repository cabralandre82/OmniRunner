import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * clearing-open-dispute — Supabase Edge Function
 *
 * Staff of either group can open a dispute on a clearing case.
 * Transitions case: OPEN | SENT_CONFIRMED → DISPUTED.
 * Disputes are resolved externally (between the groups); the platform
 * does NOT mediate.
 *
 * Idempotent: re-calling on DISPUTED returns success.
 *
 * POST /clearing-open-dispute
 * Body: { case_id: string, reason?: string }
 */

const FN = "clearing-open-dispute";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
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
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["case_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { case_id, reason } = body;

    // ── 3. Load case ────────────────────────────────────────────────────
    const { data: cc, error: ccErr } = await db
      .from("clearing_cases")
      .select("*")
      .eq("id", case_id)
      .maybeSingle();

    if (ccErr) {
      const classified = classifyError(ccErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!cc) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Clearing case not found", requestId);
    }

    // Idempotent
    if (cc.status === "DISPUTED") {
      return jsonOk({ case_id, status: "DISPUTED", idempotent: true }, requestId);
    }

    if (!["OPEN", "SENT_CONFIRMED"].includes(cc.status)) {
      status = 409;
      return jsonErr(409, "INVALID_STATUS", `Cannot dispute case with status ${cc.status}`, requestId);
    }

    // ── 4. Verify caller is staff of either group ───────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role, group_id")
      .eq("user_id", user.id)
      .in("group_id", [cc.from_group_id, cc.to_group_id])
      .in("role", ["admin_master", "coach"]);

    if (!membership || membership.length === 0) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only admin_master or coach of involved groups can dispute", requestId);
    }

    // ── 5. Transition → DISPUTED ────────────────────────────────────────
    const { error: updateErr } = await db
      .from("clearing_cases")
      .update({
        status: "DISPUTED",
        updated_at: new Date().toISOString(),
      })
      .eq("id", case_id)
      .in("status", ["OPEN", "SENT_CONFIRMED"]);

    if (updateErr) {
      const classified = classifyError(updateErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 6. Audit event ──────────────────────────────────────────────────
    await db.from("clearing_case_events").insert({
      case_id,
      actor_id: user.id,
      event_type: "DISPUTED",
      metadata: {
        actor_group_id: membership[0].group_id,
        reason: reason ?? null,
      },
    });

    return jsonOk({ case_id, status: "DISPUTED" }, requestId);
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
