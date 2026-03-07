import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-invite — Supabase Edge Function
 *
 * Staff (admin_master/coach) of the HOST group invites another group
 * to participate in a championship. Idempotent on (championship_id, to_group_id).
 *
 * POST /champ-invite
 * Body: { championship_id, to_group_id }
 */

const FN = "champ-invite";

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
      requireFields(body, ["championship_id", "to_group_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { championship_id, to_group_id } = body;

    // ── 3. Load championship ────────────────────────────────────────────
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

    if (!["draft", "open"].includes(champ.status)) {
      status = 409;
      return jsonErr(409, "INVALID_STATUS", `Cannot invite for championship with status ${champ.status}`, requestId);
    }

    // Cannot invite own group
    if (to_group_id === champ.host_group_id) {
      status = 400;
      return jsonErr(400, "SELF_INVITE", "Cannot invite the host group", requestId);
    }

    // ── 4. Verify caller is staff of host group ─────────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", champ.host_group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "coach"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only host group staff can invite", requestId);
    }

    // ── 5. Verify target group exists ───────────────────────────────────
    const { data: targetGroup } = await db
      .from("coaching_groups")
      .select("id")
      .eq("id", to_group_id)
      .maybeSingle();

    if (!targetGroup) {
      status = 404;
      return jsonErr(404, "GROUP_NOT_FOUND", "Target group not found", requestId);
    }

    // ── 6. Upsert invite (idempotent on unique constraint) ──────────────
    const { data: invite, error: insertErr } = await db
      .from("championship_invites")
      .upsert({
        championship_id,
        to_group_id,
        status: "pending",
        invited_by: user.id,
      }, { onConflict: "championship_id,to_group_id" })
      .select("id, championship_id, to_group_id, status")
      .single();

    if (insertErr) {
      const classified = classifyError(insertErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // Fire-and-forget: notify staff of invited group via service-role
    try {
      const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
      const svcUrl = Deno.env.get("SUPABASE_URL");
      if (svcKey && svcUrl) {
        const { data: staffMembers } = await db
          .from("coaching_members")
          .select("user_id")
          .eq("group_id", to_group_id)
          .in("role", ["admin_master", "coach"]);

        if (staffMembers && staffMembers.length > 0) {
          const staffIds = staffMembers.map((m: { user_id: string }) => m.user_id);
          fetch(`${svcUrl}/functions/v1/notify-rules`, {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${svcKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              rule: "championship_invite_received",
              context: { championship_id, user_ids: staffIds },
            }),
            signal: AbortSignal.timeout(15_000),
          }).catch(() => {});
        }
      }
    } catch { /* non-blocking */ }

    return jsonOk({
      invite_id: invite.id,
      championship_id: invite.championship_id,
      to_group_id: invite.to_group_id,
      status: invite.status,
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
