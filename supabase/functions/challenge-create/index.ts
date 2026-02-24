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
 * Syncs a locally-created challenge to the backend so opponents
 * can discover it via deep link and join.
 *
 * POST /challenge-create
 * Body: {
 *   id, type, title?, metric, target?, window_ms, start_mode,
 *   fixed_start_ms?, entry_fee_coins?, min_session_distance_m?,
 *   anti_cheat_policy?, created_at_ms, creator_display_name
 * }
 */

const FN = "challenge-create";

const VALID_TYPES = ["one_vs_one", "group", "team_vs_team"];
const VALID_METRICS = ["distance", "pace", "time"];
const VALID_START_MODES = ["on_accept", "scheduled"];
const VALID_ANTI_CHEAT = ["standard", "strict"];

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
      requireFields(body, ["id", "type", "metric", "window_ms", "created_at_ms", "creator_display_name"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const {
      id: challengeId,
      type,
      title,
      metric,
      target,
      window_ms,
      start_mode = "on_accept",
      fixed_start_ms,
      entry_fee_coins = 0,
      min_session_distance_m = 1000,
      anti_cheat_policy = "standard",
      created_at_ms,
      creator_display_name,
      team_a_group_id,
      team_b_group_id,
      accept_window_min,
    } = body;

    if (!VALID_TYPES.includes(type)) {
      status = 400;
      return jsonErr(400, "INVALID_TYPE", `type must be one of: ${VALID_TYPES.join(", ")}`, requestId);
    }
    if (!VALID_METRICS.includes(metric)) {
      status = 400;
      return jsonErr(400, "INVALID_METRIC", `metric must be one of: ${VALID_METRICS.join(", ")}`, requestId);
    }
    if (!VALID_START_MODES.includes(start_mode)) {
      status = 400;
      return jsonErr(400, "INVALID_START_MODE", `start_mode must be one of: ${VALID_START_MODES.join(", ")}`, requestId);
    }
    if (!VALID_ANTI_CHEAT.includes(anti_cheat_policy)) {
      status = 400;
      return jsonErr(400, "INVALID_ANTI_CHEAT", `anti_cheat_policy must be one of: ${VALID_ANTI_CHEAT.join(", ")}`, requestId);
    }

    // ── Monetization gate: stake>0 requires VERIFIED ──────────────────
    if (entry_fee_coins > 0) {
      const { data: verifiedRow, error: verErr } = await db
        .rpc("is_user_verified", { p_user_id: user.id });

      if (verErr || verifiedRow !== true) {
        status = 403;
        errorCode = "ATHLETE_NOT_VERIFIED";
        return jsonErr(
          403, "ATHLETE_NOT_VERIFIED",
          "Apenas atletas verificados podem criar desafios com stake > 0. Complete sua verificação primeiro.",
          requestId,
        );
      }
    }

    // Idempotent: if challenge already exists, return it
    const { data: existing } = await db
      .from("challenges")
      .select("id, status")
      .eq("id", challengeId)
      .maybeSingle();

    if (existing) {
      return jsonOk({ challenge_id: existing.id, already_exists: true }, requestId);
    }

    // Validate team_a_group_id for team challenges
    if (type === "team_vs_team" && !team_a_group_id) {
      status = 400;
      return jsonErr(400, "MISSING_TEAM", "team_a_group_id is required for team_vs_team challenges", requestId);
    }

    // Insert challenge
    // deno-lint-ignore no-explicit-any
    const insertData: Record<string, any> = {
      id: challengeId,
      creator_user_id: user.id,
      status: "pending",
      type,
      title: title || null,
      metric,
      target: target ?? null,
      window_ms,
      start_mode,
      fixed_start_ms: fixed_start_ms ?? null,
      entry_fee_coins,
      min_session_distance_m,
      anti_cheat_policy,
      created_at_ms,
    };

    if (type === "group" && accept_window_min) {
      insertData.accept_window_min = accept_window_min;
      insertData.accept_deadline_ms = created_at_ms + accept_window_min * 60 * 1000;
    }

    if (type === "team_vs_team" && team_a_group_id) {
      insertData.team_a_group_id = team_a_group_id;
      if (team_b_group_id) {
        insertData.team_b_group_id = team_b_group_id;
      }
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

    // Insert creator as first participant (status: accepted)
    const { error: partErr } = await db
      .from("challenge_participants")
      .insert({
        challenge_id: challengeId,
        user_id: user.id,
        display_name: creator_display_name,
        status: "accepted",
        responded_at_ms: created_at_ms,
        group_id: type === "team_vs_team" ? team_a_group_id : null,
        team: type === "team_vs_team" ? "A" : null,
      });

    if (partErr) {
      const classified = classifyError(partErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
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
