import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * clearing-confirm-sent — Supabase Edge Function
 *
 * Staff of the LOSING group confirms that tokens have been sent.
 * Transitions case: OPEN → SENT_CONFIRMED.
 * Idempotent: re-calling on SENT_CONFIRMED returns success.
 *
 * POST /clearing-confirm-sent
 * Body: { case_id: string }
 */

const FN = "clearing-confirm-sent";

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
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
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

    const { case_id } = body;

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

    // Idempotent: already sent
    if (cc.status === "SENT_CONFIRMED" || cc.status === "PAID_CONFIRMED") {
      return jsonOk({ case_id, status: cc.status, idempotent: true }, requestId);
    }

    if (cc.status !== "OPEN") {
      status = 409;
      return jsonErr(409, "INVALID_STATUS", `Cannot confirm sent on case with status ${cc.status}`, requestId);
    }

    // Check deadline
    if (new Date(cc.deadline_at).getTime() < Date.now()) {
      status = 410;
      return jsonErr(410, "CASE_EXPIRED", "Deadline has passed", requestId);
    }

    // ── 4. Verify caller is staff of from_group (losing group) ──────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", cc.from_group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "coach"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only admin_master or coach of the sending group can confirm", requestId);
    }

    // ── 5. Transition OPEN → SENT_CONFIRMED ─────────────────────────────
    const { error: updateErr } = await db
      .from("clearing_cases")
      .update({
        status: "SENT_CONFIRMED",
        sent_by: user.id,
        sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", case_id)
      .eq("status", "OPEN");

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
      event_type: "SENT_CONFIRMED",
      metadata: { from_group_id: cc.from_group_id },
    });

    return jsonOk({ case_id, status: "SENT_CONFIRMED" }, requestId);
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
