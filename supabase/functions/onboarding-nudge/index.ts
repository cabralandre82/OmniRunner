import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * onboarding-nudge — Supabase Edge Function
 *
 * Triggered daily by pg_cron at 10:00 UTC. Sends onboarding push
 * notifications to users registered in the last 7 days (D0-D7).
 *
 * Messages:
 *   D0: Welcome + connect Strava
 *   D1: First run motivation
 *   D2: Explore challenges
 *   D3: Complete 3 runs for DNA
 *   D7: One week recap
 *
 * Uses notification_log for dedup (rule = "onboarding_nudge").
 * Dispatches via send-push.
 *
 * Service-role only. Deployed with --no-verify-jwt (cron caller).
 */

const FN = "onboarding-nudge";

interface NudgeMessage {
  title: string;
  body: string;
}

const NUDGE_MESSAGES: Record<number, NudgeMessage> = {
  0: {
    title: "Bem-vindo ao Omni Runner!",
    body: "Conecte o Strava para desbloquear seu progresso \u{1F3C3}",
  },
  1: {
    title: "Sua primeira corrida te espera!",
    body: "Sua primeira corrida desbloqueia badges e inicia sua jornada de evolução!",
  },
  2: {
    title: "Já explorou os desafios?",
    body: "Crie um e convide amigos para competir!",
  },
  3: {
    title: "Continue correndo!",
    body: "Complete 3 corridas para ver seu perfil de corredor começar a se formar \u{1F4CA}",
  },
  7: {
    title: "Uma semana com o Omni Runner!",
    body: "Continue correndo para desbloquear seu DNA completo.",
  },
};

const NUDGE_DAYS = Object.keys(NUDGE_MESSAGES).map(Number);
const MS_PER_DAY = 86_400_000;
const DEDUP_HOURS = 23;
const MS_PER_HOUR = 3_600_000;

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
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");

    if (!serviceKey || !supabaseUrl) {
      status = 500;
      errorCode = "CONFIG_ERROR";
      return jsonErr(500, "CONFIG_ERROR", "Server misconfiguration", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * MS_PER_DAY);

    // Fetch users who registered in the last 7 days
    const { data: recentUsers, error: usersErr } = await db
      .from("profiles")
      .select("id, created_at")
      .gte("created_at", sevenDaysAgo.toISOString())
      .limit(1000);

    if (usersErr || !recentUsers || recentUsers.length === 0) {
      return jsonOk({ evaluated: 0, sent: 0, reason: "no_recent_users" }, requestId);
    }

    let totalEvaluated = 0;
    let totalSent = 0;

    for (const user of recentUsers) {
      const userId = user.id as string;
      const createdAt = new Date(user.created_at as string);
      const daysSinceRegistration = Math.floor(
        (now.getTime() - createdAt.getTime()) / MS_PER_DAY,
      );

      if (!NUDGE_DAYS.includes(daysSinceRegistration)) continue;

      const message = NUDGE_MESSAGES[daysSinceRegistration];
      if (!message) continue;

      totalEvaluated++;

      const contextId = `d${daysSinceRegistration}`;

      // Dedup check via notification_log
      const since = new Date(now.getTime() - DEDUP_HOURS * MS_PER_HOUR).toISOString();
      const { data: existing } = await db
        .from("notification_log")
        .select("id")
        .eq("user_id", userId)
        .eq("rule", "onboarding_nudge")
        .eq("context_id", contextId)
        .gte("sent_at", since)
        .limit(1);

      if (existing && existing.length > 0) continue;

      // Dispatch push via send-push
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 15_000);
      let ok = false;
      try {
        const res = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${serviceKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            user_ids: [userId],
            title: message.title,
            body: message.body,
            data: { type: "onboarding_nudge", day: String(daysSinceRegistration) },
          }),
          signal: ctrl.signal,
        });
        ok = res.ok;
      } catch {
        ok = false;
      } finally {
        clearTimeout(timer);
      }

      if (ok) {
        await db.from("notification_log").insert({
          user_id: userId,
          rule: "onboarding_nudge",
          context_id: contextId,
        });
        totalSent++;
      }
    }

    return jsonOk({ evaluated: totalEvaluated, sent: totalSent }, requestId);
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
