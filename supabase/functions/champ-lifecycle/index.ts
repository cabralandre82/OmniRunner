import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * champ-lifecycle — Supabase Edge Function
 *
 * Evaluates and transitions championship statuses:
 *   open  → active    (when start_at ≤ now)
 *   active → completed (when end_at ≤ now, computes final ranks)
 *
 * Can be called by cron or manually. Processes all due championships.
 *
 * POST /champ-lifecycle
 * Body: { championship_id?: string } — optional: process only one
 */

const FN = "champ-lifecycle";

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

    const rl = await checkRateLimit(db, user.id, { fn: FN, maxRequests: 10, windowSeconds: 60 }, requestId);
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // deno-lint-ignore no-explicit-any
    let body: Record<string, any> = {};
    try {
      body = await req.json();
    } catch { /* empty body OK */ }

    const now = new Date().toISOString();
    let activated = 0;
    let completed = 0;

    // ── 1. open → active ───────────────────────────────────────────────
    {
      let query = db.from("championships").select("id, status, start_at, end_at")
        .eq("status", "open")
        .lte("start_at", now);
      if (body.championship_id) query = query.eq("id", body.championship_id);

      const { data: dueOpen, error: err } = await query;
      if (err) {
        const classified = classifyError(err);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      for (const ch of (dueOpen ?? [])) {
        // Transition enrolled participants to active
        await db.from("championship_participants")
          .update({ status: "active", updated_at: now })
          .eq("championship_id", ch.id)
          .eq("status", "enrolled");

        await db.from("championships")
          .update({ status: "active", updated_at: now })
          .eq("id", ch.id)
          .eq("status", "open");

        activated++;
      }
    }

    // ── 2. active → completed ──────────────────────────────────────────
    {
      let query = db.from("championships").select("id, status, metric, end_at")
        .eq("status", "active")
        .lte("end_at", now);
      if (body.championship_id) query = query.eq("id", body.championship_id);

      const { data: dueActive, error: err } = await query;
      if (err) {
        const classified = classifyError(err);
        status = classified.httpStatus;
        errorCode = classified.code;
        return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
      }

      // deno-lint-ignore no-explicit-any
      for (const ch of (dueActive ?? []) as any[]) {
        // Fetch participants sorted by progress
        const isLowerBetter = ch.metric === "pace";
        const { data: parts } = await db
          .from("championship_participants")
          .select("id, user_id, progress_value, status")
          .eq("championship_id", ch.id)
          .in("status", ["active", "enrolled"])
          .order("progress_value", { ascending: isLowerBetter });

        // Assign final ranks (dense ranking by progress_value)
        let rank = 1;
        for (let i = 0; i < (parts ?? []).length; i++) {
          const p = parts![i];
          if (i > 0 && p.progress_value !== parts![i - 1].progress_value) {
            rank = i + 1;
          }
          await db.from("championship_participants")
            .update({ final_rank: rank, status: "completed", updated_at: now })
            .eq("id", p.id);
        }

        await db.from("championships")
          .update({ status: "completed", updated_at: now })
          .eq("id", ch.id)
          .eq("status", "active");

        completed++;
      }
    }

    return jsonOk({ activated, completed }, requestId);
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
