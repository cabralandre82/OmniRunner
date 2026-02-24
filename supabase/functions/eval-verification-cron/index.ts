import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * eval-verification-cron — Supabase Edge Function
 *
 * Scheduled via pg_cron (daily 03:00 UTC). Re-evaluates athlete verification
 * for users who need it:
 *   1. Users with recent integrity flags (last_integrity_flag_at within 30 days)
 *   2. Users in CALIBRATING status (actively building their profile)
 *   3. Users in MONITORED status (close to VERIFIED threshold)
 *   4. Users not evaluated in the last 24 hours who have recent sessions
 *
 * Each candidate is evaluated via the existing eval_athlete_verification RPC
 * (SECURITY DEFINER, idempotent). Batch size capped to avoid timeouts.
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 * ZERO override: this cron only runs the same evaluation logic that the
 * event-driven path uses. No manual status setting.
 *
 * POST /eval-verification-cron
 * Headers: Authorization: Bearer <service_role_key>
 */

const FN = "eval-verification-cron";
const BATCH_SIZE = 100;

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role key required", requestId);
    }

    const db = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });

    // ── 1. Find candidate users for re-evaluation ────────────────────

    const cutoff24h = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const cutoff30d = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();

    // Query: users who are CALIBRATING, MONITORED, or DOWNGRADED,
    // OR have recent integrity flags,
    // OR have not been evaluated in 24h but have recent sessions.
    const { data: candidates, error: queryErr } = await db
      .from("athlete_verification")
      .select("user_id")
      .or(
        `verification_status.in.(CALIBRATING,MONITORED,DOWNGRADED),` +
        `last_integrity_flag_at.gte.${cutoff30d},` +
        `last_eval_at.is.null,` +
        `last_eval_at.lt.${cutoff24h}`
      )
      .limit(BATCH_SIZE);

    if (queryErr) {
      status = 500;
      errorCode = "QUERY_FAILED";
      console.error(JSON.stringify({
        request_id: requestId, fn: FN,
        error_code: "QUERY_FAILED", detail: queryErr.message,
      }));
      return jsonErr(500, "QUERY_FAILED", "Failed to query candidates", requestId);
    }

    const userIds: string[] = (candidates ?? []).map(
      (r: { user_id: string }) => r.user_id,
    );

    if (userIds.length === 0) {
      return jsonOk({
        status: "ok",
        evaluated: 0,
        message: "No candidates for re-evaluation",
      }, requestId);
    }

    // ── 2. Evaluate each candidate ──────────────────────────────────
    let evaluated = 0;
    let errors = 0;

    for (const uid of userIds) {
      try {
        const { error: evalErr } = await db
          .rpc("eval_athlete_verification", { p_user_id: uid })
          .single();

        if (evalErr) {
          errors++;
          console.error(JSON.stringify({
            request_id: requestId, fn: FN,
            event: "eval_failed", user_id: uid,
            detail: evalErr.message,
          }));
        } else {
          evaluated++;
        }
      } catch (e) {
        errors++;
        console.error(JSON.stringify({
          request_id: requestId, fn: FN,
          event: "eval_exception", user_id: uid,
          detail: (e as Error)?.message,
        }));
      }
    }

    console.log(JSON.stringify({
      request_id: requestId, fn: FN,
      event: "batch_complete",
      candidates: userIds.length, evaluated, errors,
    }));

    return jsonOk({
      status: "ok",
      candidates: userIds.length,
      evaluated,
      errors,
    }, requestId);
  } catch (_err) {
    status = 500;
    errorCode = "INTERNAL";
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId, fn: FN, user_id: null,
        error_code: errorCode, duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId, fn: FN, user_id: null,
        status, duration_ms: elapsed(),
      });
    }
  }
});
