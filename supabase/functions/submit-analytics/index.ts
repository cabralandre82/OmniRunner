import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";

// ═════════════════════════════════════════════════════════════════════════════
// Types
// ═════════════════════════════════════════════════════════════════════════════

interface SubmitPayload {
  session_id: string;
  user_id: string;
  group_id: string;
  start_time_ms: number;
  end_time_ms: number;
  distance_m: number;
  moving_ms: number;
  avg_pace_sec_per_km?: number;
  avg_bpm?: number;
}

interface SessionRow {
  session_id: string;
  distance_m: number;
  moving_ms: number;
  avg_pace_sec_per_km: number | null;
  avg_bpm: number | null;
  start_time_ms: number;
  end_time_ms: number;
}

interface MemberRow {
  user_id: string;
  display_name: string;
  role: string;
}

// 6 evolution metrics
const METRICS = [
  "avg_pace",
  "avg_distance",
  "weekly_volume",
  "weekly_frequency",
  "avg_heart_rate",
  "avg_moving_time",
] as const;

type Metric = (typeof METRICS)[number];

const PERIODS = ["weekly", "monthly"] as const;
type Period = (typeof PERIODS)[number];

type Direction = "improving" | "stable" | "declining" | "insufficient";

// Insight types from insight_type_enum.dart
type InsightType =
  | "performance_decline"
  | "performance_improvement"
  | "consistency_drop"
  | "inactivity_warning"
  | "overtraining_risk"
  | "group_trend_summary";

type InsightPriority = "low" | "medium" | "high" | "critical";

// ═════════════════════════════════════════════════════════════════════════════
// Configuration
// ═════════════════════════════════════════════════════════════════════════════

const BASELINE_WINDOW_WEEKS = 4;
const MIN_BASELINE_SAMPLES = 3;
const STABLE_THRESHOLD_PCT = 5.0;
const SIGNIFICANT_DROP_PCT = 15.0;
const MIN_DATA_POINTS = 2;
const INACTIVITY_DAYS = 7;
const OVERTRAINING_VOLUME_PCT = 50.0;
const CONSISTENCY_DROP_PCT = 40.0;
const MS_PER_DAY = 86_400_000;
const MS_PER_WEEK = 7 * MS_PER_DAY;

const MAX_DISTANCE_M = 200_000;      // 200 km
const MIN_MOVING_MS = 60_000;         // 1 min
const MAX_MOVING_MS = 86_400_000;     // 24 h
const MIN_PACE_SEC_KM = 90;           // 1:30/km (world-class sprint)
const MAX_PACE_SEC_KM = 1_800;        // 30:00/km (slow walk)
const MIN_BPM = 30;
const MAX_BPM = 230;
const MAX_SUBMISSIONS_PER_DAY = 10;
const INSIGHT_DEDUP_WINDOW_MS = 7 * MS_PER_DAY;

// ═════════════════════════════════════════════════════════════════════════════
// Main handler
// ═════════════════════════════════════════════════════════════════════════════

// ── Handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  const FN = "submit-analytics";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
  if (req.method !== "POST") {
    status = 405;
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
  }

  // ── 1. Authenticate ────────────────────────────────────────────────
  let user: { id: string; [key: string]: unknown };
  // deno-lint-ignore no-explicit-any
  let adminDb: any;
  try {
    const auth = await requireUser(req);
    user = auth.user;
    adminDb = auth.db;
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

  // ── 1b. Rate limit ──────────────────────────────────────────────
  const rl = await checkRateLimit(adminDb, user.id, { fn: FN, maxRequests: 120, windowSeconds: 60 }, requestId);
  if (!rl.allowed) {
    status = rl.status!;
    if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
    return rl.response!;
  }

  // ── 2. Parse body ──────────────────────────────────────────────────
  // deno-lint-ignore no-explicit-any
  let rawBody: Record<string, any> = {};
  try {
    rawBody = await requireJson(req);
  } catch (e) {
    status = 400;
    if (e instanceof ValidationError) {
      return jsonErr(400, e.code, e.message, requestId);
    }
    return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
  }

  // ── 2b. Require event_name ────────────────────────────────────────
  try {
    requireFields(rawBody, ["event_name"]);
  } catch (e) {
    status = 422;
    if (e instanceof ValidationError) {
      return jsonErr(422, e.code, e.message, requestId);
    }
    return jsonErr(422, "MISSING_FIELDS", "Missing required fields", requestId);
  }

  const body = rawBody as Partial<SubmitPayload> & { event_name: string };

  // ── 5. Ping mode: body missing session fields ─────────────────────
  if (!body.session_id || !body.user_id || !body.group_id) {
    return jsonOk({
      status: "ok",
      note: "auth_ok_no_payload",
      auth_user_id: user.id,
    }, requestId);
  }

  // From here on, body has all required fields
  const fullBody = body as SubmitPayload;

  // V1 — auth.uid() == user_id
  if (user.id !== fullBody.user_id) {
    status = 403;
    return jsonErr(403, "FORBIDDEN", "user_id mismatch", requestId);
  }

  // V2 — membership
  const { data: membership } = await adminDb
    .from("coaching_members")
    .select("user_id, role")
    .eq("group_id", fullBody.group_id)
    .eq("user_id", fullBody.user_id)
    .maybeSingle();

  if (!membership) {
    status = 403;
    return jsonErr(403, "NOT_GROUP_MEMBER", "Atleta nao e membro ativo do grupo.", requestId);
  }

  // V3 — valid data (server-side bounds check)
  if (fullBody.distance_m <= 0 || fullBody.distance_m > MAX_DISTANCE_M) {
    status = 422;
    return jsonErr(422, "INVALID_SESSION_DATA", `distance_m must be 0 < d <= ${MAX_DISTANCE_M}`, requestId);
  }
  if (fullBody.moving_ms < MIN_MOVING_MS || fullBody.moving_ms > MAX_MOVING_MS) {
    status = 422;
    return jsonErr(422, "INVALID_SESSION_DATA", `moving_ms must be ${MIN_MOVING_MS} <= t <= ${MAX_MOVING_MS}`, requestId);
  }
  if (fullBody.start_time_ms >= fullBody.end_time_ms) {
    status = 422;
    return jsonErr(422, "INVALID_SESSION_DATA", "start_time_ms must be < end_time_ms", requestId);
  }
  if (fullBody.avg_pace_sec_per_km != null && (fullBody.avg_pace_sec_per_km < MIN_PACE_SEC_KM || fullBody.avg_pace_sec_per_km > MAX_PACE_SEC_KM)) {
    status = 422;
    return jsonErr(422, "INVALID_SESSION_DATA", `avg_pace_sec_per_km must be ${MIN_PACE_SEC_KM} <= p <= ${MAX_PACE_SEC_KM}`, requestId);
  }
  if (fullBody.avg_bpm != null && (fullBody.avg_bpm < MIN_BPM || fullBody.avg_bpm > MAX_BPM)) {
    status = 422;
    return jsonErr(422, "INVALID_SESSION_DATA", `avg_bpm must be ${MIN_BPM} <= h <= ${MAX_BPM}`, requestId);
  }

  // V4 — rate limiting (max submissions per user per day)
  const dayAgo = new Date(Date.now() - MS_PER_DAY).toISOString();
  const { count: todayCount } = await adminDb
    .from("analytics_submissions")
    .select("*", { count: "exact", head: true })
    .eq("user_id", fullBody.user_id)
    .gte("processed_at", dayAgo);

  if ((todayCount ?? 0) >= MAX_SUBMISSIONS_PER_DAY) {
    status = 429;
    return jsonErr(429, "RATE_LIMITED", `Max ${MAX_SUBMISSIONS_PER_DAY} submissions per day`, requestId);
  }

  // V5 — idempotency
  const { data: existing } = await adminDb
    .from("analytics_submissions")
    .select("session_id")
    .eq("session_id", fullBody.session_id)
    .maybeSingle();

  if (existing) {
    return jsonOk({ status: "already_processed", session_id: fullBody.session_id }, requestId);
  }

  // ── Insert submission record ──
  await adminDb.from("analytics_submissions").insert({
    session_id: fullBody.session_id,
    user_id: fullBody.user_id,
    group_id: fullBody.group_id,
    distance_m: fullBody.distance_m,
    moving_ms: fullBody.moving_ms,
    avg_pace_sec_per_km: fullBody.avg_pace_sec_per_km ?? null,
    avg_bpm: fullBody.avg_bpm ?? null,
    is_verified: true,
    start_time_ms: fullBody.start_time_ms,
    end_time_ms: fullBody.end_time_ms,
  });

  const nowMs = Date.now();

  // ── Fetch session history (last 4 weeks) ──
  const windowStartMs = nowMs - BASELINE_WINDOW_WEEKS * MS_PER_WEEK;
  const { data: sessions } = await adminDb
    .from("analytics_submissions")
    .select("session_id, distance_m, moving_ms, avg_pace_sec_per_km, avg_bpm, start_time_ms, end_time_ms")
    .eq("user_id", fullBody.user_id)
    .eq("group_id", fullBody.group_id)
    .gte("start_time_ms", windowStartMs)
    .order("start_time_ms", { ascending: true });

  const history: SessionRow[] = sessions ?? [];

  // ── 1. Compute baselines (batch upsert) ──
  const baselines = computeBaselines(fullBody.user_id, fullBody.group_id, history, windowStartMs, nowMs);
  if (baselines.length > 0) {
    await adminDb.from("athlete_baselines").upsert(baselines, { onConflict: "user_id,group_id,metric" });
  }
  const baselinesUpdated = baselines.length;

  // ── 2. Compute trends (weekly + monthly) ──
  const baselineMap = new Map(baselines.map((b) => [b.metric, b]));
  const allTrends: Record<string, unknown>[] = [];

  for (const period of PERIODS) {
    const periodData = buildPeriodData(history, period);
    for (const metric of METRICS) {
      const bl = baselineMap.get(metric);
      const trend = analyzeTrend(
        fullBody.user_id, fullBody.group_id, metric, period,
        bl, periodData.get(metric) ?? [], nowMs
      );
      allTrends.push(trend);
    }
  }

  if (allTrends.length > 0) {
    await adminDb.from("athlete_trends").upsert(allTrends, { onConflict: "user_id,group_id,metric,period" });
  }
  const trendsUpdated = allTrends.length;

  // ── 3. Generate insights (parallel fetches, scoped where possible) ──
  const [
    { data: groupMembers },
    { data: allGroupTrends },
    { data: allGroupBaselines },
    { data: allGroupSessions },
    { data: recentInsights },
  ] = await Promise.all([
    adminDb.from("coaching_members")
      .select("user_id, display_name, role")
      .eq("group_id", fullBody.group_id)
      .limit(200),
    adminDb.from("athlete_trends")
      .select("*")
      .eq("group_id", fullBody.group_id)
      .limit(500),
    adminDb.from("athlete_baselines")
      .select("*")
      .eq("group_id", fullBody.group_id)
      .limit(500),
    adminDb.from("analytics_submissions")
      .select("user_id, distance_m, start_time_ms")
      .eq("group_id", fullBody.group_id)
      .gte("start_time_ms", nowMs - 14 * MS_PER_DAY)
      .limit(1000),
    adminDb.from("coach_insights")
      .select("target_user_id, type")
      .eq("group_id", fullBody.group_id)
      .eq("dismissed", false)
      .gte("created_at_ms", nowMs - INSIGHT_DEDUP_WINDOW_MS)
      .limit(500),
  ]);

  const insights = generateInsights(
    fullBody.group_id,
    (groupMembers ?? []) as MemberRow[],
    allGroupTrends ?? [],
    allGroupBaselines ?? [],
    allGroupSessions ?? [],
    nowMs,
    recentInsights ?? [],
  );

  if (insights.length > 0) {
    await adminDb.from("coach_insights").insert(insights);
  }
  const insightsGenerated = insights.length;

  return jsonOk({
    status: "ok",
    baselines_updated: baselinesUpdated,
    trends_updated: trendsUpdated,
    insights_generated: insightsGenerated,
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

// ═════════════════════════════════════════════════════════════════════════════
// Baseline Calculator (mirrors Dart BaselineCalculator)
// ═════════════════════════════════════════════════════════════════════════════

function computeBaselines(
  userId: string,
  groupId: string,
  sessions: SessionRow[],
  windowStartMs: number,
  nowMs: number,
): Record<string, unknown>[] {
  const weeks = Math.max(1, (nowMs - windowStartMs) / MS_PER_WEEK);

  return METRICS.map((metric) => ({
    user_id: userId,
    group_id: groupId,
    metric,
    value: computeMetric(metric, sessions, weeks),
    sample_size: sampleSize(metric, sessions),
    window_start_ms: windowStartMs,
    window_end_ms: nowMs,
    computed_at_ms: nowMs,
  }));
}

function computeMetric(metric: Metric, sessions: SessionRow[], weeks: number): number {
  if (sessions.length === 0) return 0;

  switch (metric) {
    case "avg_pace": {
      const paces = sessions
        .map((s) => s.avg_pace_sec_per_km)
        .filter((p): p is number => p != null && p > 0);
      return paces.length === 0 ? 0 : mean(paces);
    }
    case "avg_distance":
      return mean(sessions.map((s) => s.distance_m));
    case "weekly_volume":
      return sessions.reduce((sum, s) => sum + s.distance_m, 0) / weeks;
    case "weekly_frequency":
      return sessions.length / weeks;
    case "avg_heart_rate": {
      const hrs = sessions
        .map((s) => s.avg_bpm)
        .filter((h): h is number => h != null && h > 0);
      return hrs.length === 0 ? 0 : mean(hrs);
    }
    case "avg_moving_time":
      return mean(sessions.map((s) => s.moving_ms));
  }
}

function sampleSize(metric: Metric, sessions: SessionRow[]): number {
  switch (metric) {
    case "avg_pace":
      return sessions.filter((s) => s.avg_pace_sec_per_km != null && s.avg_pace_sec_per_km > 0).length;
    case "avg_heart_rate":
      return sessions.filter((s) => s.avg_bpm != null && s.avg_bpm > 0).length;
    default:
      return sessions.length;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Evolution Analyzer (mirrors Dart EvolutionAnalyzer)
// ═════════════════════════════════════════════════════════════════════════════

interface PeriodBucket {
  key: string;
  sessions: SessionRow[];
}

function buildPeriodData(
  sessions: SessionRow[],
  period: Period,
): Map<Metric, { key: string; value: number }[]> {
  const buckets = new Map<string, SessionRow[]>();

  for (const s of sessions) {
    const key = period === "weekly" ? isoWeek(s.start_time_ms) : isoMonth(s.start_time_ms);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key)!.push(s);
  }

  const sortedKeys = [...buckets.keys()].sort();
  const result = new Map<Metric, { key: string; value: number }[]>();

  for (const metric of METRICS) {
    const points: { key: string; value: number }[] = [];
    for (const key of sortedKeys) {
      const bSessions = buckets.get(key)!;
      const val = computeMetric(metric, bSessions, 1);
      points.push({ key, value: val });
    }
    result.set(metric, points);
  }
  return result;
}

function analyzeTrend(
  userId: string,
  groupId: string,
  metric: Metric,
  period: Period,
  baseline: Record<string, unknown> | undefined,
  periodPoints: { key: string; value: number }[],
  nowMs: number,
): Record<string, unknown> {
  const blValue = (baseline?.value as number) ?? 0;
  const blReliable = (baseline?.sample_size as number ?? 0) >= MIN_BASELINE_SAMPLES;

  if (periodPoints.length < MIN_DATA_POINTS || !blReliable || blValue === 0) {
    return {
      user_id: userId,
      group_id: groupId,
      metric,
      period,
      direction: "insufficient",
      current_value: periodPoints.length > 0 ? periodPoints[periodPoints.length - 1].value : 0,
      baseline_value: blValue,
      change_percent: 0,
      data_points: periodPoints.length,
      latest_period_key: periodPoints.length > 0 ? periodPoints[periodPoints.length - 1].key : "",
      analyzed_at_ms: nowMs,
    };
  }

  const current = periodPoints[periodPoints.length - 1].value;
  const changePct = ((current - blValue) / blValue) * 100;
  const direction = resolveDirection(metric, changePct);

  return {
    user_id: userId,
    group_id: groupId,
    metric,
    period,
    direction,
    current_value: current,
    baseline_value: blValue,
    change_percent: Math.round(changePct * 100) / 100,
    data_points: periodPoints.length,
    latest_period_key: periodPoints[periodPoints.length - 1].key,
    analyzed_at_ms: nowMs,
  };
}

function resolveDirection(metric: Metric, changePct: number): Direction {
  const abs = Math.abs(changePct);
  if (abs <= STABLE_THRESHOLD_PCT) return "stable";
  const lowerBetter = metric === "avg_pace";
  if (lowerBetter) return changePct < 0 ? "improving" : "declining";
  return changePct > 0 ? "improving" : "declining";
}

// ═════════════════════════════════════════════════════════════════════════════
// Insight Generator (mirrors Dart InsightGenerator)
// ═════════════════════════════════════════════════════════════════════════════

function generateInsights(
  groupId: string,
  members: MemberRow[],
  trends: Record<string, unknown>[],
  baselines: Record<string, unknown>[],
  recentSessions: { user_id: string; distance_m: number; start_time_ms: number }[],
  nowMs: number,
  existingInsights: { target_user_id: string | null; type: string }[],
): Record<string, unknown>[] {
  const insights: Record<string, unknown>[] = [];
  const memberMap = new Map(members.map((m) => [m.user_id, m]));

  const existingKeys = new Set(
    existingInsights.map((i) => `${i.target_user_id ?? ""}::${i.type}`),
  );
  const isDuplicate = (userId: string | null, type: string) =>
    existingKeys.has(`${userId ?? ""}::${type}`);

  // Build baselines map: userId → metric → baseline
  const blByUser = new Map<string, Map<string, Record<string, unknown>>>();
  for (const b of baselines) {
    const uid = b.user_id as string;
    if (!blByUser.has(uid)) blByUser.set(uid, new Map());
    blByUser.get(uid)!.set(b.metric as string, b);
  }

  // Build activity summaries
  const sevenDaysAgo = nowMs - 7 * MS_PER_DAY;
  const activityByUser = new Map<string, { lastMs: number; sessions7d: number; dist7d: number }>();
  for (const m of members) {
    activityByUser.set(m.user_id, { lastMs: 0, sessions7d: 0, dist7d: 0 });
  }
  for (const s of recentSessions) {
    const a = activityByUser.get(s.user_id);
    if (!a) continue;
    if (s.start_time_ms > a.lastMs) a.lastMs = s.start_time_ms;
    if (s.start_time_ms >= sevenDaysAgo) {
      a.sessions7d++;
      a.dist7d += s.distance_m;
    }
  }

  // Group trends by user
  const trendsByUser = new Map<string, Record<string, unknown>[]>();
  for (const t of trends) {
    const uid = t.user_id as string;
    if (!trendsByUser.has(uid)) trendsByUser.set(uid, []);
    trendsByUser.get(uid)!.push(t);
  }

  // ── Evolution insights (per athlete, most significant metric) ──
  for (const [uid, userTrends] of trendsByUser) {
    const name = memberMap.get(uid)?.display_name ?? uid;

    const improving = userTrends
      .filter((t) => t.direction === "improving" && (t.data_points as number) >= 2)
      .sort((a, b) => Math.abs(b.change_percent as number) - Math.abs(a.change_percent as number));

    const declining = userTrends
      .filter((t) => t.direction === "declining" && (t.data_points as number) >= 2)
      .sort((a, b) => Math.abs(b.change_percent as number) - Math.abs(a.change_percent as number));

    if (improving.length > 0 && !isDuplicate(uid, "performance_improvement")) {
      const best = improving[0];
      insights.push(makeInsight(groupId, uid, name, "performance_improvement", "medium",
        `${name} evoluindo em ${metricLabel(best.metric as Metric)}`,
        `${metricLabel(best.metric as Metric)} melhorou ${Math.abs(best.change_percent as number).toFixed(1)}% em relação ao baseline.`,
        best.metric as string, best.current_value as number, best.change_percent as number, nowMs));
    }

    if (declining.length > 0 && !isDuplicate(uid, "performance_decline")) {
      const worst = declining[0];
      insights.push(makeInsight(groupId, uid, name, "performance_decline", "high",
        `${name} em queda em ${metricLabel(worst.metric as Metric)}`,
        `${metricLabel(worst.metric as Metric)} caiu ${Math.abs(worst.change_percent as number).toFixed(1)}% em relação ao baseline.`,
        worst.metric as string, worst.current_value as number, worst.change_percent as number, nowMs));
    }
  }

  // ── Inactivity ──
  for (const [uid, activity] of activityByUser) {
    const name = memberMap.get(uid)?.display_name ?? uid;
    if (activity.lastMs <= 0 && !isDuplicate(uid, "inactivity_warning")) {
      insights.push(makeInsight(groupId, uid, name, "inactivity_warning", "high",
        `${name} sem sessões registradas`,
        `Nenhuma sessão encontrada para este atleta.`,
        null, null, null, nowMs));
      continue;
    }
    const elapsed = nowMs - activity.lastMs;
    if (elapsed >= INACTIVITY_DAYS * MS_PER_DAY && !isDuplicate(uid, "inactivity_warning")) {
      const days = Math.floor(elapsed / MS_PER_DAY);
      const priority: InsightPriority = days >= INACTIVITY_DAYS * 2 ? "critical" : "high";
      insights.push(makeInsight(groupId, uid, name, "inactivity_warning", priority,
        `${name} inativo há ${days} dias`,
        `Última sessão registrada há ${days} dias.`,
        null, null, null, nowMs));
    }
  }

  // ── Weekly patterns ──
  for (const [uid, activity] of activityByUser) {
    const name = memberMap.get(uid)?.display_name ?? uid;
    const userBl = blByUser.get(uid);
    if (!userBl) continue;

    const freqBl = userBl.get("weekly_frequency");
    if (freqBl && (freqBl.sample_size as number) >= MIN_BASELINE_SAMPLES && (freqBl.value as number) > 0) {
      const blVal = freqBl.value as number;
      const dropPct = ((blVal - activity.sessions7d) / blVal) * 100;
      if (dropPct >= CONSISTENCY_DROP_PCT && !isDuplicate(uid, "consistency_drop")) {
        insights.push(makeInsight(groupId, uid, name, "consistency_drop", "medium",
          `${name} reduziu frequência`,
          `${activity.sessions7d} sessão(ões) na última semana vs ${blVal.toFixed(1)} sessões/semana no baseline (−${dropPct.toFixed(0)}%).`,
          "weekly_frequency", activity.sessions7d, -dropPct, nowMs));
      }
    }

    const volBl = userBl.get("weekly_volume");
    if (volBl && (volBl.sample_size as number) >= MIN_BASELINE_SAMPLES && (volBl.value as number) > 0) {
      const blVal = volBl.value as number;
      const spikePct = ((activity.dist7d - blVal) / blVal) * 100;
      if (spikePct >= OVERTRAINING_VOLUME_PCT && !isDuplicate(uid, "overtraining_risk")) {
        const curKm = (activity.dist7d / 1000).toFixed(1);
        const blKm = (blVal / 1000).toFixed(1);
        insights.push(makeInsight(groupId, uid, name, "overtraining_risk", "critical",
          `${name} com volume excessivo`,
          `${curKm} km na semana vs baseline de ${blKm} km (+${spikePct.toFixed(0)}%). Risco de lesão.`,
          "weekly_volume", activity.dist7d, spikePct, nowMs));
      }
    }
  }

  // ── Group trend summary ──
  const directionPerUser = new Map<string, Direction>();
  for (const t of trends) {
    const uid = t.user_id as string;
    const dir = t.direction as Direction;
    const existing = directionPerUser.get(uid);
    if (!existing || dirRank(dir) > dirRank(existing)) {
      directionPerUser.set(uid, dir);
    }
  }

  let imp = 0, stab = 0, dec = 0, insuf = 0;
  for (const dir of directionPerUser.values()) {
    if (dir === "improving") imp++;
    else if (dir === "stable") stab++;
    else if (dir === "declining") dec++;
    else insuf++;
  }

  const total = directionPerUser.size;
  if (total > 0 && !isDuplicate(null, "group_trend_summary")) {
    const parts: string[] = [];
    if (imp > 0) parts.push(`${imp} evoluindo`);
    if (stab > 0) parts.push(`${stab} estáveis`);
    if (dec > 0) parts.push(`${dec} em queda`);
    if (insuf > 0) parts.push(`${insuf} com dados insuficientes`);

    insights.push({
      group_id: groupId,
      target_user_id: null,
      target_display_name: null,
      type: "group_trend_summary",
      priority: dec > total / 2 ? "high" : "low",
      title: "Resumo do grupo",
      message: `${total} atletas: ${parts.join(", ")}.`,
      metric: null,
      reference_value: null,
      change_percent: null,
      related_entity_id: null,
      created_at_ms: nowMs,
      read_at_ms: null,
      dismissed: false,
    });
  }

  return insights;
}

// ═════════════════════════════════════════════════════════════════════════════
// Helpers
// ═════════════════════════════════════════════════════════════════════════════

function makeInsight(
  groupId: string, userId: string, displayName: string,
  type: InsightType, priority: InsightPriority,
  title: string, message: string,
  metric: string | null, refValue: number | null, changePct: number | null,
  nowMs: number,
): Record<string, unknown> {
  return {
    group_id: groupId,
    target_user_id: userId,
    target_display_name: displayName,
    type, priority, title, message,
    metric,
    reference_value: refValue,
    change_percent: changePct != null ? Math.round(changePct * 100) / 100 : null,
    related_entity_id: null,
    created_at_ms: nowMs,
    read_at_ms: null,
    dismissed: false,
  };
}

function mean(arr: number[]): number {
  if (arr.length === 0) return 0;
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

function dirRank(d: Direction): number {
  switch (d) {
    case "declining": return 3;
    case "improving": return 2;
    case "stable": return 1;
    case "insufficient": return 0;
  }
}

function metricLabel(m: Metric): string {
  switch (m) {
    case "avg_pace": return "pace médio";
    case "avg_distance": return "distância média";
    case "weekly_volume": return "volume semanal";
    case "weekly_frequency": return "frequência semanal";
    case "avg_heart_rate": return "FC média";
    case "avg_moving_time": return "tempo médio";
  }
}

function isoWeek(ms: number): string {
  const d = new Date(ms);
  const dayNum = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const weekNo = Math.ceil(((d.getTime() - yearStart.getTime()) / MS_PER_DAY + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(weekNo).padStart(2, "0")}`;
}

function isoMonth(ms: number): string {
  const d = new Date(ms);
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

