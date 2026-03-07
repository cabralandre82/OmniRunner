import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * generate-wrapped — Supabase Edge Function
 *
 * Generates a retrospective summary ("OmniWrapped") for a user's running data
 * over a specified period (month, quarter, or year).
 *
 * POST /generate-wrapped
 * Body: { period_type: 'month'|'quarter'|'year', period_key: '2026-02' }
 *
 * Returns cached data if available and fresh (< 24h). Otherwise recalculates.
 */

const FN = "generate-wrapped";

interface PeriodRange {
  startMs: number;
  endMs: number;
}

function parsePeriodRange(periodType: string, periodKey: string): PeriodRange {
  if (periodType === "month") {
    const [y, m] = periodKey.split("-").map(Number);
    const start = new Date(Date.UTC(y, m - 1, 1));
    const end = new Date(Date.UTC(y, m, 0, 23, 59, 59, 999));
    return { startMs: start.getTime(), endMs: end.getTime() };
  }

  if (periodType === "quarter") {
    const [y, qStr] = periodKey.split("-");
    const q = parseInt(qStr.replace("Q", ""), 10);
    const startMonth = (q - 1) * 3;
    const start = new Date(Date.UTC(parseInt(y), startMonth, 1));
    const end = new Date(Date.UTC(parseInt(y), startMonth + 3, 0, 23, 59, 59, 999));
    return { startMs: start.getTime(), endMs: end.getTime() };
  }

  if (periodType === "year") {
    const y = parseInt(periodKey, 10);
    const start = new Date(Date.UTC(y, 0, 1));
    const end = new Date(Date.UTC(y, 11, 31, 23, 59, 59, 999));
    return { startMs: start.getTime(), endMs: end.getTime() };
  }

  throw new Error(`Invalid period_type: ${periodType}`);
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["period_type", "period_key"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { period_type, period_key } = body;

    if (!["month", "quarter", "year"].includes(period_type)) {
      status = 400;
      return jsonErr(400, "INVALID_PERIOD", "period_type must be month, quarter, or year", requestId);
    }

    // Check cache (< 24h)
    const { data: cached } = await db
      .from("user_wrapped")
      .select("data, created_at_ms")
      .eq("user_id", user.id)
      .eq("period_type", period_type)
      .eq("period_key", period_key)
      .maybeSingle();

    const now = Date.now();
    if (cached && (now - cached.created_at_ms) < 86400000) {
      return jsonOk({ wrapped: cached.data, cached: true }, requestId);
    }

    // Parse period range
    let range: PeriodRange;
    try {
      range = parsePeriodRange(period_type, period_key);
    } catch {
      status = 400;
      return jsonErr(400, "INVALID_PERIOD_KEY", "Could not parse period_key", requestId);
    }

    // ── 1. Fetch sessions ─────────────────────────────────────────
    const { data: sessions } = await db
      .from("sessions")
      .select("start_time_ms, total_distance_m, moving_ms, avg_pace_sec_km, avg_bpm, is_verified")
      .eq("user_id", user.id)
      .eq("status", 3) // completed
      .eq("is_verified", true)
      .gte("start_time_ms", range.startMs)
      .lte("start_time_ms", range.endMs)
      .order("start_time_ms", { ascending: true });

    const runs = sessions ?? [];

    if (runs.length < 3) {
      return jsonOk({
        wrapped: null,
        reason: "insufficient_data",
        session_count: runs.length,
        min_required: 3,
      }, requestId);
    }

    // ── 2. Calculate running stats ────────────────────────────────
    let totalDistanceM = 0;
    let totalMovingMs = 0;
    let bestPaceSecKm: number | null = null;
    let longestRunM = 0;
    let totalBpmSum = 0;
    let bpmCount = 0;
    const dayOfWeekCounts = [0, 0, 0, 0, 0, 0, 0]; // Sun-Sat
    const hourCounts = new Array(24).fill(0);
    const paceByMonth: Record<string, number[]> = {};

    for (const s of runs) {
      totalDistanceM += s.total_distance_m ?? 0;
      totalMovingMs += s.moving_ms ?? 0;
      if (s.avg_pace_sec_km && (bestPaceSecKm === null || s.avg_pace_sec_km < bestPaceSecKm)) {
        bestPaceSecKm = s.avg_pace_sec_km;
      }
      if ((s.total_distance_m ?? 0) > longestRunM) {
        longestRunM = s.total_distance_m ?? 0;
      }
      if (s.avg_bpm) {
        totalBpmSum += s.avg_bpm;
        bpmCount++;
      }
      const dt = new Date(s.start_time_ms);
      dayOfWeekCounts[dt.getUTCDay()]++;
      hourCounts[dt.getUTCHours()]++;

      const monthKey = `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, "0")}`;
      if (s.avg_pace_sec_km) {
        if (!paceByMonth[monthKey]) paceByMonth[monthKey] = [];
        paceByMonth[monthKey].push(s.avg_pace_sec_km);
      }
    }

    const avgPaceSecKm = totalDistanceM > 0
      ? (totalMovingMs / 1000) / (totalDistanceM / 1000)
      : null;

    // Most active day of week
    const dayNames = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
    const mostActiveDayIdx = dayOfWeekCounts.indexOf(Math.max(...dayOfWeekCounts));
    const mostActiveDay = dayNames[mostActiveDayIdx];

    // Most active hour
    const mostActiveHour = hourCounts.indexOf(Math.max(...hourCounts));

    // Pace evolution by month (avg per month)
    const paceEvolution: { month: string; avgPace: number }[] = [];
    for (const [month, paces] of Object.entries(paceByMonth)) {
      const avg = paces.reduce((a, b) => a + b, 0) / paces.length;
      paceEvolution.push({ month, avgPace: Math.round(avg * 10) / 10 });
    }
    paceEvolution.sort((a, b) => a.month.localeCompare(b.month));

    // Pace improvement
    let paceImprovement: number | null = null;
    if (paceEvolution.length >= 2) {
      const first = paceEvolution[0].avgPace;
      const last = paceEvolution[paceEvolution.length - 1].avgPace;
      if (first > 0) {
        paceImprovement = Math.round(((first - last) / first) * 1000) / 10;
      }
    }

    // ── 3. Fetch challenges ───────────────────────────────────────
    const { data: challengeResults } = await db
      .from("challenge_results")
      .select("challenge_id, outcome, coins_earned")
      .eq("user_id", user.id)
      .gte("calculated_at_ms", range.startMs)
      .lte("calculated_at_ms", range.endMs);

    const results = challengeResults ?? [];
    const challengeStats = {
      total: results.length,
      wins: results.filter((r: { outcome: string }) => r.outcome === "won" || r.outcome === "completed_target").length,
      losses: results.filter((r: { outcome: string }) => r.outcome === "lost" || r.outcome === "did_not_finish").length,
      ties: results.filter((r: { outcome: string }) => r.outcome === "tied").length,
    };

    // ── 4. Fetch badges ───────────────────────────────────────────
    const { data: badges } = await db
      .from("badge_awards")
      .select("badge_id, awarded_at_ms")
      .eq("user_id", user.id)
      .gte("awarded_at_ms", range.startMs)
      .lte("awarded_at_ms", range.endMs);

    // ── 5. Fetch profile progress ─────────────────────────────────
    const { data: profile } = await db
      .from("profile_progress")
      .select("total_xp, daily_streak_count, streak_best, lifetime_session_count")
      .eq("user_id", user.id)
      .maybeSingle();

    // ── 6. Build wrapped data ─────────────────────────────────────
    const wrapped = {
      period_type,
      period_key,
      generated_at_ms: now,
      running: {
        total_sessions: runs.length,
        total_distance_km: Math.round((totalDistanceM / 1000) * 100) / 100,
        total_moving_min: Math.round(totalMovingMs / 60000),
        avg_pace_sec_km: avgPaceSecKm ? Math.round(avgPaceSecKm * 10) / 10 : null,
        best_pace_sec_km: bestPaceSecKm ? Math.round(bestPaceSecKm * 10) / 10 : null,
        longest_run_km: Math.round((longestRunM / 1000) * 100) / 100,
        avg_bpm: bpmCount > 0 ? Math.round(totalBpmSum / bpmCount) : null,
        pace_evolution: paceEvolution,
        pace_improvement_pct: paceImprovement,
      },
      patterns: {
        most_active_day: mostActiveDay,
        most_active_day_count: dayOfWeekCounts[mostActiveDayIdx],
        most_active_hour: mostActiveHour,
        most_active_hour_count: hourCounts[mostActiveHour],
        day_distribution: dayNames.map((name, i) => ({
          day: name,
          count: dayOfWeekCounts[i],
        })),
      },
      challenges: challengeStats,
      badges: {
        count: (badges ?? []).length,
        ids: (badges ?? []).map((b: { badge_id: string }) => b.badge_id),
      },
      progression: {
        total_xp: profile?.total_xp ?? 0,
        current_streak: profile?.daily_streak_count ?? 0,
        best_streak: profile?.streak_best ?? 0,
        lifetime_sessions: profile?.lifetime_session_count ?? 0,
      },
    };

    // ── 7. Cache result ───────────────────────────────────────────
    await db
      .from("user_wrapped")
      .upsert({
        user_id: user.id,
        period_type,
        period_key,
        data: wrapped,
        created_at_ms: now,
      }, { onConflict: "user_id,period_type,period_key" });

    return jsonOk({ wrapped, cached: false }, requestId);

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
