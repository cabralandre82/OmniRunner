import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";

/**
 * evaluate-badges — Supabase Edge Function
 *
 * Server-side badge evaluation after a verified session is synced.
 * Prevents client-side badge manipulation by running criteria checks
 * on the backend with authoritative data.
 *
 * Also credits XP + Coins via profile_progress, wallets, and ledger.
 *
 * Runs with service_role key (bypasses RLS).
 *
 * POST /evaluate-badges
 * Body: { user_id: string, session_id: string }
 */

interface BadgeRow {
  id: string;
  name: string;
  category: string;
  tier: string;
  xp_reward: number;
  coins_reward: number;
  criteria_type: string;
  criteria_json: Record<string, unknown>;
  season_id: string | null;
}

interface SessionRow {
  id: string;
  user_id: string;
  total_distance_m: number;
  start_time_ms: number;
  end_time_ms: number;
  moving_ms: number;
  avg_pace_sec_km: number | null;
  is_verified: boolean;
  avg_bpm: number | null;
}

interface ProfileProgress {
  total_xp: number;
  lifetime_session_count: number;
  lifetime_distance_m: number;
  lifetime_moving_ms: number;
  daily_streak_count: number;
  streak_best: number;
}

// ── Handler ──────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  const FN = "evaluate-badges";
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
  if (req.method !== "POST") {
    status = 405;
    return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
  }

  // ── 1. Authenticate ────────────────────────────────────────────────
  let authUser: { id: string; [key: string]: unknown };
  // deno-lint-ignore no-explicit-any
  let db: any;
  try {
    const auth = await requireUser(req);
    authUser = auth.user;
    db = auth.db;
    userId = authUser.id;
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
  const rl = await checkRateLimit(db, authUser.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
  if (!rl.allowed) {
    status = rl.status!;
    if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
    return rl.response!;
  }

  // ── 2. Parse body ──────────────────────────────────────────────────
  let body: { user_id?: string; session_id?: string } = {};
  try {
    body = await requireJson(req) as typeof body;
  } catch (e) {
    status = 400;
    if (e instanceof ValidationError) {
      return jsonErr(400, e.code, e.message, requestId);
    }
    return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
  }

  // ── 2b. Require user_id ───────────────────────────────────────────
  try {
    requireFields(body as Record<string, unknown>, ["user_id"]);
  } catch (e) {
    status = 422;
    if (e instanceof ValidationError) {
      return jsonErr(422, e.code, e.message, requestId);
    }
    return jsonErr(422, "MISSING_FIELDS", "Missing required fields", requestId);
  }

  // ── 3. Ping mode: user_id present but session_id missing ──────────
  if (!body.session_id) {
    return jsonOk({
      status: "ok",
      note: "auth_ok_no_payload",
      auth_user_id: authUser.id,
    }, requestId);
  }

  // user_id validated in 2b; session_id guaranteed present after ping-mode guard

  const { user_id, session_id } = body as { user_id: string; session_id: string };

  // Compute current ISO week start (Monday) for weekly_distance criteria
  const nowDate = new Date();
  const dayOfWeek = nowDate.getUTCDay();
  const mondayOffset = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
  const weekStartDate = new Date(Date.UTC(
    nowDate.getUTCFullYear(),
    nowDate.getUTCMonth(),
    nowDate.getUTCDate() - mondayOffset,
  ));
  const weekStartStr = weekStartDate.toISOString().slice(0, 10);

  // Fetch session, progress, existing awards, badge catalog, and extra context in parallel
  const [
    sessionRes, progressRes, awardsRes, badgesRes,
    challengeResultsRes, challengeWinsRes, champCompletedRes,
    weeklyProgressRes, bestPaceRes,
  ] = await Promise.all([
    db.from("sessions").select("*").eq("id", session_id).eq("user_id", user_id).single(),
    db.from("profile_progress").select("*").eq("user_id", user_id).single(),
    db.from("badge_awards").select("badge_id").eq("user_id", user_id),
    db.from("badges").select("*"),
    db.from("challenge_results")
      .select("challenge_id, outcome")
      .eq("user_id", user_id)
      .in("outcome", ["won", "completed_target", "participated"]),
    db.from("challenge_results")
      .select("challenge_id")
      .eq("user_id", user_id)
      .eq("outcome", "won"),
    db.from("championship_participants")
      .select("championship_id")
      .eq("user_id", user_id)
      .eq("status", "completed"),
    db.from("v_weekly_progress")
      .select("total_distance_m")
      .eq("user_id", user_id)
      .eq("week_start", weekStartStr)
      .limit(1),
    db.from("sessions")
      .select("avg_pace_sec_km")
      .eq("user_id", user_id)
      .eq("is_verified", true)
      .gt("total_distance_m", 1000)
      .not("avg_pace_sec_km", "is", null)
      .order("avg_pace_sec_km", { ascending: true })
      .limit(1),
  ]);

  if (sessionRes.error || !sessionRes.data) {
    status = 404;
    return jsonErr(404, "NOT_FOUND", "Session not found", requestId);
  }

  const session = sessionRes.data as SessionRow;
  if (!session.is_verified) {
    return jsonOk({ status: "skipped", reason: "session_not_verified" }, requestId);
  }

  const progress = (progressRes.data ?? {
    total_xp: 0, lifetime_session_count: 0,
    lifetime_distance_m: 0, lifetime_moving_ms: 0,
    daily_streak_count: 0, streak_best: 0,
  }) as ProfileProgress;

  const alreadyAwarded = new Set((awardsRes.data ?? []).map((a: { badge_id: string }) => a.badge_id));
  const allBadges = (badgesRes.data ?? []) as BadgeRow[];
  const completedChallenges = (challengeResultsRes.data ?? []).length;
  const challengeWins = (challengeWinsRes.data ?? []).length;
  const champCompleted = (champCompletedRes.data ?? []).length;
  const weeklyDistanceM = (weeklyProgressRes.data?.[0]?.total_distance_m as number) ?? 0;
  const previousBestPace = (bestPaceRes.data?.[0]?.avg_pace_sec_km as number) ?? null;

  const nowMs = Date.now();
  const newAwards: Record<string, unknown>[] = [];
  const ledgerEntries: Record<string, unknown>[] = [];
  const xpEntries: Record<string, unknown>[] = [];
  let totalXpAwarded = 0;
  let totalCoinsAwarded = 0;

  // Session metrics
  const distM = session.total_distance_m;
  const durationMs = (session.end_time_ms ?? nowMs) - session.start_time_ms;
  const movingMs = session.moving_ms ?? durationMs;
  const paceSecKm = distM > 0 ? (movingMs / 1000) / (distM / 1000) : null;
  const sessionHour = new Date(session.start_time_ms).getUTCHours();

  // Aggregated stats (including this session)
  const lifetimeDist = progress.lifetime_distance_m + distM;
  const lifetimeSessions = progress.lifetime_session_count + 1;
  const lifetimeMovingMs = progress.lifetime_moving_ms + movingMs;

  for (const badge of allBadges) {
    if (alreadyAwarded.has(badge.id)) continue;

    const met = evaluateCriteria(
      badge.criteria_type,
      badge.criteria_json,
      {
        distM, durationMs, movingMs, paceSecKm, sessionHour,
        lifetimeDist, lifetimeSessions, lifetimeMovingMs,
        dailyStreak: Math.max(progress.daily_streak_count, progress.streak_best),
        completedChallenges,
        avgBpm: session.avg_bpm,
        challengeWins,
        champCompleted,
        weeklyDistanceM: weeklyDistanceM + distM,
        previousBestPace,
      },
    );

    if (!met) continue;

    newAwards.push({
      user_id,
      badge_id: badge.id,
      trigger_session_id: session_id,
      unlocked_at_ms: nowMs,
      xp_awarded: badge.xp_reward,
      coins_awarded: badge.coins_reward,
    });

    if (badge.xp_reward > 0) {
      xpEntries.push({
        user_id,
        xp: badge.xp_reward,
        source: "badge",
        ref_id: badge.id,
        created_at_ms: nowMs,
      });
      totalXpAwarded += badge.xp_reward;
    }

    if (badge.coins_reward > 0) {
      ledgerEntries.push({
        user_id,
        delta_coins: badge.coins_reward,
        reason: "badge_reward",
        ref_id: badge.id,
        created_at_ms: nowMs,
      });
      totalCoinsAwarded += badge.coins_reward;
    }
  }

  // Batch writes
  if (newAwards.length > 0) {
    await db.from("badge_awards").insert(newAwards);
  }
  if (xpEntries.length > 0) {
    await db.from("xp_transactions").insert(xpEntries);
  }
  if (ledgerEntries.length > 0) {
    await db.from("coin_ledger").insert(ledgerEntries);
  }
  if (totalXpAwarded > 0) {
    await db.rpc("increment_profile_progress", {
      p_user_id: user_id,
      p_xp: totalXpAwarded,
      p_distance_m: 0,
      p_moving_ms: 0,
    });
  }
  if (totalCoinsAwarded > 0) {
    await db.rpc("increment_wallet_balance", {
      p_user_id: user_id,
      p_delta: totalCoinsAwarded,
    });
  }

  // Push notifications for newly earned badges
  if (newAwards.length > 0) {
    try {
      const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
      const svcUrl = Deno.env.get("SUPABASE_URL");
      if (svcKey && svcUrl) {
        for (const award of newAwards) {
          const badgeDef = allBadges.find((b) => b.id === award.badge_id);
          fetch(`${svcUrl}/functions/v1/notify-rules`, {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${svcKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              rule: "badge_earned",
              context: {
                user_id: user_id,
                badge_id: award.badge_id,
                badge_name: badgeDef?.name ?? award.badge_id,
              },
            }),
          }).catch(() => {});
        }
      }
    } catch { /* fire-and-forget */ }
  }

  return jsonOk({
    status: "ok",
    badges_unlocked: newAwards.length,
    badge_ids: newAwards.map((a) => a.badge_id),
    xp_awarded: totalXpAwarded,
    coins_awarded: totalCoinsAwarded,
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

interface EvalContext {
  distM: number;
  durationMs: number;
  movingMs: number;
  paceSecKm: number | null;
  sessionHour: number;
  lifetimeDist: number;
  lifetimeSessions: number;
  lifetimeMovingMs: number;
  dailyStreak: number;
  completedChallenges: number;
  avgBpm: number | null;
  challengeWins: number;
  champCompleted: number;
  weeklyDistanceM: number;
  previousBestPace: number | null;
}

function evaluateCriteria(
  type: string,
  params: Record<string, unknown>,
  ctx: EvalContext,
): boolean {
  switch (type) {
    case "single_session_distance":
      return ctx.distM >= (params.threshold_m as number);

    case "lifetime_distance":
      return ctx.lifetimeDist >= (params.threshold_m as number);

    case "session_count":
      return ctx.lifetimeSessions >= (params.count as number);

    case "pace_below": {
      const maxPace = params.max_pace_sec_per_km as number;
      const minDist = (params.min_distance_m as number) ?? 5000;
      return ctx.paceSecKm != null && ctx.paceSecKm < maxPace && ctx.distM >= minDist;
    }

    case "personal_record_pace": {
      const minDistPr = (params.min_distance_m as number) ?? 1000;
      if (ctx.paceSecKm == null || ctx.distM < minDistPr) return false;
      if (ctx.previousBestPace == null) return true;
      return ctx.paceSecKm < ctx.previousBestPace;
    }

    case "single_session_duration":
      return ctx.movingMs >= (params.threshold_ms as number);

    case "lifetime_duration":
      return ctx.lifetimeMovingMs >= (params.threshold_ms as number);

    case "daily_streak":
      return ctx.dailyStreak >= (params.days as number);

    case "weekly_distance":
      return ctx.weeklyDistanceM >= (params.threshold_m as number);

    case "challenges_completed":
      return ctx.completedChallenges >= (params.count as number);

    case "challenge_won":
      return ctx.challengeWins >= (params.count as number);

    case "championship_completed":
      return ctx.champCompleted >= (params.count as number);

    case "session_before_hour":
      return ctx.sessionHour < (params.hour_local as number);

    case "session_after_hour":
      return ctx.sessionHour >= (params.hour_local as number);

    case "consecutive_wins":
    case "group_leader":
      return false;

    default:
      return false;
  }
}

