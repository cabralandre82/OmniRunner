import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-open — Supabase Edge Function
 *
 * Transitions a championship from "draft" to "open", allowing athlete enrollment.
 * Only staff (admin_master/professor) of the host group may call this.
 *
 * POST /champ-open
 * Body: { championship_id: string }
 */

const FN = "champ-open";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 20, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["championship_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { championship_id } = body;

    // Fetch championship
    const { data: champ, error: champErr } = await db
      .from("championships")
      .select("id, host_group_id, status")
      .eq("id", championship_id)
      .maybeSingle();

    if (champErr) {
      const classified = classifyError(champErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!champ) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Championship not found", requestId);
    }

    if (champ.status !== "draft") {
      status = 409;
      return jsonErr(409, "INVALID_STATUS",
        `Championship is already "${champ.status}". Only draft championships can be opened.`,
        requestId);
    }

    // Verify caller is staff of host group
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", champ.host_group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "professor"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only host group staff can open a championship", requestId);
    }

    // Transition draft → open
    const { data: updated, error: updateErr } = await db
      .from("championships")
      .update({ status: "open" })
      .eq("id", championship_id)
      .eq("status", "draft")
      .select("id, status")
      .maybeSingle();

    if (updateErr) {
      const classified = classifyError(updateErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!updated) {
      return jsonOk({ championship_id, status: "open", already_open: true }, requestId);
    }

    return jsonOk({
      championship_id: updated.id,
      status: updated.status,
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
