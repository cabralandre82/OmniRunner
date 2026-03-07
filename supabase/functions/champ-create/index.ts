import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-create — Supabase Edge Function
 *
 * Creates a new championship in "draft" status from a template or ad-hoc.
 * Only staff (admin_master/coach) of the host group may call this.
 *
 * POST /champ-create
 * Body: {
 *   host_group_id: string,
 *   name: string,
 *   metric: string,
 *   start_at_iso: string,
 *   end_at_iso: string,
 *   description?: string,
 *   requires_badge?: boolean,
 *   max_participants?: number,
 *   template_id?: string,
 * }
 */

const FN = "champ-create";
const VALID_METRICS = ["distance", "time", "pace", "sessions", "elevation"];

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["host_group_id", "name", "metric", "start_at_iso", "end_at_iso"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const {
      host_group_id,
      name,
      metric,
      start_at_iso,
      end_at_iso,
      description,
      requires_badge,
      max_participants,
      template_id,
    } = body;

    if (!VALID_METRICS.includes(metric)) {
      status = 400;
      return jsonErr(400, "INVALID_METRIC", `Invalid metric "${metric}". Use: ${VALID_METRICS.join(", ")}`, requestId);
    }

    const startAt = new Date(start_at_iso);
    const endAt = new Date(end_at_iso);

    if (isNaN(startAt.getTime()) || isNaN(endAt.getTime())) {
      status = 400;
      return jsonErr(400, "INVALID_DATE", "Invalid date format", requestId);
    }

    if (endAt <= startAt) {
      status = 400;
      return jsonErr(400, "DATE_ORDER", "end_at must be after start_at", requestId);
    }

    // Verify caller is staff of host group
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", host_group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "coach"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only staff of the host group can create championships", requestId);
    }

    // Verify host group exists
    const { data: group } = await db
      .from("coaching_groups")
      .select("id")
      .eq("id", host_group_id)
      .maybeSingle();

    if (!group) {
      status = 404;
      return jsonErr(404, "GROUP_NOT_FOUND", "Host group not found", requestId);
    }

    // Insert championship
    const insertData: Record<string, unknown> = {
      host_group_id,
      name: String(name).slice(0, 200),
      description: String(description ?? "").slice(0, 500),
      metric,
      requires_badge: requires_badge === true,
      start_at: startAt.toISOString(),
      end_at: endAt.toISOString(),
      status: "draft",
      created_by: user.id,
    };

    if (max_participants != null && typeof max_participants === "number" && max_participants > 0) {
      insertData.max_participants = max_participants;
    }

    if (template_id && typeof template_id === "string") {
      insertData.template_id = template_id;
    }

    const { data: champ, error: insertErr } = await db
      .from("championships")
      .insert(insertData)
      .select("id, status")
      .single();

    if (insertErr) {
      const classified = classifyError(insertErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      championship_id: champ.id,
      status: champ.status,
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
