import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * challenge-list-mine — Supabase Edge Function
 *
 * Returns all challenges where the authenticated user is a participant,
 * with full participant lists and team info. Used by the client to sync
 * remote state into the local Isar database.
 *
 * POST /challenge-list-mine
 * Body: {} (no params needed)
 */

const FN = "challenge-list-mine";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 30, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // 1. Find all challenge IDs where user is a participant
    const { data: myParts, error: partErr } = await db
      .from("challenge_participants")
      .select("challenge_id")
      .eq("user_id", user.id);

    if (partErr) {
      const classified = classifyError(partErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    const challengeIds = (myParts ?? []).map((p: { challenge_id: string }) => p.challenge_id);

    if (challengeIds.length === 0) {
      return jsonOk({ challenges: [], count: 0 }, requestId);
    }

    // 2. Fetch all those challenges
    const { data: challenges, error: chErr } = await db
      .from("challenges")
      .select("*")
      .in("id", challengeIds)
      .order("created_at_ms", { ascending: false })
      .limit(200);

    if (chErr) {
      const classified = classifyError(chErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // 3. Fetch all participants for those challenges
    const { data: allParts, error: allPartErr } = await db
      .from("challenge_participants")
      .select("challenge_id, user_id, display_name, status, progress_value, responded_at_ms, group_id, team")
      .in("challenge_id", challengeIds)
      .order("responded_at_ms", { ascending: true, nullsFirst: false });

    if (allPartErr) {
      const classified = classifyError(allPartErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // 4. Group participants by challenge_id
    // deno-lint-ignore no-explicit-any
    const partsByChallenge: Record<string, any[]> = {};
    for (const p of (allParts ?? [])) {
      if (!partsByChallenge[p.challenge_id]) {
        partsByChallenge[p.challenge_id] = [];
      }
      partsByChallenge[p.challenge_id].push(p);
    }

    // 5. Assemble response
    // deno-lint-ignore no-explicit-any
    const enriched = (challenges ?? []).map((c: any) => ({
      id: c.id,
      creator_user_id: c.creator_user_id,
      status: c.status,
      type: c.type,
      title: c.title,
      goal: c.goal ?? c.metric,
      target: c.target,
      window_ms: c.window_ms,
      start_mode: c.start_mode,
      fixed_start_ms: c.fixed_start_ms,
      entry_fee_coins: c.entry_fee_coins,
      min_session_distance_m: c.min_session_distance_m,
      anti_cheat_policy: c.anti_cheat_policy,
      created_at_ms: c.created_at_ms,
      starts_at_ms: c.starts_at_ms,
      ends_at_ms: c.ends_at_ms,
      participants: partsByChallenge[c.id] ?? [],
    }));

    return jsonOk({ challenges: enriched, count: enriched.length }, requestId);
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
