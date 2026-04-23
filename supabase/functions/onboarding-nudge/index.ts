import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * onboarding-nudge — Supabase Edge Function
 *
 * Triggered hourly by pg_cron ('0 * * * *' — L12-07). For each user
 * registered in the last 7 days, checks whether the user's current
 * local hour matches their `profiles.notification_hour_local` (default
 * 9) in their `profiles.timezone` (default 'America/Sao_Paulo'). Only
 * dispatches the nudge during that single hour per user per day.
 *
 * L12-09 idempotency (UNIQUE on notification_log(user_id, rule,
 * context_id) with context_id = "d${daysSinceRegistration}")
 * guarantees exactly-once per user per day even if the hourly loop
 * fires 24×/day. 23 of 24 invocations are near-no-ops.
 *
 * Messages:
 *   D0: Welcome + connect Strava
 *   D1: First run motivation
 *   D2: Explore challenges
 *   D3: Complete 3 runs for DNA
 *   D4: Join an assessoria
 *   D5: Check your progress
 *   D6: Weekly goal motivation
 *   D7: One week recap
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
  4: {
    title: "Já faz parte de uma assessoria?",
    body: "Assessorias desbloqueiam ranking de grupo, treinos prescritos e desafios em equipe!",
  },
  5: {
    title: "Confira seu progresso!",
    body: "Acesse o hub de Progresso para ver badges, missões e sua evolução \u{1F4AA}",
  },
  6: {
    title: "Sua meta semanal está perto!",
    body: "Mais uma corrida e você mantém sua sequência ativa \u{1F525}",
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

const DEFAULT_TIMEZONE = "America/Sao_Paulo";
const DEFAULT_NOTIFICATION_HOUR = 9;

/**
 * Returns the current hour-of-day (0..23) as observed in the given IANA
 * timezone using the runtime's Intl tables. Falls back silently to the
 * default Sao_Paulo hour if `tz` is bogus (defence in depth against
 * rows that somehow bypassed the DB CHECK).
 */
function currentHourInTimezone(tz: string): number {
  try {
    const fmt = new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      hour12: false,
      timeZone: tz || DEFAULT_TIMEZONE,
    });
    const parts = fmt.formatToParts(new Date());
    const hourPart = parts.find((p) => p.type === "hour");
    if (!hourPart) return new Date().getUTCHours();
    const n = Number.parseInt(hourPart.value, 10);
    if (!Number.isFinite(n) || n < 0 || n > 23) return new Date().getUTCHours();
    return n === 24 ? 0 : n;
  } catch {
    const fallback = new Intl.DateTimeFormat("en-US", {
      hour: "numeric",
      hour12: false,
      timeZone: DEFAULT_TIMEZONE,
    }).formatToParts(new Date()).find((p) => p.type === "hour")?.value ?? "9";
    const n = Number.parseInt(fallback, 10);
    return Number.isFinite(n) ? (n === 24 ? 0 : n) : 9;
  }
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "2.0.0" }), {
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

    // Fetch users who registered in the last 7 days. `timezone` /
    // `notification_hour_local` may not exist on very old dev DBs — we
    // SELECT defensively and fall back to Sao_Paulo/9 below.
    let recentUsers:
      | Array<{
          id: string;
          created_at: string;
          timezone?: string | null;
          notification_hour_local?: number | null;
        }>
      | null = null;
    let usersErr: { message?: string } | null = null;
    {
      const res = await db
        .from("profiles")
        .select("id, created_at, timezone, notification_hour_local")
        .gte("created_at", sevenDaysAgo.toISOString())
        .limit(1000);
      if (res.error) {
        // Fallback for pre-L12-07 schemas (no timezone columns).
        const fallback = await db
          .from("profiles")
          .select("id, created_at")
          .gte("created_at", sevenDaysAgo.toISOString())
          .limit(1000);
        recentUsers = fallback.data as typeof recentUsers;
        usersErr = fallback.error as typeof usersErr;
      } else {
        recentUsers = res.data as typeof recentUsers;
      }
    }

    if (usersErr || !recentUsers || recentUsers.length === 0) {
      return jsonOk({ evaluated: 0, sent: 0, reason: "no_recent_users" }, requestId);
    }

    let totalEvaluated = 0;
    let totalSent = 0;
    let totalSkippedOffHour = 0;

    for (const user of recentUsers) {
      const userId = user.id as string;
      const createdAt = new Date(user.created_at as string);
      const daysSinceRegistration = Math.floor(
        (now.getTime() - createdAt.getTime()) / MS_PER_DAY,
      );

      if (!NUDGE_DAYS.includes(daysSinceRegistration)) continue;

      const message = NUDGE_MESSAGES[daysSinceRegistration];
      if (!message) continue;

      // L12-07 — respect user's preferred local-hour window. The cron
      // runs hourly, but we only dispatch during the user's configured
      // notification hour (default 9) in their configured timezone
      // (default Sao_Paulo). L12-09 dedup ensures exactly-once/day even
      // if we somehow fire twice in the same hour.
      const userTz =
        (user.timezone && typeof user.timezone === "string"
          ? user.timezone
          : DEFAULT_TIMEZONE);
      const userPrefHour =
        typeof user.notification_hour_local === "number" &&
        user.notification_hour_local >= 0 &&
        user.notification_hour_local <= 23
          ? user.notification_hour_local
          : DEFAULT_NOTIFICATION_HOUR;

      const localHour = currentHourInTimezone(userTz);
      if (localHour !== userPrefHour) {
        totalSkippedOffHour++;
        continue;
      }

      totalEvaluated++;

      const contextId = `d${daysSinceRegistration}`;

      // L12-09 — race-safe claim: INSERT ... ON CONFLICT DO NOTHING via RPC.
      // Returns TRUE iff this caller won the claim (and owns the dispatch).
      // A legacy select+insert fallback kicks in if the RPC isn't installed
      // yet (e.g. fresh dev DB before this PR's migration).
      let claimed = false;
      try {
        const { data, error } = await db.rpc("fn_try_claim_notification", {
          p_user_id: userId,
          p_rule: "onboarding_nudge",
          p_context_id: contextId,
        });
        if (error) throw error;
        claimed = data === true;
      } catch {
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

        const { error: insErr } = await db.from("notification_log").insert({
          user_id: userId,
          rule: "onboarding_nudge",
          context_id: contextId,
        });
        claimed = !insErr || (insErr.code as string | undefined) !== "23505";
        if (insErr && (insErr.code as string | undefined) === "23505") continue;
      }

      if (!claimed) continue;

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
        totalSent++;
      } else {
        // Dispatch failed — release the claim within the 60s window so the
        // next cron run retries (L12-09).
        try {
          await db.rpc("fn_release_notification", {
            p_user_id: userId,
            p_rule: "onboarding_nudge",
            p_context_id: contextId,
            p_max_age_seconds: 60,
          });
        } catch {
          // non-fatal — at worst, this user waits until the next day bucket
        }
      }
    }

    return jsonOk(
      {
        evaluated: totalEvaluated,
        sent: totalSent,
        skipped_off_hour: totalSkippedOffHour,
      },
      requestId,
    );
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
