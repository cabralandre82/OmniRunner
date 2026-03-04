import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { log } from "../_shared/logger.ts";

/**
 * notify-rules — Supabase Edge Function
 *
 * Evaluates smart notification rules and dispatches pushes via send-push.
 * Can be called by a cron job (evaluate all) or triggered with a specific
 * rule + context (e.g. after challenge creation).
 *
 * Rules:
 *   1. challenge_received  — notify user when invited to a challenge
 *   2. streak_at_risk      — notify users whose streak expires today
 *   3. championship_starting — notify participants of championships starting soon
 *   4. friend_request_received — notify user of incoming friend invite
 *   5. friend_request_accepted — notify inviter that friend accepted
 *   6. challenge_settled — notify participants of challenge result
 *   7. challenge_expiring — remind participants of approaching deadline
 *   8. inactivity_nudge — nudge users inactive for 5+ days
 *   9. badge_earned — notify user of new badge
 *  10. league_rank_change — notify assessoria members of rank change
 *  11. join_request_approved — notify athlete their join was approved
 *
 * POST /notify-rules
 * Body: {
 *   rule?: string,          — specific rule to evaluate (omit = evaluate all)
 *   context?: {             — optional context for targeted evaluation
 *     user_ids?: string[],
 *     challenge_id?: string,
 *     championship_id?: string,
 *   }
 * }
 *
 * Service-role only.
 */

const FN = "notify-rules";
const DEDUP_HOURS = 12;
const MS_PER_HOUR = 3_600_000;
const MS_PER_DAY = 86_400_000;

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
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── Auth: service-role only ────────────────────────────────────────
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");

    if (!serviceKey || !supabaseUrl) {
      status = 500;
      errorCode = "CONFIG_ERROR";
      return jsonErr(500, "CONFIG_ERROR", "Server misconfiguration", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const bearer = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7).trim()
      : "";

    if (bearer !== serviceKey) {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Service-role only", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    // ── Parse body ─────────────────────────────────────────────────────
    let body: {
      rule?: string;
      context?: {
        user_ids?: string[];
        challenge_id?: string;
        championship_id?: string;
      };
    } = {};

    try {
      body = await req.json();
    } catch {
      // empty body = evaluate all rules
    }

    const results: Record<string, { evaluated: number; sent: number }> = {};

    log("info", "notify-rules invoked", {
      request_id: requestId,
      rule: body.rule ?? "all",
      has_context: !!body.context,
    });

    // ── Evaluate rules ─────────────────────────────────────────────────
    const allRules = [
      "challenge_received", "challenge_accepted", "join_request_received",
      "streak_at_risk", "championship_starting",
      "championship_invite_received", "challenge_team_invite_received",
      "friend_request_received", "friend_request_accepted",
      "challenge_settled", "challenge_expiring", "inactivity_nudge",
      "badge_earned", "league_rank_change", "join_request_approved",
    ];
    const rulesToRun = body.rule ? [body.rule] : allRules;

    for (const rule of rulesToRun) {
      switch (rule) {
        case "challenge_received":
          results[rule] = await evaluateChallengeReceived(db, supabaseUrl, serviceKey, body.context);
          break;
        case "challenge_accepted":
          results[rule] = await evaluateChallengeAccepted(db, supabaseUrl, serviceKey, body.context);
          break;
        case "join_request_received":
          results[rule] = await evaluateJoinRequestReceived(db, supabaseUrl, serviceKey, body.context);
          break;
        case "streak_at_risk":
          results[rule] = await evaluateStreakAtRisk(db, supabaseUrl, serviceKey);
          break;
        case "championship_starting":
          results[rule] = await evaluateChampionshipStarting(db, supabaseUrl, serviceKey, body.context);
          break;
        case "championship_invite_received":
          results[rule] = await evaluateChampInviteReceived(db, supabaseUrl, serviceKey, body.context);
          break;
        case "challenge_team_invite_received":
          results[rule] = await evaluateChallengeTeamInviteReceived(db, supabaseUrl, serviceKey, body.context);
          break;
        case "low_credits_alert":
          results[rule] = await evaluateLowCreditsAlert(db, supabaseUrl, serviceKey, body.context);
          break;
        case "friend_request_received":
          results[rule] = await evaluateFriendRequestReceived(db, supabaseUrl, serviceKey, body.context);
          break;
        case "friend_request_accepted":
          results[rule] = await evaluateFriendRequestAccepted(db, supabaseUrl, serviceKey, body.context);
          break;
        case "challenge_settled":
          results[rule] = await evaluateChallengeSettled(db, supabaseUrl, serviceKey, body.context);
          break;
        case "challenge_expiring":
          results[rule] = await evaluateChallengeExpiring(db, supabaseUrl, serviceKey);
          break;
        case "inactivity_nudge":
          results[rule] = await evaluateInactivityNudge(db, supabaseUrl, serviceKey);
          break;
        case "badge_earned":
          results[rule] = await evaluateBadgeEarned(db, supabaseUrl, serviceKey, body.context);
          break;
        case "league_rank_change":
          results[rule] = await evaluateLeagueRankChange(db, supabaseUrl, serviceKey, body.context);
          break;
        case "join_request_approved":
          results[rule] = await evaluateJoinRequestApproved(db, supabaseUrl, serviceKey, body.context);
          break;
        default:
          results[rule] = { evaluated: 0, sent: 0 };
      }
    }

    const totalEvaluated = Object.values(results).reduce((s, r) => s + r.evaluated, 0);
    const totalSent = Object.values(results).reduce((s, r) => s + r.sent, 0);
    log("info", "notify-rules completed", {
      request_id: requestId,
      rules_run: Object.keys(results).length,
      total_evaluated: totalEvaluated,
      total_sent: totalSent,
      duration_ms: elapsed(),
    });

    return jsonOk({ rules: results }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    log("error", "notify-rules unexpected error", { request_id: requestId });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({ request_id: requestId, fn: FN, user_id: null, error_code: errorCode, duration_ms: elapsed() });
    } else {
      logRequest({ request_id: requestId, fn: FN, user_id: null, status, duration_ms: elapsed() });
    }
  }
});

// ═════════════════════════════════════════════════════════════════════════════
// Rule 1: Challenge Received
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChallengeReceived(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { user_ids?: string[]; challenge_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  let query = db
    .from("challenge_participants")
    .select("user_id, challenge_id, challenges!inner(name)")
    .eq("status", "invited");

  if (context?.challenge_id) {
    query = query.eq("challenge_id", context.challenge_id);
  }
  if (context?.user_ids?.length) {
    query = query.in("user_id", context.user_ids);
  }

  const { data: pending } = await query.limit(100);
  if (!pending || pending.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;
  for (const p of pending) {
    const userId = p.user_id as string;
    const challengeName = (p.challenges as { name: string })?.name ?? "Desafio";
    const contextId = p.challenge_id as string;

    if (await wasRecentlyNotified(db, userId, "challenge_received", contextId)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Novo desafio recebido!",
      body: `Você foi convidado para "${challengeName}". Aceite agora!`,
      data: { type: "challenge_received", challenge_id: contextId },
    });

    if (ok) {
      await logNotification(db, userId, "challenge_received", contextId);
      sent++;
    }
  }

  return { evaluated: pending.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 2: Streak at Risk
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateStreakAtRisk(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
): Promise<{ evaluated: number; sent: number }> {
  const nowMs = Date.now();
  const todayStart = new Date();
  todayStart.setUTCHours(0, 0, 0, 0);
  const todayStartMs = todayStart.getTime();

  // Users with active streak (>= 3 days) who haven't run today
  const { data: atRisk } = await db
    .from("v_user_progression")
    .select("user_id, display_name, streak_current")
    .gte("streak_current", 3)
    .limit(500);

  if (!atRisk || atRisk.length === 0) return { evaluated: 0, sent: 0 };

  // Check which of these users have a session today
  const userIds = atRisk.map((u: { user_id: string }) => u.user_id);
  const { data: todaySessions } = await db
    .from("sessions")
    .select("user_id")
    .in("user_id", userIds)
    .gte("start_time_ms", todayStartMs)
    .eq("is_verified", true);

  const ranToday = new Set(
    (todaySessions ?? []).map((s: { user_id: string }) => s.user_id),
  );

  const needsNotif = atRisk.filter(
    (u: { user_id: string }) => !ranToday.has(u.user_id),
  );

  let sent = 0;
  const todayKey = todayStart.toISOString().slice(0, 10);

  for (const u of needsNotif) {
    const userId = u.user_id as string;
    const streak = u.streak_current as number;

    if (await wasRecentlyNotified(db, userId, "streak_at_risk", todayKey)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Sua sequência está em risco!",
      body: `Você está com ${streak} dias seguidos. Corra hoje para manter!`,
      data: { type: "streak_at_risk", streak: String(streak) },
    });

    if (ok) {
      await logNotification(db, userId, "streak_at_risk", todayKey);
      sent++;
    }
  }

  return { evaluated: needsNotif.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 3: Championship Starting
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChampionshipStarting(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { championship_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  const now = new Date();
  const soonEnd = new Date(now.getTime() + MS_PER_DAY);

  // Championships starting within the next 24 hours
  let query = db
    .from("championships")
    .select("id, name, start_at")
    .gte("start_at", now.toISOString())
    .lte("start_at", soonEnd.toISOString())
    .in("status", ["open", "active"]);

  if (context?.championship_id) {
    query = db
      .from("championships")
      .select("id, name, start_at")
      .eq("id", context.championship_id)
      .in("status", ["draft", "open", "active"]);
  }

  const { data: champs } = await query.limit(50);
  if (!champs || champs.length === 0) return { evaluated: 0, sent: 0 };

  let totalSent = 0;

  for (const champ of champs) {
    const champId = champ.id as string;
    const champName = champ.name as string;
    const startAt = new Date(champ.start_at as string);

    const hoursUntil = Math.max(
      0,
      Math.round((startAt.getTime() - now.getTime()) / MS_PER_HOUR),
    );

    // Get participants
    const { data: participants } = await db
      .from("championship_participants")
      .select("user_id")
      .eq("championship_id", champId)
      .in("status", ["enrolled", "active"])
      .limit(500);

    if (!participants || participants.length === 0) continue;

    for (const p of participants) {
      const userId = p.user_id as string;

      if (await wasRecentlyNotified(db, userId, "championship_starting", champId)) {
        continue;
      }

      const timeLabel = hoursUntil <= 1
        ? "em breve"
        : `em ${hoursUntil}h`;

      const ok = await dispatchPush(supabaseUrl, serviceKey, {
        user_ids: [userId],
        title: "Campeonato começando!",
        body: `"${champName}" começa ${timeLabel}. Prepare-se!`,
        data: { type: "championship_starting", championship_id: champId },
      });

      if (ok) {
        await logNotification(db, userId, "championship_starting", champId);
        totalSent++;
      }
    }
  }

  return { evaluated: champs.length, sent: totalSent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 4: Championship Invite Received
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChampInviteReceived(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { user_ids?: string[]; championship_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.user_ids?.length || !context?.championship_id) {
    return { evaluated: 0, sent: 0 };
  }

  const { data: champ } = await db
    .from("championships")
    .select("name")
    .eq("id", context.championship_id)
    .maybeSingle();

  const champName = champ?.name ?? "Campeonato";
  let sent = 0;

  for (const userId of context.user_ids) {
    if (await wasRecentlyNotified(db, userId, "championship_invite_received", context.championship_id)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Convite de campeonato!",
      body: `Sua assessoria foi convidada para "${champName}". Responda no painel.`,
      data: { type: "championship_invite_received", championship_id: context.championship_id },
    });

    if (ok) {
      await logNotification(db, userId, "championship_invite_received", context.championship_id);
      sent++;
    }
  }

  return { evaluated: context.user_ids.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 5: Challenge Team Invite Received
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChallengeTeamInviteReceived(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { user_ids?: string[]; challenge_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.user_ids?.length || !context?.challenge_id) {
    return { evaluated: 0, sent: 0 };
  }

  const { data: challenge } = await db
    .from("challenges")
    .select("title")
    .eq("id", context.challenge_id)
    .maybeSingle();

  const challName = challenge?.title ?? "Desafio de Equipe";
  let sent = 0;

  for (const userId of context.user_ids) {
    if (await wasRecentlyNotified(db, userId, "challenge_team_invite_received", context.challenge_id)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Desafio de equipe recebido!",
      body: `Sua assessoria foi desafiada: "${challName}". Responda no painel.`,
      data: { type: "challenge_team_invite_received", challenge_id: context.challenge_id },
    });

    if (ok) {
      await logNotification(db, userId, "challenge_team_invite_received", context.challenge_id);
      sent++;
    }
  }

  return { evaluated: context.user_ids.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 6: Challenge Accepted (opponent joined)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChallengeAccepted(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { challenge_id?: string; joiner_user_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.challenge_id) {
    return { evaluated: 0, sent: 0 };
  }

  const challengeId = context.challenge_id;
  const joinerId = context.joiner_user_id;

  const { data: challenge } = await db
    .from("challenges")
    .select("title, creator_user_id")
    .eq("id", challengeId)
    .maybeSingle();

  if (!challenge) return { evaluated: 0, sent: 0 };

  const challName = challenge.title ?? "Desafio";

  // Get joiner display name
  let joinerName = "Um atleta";
  if (joinerId) {
    const { data: joinerProfile } = await db
      .from("profiles")
      .select("display_name")
      .eq("id", joinerId)
      .maybeSingle();
    if (joinerProfile?.display_name) {
      joinerName = joinerProfile.display_name;
    }
  }

  // Notify all OTHER accepted participants (including the creator)
  const { data: participants } = await db
    .from("challenge_participants")
    .select("user_id")
    .eq("challenge_id", challengeId)
    .eq("status", "accepted")
    .limit(100);

  const targetIds = (participants ?? [])
    .map((p: { user_id: string }) => p.user_id)
    .filter((uid: string) => uid !== joinerId);

  // Also include the creator (may not be in participants table for some flows)
  if (challenge.creator_user_id && challenge.creator_user_id !== joinerId) {
    if (!targetIds.includes(challenge.creator_user_id)) {
      targetIds.push(challenge.creator_user_id);
    }
  }

  if (targetIds.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;
  const dedupKey = `${challengeId}:${joinerId ?? "unknown"}`;

  for (const userId of targetIds) {
    if (await wasRecentlyNotified(db, userId, "challenge_accepted", dedupKey)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Desafio aceito!",
      body: `${joinerName} aceitou "${challName}". Prepare-se!`,
      data: { type: "challenge_accepted", challenge_id: challengeId },
    });

    if (ok) {
      await logNotification(db, userId, "challenge_accepted", dedupKey);
      sent++;
    }
  }

  return { evaluated: targetIds.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 7: Join Request Received (athlete wants to join assessoria)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateJoinRequestReceived(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { group_id?: string; athlete_name?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.group_id) {
    return { evaluated: 0, sent: 0 };
  }

  const groupId = context.group_id;
  const athleteName = context.athlete_name ?? "Um atleta";

  // Get group name
  const { data: group } = await db
    .from("coaching_groups")
    .select("name")
    .eq("id", groupId)
    .maybeSingle();

  const groupName = group?.name ?? "sua assessoria";

  // Get staff members (admin_master + coach) of this group
  const { data: staff } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .in("role", ["admin_master", "coach"])
    .limit(50);

  if (!staff || staff.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;
  const dedupKey = `${groupId}:${athleteName}`;

  for (const s of staff) {
    const userId = s.user_id as string;

    if (await wasRecentlyNotified(db, userId, "join_request_received", dedupKey)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Nova solicitação de entrada",
      body: `${athleteName} quer entrar em "${groupName}". Aprove no app.`,
      data: { type: "join_request_received", group_id: groupId },
    });

    if (ok) {
      await logNotification(db, userId, "join_request_received", dedupKey);
      sent++;
    }
  }

  return { evaluated: staff.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 8: Friend Request Received
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateFriendRequestReceived(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { to_user_id?: string; from_user_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.to_user_id || !context?.from_user_id) {
    return { evaluated: 0, sent: 0 };
  }

  const { data: sender } = await db
    .from("profiles")
    .select("display_name")
    .eq("id", context.from_user_id)
    .maybeSingle();

  const senderName = sender?.display_name ?? "Alguém";
  const dedupKey = `${context.from_user_id}:${context.to_user_id}`;

  if (await wasRecentlyNotified(db, context.to_user_id, "friend_request_received", dedupKey)) {
    return { evaluated: 1, sent: 0 };
  }

  const ok = await dispatchPush(supabaseUrl, serviceKey, {
    user_ids: [context.to_user_id],
    title: "Novo pedido de amizade!",
    body: `${senderName} quer ser seu amigo de corrida.`,
    data: { type: "friend_request_received", from_user_id: context.from_user_id },
  });

  if (ok) {
    await logNotification(db, context.to_user_id, "friend_request_received", dedupKey);
  }

  return { evaluated: 1, sent: ok ? 1 : 0 };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 9: Friend Request Accepted
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateFriendRequestAccepted(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { accepter_user_id?: string; original_sender_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.accepter_user_id || !context?.original_sender_id) {
    return { evaluated: 0, sent: 0 };
  }

  const { data: accepter } = await db
    .from("profiles")
    .select("display_name")
    .eq("id", context.accepter_user_id)
    .maybeSingle();

  const accepterName = accepter?.display_name ?? "Alguém";
  const dedupKey = `${context.accepter_user_id}:${context.original_sender_id}`;

  if (await wasRecentlyNotified(db, context.original_sender_id, "friend_request_accepted", dedupKey)) {
    return { evaluated: 1, sent: 0 };
  }

  const ok = await dispatchPush(supabaseUrl, serviceKey, {
    user_ids: [context.original_sender_id],
    title: "Pedido aceito!",
    body: `${accepterName} aceitou sua amizade. Vejam os perfis!`,
    data: { type: "friend_request_accepted", accepter_user_id: context.accepter_user_id },
  });

  if (ok) {
    await logNotification(db, context.original_sender_id, "friend_request_accepted", dedupKey);
  }

  return { evaluated: 1, sent: ok ? 1 : 0 };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 10: Challenge Settled (results ready)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChallengeSettled(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { challenge_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.challenge_id) return { evaluated: 0, sent: 0 };

  const challengeId = context.challenge_id;

  const { data: challenge } = await db
    .from("challenges")
    .select("title")
    .eq("id", challengeId)
    .maybeSingle();

  if (!challenge) return { evaluated: 0, sent: 0 };

  const challName = challenge.title ?? "Desafio";

  const { data: participants } = await db
    .from("challenge_participants")
    .select("user_id")
    .eq("challenge_id", challengeId)
    .in("status", ["accepted", "completed"])
    .limit(100);

  if (!participants || participants.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;

  for (const p of participants) {
    const userId = p.user_id as string;

    if (await wasRecentlyNotified(db, userId, "challenge_settled", challengeId)) {
      continue;
    }

    const { data: result } = await db
      .from("challenge_results")
      .select("outcome")
      .eq("challenge_id", challengeId)
      .eq("user_id", userId)
      .maybeSingle();

    const outcome = result?.outcome as string | null;
    let bodyText = `O desafio "${challName}" foi encerrado. Veja o resultado!`;
    if (outcome === "win") {
      bodyText = `Você venceu "${challName}"! Confira seus ganhos!`;
    } else if (outcome === "loss") {
      bodyText = `O desafio "${challName}" terminou. Veja os detalhes.`;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Resultado do desafio!",
      body: bodyText,
      data: { type: "challenge_settled", challenge_id: challengeId },
    });

    if (ok) {
      await logNotification(db, userId, "challenge_settled", challengeId);
      sent++;
    }
  }

  return { evaluated: participants.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 11: Challenge Expiring (deadline < 24h)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateChallengeExpiring(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
): Promise<{ evaluated: number; sent: number }> {
  const nowMs = Date.now();
  const soonMs = nowMs + MS_PER_DAY;

  const { data: expiring } = await db
    .from("challenges")
    .select("id, title, ends_at_ms")
    .eq("status", "active")
    .gt("ends_at_ms", nowMs)
    .lte("ends_at_ms", soonMs)
    .limit(100);

  if (!expiring || expiring.length === 0) return { evaluated: 0, sent: 0 };

  let totalSent = 0;

  for (const ch of expiring) {
    const challengeId = ch.id as string;
    const challName = ch.title ?? "Desafio";
    const endsMs = ch.ends_at_ms as number;
    const hoursLeft = Math.max(1, Math.round((endsMs - nowMs) / MS_PER_HOUR));

    const { data: participants } = await db
      .from("challenge_participants")
      .select("user_id, contributing_session_ids")
      .eq("challenge_id", challengeId)
      .eq("status", "accepted")
      .limit(100);

    if (!participants) continue;

    // Only notify participants who haven't contributed yet
    const needsReminder = participants.filter(
      (p: { contributing_session_ids: string[] | null }) =>
        !p.contributing_session_ids || p.contributing_session_ids.length === 0,
    );

    for (const p of needsReminder) {
      const userId = p.user_id as string;

      if (await wasRecentlyNotified(db, userId, "challenge_expiring", challengeId)) {
        continue;
      }

      const ok = await dispatchPush(supabaseUrl, serviceKey, {
        user_ids: [userId],
        title: "Desafio expirando!",
        body: `"${challName}" termina em ${hoursLeft}h. Corra agora!`,
        data: { type: "challenge_expiring", challenge_id: challengeId },
      });

      if (ok) {
        await logNotification(db, userId, "challenge_expiring", challengeId);
        totalSent++;
      }
    }
  }

  return { evaluated: expiring.length, sent: totalSent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 12: Inactivity Nudge (5+ days without running)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateInactivityNudge(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
): Promise<{ evaluated: number; sent: number }> {
  const nowMs = Date.now();
  const todayKey = new Date().toISOString().slice(0, 10);

  // SQL set-difference: users active in 30 days EXCEPT active in 5 days (capped at 500)
  const { data: inactive, error: rpcErr } = await db.rpc("fn_inactive_users", {
    p_active_window_days: 30,
    p_recent_window_days: 5,
    p_limit: 500,
  });

  if (rpcErr || !inactive || inactive.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;

  for (const row of inactive) {
    const userId = row.user_id as string;

    if (await wasRecentlyNotified(db, userId, "inactivity_nudge", todayKey)) {
      continue;
    }

    // Find how many days since last run
    const { data: lastSession } = await db
      .from("sessions")
      .select("start_time_ms")
      .eq("user_id", userId)
      .eq("is_verified", true)
      .order("start_time_ms", { ascending: false })
      .limit(1);

    const lastMs = lastSession?.[0]?.start_time_ms as number | undefined;
    const daysSince = lastMs ? Math.floor((nowMs - lastMs) / MS_PER_DAY) : 5;

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Sentimos sua falta!",
      body: `Faz ${daysSince} dias que você não corre. Uma corridinha leve?`,
      data: { type: "inactivity_nudge", days: String(daysSince) },
    });

    if (ok) {
      await logNotification(db, userId, "inactivity_nudge", todayKey);
      sent++;
    }
  }

  return { evaluated: inactive.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 13: Badge Earned
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateBadgeEarned(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { user_id?: string; badge_id?: string; badge_name?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.user_id || !context?.badge_id) {
    return { evaluated: 0, sent: 0 };
  }

  const userId = context.user_id;
  const badgeName = context.badge_name ?? "uma conquista";
  const dedupKey = `${userId}:${context.badge_id}`;

  if (await wasRecentlyNotified(db, userId, "badge_earned", dedupKey)) {
    return { evaluated: 1, sent: 0 };
  }

  const ok = await dispatchPush(supabaseUrl, serviceKey, {
    user_ids: [userId],
    title: "Nova conquista!",
    body: `Você desbloqueou "${badgeName}". Confira no seu perfil!`,
    data: { type: "badge_earned", badge_id: context.badge_id },
  });

  if (ok) {
    await logNotification(db, userId, "badge_earned", dedupKey);
  }

  return { evaluated: 1, sent: ok ? 1 : 0 };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 14: League Rank Change
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateLeagueRankChange(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { group_id?: string; new_rank?: number; old_rank?: number; season_name?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.group_id || context.new_rank == null || context.old_rank == null) {
    return { evaluated: 0, sent: 0 };
  }

  const groupId = context.group_id;
  const newRank = context.new_rank;
  const oldRank = context.old_rank;
  const seasonName = context.season_name ?? "Liga OmniRunner";

  if (newRank === oldRank) return { evaluated: 0, sent: 0 };

  const wentUp = newRank < oldRank;
  const title = wentUp ? "Sua assessoria subiu!" : "Atenção na Liga!";
  const bodyText = wentUp
    ? `Sua assessoria subiu para #${newRank} na ${seasonName}!`
    : `Sua assessoria caiu para #${newRank} na ${seasonName}. Mobilize o time!`;

  // Notify all members of the group
  const { data: members } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .in("role", ["admin_master", "coach", "athlete"])
    .limit(200);

  if (!members || members.length === 0) return { evaluated: 0, sent: 0 };

  const dedupKey = `${groupId}:${newRank}`;
  let sent = 0;

  for (const m of members) {
    const userId = m.user_id as string;

    if (await wasRecentlyNotified(db, userId, "league_rank_change", dedupKey)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title,
      body: bodyText,
      data: { type: "league_rank_change", group_id: groupId, rank: String(newRank) },
    });

    if (ok) {
      await logNotification(db, userId, "league_rank_change", dedupKey);
      sent++;
    }
  }

  return { evaluated: members.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule 15: Join Request Approved (athlete accepted into assessoria)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateJoinRequestApproved(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { user_id?: string; group_id?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.user_id || !context?.group_id) {
    return { evaluated: 0, sent: 0 };
  }

  const userId = context.user_id;
  const groupId = context.group_id;

  const { data: group } = await db
    .from("coaching_groups")
    .select("name")
    .eq("id", groupId)
    .maybeSingle();

  const groupName = group?.name ?? "uma assessoria";
  const dedupKey = `${groupId}:${userId}`;

  if (await wasRecentlyNotified(db, userId, "join_request_approved", dedupKey)) {
    return { evaluated: 1, sent: 0 };
  }

  const ok = await dispatchPush(supabaseUrl, serviceKey, {
    user_ids: [userId],
    title: "Você foi aceito!",
    body: `Bem-vindo à "${groupName}"! Seus treinos agora contam para o grupo.`,
    data: { type: "join_request_approved", group_id: groupId },
  });

  if (ok) {
    await logNotification(db, userId, "join_request_approved", dedupKey);
  }

  return { evaluated: 1, sent: ok ? 1 : 0 };
}

// ═════════════════════════════════════════════════════════════════════════════
// Rule: Low Credits Alert (hybrid auto-topup fallback)
// ═════════════════════════════════════════════════════════════════════════════

async function evaluateLowCreditsAlert(
  // deno-lint-ignore no-explicit-any
  db: any,
  supabaseUrl: string,
  serviceKey: string,
  context?: { group_id?: string; balance?: number; threshold?: number; product_name?: string },
): Promise<{ evaluated: number; sent: number }> {
  if (!context?.group_id) return { evaluated: 0, sent: 0 };

  const groupId = context.group_id;
  const balance = context.balance ?? 0;
  const threshold = context.threshold ?? 50;
  const productName = context.product_name ?? "créditos";

  const { data: group } = await db
    .from("coaching_groups")
    .select("name")
    .eq("id", groupId)
    .maybeSingle();

  const groupName = group?.name ?? "sua assessoria";

  const { data: staff } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("role", "admin_master")
    .limit(10);

  if (!staff || staff.length === 0) return { evaluated: 0, sent: 0 };

  let sent = 0;
  const dedupKey = `low_credits:${groupId}`;

  for (const s of staff) {
    const userId = s.user_id as string;

    if (await wasRecentlyNotified(db, userId, "low_credits_alert", dedupKey)) {
      continue;
    }

    const ok = await dispatchPush(supabaseUrl, serviceKey, {
      user_ids: [userId],
      title: "Créditos baixos",
      body: `"${groupName}" tem apenas ${balance} OmniCoins (mínimo: ${threshold}). Compre mais pelo portal.`,
      data: { type: "low_credits_alert", group_id: groupId },
    });

    if (ok) {
      await logNotification(db, userId, "low_credits_alert", dedupKey);
      sent++;
    }
  }

  return { evaluated: staff.length, sent };
}

// ═════════════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════════════

async function wasRecentlyNotified(
  // deno-lint-ignore no-explicit-any
  db: any,
  userId: string,
  rule: string,
  contextId: string,
): Promise<boolean> {
  const since = new Date(Date.now() - DEDUP_HOURS * MS_PER_HOUR).toISOString();

  const { data } = await db
    .from("notification_log")
    .select("id")
    .eq("user_id", userId)
    .eq("rule", rule)
    .eq("context_id", contextId)
    .gte("sent_at", since)
    .limit(1);

  return data != null && data.length > 0;
}

async function logNotification(
  // deno-lint-ignore no-explicit-any
  db: any,
  userId: string,
  rule: string,
  contextId: string,
): Promise<void> {
  await db.from("notification_log").insert({
    user_id: userId,
    rule,
    context_id: contextId,
  });
}

async function dispatchPush(
  supabaseUrl: string,
  serviceKey: string,
  payload: {
    user_ids: string[];
    title: string;
    body: string;
    data?: Record<string, string>;
  },
): Promise<boolean> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 15_000);
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });

    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}
