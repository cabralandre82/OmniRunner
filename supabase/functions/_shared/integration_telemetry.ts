// L16-06 — Integration telemetry helper for edge functions.
//
// Wraps `public.fn_log_integration_event(...)` so every edge function
// that talks to Strava / TrainingPeaks / Garmin / etc. can emit
// observability events with a single call. Failure to log telemetry
// never aborts the calling flow; instead the error is swallowed and
// logged to stderr.
//
// Usage:
//   import { logIntegrationEvent } from "../_shared/integration_telemetry.ts";
//
//   await logIntegrationEvent(db, {
//     provider:    "strava",
//     event_type:  "webhook_received",
//     status:      "success",
//     user_id:     connection.user_id,
//     external_id: String(event.object_id),
//     latency_ms:  Date.now() - startedAt,
//     metadata:    { aspect_type: event.aspect_type },
//   });
//
// Contract with the RPC:
//   - `provider`, `event_type`, `status` are REQUIRED.
//   - `error_code` is truncated to 64 chars on the SQL side.
//   - `external_id` is truncated to 128 chars on the SQL side.
//   - `latency_ms` is clamped to [0, 599999] on the SQL side.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export type IntegrationProvider =
  | "strava"
  | "trainingpeaks"
  | "garmin"
  | "polar"
  | "coros"
  | "suunto"
  | "apple_health"
  | "google_fit";

export type IntegrationEventType =
  | "oauth_start"
  | "oauth_callback_success"
  | "oauth_callback_error"
  | "token_refresh_success"
  | "token_refresh_failure"
  | "webhook_received"
  | "webhook_dedup"
  | "webhook_validated"
  | "session_imported"
  | "session_ignored"
  | "sync_success"
  | "sync_failure"
  | "disconnect"
  | "token_revoked";

export type IntegrationStatus = "success" | "error" | "skipped" | "ignored";

export interface IntegrationTelemetryInput {
  provider: IntegrationProvider;
  event_type: IntegrationEventType;
  status: IntegrationStatus;
  user_id?: string | null;
  error_code?: string | null;
  latency_ms?: number | null;
  external_id?: string | null;
  metadata?: Record<string, unknown>;
}

export async function logIntegrationEvent(
  // deno-lint-ignore no-explicit-any
  db: SupabaseClient<any, "public", any>,
  input: IntegrationTelemetryInput,
): Promise<void> {
  try {
    const { error } = await db.rpc("fn_log_integration_event", {
      p_provider: input.provider,
      p_event_type: input.event_type,
      p_status: input.status,
      p_user_id: input.user_id ?? null,
      p_error_code: input.error_code ?? null,
      p_latency_ms: input.latency_ms ?? null,
      p_external_id: input.external_id ?? null,
      p_metadata: input.metadata ?? {},
    });
    if (error) {
      console.error(JSON.stringify({
        fn: "integration_telemetry",
        msg: "rpc_error",
        code: error.code ?? null,
        detail: error.message?.slice(0, 200) ?? null,
      }));
    }
  } catch (err) {
    console.error(JSON.stringify({
      fn: "integration_telemetry",
      msg: "throw",
      detail: (err as Error).message?.slice(0, 200) ?? null,
    }));
  }
}
