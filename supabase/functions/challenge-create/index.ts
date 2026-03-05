import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * challenge-create — Supabase Edge Function
 *
 * Syncs a locally-created challenge to the backend.
 *
 * POST /challenge-create
 * Body: {
 *   id, type, title?, goal, target?, window_ms, start_mode,
 *   fixed_start_ms?, entry_fee_coins?, min_session_distance_m?,
 *   anti_cheat_policy?, created_at_ms, creator_display_name,
 *   accept_window_min?, max_participants?
 * }
 *
 * Goal types:
 *   - fastest_at_distance: target REQUIRED (distance in meters)
 *   - most_distance: target optional
 *   - best_pace_at_distance: target REQUIRED (qualifying distance in meters)
 *   - collective_distance: target REQUIRED (collective distance in meters)
 */

const FN = "challenge-create";

const VALID_TYPES = ["one_vs_one", "group", "team"];
const VALID_GOALS = ["fastest_at_distance", "most_distance", "best_pace_at_distance", "collective_distance"];
const VALID_START_MODES = ["on_accept", "scheduled"];
const VALID_ANTI_CHEAT = ["standard", "strict"];
const GOALS_REQUIRING_TARGET = ["fastest_at_distance", "best_pace_at_distance", "collective_distance"];

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
      requireFields(body, ["id", "goal", "window_ms", "created_at_ms", "creator_display_name"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const {
      id: challengeId,
      type = "one_vs_one",
      title,
      goal,
      target,
      window_ms,
      start_mode = "on_accept",
      fixed_start_ms,
      entry_fee_coins = 0,
      min_session_distance_m = 1000,
      anti_cheat_policy = "standard",
      created_at_ms,
      creator_display_name,
      accept_window_min,
    } = body;

    if (title != null && typeof title !== "string") {
      status = 400;
      return jsonErr(400, "INVALID_FIELD", "title must be a string", requestId);
    }
    if (typeof title === "string" && title.length > 100) {
      status = 400;
      return jsonErr(400, "FIELD_TOO_LONG", "title must be at most 100 characters", requestId);
    }

    if (typeof creator_display_name === "string" && creator_display_name.length > 100) {
      status = 400;
      return jsonErr(400, "FIELD_TOO_LONG", "creator_display_name must be at most 100 characters", requestId);
    }

    if (typeof window_ms !== "number" || window_ms <= 0) {
      status = 400;
      return jsonErr(400, "INVALID_FIELD", "window_ms must be a positive number", requestId);
    }

    if (typeof created_at_ms !== "number" || created_at_ms <= 0) {
      status = 400;
      return jsonErr(400, "INVALID_FIELD", "created_at_ms must be a positive number", requestId);
    }

    if (entry_fee_coins != null && (typeof entry_fee_coins !== "number" || entry_fee_coins < 0)) {
      status = 400;
      return jsonErr(400, "INVALID_FIELD", "entry_fee_coins must be a non-negative number", requestId);
    }

    if (!VALID_TYPES.includes(type)) {
      status = 400;
      return jsonErr(400, "INVALID_TYPE", `type must be one of: ${VALID_TYPES.join(", ")}`, requestId);
    }
    if (!VALID_GOALS.includes(goal)) {
      status = 400;
      return jsonErr(400, "INVALID_GOAL", `goal must be one of: ${VALID_GOALS.join(", ")}`, requestId);
    }
    if (!VALID_START_MODES.includes(start_mode)) {
      status = 400;
      return jsonErr(400, "INVALID_START_MODE", `start_mode must be one of: ${VALID_START_MODES.join(", ")}`, requestId);
    }
    if (!VALID_ANTI_CHEAT.includes(anti_cheat_policy)) {
      status = 400;
      return jsonErr(400, "INVALID_ANTI_CHEAT", `anti_cheat_policy must be one of: ${VALID_ANTI_CHEAT.join(", ")}`, requestId);
    }

    if (GOALS_REQUIRING_TARGET.includes(goal) && (target == null || target <= 0)) {
      status = 400;
      return jsonErr(400, "TARGET_REQUIRED",
        `O goal '${goal}' exige um target (distância em metros). Ex: 10000 para 10km.`,
        requestId);
    }

    if (goal === "collective_distance" && type !== "group") {
      status = 400;
      return jsonErr(400, "INVALID_GOAL_TYPE",
        "collective_distance só pode ser usado em desafios de grupo cooperativo.",
        requestId);
    }

    if (type === "team" && goal === "collective_distance") {
      status = 400;
      return jsonErr(400, "INVALID_GOAL_TYPE",
        "Desafios de time não suportam collective_distance. Use group para metas cooperativas.",
        requestId);
    }

    // Assessoria gate
    const { data: memberRow } = await db
      .from("coaching_members")
      .select("id, group_id")
      .eq("user_id", user.id)
      .limit(1)
      .maybeSingle();

    if (!memberRow) {
      status = 403;
      errorCode = "NO_ASSESSORIA";
      return jsonErr(
        403, "NO_ASSESSORIA",
        "Você precisa estar em uma assessoria para criar desafios.",
        requestId,
      );
    }

    // Monetization gate
    if (entry_fee_coins > 0) {
      const { data: verifiedRow, error: verErr } = await db
        .rpc("is_user_verified", { p_user_id: user.id });

      if (verErr || verifiedRow !== true) {
        status = 403;
        errorCode = "ATHLETE_NOT_VERIFIED";
        return jsonErr(
          403, "ATHLETE_NOT_VERIFIED",
          "Apenas atletas verificados podem criar desafios com stake > 0.",
          requestId,
        );
      }
    }

    // Idempotent
    const { data: existing } = await db
      .from("challenges")
      .select("id, status")
      .eq("id", challengeId)
      .maybeSingle();

    if (existing) {
      return jsonOk({ challenge_id: existing.id, already_exists: true }, requestId);
    }

    // deno-lint-ignore no-explicit-any
    const insertData: Record<string, any> = {
      id: challengeId,
      creator_user_id: user.id,
      status: "pending",
      type,
      title: title || null,
      goal,
      target: target ?? null,
      window_ms,
      start_mode,
      fixed_start_ms: fixed_start_ms ?? null,
      entry_fee_coins,
      min_session_distance_m,
      anti_cheat_policy,
      created_at_ms,
    };

    if ((type === "group" || type === "team") && accept_window_min) {
      insertData.accept_window_min = accept_window_min;
      insertData.accept_deadline_ms = created_at_ms + accept_window_min * 60 * 1000;
    }

    const { data: challenge, error: insertErr } = await db
      .from("challenges")
      .insert(insertData)
      .select("id")
      .single();

    if (insertErr) {
      const classified = classifyError(insertErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // Creator as first participant (team A for team challenges)
    // deno-lint-ignore no-explicit-any
    const participantData: Record<string, any> = {
      challenge_id: challengeId,
      user_id: user.id,
      display_name: creator_display_name,
      status: "accepted",
      responded_at_ms: created_at_ms,
    };
    if (type === "team") {
      participantData.team = "A";
    }

    const { error: partErr } = await db
      .from("challenge_participants")
      .insert(participantData);

    if (partErr) {
      const classified = classifyError(partErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── Entry fee debit (atomic balance check) ────────────────────────
    if (entry_fee_coins > 0) {
      const { data: debited, error: debitErr } = await db
        .rpc("debit_wallet_checked", {
          p_user_id: user.id,
          p_amount: entry_fee_coins,
        });

      if (debitErr || debited !== true) {
        // Rollback: remove participant + challenge
        await db.from("challenge_participants").delete()
          .eq("challenge_id", challengeId).eq("user_id", user.id);
        await db.from("challenges").delete().eq("id", challengeId);

        status = 402;
        errorCode = "INSUFFICIENT_BALANCE";
        return jsonErr(
          402, "INSUFFICIENT_BALANCE",
          "Saldo insuficiente de OmniCoins para criar este desafio.",
          requestId,
        );
      }

      await db.from("coin_ledger").insert({
        user_id: user.id,
        delta_coins: -entry_fee_coins,
        reason: "challenge_entry_fee",
        ref_id: challengeId,
        created_at_ms: created_at_ms,
      });
    }

    return jsonOk({ challenge_id: challenge.id, created: true }, requestId);
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
