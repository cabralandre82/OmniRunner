import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * matchmake — Supabase Edge Function
 *
 * Queue-based matchmaking for 1v1 challenges. The user declares an intent
 * (metric, target, stake, duration) and the system either:
 *   1. Finds a compatible opponent → creates challenge → returns it
 *   2. No match → queues the user → returns queue entry
 *
 * Also supports:
 *   - GET  → current queue status for the user
 *   - POST { action: "cancel" } → cancel waiting entry
 *   - POST { action: "queue", ... } → enter queue / find match
 */

const FN = "matchmake";
const VALID_METRICS = ["distance", "pace", "time"];

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
    // ── Auth ──────────────────────────────────────────────────────────
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
      return rl.response!;
    }

    // ── GET: return current queue status ──────────────────────────────
    if (req.method === "GET") {
      const { data: entry } = await db
        .from("challenge_queue")
        .select("*")
        .eq("user_id", user.id)
        .in("status", ["waiting", "matched"])
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      let queuePosition: number | null = null;
      if (entry && entry.status === "waiting") {
        const { count } = await db
          .from("challenge_queue")
          .select("id", { count: "exact", head: true })
          .eq("status", "waiting")
          .eq("metric", entry.metric)
          .eq("skill_bracket", entry.skill_bracket)
          .lte("created_at", entry.created_at);
        queuePosition = count ?? null;
      }

      return jsonOk({ queue_entry: entry ?? null, queue_position: queuePosition }, requestId);
    }

    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use GET or POST", requestId);
    }

    // ── POST: parse body ─────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const action = body.action as string;

    // ── Cancel ───────────────────────────────────────────────────────
    if (action === "cancel") {
      const { data: cancelled, error: cancelErr } = await db
        .from("challenge_queue")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("user_id", user.id)
        .eq("status", "waiting")
        .select("id")
        .maybeSingle();

      if (cancelErr) {
        const c = classifyError(cancelErr);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }

      return jsonOk({
        status: cancelled ? "cancelled" : "no_active_entry",
        queue_id: cancelled?.id ?? null,
      }, requestId);
    }

    // ── Queue / Match ────────────────────────────────────────────────
    if (action !== "queue") {
      status = 400;
      return jsonErr(400, "INVALID_ACTION", 'action must be "queue" or "cancel"', requestId);
    }

    try {
      requireFields(body, ["metric", "window_ms"]);
    } catch (e) {
      status = 422;
      if (e instanceof ValidationError) {
        return jsonErr(422, e.code, e.message, requestId);
      }
      return jsonErr(422, "MISSING_FIELDS", "Missing fields", requestId);
    }

    const metric = body.metric as string;
    const target = body.target as number | null ?? null;
    const entryFeeCoins = (body.entry_fee_coins as number) ?? 0;
    const windowMs = body.window_ms as number;

    if (!VALID_METRICS.includes(metric)) {
      status = 400;
      return jsonErr(400, "INVALID_METRIC", `metric must be: ${VALID_METRICS.join(", ")}`, requestId);
    }
    if (windowMs <= 0) {
      status = 400;
      return jsonErr(400, "INVALID_WINDOW", "window_ms must be positive", requestId);
    }

    // ── Assessoria gate: matchmaking requires group membership ────────
    const { data: memberRow } = await db
      .from("coaching_members")
      .select("id")
      .eq("user_id", user.id)
      .limit(1)
      .maybeSingle();

    if (!memberRow) {
      status = 403;
      errorCode = "NO_ASSESSORIA";
      return jsonErr(
        403, "NO_ASSESSORIA",
        "Você precisa estar em uma assessoria para buscar oponentes. Peça o código de convite ao seu professor.",
        requestId,
      );
    }

    // Monetization gate: stake > 0 requires VERIFIED
    if (entryFeeCoins > 0) {
      const { data: verified, error: vErr } = await db
        .rpc("is_user_verified", { p_user_id: user.id });

      if (vErr || verified !== true) {
        status = 403;
        errorCode = "ATHLETE_NOT_VERIFIED";
        return jsonErr(403, "ATHLETE_NOT_VERIFIED",
          "Apenas atletas verificados podem participar de desafios com stake > 0.",
          requestId);
      }
    }

    // Compute skill bracket
    const { data: bracket } = await db
      .rpc("fn_compute_skill_bracket", { p_user_id: user.id });
    const skillBracket = (bracket as string) ?? "beginner";

    // Get user display name
    const { data: profile } = await db
      .from("profiles")
      .select("display_name")
      .eq("id", user.id)
      .single();
    const displayName = (profile?.display_name as string) ?? "Atleta";

    // ── Try atomic match ─────────────────────────────────────────────
    const { data: matchRows, error: matchErr } = await db.rpc("fn_try_match", {
      p_user_id: user.id,
      p_metric: metric,
      p_target: target,
      p_entry_fee_coins: entryFeeCoins,
      p_window_ms: windowMs,
      p_skill_bracket: skillBracket,
    });

    if (matchErr) {
      console.error(JSON.stringify({
        request_id: requestId, fn: FN, event: "match_rpc_error",
        detail: matchErr.message,
      }));
    }

    const match = Array.isArray(matchRows) && matchRows.length > 0
      ? matchRows[0]
      : null;

    if (match) {
      // ── MATCH FOUND: create challenge ──────────────────────────────
      const challengeId = crypto.randomUUID();
      const nowMs = Date.now();
      const finalTarget = target ?? match.matched_target ?? null;
      const finalWindowMs = Math.max(windowMs, match.matched_window_ms ?? windowMs);

      // Get opponent display name
      const { data: oppProfile } = await db
        .from("profiles")
        .select("display_name")
        .eq("id", match.matched_user_id)
        .single();
      const oppName = (oppProfile?.display_name as string) ?? "Atleta";

      // Create challenge
      const { error: chErr } = await db.from("challenges").insert({
        id: challengeId,
        creator_user_id: user.id,
        status: "pending",
        type: "one_vs_one",
        title: `Matchmaking: ${displayName} vs ${oppName}`,
        metric,
        target: finalTarget,
        window_ms: finalWindowMs,
        start_mode: "on_accept",
        entry_fee_coins: entryFeeCoins,
        min_session_distance_m: 1000,
        anti_cheat_policy: "standard",
        created_at_ms: nowMs,
      });

      if (chErr) {
        const c = classifyError(chErr);
        status = c.httpStatus;
        errorCode = c.code;
        return jsonErr(c.httpStatus, c.code, c.message, requestId);
      }

      // Add both participants
      const { error: p1Err } = await db.from("challenge_participants").insert([
        {
          challenge_id: challengeId,
          user_id: user.id,
          display_name: displayName,
          status: "accepted",
          responded_at_ms: nowMs,
        },
        {
          challenge_id: challengeId,
          user_id: match.matched_user_id,
          display_name: oppName,
          status: "accepted",
          responded_at_ms: nowMs,
        },
      ]);

      if (p1Err) {
        console.error(JSON.stringify({
          request_id: requestId, fn: FN, event: "participant_insert_error",
          detail: p1Err.message,
        }));
      }

      // Update the queuer's matched entry with challenge ID
      await db.from("challenge_queue")
        .update({
          matched_challenge_id: challengeId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", match.queue_id);

      // Insert queue entry for current user (already matched)
      await db.from("challenge_queue").insert({
        user_id: user.id,
        metric,
        target,
        entry_fee_coins: entryFeeCoins,
        window_ms: windowMs,
        skill_bracket: skillBracket,
        status: "matched",
        matched_with_user_id: match.matched_user_id,
        matched_challenge_id: challengeId,
        matched_at: new Date().toISOString(),
      });

      console.log(JSON.stringify({
        request_id: requestId, fn: FN, event: "match_created",
        challenge_id: challengeId,
        user_a: user.id,
        user_b: match.matched_user_id,
        skill_a: skillBracket,
        metric,
        entry_fee_coins: entryFeeCoins,
      }));

      return jsonOk({
        status: "matched",
        challenge_id: challengeId,
        opponent: {
          user_id: match.matched_user_id,
          display_name: oppName,
        },
        skill_bracket: skillBracket,
      }, requestId);
    }

    // ── NO MATCH: queue the user ─────────────────────────────────────

    // Cancel any existing waiting entry first
    await db.from("challenge_queue")
      .update({ status: "cancelled", updated_at: new Date().toISOString() })
      .eq("user_id", user.id)
      .eq("status", "waiting");

    const { data: queued, error: qErr } = await db.from("challenge_queue")
      .insert({
        user_id: user.id,
        metric,
        target,
        entry_fee_coins: entryFeeCoins,
        window_ms: windowMs,
        skill_bracket: skillBracket,
        status: "waiting",
      })
      .select("id, expires_at, skill_bracket")
      .single();

    if (qErr) {
      const c = classifyError(qErr);
      status = c.httpStatus;
      errorCode = c.code;
      return jsonErr(c.httpStatus, c.code, c.message, requestId);
    }

    console.log(JSON.stringify({
      request_id: requestId, fn: FN, event: "queued",
      queue_id: queued.id,
      user_id: user.id,
      metric,
      skill_bracket: skillBracket,
      entry_fee_coins: entryFeeCoins,
    }));

    return jsonOk({
      status: "queued",
      queue_id: queued.id,
      expires_at: queued.expires_at,
      skill_bracket: queued.skill_bracket,
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
