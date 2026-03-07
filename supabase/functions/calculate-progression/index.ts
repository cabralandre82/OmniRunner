import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * calculate-progression — Supabase Edge Function
 *
 * Idempotent per-run progression calculator.
 * Receives a session_id, validates the run, and awards XP, updates streak,
 * and checks weekly goal progress. Uses fn_mark_progression_applied for
 * atomic idempotency (prevents double XP).
 *
 * XP sources (from DECISAO 044 §2.1):
 *   - Base: 20 XP for any verified session >= 200m
 *   - Distance bonus: floor(distKm * 10), cap 500
 *   - Duration bonus: floor(durMin / 5) * 2, cap 120
 *   - HR bonus: 10 if avgBpm != null
 *   - Daily session cap: 1000 XP from sessions
 *   - Daily session count cap: 10 sessions/day
 *
 * POST /calculate-progression
 * Headers: Authorization: Bearer <jwt>
 * Body: { session_id }
 */

const FN = "calculate-progression";
const SESSION_XP_DAILY_CAP = 1000;
const SESSION_COUNT_DAILY_CAP = 10;
const DIST_BONUS_CAP = 500;
const DUR_BONUS_CAP = 120;
const MIN_DISTANCE_M = 200;

// ── XP Calculation ──────────────────────────────────────────────────────

interface SessionData {
  total_distance_m: number;
  moving_ms: number;
  avg_bpm: number | null;
  start_time_ms: number;
}

function computeSessionXp(s: SessionData): {
  base: number;
  distBonus: number;
  durBonus: number;
  hrBonus: number;
  total: number;
} {
  if (s.total_distance_m < MIN_DISTANCE_M) {
    return { base: 0, distBonus: 0, durBonus: 0, hrBonus: 0, total: 0 };
  }

  const base = 20;
  const distKm = s.total_distance_m / 1000;
  const distBonus = Math.min(Math.floor(distKm * 10), DIST_BONUS_CAP);
  const durMin = (s.moving_ms ?? 0) / 1000 / 60;
  const durBonus = Math.min(Math.floor(durMin / 5) * 2, DUR_BONUS_CAP);
  const hrBonus = s.avg_bpm != null ? 10 : 0;

  return {
    base,
    distBonus,
    durBonus,
    hrBonus,
    total: base + distBonus + durBonus + hrBonus,
  };
}

// ── Handler ─────────────────────────────────────────────────────────────

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

    // ── 1. Authenticate ──────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    try {
      const auth = await requireUser(req);
      userId = auth.user.id;
      db = auth.db;
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
    const rl = await checkRateLimit(db, userId, {
      fn: FN,
      maxRequests: 30,
      windowSeconds: 60,
    }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse & validate input ───────────────────────────────────
    let body: Record<string, unknown>;
    try {
      body = await requireJson(req);
      requireFields(body, ["session_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const sessionId = String(body.session_id);

    // ── 3. Atomic mark + fetch (idempotency) ────────────────────────
    const { data: markRows, error: markErr } = await db.rpc(
      "fn_mark_progression_applied",
      { p_session_id: sessionId, p_user_id: userId },
    );

    if (markErr) {
      const c = classifyError(markErr);
      status = c.httpStatus;
      errorCode = c.code;
      return jsonErr(c.httpStatus, c.code, c.message, requestId);
    }

    if (!markRows || markRows.length === 0) {
      status = 404;
      return jsonErr(404, "SESSION_NOT_FOUND",
        "Session not found, not verified, or not owned by you", requestId);
    }

    const row = markRows[0];

    if (row.was_already_applied && row.is_verified) {
      return jsonOk({
        status: "already_applied",
        session_id: sessionId,
        note: "Progression was already calculated for this run",
      }, requestId);
    }

    if (row.was_already_applied && !row.is_verified) {
      return jsonOk({
        status: "not_verified",
        session_id: sessionId,
        xp_awarded: 0,
        note: "Session is not verified — no XP awarded",
      }, requestId);
    }

    // ── 4. Daily caps check ─────────────────────────────────────────
    const { data: dailyCount, error: dcErr } = await db.rpc(
      "fn_count_daily_sessions",
      { p_user_id: userId },
    );

    if (dcErr) {
      const c = classifyError(dcErr);
      status = c.httpStatus;
      errorCode = c.code;
      return jsonErr(c.httpStatus, c.code, c.message, requestId);
    }

    if (typeof dailyCount === "number" && dailyCount > SESSION_COUNT_DAILY_CAP) {
      return jsonOk({
        status: "daily_cap_reached",
        session_id: sessionId,
        daily_sessions: dailyCount,
        cap: SESSION_COUNT_DAILY_CAP,
        xp_awarded: 0,
        note: "Daily session cap reached — no XP awarded",
      }, requestId);
    }

    const { data: dailyXp, error: dxErr } = await db.rpc(
      "fn_get_daily_session_xp",
      { p_user_id: userId },
    );

    if (dxErr) {
      const c = classifyError(dxErr);
      status = c.httpStatus;
      errorCode = c.code;
      return jsonErr(c.httpStatus, c.code, c.message, requestId);
    }

    const currentDailyXp = typeof dailyXp === "number" ? dailyXp : 0;

    // ── 5. Compute XP ───────────────────────────────────────────────
    const session: SessionData = {
      total_distance_m: row.total_distance_m ?? 0,
      moving_ms: row.moving_ms ?? 0,
      avg_bpm: row.avg_bpm ?? null,
      start_time_ms: row.start_time_ms ?? 0,
    };

    const xpBreakdown = computeSessionXp(session);
    const remaining = Math.max(0, SESSION_XP_DAILY_CAP - currentDailyXp);
    const xpAwarded = Math.min(xpBreakdown.total, remaining);
    const capped = xpAwarded < xpBreakdown.total;

    // ── 6. Record XP transaction ────────────────────────────────────
    if (xpAwarded > 0) {
      const nowMs = Date.now();
      const { error: xpErr } = await db.from("xp_transactions").insert({
        user_id: userId,
        xp: xpAwarded,
        source: "session",
        ref_id: sessionId,
        created_at_ms: nowMs,
      });

      if (xpErr) {
        const c = classifyError(xpErr);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }

      // ── 7. Update profile_progress (XP + level + stats) ──────────
      const { error: progErr } = await db.rpc("increment_profile_progress", {
        p_user_id: userId,
        p_xp: xpAwarded,
        p_distance_m: session.total_distance_m,
        p_moving_ms: session.moving_ms,
      });

      if (progErr) {
        const c = classifyError(progErr);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }
    }

    // ── 8. Update streak ────────────────────────────────────────────
    let streakResult: {
      streak_current: number;
      streak_best: number;
      freeze_used: boolean;
    } | null = null;

    const { data: streakRows, error: streakErr } = await db.rpc(
      "fn_update_streak",
      { p_user_id: userId, p_session_day_ms: session.start_time_ms },
    );

    if (streakErr) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        error_code: "STREAK_ERROR",
        detail: streakErr.message,
      }));
    } else if (streakRows && streakRows.length > 0) {
      streakResult = streakRows[0];
    }

    // ── 9. Check weekly goal ────────────────────────────────────────
    let goalResult: Record<string, unknown> | null = null;

    const { data: goalData, error: goalErr } = await db.rpc(
      "fn_check_weekly_goal",
      { p_user_id: userId },
    );

    if (goalErr) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        error_code: "GOAL_CHECK_ERROR",
        detail: goalErr.message,
      }));
    } else if (goalData) {
      goalResult = goalData;

      // If goal was just completed, award the goal XP too
      if (goalData.status === "completed" && goalData.xp_awarded > 0) {
        const goalXp = goalData.xp_awarded as number;
        const goalNowMs = Date.now();

        await db.from("xp_transactions").insert({
          user_id: userId,
          xp: goalXp,
          source: "mission",
          ref_id: goalData.goal_id,
          created_at_ms: goalNowMs,
        });

        await db.rpc("increment_profile_progress", {
          p_user_id: userId,
          p_xp: goalXp,
          p_distance_m: 0,
          p_moving_ms: 0,
        });
      }
    }

    // ── 10. Fetch updated level for response ────────────────────────
    let newLevel: number | null = null;
    let xpToNext: number | null = null;

    const { data: progRow } = await db
      .from("profile_progress")
      .select("level, total_xp")
      .eq("user_id", userId)
      .single();

    if (progRow) {
      newLevel = progRow.level;
      const nextLevelXp = Math.floor(
        100 * Math.pow((progRow.level + 1), 1.5),
      );
      xpToNext = Math.max(0, nextLevelXp - progRow.total_xp);
    }

    // ── 11. Build response ──────────────────────────────────────────
    return jsonOk({
      status: "ok",
      session_id: sessionId,
      xp: {
        breakdown: xpBreakdown,
        awarded: xpAwarded,
        capped,
        daily_total: currentDailyXp + xpAwarded,
        daily_cap: SESSION_XP_DAILY_CAP,
      },
      level: newLevel,
      xp_to_next_level: xpToNext,
      streak: streakResult,
      weekly_goal: goalResult,
    }, requestId);
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    console.error(JSON.stringify({
      request_id: requestId,
      fn: FN,
      user_id: userId,
      error_code: "UNHANDLED",
      detail: err instanceof Error ? err.message : String(err),
    }));
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        error_code: errorCode,
        duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        status,
        duration_ms: elapsed(),
      });
    }
  }
});
