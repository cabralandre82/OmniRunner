import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import {
  buildSlackDriftPayload,
  classifyWalletDrift,
  DEFAULT_DRIFT_WARN_THRESHOLD,
  postSlackAlert,
  type WalletDriftClassification,
} from "../_shared/wallet_drift.ts";

/**
 * reconcile-wallets-cron — Supabase Edge Function (L06-03 hardened).
 *
 * Scheduled via pg_cron `30 4 * * *` UTC (slot engineered by L12-02).
 * Calls `reconcile_all_wallets()` RPC which compares every wallet's
 * `balance_coins` against `SUM(coin_ledger.delta_coins)`. Any drift is
 * auto-corrected and logged as `admin_adjustment`.
 *
 * On drift > 0 the function now follows a defence-in-depth alert pipeline:
 *
 *   1. Classify severity via `classifyWalletDrift(drifted, threshold)`:
 *        - 1 .. WARN_THRESHOLD              → warn     (P2)
 *        - > WARN_THRESHOLD                 → critical (P1)
 *
 *   2. Persist a forensic row in `public.wallet_drift_events` via
 *      `fn_record_wallet_drift_event` BEFORE attempting any external
 *      delivery — Slack/PagerDuty outages can never lose the audit trail.
 *
 *   3. POST a Slack incoming-webhook alert (if `WALLET_DRIFT_ALERT_WEBHOOK`
 *      is set in env). Block Kit + plain-text fallback. 5s timeout.
 *
 *   4. Update the persisted row via `fn_mark_wallet_drift_event_alerted`
 *      with the delivery outcome (success / channel / error).
 *
 *   5. Always emit a structured `console.error` line carrying severity tag
 *      so the log-based alert rules (`severity: ALERT|CRITICAL`) keep
 *      working as a back-stop.
 *
 * Env vars (all optional → degrade gracefully):
 *   WALLET_DRIFT_WARN_THRESHOLD    integer, default 10
 *   WALLET_DRIFT_ALERT_WEBHOOK     Slack incoming-webhook URL
 *   WALLET_DRIFT_RUNBOOK_URL       link rendered in the Slack message
 *   ENVIRONMENT_LABEL              e.g. "production" | "staging" (Slack tag)
 *
 * Auth: service-role key only (called by pg_net from pg_cron).
 *
 * POST /reconcile-wallets-cron
 * Headers: Authorization: Bearer <service_role_key>
 *
 * Audit: docs/audit/findings/L06-03-reconcile-wallets-cron-sem-alerta-em-drift-0.md
 */

const FN = "reconcile-wallets-cron";

function readPositiveIntEnv(name: string, fallback: number): number {
  const raw = Deno.env.get(name);
  if (!raw) return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === "GET" && new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", version: "3.0.0" }), {
      headers: { "Content-Type": "application/json" },
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

    const result = data as {
      total_wallets: number;
      drifted: number;
      run_at: string;
    };

    // ── L06-03: severity-tiered alert pipeline ─────────────────────────
    const warnThreshold = readPositiveIntEnv(
      "WALLET_DRIFT_WARN_THRESHOLD",
      DEFAULT_DRIFT_WARN_THRESHOLD,
    );
    const classification: WalletDriftClassification = classifyWalletDrift(
      result.drifted,
      warnThreshold,
    );

    let alertOutcome: {
      event_id: string | null;
      delivered: boolean;
      delivery_status: number | null;
      delivery_error: string | null;
      channel: string | null;
    } = {
      event_id: null,
      delivered: false,
      delivery_status: null,
      delivery_error: null,
      channel: null,
    };

    if (classification.shouldAlert) {
      // 1) Persist FIRST. If this fails we still emit a console alert
      //    but the cron itself does not 500 (drift was already corrected
      //    and the structured log is captured by the aggregator).
      let eventId: string | null = null;
      try {
        const { data: recordedId, error: recErr } = await db.rpc(
          "fn_record_wallet_drift_event",
          {
            p_run_id: requestId,
            p_total_wallets: result.total_wallets,
            p_drifted_count: result.drifted,
            p_severity: classification.severity,
            p_notes: {
              warn_threshold: warnThreshold,
              environment: Deno.env.get("ENVIRONMENT_LABEL") ?? "unknown",
              p_tier: classification.pTier,
              run_at: result.run_at,
            },
          },
        );
        if (recErr) {
          console.error(JSON.stringify({
            request_id: requestId, fn: FN,
            event: "drift_event_persist_failed",
            severity: "ALERT",
            error_code: "RPC_FAILED",
            detail: recErr.message,
          }));
        } else {
          eventId = recordedId as string;
        }
      } catch (e) {
        console.error(JSON.stringify({
          request_id: requestId, fn: FN,
          event: "drift_event_persist_threw",
          severity: "ALERT",
          detail: e instanceof Error ? e.message : String(e),
        }));
      }
      alertOutcome.event_id = eventId;

      // 2) Slack delivery (best-effort).
      const webhookUrl = Deno.env.get("WALLET_DRIFT_ALERT_WEBHOOK");
      if (webhookUrl) {
        const payload = buildSlackDriftPayload(classification, {
          totalWallets: result.total_wallets,
          driftedCount: result.drifted,
          runId: requestId,
          runAt: result.run_at,
          environment: Deno.env.get("ENVIRONMENT_LABEL") ?? "unknown",
          runbookUrl: Deno.env.get("WALLET_DRIFT_RUNBOOK_URL"),
        });
        if (payload) {
          const delivery = await postSlackAlert(webhookUrl, payload);
          alertOutcome.delivered = delivery.ok;
          alertOutcome.delivery_status = delivery.status;
          alertOutcome.delivery_error = delivery.error ?? null;
          alertOutcome.channel = "slack";

          // 3) Mark the persisted event with the delivery outcome.
          if (eventId) {
            try {
              await db.rpc("fn_mark_wallet_drift_event_alerted", {
                p_event_id: eventId,
                p_channel: "slack",
                p_error: delivery.ok ? null : (delivery.error ?? `HTTP ${delivery.status}`),
              });
            } catch (e) {
              console.error(JSON.stringify({
                request_id: requestId, fn: FN,
                event: "drift_event_mark_alerted_threw",
                severity: "ALERT",
                detail: e instanceof Error ? e.message : String(e),
              }));
            }
          }
        }
      }

      // 4) Always emit the structured alert log line — back-stop for any
      //    pipeline that does NOT have webhooks wired yet.
      console.error(JSON.stringify({
        request_id: requestId,
        fn: FN,
        severity: classification.severity === "critical" ? "CRITICAL" : "ALERT",
        p_tier: classification.pTier,
        event: "wallet_drift_detected",
        total_wallets: result.total_wallets,
        drifted: result.drifted,
        warn_threshold: warnThreshold,
        run_at: result.run_at,
        drift_event_id: eventId,
        slack_delivered: alertOutcome.delivered,
        slack_status: alertOutcome.delivery_status,
        slack_error: alertOutcome.delivery_error,
        message: `${result.drifted} wallet(s) had balance drift and were auto-corrected`,
      }));
    }

    console.log(JSON.stringify({
      request_id: requestId, fn: FN,
      event: "reconcile_complete",
      total_wallets: result.total_wallets,
      drifted: result.drifted,
      severity: classification.severity,
    }));

    return jsonOk({
      status: "ok",
      total_wallets: result.total_wallets,
      drifted: result.drifted,
      run_at: result.run_at,
      severity: classification.severity,
      p_tier: classification.pTier,
      drift_event_id: alertOutcome.event_id,
      slack_delivered: alertOutcome.delivered,
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
