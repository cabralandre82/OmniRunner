import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * challenge-get — Supabase Edge Function
 *
 * Fetches a challenge by ID with its participants.
 * Any authenticated user can call this (needed for deep link join flow).
 * Uses service-role DB client so RLS doesn't block non-participants.
 *
 * POST /challenge-get
 * Body: { challenge_id: string }
 */

const FN = "challenge-get";

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 60, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["challenge_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { challenge_id } = body;

    const { data: challenge, error: fetchErr } = await db
      .from("challenges")
      .select("*")
      .eq("id", challenge_id)
      .maybeSingle();

    if (fetchErr) {
      const classified = classifyError(fetchErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!challenge) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Desafio não encontrado", requestId);
    }

    const { data: rawParticipants, error: partErr } = await db
      .from("challenge_participants")
      .select("user_id, display_name, status, progress_value, responded_at_ms, group_id, contributing_session_ids")
      .eq("challenge_id", challenge_id)
      .order("responded_at_ms", { ascending: true, nullsFirst: false });

    if (partErr) {
      const classified = classifyError(partErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // Anti-gaming: while a challenge is active, hide opponent's progress details.
    // Each athlete can only see IF the opponent submitted, not their actual values.
    const participants = (rawParticipants ?? []).map((p: Record<string, unknown>) => {
      const sessionIds = (p.contributing_session_ids as string[] | null) ?? [];
      const isCallerRow = p.user_id === user.id;
      const isActive = challenge.status === "active";

      if (isActive && !isCallerRow) {
        return {
          user_id: p.user_id,
          display_name: p.display_name,
          status: p.status,
          progress_value: null,
          responded_at_ms: p.responded_at_ms,
          group_id: p.group_id,
          has_submitted: sessionIds.length > 0,
        };
      }

      return {
        user_id: p.user_id,
        display_name: p.display_name,
        status: p.status,
        progress_value: p.progress_value,
        responded_at_ms: p.responded_at_ms,
        group_id: p.group_id,
        has_submitted: sessionIds.length > 0,
      };
    });

    // Resolve caller's group
    let callerGroupId: string | null = null;
    {
      const { data: profile } = await db
        .from("profiles")
        .select("active_coaching_group_id")
        .eq("id", user.id)
        .maybeSingle();
      callerGroupId = profile?.active_coaching_group_id ?? null;
    }

    // Resolve team group names for team_vs_team challenges
    let teamAGroupName: string | null = null;
    let teamBGroupName: string | null = null;

    if (challenge.type === "team_vs_team") {
      const teamIds = [challenge.team_a_group_id, challenge.team_b_group_id].filter(Boolean);
      if (teamIds.length > 0) {
        const { data: groups } = await db
          .from("coaching_groups")
          .select("id, name")
          .in("id", teamIds);
        for (const g of (groups ?? [])) {
          if (g.id === challenge.team_a_group_id) teamAGroupName = g.name;
          if (g.id === challenge.team_b_group_id) teamBGroupName = g.name;
        }
      }
    }

    return jsonOk({
      challenge: {
        id: challenge.id,
        creator_user_id: challenge.creator_user_id,
        status: challenge.status,
        type: challenge.type,
        title: challenge.title,
        metric: challenge.metric,
        target: challenge.target,
        window_ms: challenge.window_ms,
        start_mode: challenge.start_mode,
        fixed_start_ms: challenge.fixed_start_ms,
        entry_fee_coins: challenge.entry_fee_coins,
        min_session_distance_m: challenge.min_session_distance_m,
        anti_cheat_policy: challenge.anti_cheat_policy,
        created_at_ms: challenge.created_at_ms,
        starts_at_ms: challenge.starts_at_ms,
        ends_at_ms: challenge.ends_at_ms,
        team_a_group_id: challenge.team_a_group_id ?? null,
        team_b_group_id: challenge.team_b_group_id ?? null,
        team_a_group_name: teamAGroupName,
        team_b_group_name: teamBGroupName,
      },
      participants: participants,
      caller_user_id: user.id,
      caller_group_id: callerGroupId,
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
