import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-accept-invite — Supabase Edge Function
 *
 * Staff (admin_master/coach) of the INVITED group accepts or declines
 * a championship invitation.
 *
 * POST /champ-accept-invite
 * Body: { invite_id: string, accept: boolean }
 */

const FN = "champ-accept-invite";

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["invite_id", "accept"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { invite_id, accept } = body;

    const { data: invite, error: fetchErr } = await db
      .from("championship_invites")
      .select("id, championship_id, to_group_id, status")
      .eq("id", invite_id)
      .maybeSingle();

    if (fetchErr) {
      const classified = classifyError(fetchErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!invite) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Invite not found", requestId);
    }

    if (invite.status !== "pending") {
      status = 409;
      return jsonErr(409, "ALREADY_RESPONDED", `Invite already ${invite.status}`, requestId);
    }

    // Verify caller is staff of the invited group
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", invite.to_group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "coach"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only staff of the invited group can respond", requestId);
    }

    const newStatus = accept === true ? "accepted" : "declined";

    const { data: updated, error: updateErr } = await db
      .from("championship_invites")
      .update({
        status: newStatus,
        responded_by: user.id,
        responded_at: new Date().toISOString(),
      })
      .eq("id", invite_id)
      .eq("status", "pending")
      .select("id, championship_id, to_group_id, status")
      .maybeSingle();

    if (updateErr) {
      const classified = classifyError(updateErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!updated) {
      return jsonOk({ invite_id, status: newStatus, already_responded: true }, requestId);
    }

    return jsonOk({
      invite_id: updated.id,
      championship_id: updated.championship_id,
      to_group_id: updated.to_group_id,
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
