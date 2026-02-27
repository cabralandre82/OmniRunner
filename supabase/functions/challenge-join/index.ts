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

    const { challenge_id, display_name, team: requestedTeam } = body;

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

    // ── Assessoria gate: all challenges require group membership ──────
    const { data: memberRow } = await db
      .from("coaching_members")
      .select("id")
      .eq("user_id", user.id)
      .limit(1)
      .maybeSingle();

    if (!memberRow) {
      status = 403;
      errorCode = "NO_ASSESSORIA";
      return jsonErr(
        403, "NO_ASSESSORIA",
        "Você precisa estar em uma assessoria para participar de desafios. Peça o código de convite ao seu professor.",
        requestId,
      );
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

      // Check group/team capacity
      if (challenge.type === "group" || challenge.type === "team") {
        const { data: parts } = await db
          .from("challenge_participants")
          .select("user_id, team")
          .eq("challenge_id", challenge_id);

        if ((parts ?? []).length >= 50) {
          status = 409;
          return jsonErr(409, "CHALLENGE_FULL", "Desafio lotado (máximo 50 participantes)", requestId);
        }

        // Team challenges: validate equal team sizes
        if (challenge.type === "team") {
          if (!requestedTeam || !["A", "B"].includes(requestedTeam)) {
            status = 400;
            return jsonErr(400, "TEAM_REQUIRED", "Para desafios de time, informe team: 'A' ou 'B'", requestId);
          }
          const myTeamCount = (parts ?? []).filter(
            (p: { team: string | null }) => p.team === requestedTeam
          ).length;
          const otherTeam = requestedTeam === "A" ? "B" : "A";
          const otherTeamCount = (parts ?? []).filter(
            (p: { team: string | null }) => p.team === otherTeam
          ).length;
          if (myTeamCount > otherTeamCount) {
            status = 409;
            return jsonErr(409, "TEAM_FULL",
              `Time ${requestedTeam} já tem mais membros que o time ${otherTeam}. Equilibre os times.`,
              requestId);
          }
        }
      }

      // Insert new participant as accepted
      // deno-lint-ignore no-explicit-any
      const insertPayload: Record<string, any> = {
        challenge_id,
        user_id: user.id,
        display_name,
        status: "accepted",
        responded_at_ms: Date.now(),
      };
      if (challenge.type === "team" && requestedTeam) {
        insertPayload.team = requestedTeam;
      }

      const { error: insertErr } = await db
        .from("challenge_participants")
        .insert(insertPayload);

      if (insertErr) {
        const classified = classifyError(insertErr);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }
    }

    // ── Entry fee debit (atomic balance check) ────────────────────────
    if (challenge.entry_fee_coins > 0) {
      const { data: debited, error: debitErr } = await db
        .rpc("debit_wallet_checked", {
          p_user_id: user.id,
          p_amount: challenge.entry_fee_coins,
        });

      if (debitErr || debited !== true) {
        // Rollback: remove just-inserted participant
        if (!existingPart) {
          await db.from("challenge_participants").delete()
            .eq("challenge_id", challenge_id).eq("user_id", user.id);
        } else if (existingPart.status === "invited") {
          await db.from("challenge_participants")
            .update({ status: "invited", responded_at_ms: null })
            .eq("challenge_id", challenge_id).eq("user_id", user.id);
        }

        status = 402;
        errorCode = "INSUFFICIENT_BALANCE";
        return jsonErr(
          402, "INSUFFICIENT_BALANCE",
          "Saldo insuficiente de OmniCoins para participar deste desafio.",
          requestId,
        );
      }

      await db.from("coin_ledger").insert({
        user_id: user.id,
        delta_coins: -challenge.entry_fee_coins,
        reason: "challenge_entry_fee",
        ref_id: challenge_id,
        created_at_ms: Date.now(),
      });
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
      } else if (challenge.type === "team") {
        const acceptedA = (allParts ?? []).filter(
          (p: { status: string; team: string | null }) => p.status === "accepted" && p.team === "A"
        ).length;
        const acceptedB = (allParts ?? []).filter(
          (p: { status: string; team: string | null }) => p.status === "accepted" && p.team === "B"
        ).length;
        const teamsBalanced = acceptedA >= 1 && acceptedA === acceptedB;
        const deadlinePassed = challenge.accept_deadline_ms
          ? Date.now() >= challenge.accept_deadline_ms
          : false;

        if (invitedCount === 0 && teamsBalanced) {
          shouldStart = true;
        } else if (deadlinePassed && teamsBalanced) {
          shouldStart = true;
        }
      } else {
        const deadlinePassed = challenge.accept_deadline_ms
          ? Date.now() >= challenge.accept_deadline_ms
          : false;

        if (invitedCount === 0 && acceptedCount >= 2) {
          shouldStart = true;
        } else if (deadlinePassed && acceptedCount >= 2) {
          shouldStart = true;
        }
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

    // ── Push notification: notify creator + other participants ────────
    try {
      const serviceKey =
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
        Deno.env.get("SERVICE_ROLE_KEY");
      const supabaseUrl = Deno.env.get("SUPABASE_URL");

      if (serviceKey && supabaseUrl) {
        fetch(`${supabaseUrl}/functions/v1/notify-rules`, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${serviceKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            rule: "challenge_accepted",
            context: {
              challenge_id,
              joiner_user_id: user.id,
            },
          }),
        }).catch(() => {/* fire-and-forget */});
      }
    } catch {
      // Push is best-effort — never block the join response
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
