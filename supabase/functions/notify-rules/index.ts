import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

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

    // ── Evaluate rules ─────────────────────────────────────────────────
    const allRules = [
      "challenge_received", "streak_at_risk", "championship_starting",
      "championship_invite_received", "challenge_team_invite_received",
    ];
    const rulesToRun = body.rule ? [body.rule] : allRules;

    for (const rule of rulesToRun) {
      switch (rule) {
        case "challenge_received":
          results[rule] = await evaluateChallengeReceived(db, supabaseUrl, serviceKey, body.context);
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
        default:
          results[rule] = { evaluated: 0, sent: 0 };
      }
    }

    return jsonOk({ rules: results }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
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
    .gte("streak_current", 3);

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
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    return res.ok;
  } catch {
    return false;
  }
}
