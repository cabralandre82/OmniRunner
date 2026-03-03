import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * challenge-invite-group — Supabase Edge Function
 *
 * Creator (or staff of creator's group) invites another assessoria
 * to a team_vs_team challenge. Sets team_b_group_id on the challenge
 * and creates an entry in challenge_team_invites.
 *
 * POST /challenge-invite-group
 * Body: { challenge_id: string, to_group_id: string }
 */

const FN = "challenge-invite-group";

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
      requireFields(body, ["challenge_id", "to_group_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { challenge_id, to_group_id } = body;

    // Load challenge
    const { data: challenge, error: challengeErr } = await db
      .from("challenges")
      .select("id, type, status, team_a_group_id, team_b_group_id, creator_user_id")
      .eq("id", challenge_id)
      .maybeSingle();

    if (challengeErr) {
      const classified = classifyError(challengeErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!challenge) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Desafio não encontrado", requestId);
    }

    if (challenge.type !== "team_vs_team") {
      status = 400;
      return jsonErr(400, "NOT_TEAM", "Este desafio não é do tipo equipe vs equipe", requestId);
    }

    if (challenge.status !== "pending") {
      status = 409;
      return jsonErr(409, "INVALID_STATUS", "Desafio já iniciado, não é possível convidar", requestId);
    }

    if (to_group_id === challenge.team_a_group_id) {
      status = 400;
      return jsonErr(400, "SELF_INVITE", "Não pode convidar a própria assessoria", requestId);
    }

    if (challenge.team_b_group_id && challenge.team_b_group_id !== to_group_id) {
      status = 409;
      return jsonErr(409, "ALREADY_INVITED", "Outra assessoria já foi convidada para este desafio", requestId);
    }

    // Verify caller is creator or staff of team A
    const isCreator = challenge.creator_user_id === user.id;
    if (!isCreator) {
      const { data: membership } = await db
        .from("coaching_members")
        .select("role")
        .eq("group_id", challenge.team_a_group_id)
        .eq("user_id", user.id)
        .maybeSingle();

      if (!membership || !["admin_master", "coach"].includes(membership.role)) {
        status = 403;
        return jsonErr(403, "FORBIDDEN", "Apenas o criador ou staff da assessoria podem convidar", requestId);
      }
    }

    // Verify target group exists
    const { data: targetGroup } = await db
      .from("coaching_groups")
      .select("id, name")
      .eq("id", to_group_id)
      .maybeSingle();

    if (!targetGroup) {
      status = 404;
      return jsonErr(404, "GROUP_NOT_FOUND", "Assessoria não encontrada", requestId);
    }

    // Set team_b_group_id on challenge
    const { error: updateErr } = await db
      .from("challenges")
      .update({ team_b_group_id: to_group_id })
      .eq("id", challenge_id);

    if (updateErr) {
      const classified = classifyError(updateErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // Upsert invite record
    const { data: invite, error: inviteErr } = await db
      .from("challenge_team_invites")
      .upsert({
        challenge_id,
        to_group_id,
        invited_by: user.id,
        status: "pending",
      }, { onConflict: "challenge_id,to_group_id" })
      .select("id, status")
      .single();

    if (inviteErr) {
      const classified = classifyError(inviteErr);
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
              rule: "challenge_team_invite_received",
              context: { challenge_id, user_ids: staffIds },
            }),
          }).catch(() => {});
        }
      }
    } catch { /* non-blocking */ }

    return jsonOk({
      invite_id: invite.id,
      challenge_id,
      to_group_id,
      to_group_name: targetGroup.name,
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
