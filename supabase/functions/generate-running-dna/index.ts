import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * generate-running-dna — Supabase Edge Function
 *
 * Calculates a 6-axis radar profile ("Running DNA") from the user's
 * last 6 months of verified sessions. Generates natural-language
 * insights and PR predictions via simple linear regression.
 *
 * POST /generate-running-dna
 * Body: {} (empty — uses caller's own data)
 *
 * Cache: 7 days in `running_dna` table.
 */

const FN = "generate-running-dna";
const CACHE_TTL_MS = 7 * 86400000;
const MIN_SESSIONS = 10;
const SIX_MONTHS_MS = 180 * 86400000;

function clamp(v: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, v));
}

// Simple linear regression: y = a*x + b
function linearRegression(points: { x: number; y: number }[]): {
  slope: number;
  intercept: number;
  r2: number;
} {
  const n = points.length;
  if (n < 2) return { slope: 0, intercept: 0, r2: 0 };

  let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
  for (const p of points) {
    sumX += p.x;
    sumY += p.y;
    sumXY += p.x * p.y;
    sumX2 += p.x * p.x;
    sumY2 += p.y * p.y;
  }

  const denom = n * sumX2 - sumX * sumX;
  if (denom === 0) return { slope: 0, intercept: sumY / n, r2: 0 };

  const slope = (n * sumXY - sumX * sumY) / denom;
  const intercept = (sumY - slope * sumX) / n;

  const ssRes = points.reduce((s, p) => s + (p.y - (slope * p.x + intercept)) ** 2, 0);
  const yMean = sumY / n;
  const ssTot = points.reduce((s, p) => s + (p.y - yMean) ** 2, 0);
  const r2 = ssTot > 0 ? 1 - ssRes / ssTot : 0;

  return { slope, intercept, r2 };
}

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 5, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      return rl.response!;
    }

    // Check cache
    const now = Date.now();
    const { data: cached } = await db
      .from("running_dna")
      .select("radar_scores, insights, pr_predictions, stats, updated_at_ms")
      .eq("user_id", user.id)
      .maybeSingle();

    if (cached && (now - cached.updated_at_ms) < CACHE_TTL_MS) {
      return jsonOk({
        dna: {
          radar_scores: cached.radar_scores,
          insights: cached.insights,
          pr_predictions: cached.pr_predictions,
          stats: cached.stats,
        },
        cached: true,
      }, requestId);
    }

    // ── 1. Fetch sessions (last 6 months) ─────────────────────────
    const cutoff = now - SIX_MONTHS_MS;

    const { data: sessions } = await db
      .from("sessions")
      .select("start_time_ms, total_distance_m, moving_ms, avg_pace_sec_km, avg_bpm")
      .eq("user_id", user.id)
      .eq("status", 3) // completed
      .eq("is_verified", true)
      .gte("start_time_ms", cutoff)
      .order("start_time_ms", { ascending: true });

    const runs = sessions ?? [];

    if (runs.length < MIN_SESSIONS) {
      return jsonOk({
        dna: null,
        reason: "insufficient_data",
        session_count: runs.length,
        min_required: MIN_SESSIONS,
      }, requestId);
    }

    // ── 2. Calculate radar axes ───────────────────────────────────

    // Last 30 days for "current" metrics
    const thirtyDaysAgo = now - 30 * 86400000;
    const recentRuns = runs.filter((s: { start_time_ms: number }) => s.start_time_ms >= thirtyDaysAgo);

    // VELOCIDADE (0-100): avg pace last month, 4:00/km=100, 8:00/km=0
    let speedScore = 50;
    if (recentRuns.length > 0) {
      const avgPace = recentRuns.reduce(
        (s: number, r: { avg_pace_sec_km: number | null }) => s + (r.avg_pace_sec_km ?? 480), 0
      ) / recentRuns.length;
      speedScore = clamp(Math.round(100 - ((avgPace - 240) / (480 - 240)) * 100), 0, 100);
    }

    // RESISTÊNCIA (0-100): avg distance last month, >15km=100, <2km=0
    let enduranceScore = 50;
    if (recentRuns.length > 0) {
      const avgDistKm = recentRuns.reduce(
        (s: number, r: { total_distance_m: number | null }) => s + ((r.total_distance_m ?? 0) / 1000), 0
      ) / recentRuns.length;
      enduranceScore = clamp(Math.round(((avgDistKm - 2) / (15 - 2)) * 100), 0, 100);
    }

    // CONSISTÊNCIA (0-100): sessions/week last month, >=6=100, <1=0
    let consistencyScore = 50;
    if (recentRuns.length > 0) {
      const weeksSpan = Math.max(1, (now - thirtyDaysAgo) / (7 * 86400000));
      const sessionsPerWeek = recentRuns.length / weeksSpan;
      consistencyScore = clamp(Math.round((sessionsPerWeek / 6) * 100), 0, 100);
    }

    // EVOLUÇÃO (0-100): pace improvement trend over 3 months
    const threeMonthsAgo = now - 90 * 86400000;
    const threeMonthRuns = runs.filter((s: { start_time_ms: number }) => s.start_time_ms >= threeMonthsAgo);

    let evolutionScore = 50;
    if (threeMonthRuns.length >= 5) {
      // Group by month, get avg pace per month
      const monthBuckets: Record<string, number[]> = {};
      for (const s of threeMonthRuns) {
        if (!s.avg_pace_sec_km) continue;
        const dt = new Date(s.start_time_ms);
        const key = `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, "0")}`;
        if (!monthBuckets[key]) monthBuckets[key] = [];
        monthBuckets[key].push(s.avg_pace_sec_km);
      }

      const monthPaces = Object.entries(monthBuckets)
        .map(([month, paces]) => ({
          month,
          avgPace: paces.reduce((a, b) => a + b, 0) / paces.length,
        }))
        .sort((a, b) => a.month.localeCompare(b.month));

      if (monthPaces.length >= 2) {
        const first = monthPaces[0].avgPace;
        const last = monthPaces[monthPaces.length - 1].avgPace;
        const pctChange = first > 0 ? ((first - last) / first) * 100 : 0;
        // >2%/month improvement=100, stable=50, worsening=0
        evolutionScore = clamp(Math.round(50 + pctChange * 25), 0, 100);
      }
    }

    // VERSATILIDADE (0-100): variety of distances
    let versatilityScore = 50;
    if (recentRuns.length >= 3) {
      const distances = recentRuns.map(
        (r: { total_distance_m: number | null }) => (r.total_distance_m ?? 0) / 1000
      );
      const mean = distances.reduce((a: number, b: number) => a + b, 0) / distances.length;
      const variance = distances.reduce(
        (s: number, d: number) => s + (d - mean) ** 2, 0
      ) / distances.length;
      const stddev = Math.sqrt(variance);
      // High stddev (>4km) = 100, low (<0.5km) = 0
      versatilityScore = clamp(Math.round((stddev / 4) * 100), 0, 100);
    }

    // COMPETITIVIDADE (0-100): win rate in challenges
    let competitivenessScore = 50;
    {
      const { data: results } = await db
        .from("challenge_results")
        .select("outcome")
        .eq("user_id", user.id)
        .gte("calculated_at_ms", threeMonthsAgo);

      const allResults = results ?? [];
      if (allResults.length >= 3) {
        const wins = allResults.filter(
          (r: { outcome: string }) => r.outcome === "won" || r.outcome === "completed_target"
        ).length;
        competitivenessScore = clamp(Math.round((wins / allResults.length) * 100), 0, 100);
      }
    }

    const radarScores = {
      speed: speedScore,
      endurance: enduranceScore,
      consistency: consistencyScore,
      evolution: evolutionScore,
      versatility: versatilityScore,
      competitiveness: competitivenessScore,
    };

    // ── 3. Generate insights ──────────────────────────────────────

    const insights: string[] = [];

    // Day-of-week pattern
    const dayOfWeekCounts = [0, 0, 0, 0, 0, 0, 0];
    const hourCounts = new Array(24).fill(0);
    for (const s of runs) {
      const dt = new Date(s.start_time_ms);
      dayOfWeekCounts[dt.getUTCDay()]++;
      hourCounts[dt.getUTCHours()]++;
    }
    const dayNames = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
    const topDay = dayOfWeekCounts.indexOf(Math.max(...dayOfWeekCounts));
    const topDayPct = Math.round((dayOfWeekCounts[topDay] / runs.length) * 100);
    insights.push(`Você corre mais às ${dayNames[topDay]}s (${topDayPct}% das corridas)`);

    // Hour pattern
    const topHour = hourCounts.indexOf(Math.max(...hourCounts));
    const topHourPct = Math.round((hourCounts[topHour] / runs.length) * 100);
    const periodLabel = topHour < 6 ? "madrugador" : topHour < 12 ? "matutino" : topHour < 18 ? "vespertino" : "noturno";
    insights.push(`Corredor ${periodLabel}: ${topHourPct}% das corridas entre ${topHour}h e ${topHour + 1}h`);

    // Distance comfort zone
    const allDistKm = runs.map((r: { total_distance_m: number | null }) => (r.total_distance_m ?? 0) / 1000);
    const medianDist = allDistKm.sort((a: number, b: number) => a - b)[Math.floor(allDistKm.length / 2)];
    if (medianDist < 7) {
      insights.push(`Sua zona de conforto é ${medianDist.toFixed(0)}-${(medianDist + 2).toFixed(0)} km. Considere treinos de ${(medianDist + 5).toFixed(0)} km+ para evoluir`);
    } else {
      insights.push(`Boa variedade de distância! Mediana de ${medianDist.toFixed(1)} km por corrida`);
    }

    // Pace after rest
    if (runs.length >= 10) {
      const paceAfterRest: number[] = [];
      const paceNoRest: number[] = [];
      for (let i = 1; i < runs.length; i++) {
        if (!runs[i].avg_pace_sec_km) continue;
        const gapDays = (runs[i].start_time_ms - runs[i - 1].start_time_ms) / 86400000;
        if (gapDays >= 2) {
          paceAfterRest.push(runs[i].avg_pace_sec_km);
        } else {
          paceNoRest.push(runs[i].avg_pace_sec_km);
        }
      }
      if (paceAfterRest.length >= 3 && paceNoRest.length >= 3) {
        const avgRest = paceAfterRest.reduce((a, b) => a + b, 0) / paceAfterRest.length;
        const avgNoRest = paceNoRest.reduce((a, b) => a + b, 0) / paceNoRest.length;
        const diff = ((avgNoRest - avgRest) / avgNoRest) * 100;
        if (diff > 2) {
          insights.push(`Seu pace melhora ${diff.toFixed(0)}% após 2+ dias de descanso`);
        }
      }
    }

    // Strongest/weakest axis
    const axes = Object.entries(radarScores) as [string, number][];
    axes.sort((a, b) => b[1] - a[1]);
    const axisLabels: Record<string, string> = {
      speed: "Velocidade",
      endurance: "Resistência",
      consistency: "Consistência",
      evolution: "Evolução",
      versatility: "Versatilidade",
      competitiveness: "Competitividade",
    };
    insights.push(`Seu ponto forte é ${axisLabels[axes[0][0]]} (${axes[0][1]}/100)`);
    insights.push(`Área para crescer: ${axisLabels[axes[axes.length - 1][0]]} (${axes[axes.length - 1][1]}/100)`);

    // ── 4. PR predictions ─────────────────────────────────────────

    interface PrPrediction {
      distance_label: string;
      current_best_pace: number;
      predicted_pace: number | null;
      weeks_to_pr: number | null;
      confidence: number;
    }

    const prPredictions: PrPrediction[] = [];

    const distanceBands = [
      { label: "5K", minM: 4500, maxM: 5500 },
      { label: "10K", minM: 9000, maxM: 11000 },
      { label: "Meia", minM: 20000, maxM: 22000 },
    ];

    for (const band of distanceBands) {
      const bandRuns = runs.filter(
        (r: { total_distance_m: number | null; avg_pace_sec_km: number | null }) =>
          (r.total_distance_m ?? 0) >= band.minM &&
          (r.total_distance_m ?? 0) <= band.maxM &&
          r.avg_pace_sec_km != null
      );

      if (bandRuns.length < 4) continue;

      // Group by month, take best pace per month
      const monthBest: Record<string, number> = {};
      for (const r of bandRuns) {
        const dt = new Date(r.start_time_ms);
        const key = `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, "0")}`;
        const pace = r.avg_pace_sec_km as number;
        if (!monthBest[key] || pace < monthBest[key]) {
          monthBest[key] = pace;
        }
      }

      const monthEntries = Object.entries(monthBest).sort((a, b) => a[0].localeCompare(b[0]));
      if (monthEntries.length < 2) continue;

      const points = monthEntries.map(([, pace], i) => ({ x: i, y: pace }));
      const reg = linearRegression(points);

      const currentBest = Math.min(...bandRuns.map((r: { avg_pace_sec_km: number }) => r.avg_pace_sec_km));

      let predictedPace: number | null = null;
      let weeksToPr: number | null = null;

      if (reg.r2 >= 0.3 && reg.slope < 0) {
        // Negative slope = improving
        const nextMonthPace = reg.slope * monthEntries.length + reg.intercept;
        predictedPace = Math.round(nextMonthPace * 10) / 10;

        if (predictedPace < currentBest) {
          const monthsToReach = (currentBest - reg.intercept) / reg.slope - (monthEntries.length - 1);
          weeksToPr = Math.max(1, Math.round(monthsToReach * 4.33));
        }
      }

      prPredictions.push({
        distance_label: band.label,
        current_best_pace: Math.round(currentBest * 10) / 10,
        predicted_pace: predictedPace,
        weeks_to_pr: weeksToPr,
        confidence: Math.round(reg.r2 * 100),
      });
    }

    // ── 5. Extra stats ────────────────────────────────────────────

    const totalKm = runs.reduce(
      (s: number, r: { total_distance_m: number | null }) => s + ((r.total_distance_m ?? 0) / 1000), 0
    );
    const totalMovingMin = runs.reduce(
      (s: number, r: { moving_ms: number | null }) => s + ((r.moving_ms ?? 0) / 60000), 0
    );

    const stats = {
      sessions_analyzed: runs.length,
      period_days: 180,
      total_km: Math.round(totalKm * 100) / 100,
      total_moving_min: Math.round(totalMovingMin),
      avg_sessions_per_week: Math.round((runs.length / 26) * 10) / 10,
    };

    // ── 6. Cache result ───────────────────────────────────────────

    const dna = {
      radar_scores: radarScores,
      insights,
      pr_predictions: prPredictions.length > 0 ? prPredictions : null,
      stats,
    };

    await db
      .from("running_dna")
      .upsert({
        user_id: user.id,
        radar_scores: radarScores,
        insights,
        pr_predictions: prPredictions.length > 0 ? prPredictions : null,
        stats,
        updated_at_ms: now,
      }, { onConflict: "user_id" });

    return jsonOk({ dna, cached: false }, requestId);

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
