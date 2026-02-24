import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * challenge-join — Supabase Edge Function
 *
 * Allows an authenticated user to join/accept a pending challenge.
 * For 1v1 + on_accept: auto-activates when both participants accepted.
 *
 * POST /challenge-join
 * Body: { challenge_id: string, display_name: string }
 */

const FN = "challenge-join";

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
      requireFields(body, ["challenge_id", "display_name"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { challenge_id, display_name } = body;

    // Fetch challenge
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

    const allowedStatuses = ["pending"];
    if (!allowedStatuses.includes(challenge.status)) {
      status = 409;
      return jsonErr(409, "INVALID_STATUS", `Desafio não está aceitando participantes (status: ${challenge.status})`, requestId);
    }

    if (challenge.creator_user_id === user.id) {
      status = 409;
      return jsonErr(409, "ALREADY_CREATOR", "Você é o criador deste desafio", requestId);
    }

    // ── Monetization gate: stake>0 requires VERIFIED ──────────────────
    if (challenge.entry_fee_coins > 0) {
      const { data: verifiedRow, error: verErr } = await db
        .rpc("is_user_verified", { p_user_id: user.id });

      if (verErr || verifiedRow !== true) {
        status = 403;
        errorCode = "ATHLETE_NOT_VERIFIED";
        return jsonErr(
          403, "ATHLETE_NOT_VERIFIED",
          "Apenas atletas verificados podem participar de desafios com stake > 0. Complete sua verificação primeiro.",
          requestId,
        );
      }
    }

    // For team_vs_team challenges, determine team assignment
    let joinerGroupId: string | null = null;
    let joinerTeam: string | null = null;
    if (challenge.type === "team_vs_team") {
      const { data: profile } = await db
        .from("profiles")
        .select("active_coaching_group_id")
        .eq("id", user.id)
        .maybeSingle();

      joinerGroupId = profile?.active_coaching_group_id ?? null;

      if (!joinerGroupId) {
        status = 400;
        return jsonErr(400, "NO_GROUP", "Você precisa estar em uma assessoria para participar de um desafio de equipe", requestId);
      }

      const isSameGroup = challenge.team_a_group_id === challenge.team_b_group_id;

      if (isSameGroup) {
        // Intra-assessoria: athlete must belong to the group and specify team
        if (joinerGroupId !== challenge.team_a_group_id) {
          status = 403;
          return jsonErr(403, "WRONG_GROUP",
            "Sua assessoria não participa deste desafio.",
            requestId);
        }
        const requestedTeam = body.team as string | undefined;
        if (!requestedTeam || !["A", "B"].includes(requestedTeam)) {
          status = 400;
          return jsonErr(400, "TEAM_REQUIRED",
            "Para desafios internos, escolha o time (A ou B).",
            requestId);
        }
        joinerTeam = requestedTeam;
      } else {
        // Cross-assessoria: derive team from group membership
        const isTeamA = joinerGroupId === challenge.team_a_group_id;
        const isTeamB = joinerGroupId === challenge.team_b_group_id;

        if (!isTeamA && !isTeamB) {
          status = 403;
          return jsonErr(403, "WRONG_GROUP",
            "Sua assessoria não participa deste desafio. Apenas as assessorias convidadas podem entrar.",
            requestId);
        }
        joinerTeam = isTeamA ? "A" : "B";
      }
    }

    // Check if already participant
    const { data: existingPart } = await db
      .from("challenge_participants")
      .select("user_id, status")
      .eq("challenge_id", challenge_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingPart) {
      if (existingPart.status === "accepted") {
        return jsonOk({ challenge_id, joined: true, already_joined: true, status: challenge.status }, requestId);
      }
      if (existingPart.status === "invited") {
        // Update from invited to accepted
        const { error: updateErr } = await db
          .from("challenge_participants")
          .update({
            status: "accepted",
            responded_at_ms: Date.now(),
          })
          .eq("challenge_id", challenge_id)
          .eq("user_id", user.id);

        if (updateErr) {
          const classified = classifyError(updateErr);
          status = classified.httpStatus;
          errorCode = classified.code;
          return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
        }
      } else {
        status = 409;
        return jsonErr(409, "CANNOT_JOIN", `Participação com status '${existingPart.status}' não pode ser alterada`, requestId);
      }
    } else {
      // Check capacity for 1v1
      if (challenge.type === "one_vs_one") {
        const { data: parts } = await db
          .from("challenge_participants")
          .select("user_id")
          .eq("challenge_id", challenge_id);

        if ((parts ?? []).length >= 2) {
          status = 409;
          return jsonErr(409, "CHALLENGE_FULL", "Desafio 1v1 já tem 2 participantes", requestId);
        }
      }

      // Check team capacity (max 25 per team for team_vs_team)
      if (challenge.type === "team_vs_team" && joinerTeam) {
        const { data: teamParts } = await db
          .from("challenge_participants")
          .select("user_id")
          .eq("challenge_id", challenge_id)
          .eq("team", joinerTeam);

        if ((teamParts ?? []).length >= 25) {
          status = 409;
          return jsonErr(409, "TEAM_FULL", "Sua equipe já atingiu o limite de 25 atletas neste desafio", requestId);
        }
      }

      // Check group capacity
      if (challenge.type === "group") {
        const { data: parts } = await db
          .from("challenge_participants")
          .select("user_id")
          .eq("challenge_id", challenge_id);

        if ((parts ?? []).length >= 50) {
          status = 409;
          return jsonErr(409, "CHALLENGE_FULL", "Desafio lotado (máximo 50 participantes)", requestId);
        }
      }

      // Insert new participant as accepted
      const { error: insertErr } = await db
        .from("challenge_participants")
        .insert({
          challenge_id,
          user_id: user.id,
          display_name,
          status: "accepted",
          responded_at_ms: Date.now(),
          group_id: joinerGroupId,
          team: joinerTeam,
        });

      if (insertErr) {
        const classified = classifyError(insertErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }
    }

    // Check if challenge should auto-activate (on_accept mode)
    let newChallengeStatus = challenge.status;

    if (challenge.status === "pending" && challenge.start_mode === "on_accept") {
      const { data: allParts } = await db
        .from("challenge_participants")
        .select("user_id, status, team")
        .eq("challenge_id", challenge_id);

      const acceptedCount = (allParts ?? []).filter(
        (p: { status: string }) => p.status === "accepted"
      ).length;
      const invitedCount = (allParts ?? []).filter(
        (p: { status: string }) => p.status === "invited"
      ).length;

      let shouldStart = false;

      if (challenge.type === "one_vs_one") {
        shouldStart = acceptedCount === 2;
      } else if (challenge.type === "group") {
        // Group: activate when ALL invited have accepted (no more "invited")
        // OR when accept deadline has passed and at least 2 accepted
        const deadlinePassed = challenge.accept_deadline_ms
          ? Date.now() >= challenge.accept_deadline_ms
          : false;

        if (invitedCount === 0 && acceptedCount >= 2) {
          shouldStart = true;
        } else if (deadlinePassed && acceptedCount >= 2) {
          shouldStart = true;
        }
      } else {
        shouldStart = acceptedCount >= 2;
      }

      if (shouldStart) {
        const WARMUP_MS = 5 * 60 * 1000; // 5 min prep time
        const nowMs = Date.now();
        const startsAtMs = nowMs + WARMUP_MS;
        const endsAtMs = startsAtMs + challenge.window_ms;

        const { error: activateErr } = await db
          .from("challenges")
          .update({
            status: "active",
            starts_at_ms: startsAtMs,
            ends_at_ms: endsAtMs,
          })
          .eq("id", challenge_id)
          .eq("status", "pending");

        if (!activateErr) {
          newChallengeStatus = "active";
        }
      }
    }

    return jsonOk({
      challenge_id,
      joined: true,
      status: newChallengeStatus,
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
