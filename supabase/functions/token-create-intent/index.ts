import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { log } from "../_shared/logger.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * token-create-intent — Supabase Edge Function
 *
 * Staff creates an OPEN token intent with a unique nonce and expiry.
 * The nonce is embedded in a QR code for the athlete to scan.
 *
 * POST /token-create-intent
 * Headers: Authorization: Bearer <jwt>
 * Body: { group_id, type, amount, nonce, expires_at_iso, target_user_id? }
 */

const VALID_TYPES = ["ISSUE_TO_ATHLETE", "BURN_FROM_ATHLETE", "CHAMP_BADGE_ACTIVATE"];
const MAX_AMOUNT = 100_000;
const FN = "token-create-intent";

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

    // ── 1. Auth ────────────────────────────────────────────────────────
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

    // ── 1b. Rate limit ────────────────────────────────────────────────
    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 60, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse + validate body ──────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["group_id", "type", "amount", "nonce", "expires_at_iso"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { group_id, type, amount, nonce, expires_at_iso, target_user_id, championship_id } = body;

    if (!VALID_TYPES.includes(type)) {
      status = 400;
      return jsonErr(400, "INVALID_TYPE", `type must be one of: ${VALID_TYPES.join(", ")}`, requestId);
    }

    if (typeof amount !== "number" || !Number.isInteger(amount) || amount <= 0 || amount > MAX_AMOUNT) {
      status = 400;
      return jsonErr(400, "INVALID_AMOUNT", `amount must be integer 1..${MAX_AMOUNT}`, requestId);
    }

    // ── 3. Verify staff role in group ─────────────────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !["admin_master", "coach", "assistant"].includes(membership.role)) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only staff can create intents", requestId);
    }

    // ── 3b. Daily limit check (DECISAO 052) ─────────────────────────
    if (type === "ISSUE_TO_ATHLETE" || type === "BURN_FROM_ATHLETE") {
      const { data: remaining, error: limitErr } = await db.rpc("check_daily_token_usage", {
        p_group_id: group_id,
        p_type: type,
      });

      if (!limitErr && typeof remaining === "number" && remaining < amount) {
        status = 429;
        const limitName = type === "ISSUE_TO_ATHLETE" ? "daily_token_limit" : "daily_redemption_limit";
        return jsonErr(429, "DAILY_LIMIT_EXCEEDED", `Daily ${limitName} reached. Remaining capacity: ${Math.max(0, remaining)}`, requestId);
      }
    }

    // ── 3c. Inventory capacity check (emission must not exceed backing) ──
    if (type === "ISSUE_TO_ATHLETE") {
      const { data: inv } = await db
        .from("coaching_token_inventory")
        .select("available_tokens")
        .eq("group_id", group_id)
        .maybeSingle();

      const available = inv?.available_tokens ?? 0;
      if (amount > available) {
        status = 409;
        return jsonErr(409, "INSUFFICIENT_INVENTORY",
          `Capacidade insuficiente. Disponível: ${available}, solicitado: ${amount}`,
          requestId);
      }
    }

    // ── 3d. Badge inventory check ───────────────────────────────────────
    if (type === "CHAMP_BADGE_ACTIVATE") {
      const { data: badgeInv } = await db
        .from("coaching_badge_inventory")
        .select("available_badges")
        .eq("group_id", group_id)
        .maybeSingle();

      const availableBadges = badgeInv?.available_badges ?? 0;
      if (amount > availableBadges) {
        status = 409;
        return jsonErr(409, "INSUFFICIENT_BADGE_INVENTORY",
          `Badges insuficientes. Disponível: ${availableBadges}, solicitado: ${amount}`,
          requestId);
      }
    }

    log("info", "token-create-intent: creating intent", {
      request_id: requestId,
      group_id,
      type,
      amount,
    });

    // ── 4. Insert intent ──────────────────────────────────────────────
    const insertPayload: Record<string, unknown> = {
      group_id,
      type,
      amount,
      nonce,
      status: "OPEN",
      created_by: user.id,
      expires_at: expires_at_iso,
    };
    if (target_user_id) {
      insertPayload.target_user_id = target_user_id;
    }
    if (championship_id) {
      insertPayload.championship_id = championship_id;
    }

    const { data: intent, error: insertError } = await db
      .from("token_intents")
      .insert(insertPayload)
      .select("id, nonce, status, expires_at")
      .single();

    if (insertError) {
      const classified = classifyError(insertError);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    log("info", "token-create-intent: created", {
      request_id: requestId,
      intent_id: intent.id,
      type,
      amount,
      duration_ms: elapsed(),
    });

    return jsonOk({
      intent_id: intent.id,
      nonce: intent.nonce,
      status: intent.status,
      expires_at: intent.expires_at,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    log("error", "token-create-intent: unexpected error", { request_id: requestId });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: userId, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: userId, status, duration_ms: elapsed() });
    }
  }
});
