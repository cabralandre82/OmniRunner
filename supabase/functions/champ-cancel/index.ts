import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-cancel — Supabase Edge Function
 *
 * Cancels a championship (draft, open, or active → cancelled).
 * Withdraws all enrolled/active participants.
 * Revokes all pending invites.
 * Only staff (admin_master/coach) of the host group may call this.
 *
 * POST /champ-cancel
 * Body: { championship_id: string }
 */

const FN = "champ-cancel";

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

    const rl = await checkRateLimit(db, user.id, {
      fn: FN, maxRequests: 10, windowSeconds: 60,
    }, requestId);
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

    // (L05-06) All four writes — withdraw participants, revoke
    // invites, refund badges, flip championship to 'cancelled' —
    // happen inside `public.fn_champ_cancel_atomic`. That RPC
    // owns the authorization check (FORBIDDEN if caller is not
    // admin_master / coach of the host group), the status
    // precondition (INVALID_STATUS on anything but
    // draft/open/active), and the row lock (FOR UPDATE). Any
    // failure inside raises and rolls back the whole
    // transaction — no more "cancelled but badges silently
    // lost" path.
    const { data: rpcData, error: rpcErr } = await db.rpc(
      "fn_champ_cancel_atomic",
      { p_championship_id: championship_id, p_caller_user_id: user.id },
    );

    if (rpcErr) {
      const msg = rpcErr.message ?? String(rpcErr);
      if (msg.includes("FORBIDDEN")) {
        status = 403;
        errorCode = "FORBIDDEN";
        return jsonErr(
          403,
          "FORBIDDEN",
          "Apenas o staff da assessoria organizadora pode cancelar o campeonato",
          requestId,
        );
      }
      if (msg.includes("NOT_FOUND")) {
        status = 404;
        errorCode = "NOT_FOUND";
        return jsonErr(404, "NOT_FOUND", "Campeonato não encontrado", requestId);
      }
      if (msg.includes("INVALID_STATUS")) {
        status = 409;
        errorCode = "INVALID_STATUS";
        return jsonErr(
          409,
          "INVALID_STATUS",
          "Campeonato não está em estado cancelável.",
          requestId,
        );
      }
      const classified = classifyError(rpcErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    return jsonOk({
      championship_id,
      status: "cancelled",
      noop: Boolean(rpcData?.noop),
      participants_withdrawn: rpcData?.participants_withdrawn ?? 0,
      invites_revoked: rpcData?.invites_revoked ?? 0,
      badges_refunded: rpcData?.badges_refunded ?? 0,
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
