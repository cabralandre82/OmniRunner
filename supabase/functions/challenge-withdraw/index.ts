import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { creditWallets } from "../_shared/wallet_credit.ts";

/**
 * challenge-withdraw — Supabase Edge Function
 *
 * Allows a participant to voluntarily withdraw from a challenge.
 * If the challenge has an entry fee, coins are refunded to the user's wallet.
 * Only allowed when the challenge is still pending or active (not settling/completed).
 *
 * POST /challenge-withdraw
 * Body: { challenge_id: string }
 */

const FN = "challenge-withdraw";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "1.0.0" }), {
      headers: { "Content-Type": "application/json" },
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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      httpStatus = rl.status!;
      if (httpStatus >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["challenge_id"]);
    } catch (e) {
      httpStatus = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { challenge_id } = body;

    // Fetch challenge
    const { data: challenge, error: chErr } = await db
      .from("challenges")
      .select("id, status, entry_fee_coins, creator_user_id")
      .eq("id", challenge_id)
      .maybeSingle();

    if (chErr) {
      const classified = classifyError(chErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!challenge) {
      httpStatus = 404;
      return jsonErr(404, "NOT_FOUND", "Desafio não encontrado", requestId);
    }

    // Cannot withdraw from challenges that are settling or already completed
    if (!["pending", "active"].includes(challenge.status)) {
      httpStatus = 409;
      return jsonErr(409, "INVALID_STATUS",
        `Não é possível sair de um desafio com status "${challenge.status}"`, requestId);
    }

    // Verify user is a participant
    const { data: participation, error: partErr } = await db
      .from("challenge_participants")
      .select("user_id, status")
      .eq("challenge_id", challenge_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (partErr) {
      const classified = classifyError(partErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!participation) {
      httpStatus = 404;
      return jsonErr(404, "NOT_PARTICIPANT", "Você não participa deste desafio", requestId);
    }

    if (participation.status === "withdrawn") {
      return jsonOk({ challenge_id, withdrawn: true, already_withdrawn: true }, requestId);
    }

    if (!["accepted", "invited"].includes(participation.status)) {
      httpStatus = 409;
      return jsonErr(409, "INVALID_PARTICIPANT_STATUS",
        `Não é possível sair com status "${participation.status}"`, requestId);
    }

    // Withdraw the participant
    const { error: updateErr } = await db
      .from("challenge_participants")
      .update({
        status: "withdrawn",
        updated_at: new Date().toISOString(),
      })
      .eq("challenge_id", challenge_id)
      .eq("user_id", user.id);

    if (updateErr) {
      const classified = classifyError(updateErr);
      httpStatus = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // Refund entry fee if applicable. Goes through the canonical
    // wallet-credit helper (L18-08) which validates the entry shape,
    // emits a structured log line, and forwards to fn_increment_
    // wallets_batch (which sets the L18-01 wallet-mutation guard +
    // pairs ledger insert in a single transaction).
    let refunded = 0;
    if (challenge.entry_fee_coins > 0 && participation.status === "accepted") {
      const svcUrl = Deno.env.get("SUPABASE_URL");
      const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
      if (svcUrl && svcKey) {
        const adminDb = createClient(svcUrl, svcKey);
        const result = await creditWallets(
          adminDb,
          [{
            user_id: user.id,
            delta: challenge.entry_fee_coins,
            reason: "challenge_withdrawal_refund",
            ref_id: challenge_id,
          }],
          { request_id: requestId, fn: FN, meta: { challenge_id } },
        );

        if (!result.ok) {
          errorCode = "REFUND_FAILED";
          httpStatus = 500;
          return jsonErr(500, "REFUND_FAILED",
            "Saída registrada mas o reembolso falhou. Entre em contato com o suporte.", requestId);
        }
        refunded = challenge.entry_fee_coins;
      }
    }

    return jsonOk({
      challenge_id,
      withdrawn: true,
      refunded_coins: refunded,
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
