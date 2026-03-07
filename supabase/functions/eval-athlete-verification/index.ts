import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * eval-athlete-verification — Supabase Edge Function
 *
 * Evaluates the calling user's athlete verification status based on their
 * session history. Idempotent: running N times with the same session data
 * produces the same result.
 *
 * CRITICAL SECURITY:
 *   - user_id is ALWAYS taken from the JWT (auth.uid), NEVER from the client.
 *   - No admin override, no manual set, no backdoor.
 *   - stake=0 always allowed; stake>0 requires VERIFIED.
 *
 * POST /eval-athlete-verification
 * Headers: Authorization: Bearer <jwt>
 * Body: {} (empty or omitted — no client input needed)
 *
 * Returns: {
 *   ok: true,
 *   verification_status, trust_score, checklist: { ... },
 *   counts: { ... }, thresholds: { ... }
 * }
 *
 * Error codes:
 *   AUTH_ERROR                — JWT missing or invalid
 *   VERIFICATION_EVAL_FAILED — RPC call failed
 *   SESSION_DATA_MISSING     — User has no verification record (auto-created)
 */

const FN = "eval-athlete-verification";

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

    // ── 1. Authenticate — user_id comes from JWT, NEVER from client ────
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

    // ── 2. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(
      db, user.id,
      { fn: FN, maxRequests: 10, windowSeconds: 60 },
      requestId,
    );
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 3. Run evaluation RPC (SECURITY DEFINER — server-side only) ────
    const { error: evalErr } = await db
      .rpc("eval_athlete_verification", { p_user_id: user.id })
      .single();

    if (evalErr) {
      status = 500;
      errorCode = "VERIFICATION_EVAL_FAILED";
      console.error(JSON.stringify({
        request_id: requestId, fn: FN, user_id: userId,
        error_code: "VERIFICATION_EVAL_FAILED",
        detail: evalErr.message,
      }));
      return jsonErr(
        500, "VERIFICATION_EVAL_FAILED",
        "Não foi possível avaliar a verificação. Tente novamente.",
        requestId,
      );
    }

    // ── 4. Fetch full state + checklist ─────────────────────────────────
    const { data: stateRow, error: stateErr } = await db
      .from("athlete_verification")
      .select("*")
      .eq("user_id", user.id)
      .single();

    if (stateErr || !stateRow) {
      status = 500;
      errorCode = "SESSION_DATA_MISSING";
      return jsonErr(
        500, "SESSION_DATA_MISSING",
        "Registro de verificação não encontrado.",
        requestId,
      );
    }

    // ── 5. Compute checklist booleans server-side ───────────────────────
    const REQUIRED_RUNS = 7;
    const REQUIRED_TRUST = 80;
    const RECENT_WINDOW_DAYS = 30;

    const cutoff = new Date();
    cutoff.setDate(cutoff.getDate() - RECENT_WINDOW_DAYS);

    const MIN_VALID_DISTANCE_M = 1000;

    // Count verified sessions (only real runs ≥ 1 km)
    const { count: verifiedCount } = await db
      .from("sessions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("is_verified", true)
      .gte("total_distance_m", MIN_VALID_DISTANCE_M);

    // Count recent flagged sessions (only real runs ≥ 1 km)
    const { count: recentFlaggedCount } = await db
      .from("sessions")
      .select("id", { count: "exact", head: true })
      .eq("user_id", user.id)
      .eq("is_verified", false)
      .gte("total_distance_m", MIN_VALID_DISTANCE_M)
      .gte("created_at", cutoff.toISOString());

    // Average and total distance
    const { data: distRows } = await db
      .from("sessions")
      .select("total_distance_m")
      .eq("user_id", user.id)
      .eq("is_verified", true)
      .gte("total_distance_m", MIN_VALID_DISTANCE_M);

    const distances: number[] = (distRows ?? []).map(
      (r: { total_distance_m: number }) => r.total_distance_m,
    );
    const totalDist = distances.reduce((a: number, b: number) => a + b, 0);
    const avgDist = distances.length > 0 ? totalDist / distances.length : 0;

    const vCount = verifiedCount ?? 0;
    const rfCount = recentFlaggedCount ?? 0;

    const checklist = {
      identity_ok: null as boolean | null,
      permissions_ok: null as boolean | null,
      valid_runs_ok: vCount >= REQUIRED_RUNS,
      integrity_ok: rfCount === 0,
      baseline_ok: avgDist >= 1000 && vCount >= 3,
      trust_ok: stateRow.trust_score >= REQUIRED_TRUST,
    };

    const counts = {
      valid_runs_count: vCount,
      flagged_runs_recent: rfCount,
      total_distance_m: totalDist,
      avg_distance_m: avgDist,
    };

    const thresholds = {
      required_valid_runs: REQUIRED_RUNS,
      required_trust_score: REQUIRED_TRUST,
    };

    return jsonOk({
      verification_status: stateRow.verification_status,
      trust_score: stateRow.trust_score,
      verified_at: stateRow.verified_at,
      last_eval_at: stateRow.last_eval_at,
      verification_flags: stateRow.verification_flags,
      calibration_valid_runs: stateRow.calibration_valid_runs,
      checklist,
      counts,
      thresholds,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId, fn: FN, user_id: userId,
        error_code: errorCode, duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId, fn: FN, user_id: userId,
        status, duration_ms: elapsed(),
      });
    }
  }
});
