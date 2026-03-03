import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * reconcile-wallets-cron — Supabase Edge Function
 *
 * Scheduled via pg_cron (e.g. daily 04:00 UTC).
 * Calls reconcile_all_wallets() RPC which compares every wallet's
 * balance_coins against the SUM of its coin_ledger entries. Any drift
 * is auto-corrected and logged as admin_correction.
 *
 * If drifted wallets are found, the function logs a structured alert
 * suitable for external monitoring (Datadog, Grafana, etc.).
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /reconcile-wallets-cron
 * Headers: Authorization: Bearer <service_role_key>
 */

const FN = "reconcile-wallets-cron";

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

    // ── Call the batch reconciliation RPC ──────────────────────────────
    const { data, error: rpcErr } = await db
      .rpc("reconcile_all_wallets")
      .single();

    if (rpcErr) {
      status = 500;
      errorCode = "RPC_FAILED";
      console.error(JSON.stringify({
        request_id: requestId, fn: FN,
        error_code: "RPC_FAILED", detail: rpcErr.message,
      }));
      return jsonErr(500, "RPC_FAILED", "reconcile_all_wallets failed", requestId);
    }

    const result = data as { total_wallets: number; drifted: number; run_at: string };

    // ── Alert if drift detected ───────────────────────────────────────
    if (result.drifted > 0) {
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        severity: "ALERT",
        event: "wallet_drift_detected",
        total_wallets: result.total_wallets,
        drifted: result.drifted,
        run_at: result.run_at,
        message: `${result.drifted} wallet(s) had balance drift and were auto-corrected`,
      }));
    }

    console.log(JSON.stringify({
      request_id: requestId, fn: FN,
      event: "reconcile_complete",
      total_wallets: result.total_wallets,
      drifted: result.drifted,
    }));

    return jsonOk({
      status: "ok",
      total_wallets: result.total_wallets,
      drifted: result.drifted,
      run_at: result.run_at,
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
