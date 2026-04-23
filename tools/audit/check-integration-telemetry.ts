/**
 * check-integration-telemetry.ts
 *
 * L16-06 — CI guard for integration telemetry primitives.
 *
 * Invariants:
 *   1. Migration defines `integration_events` with CHECK constraints
 *      on provider / event_type / status + clamping on latency/error_code,
 *      RLS enabled, policies, and three indexes (provider+type+time,
 *      user+time, errors partial).
 *   2. Migration defines `fn_log_integration_event` (SECURITY DEFINER,
 *      service-role execute, rejects empty provider/event_type/status,
 *      clamps latency in [0, 599999]).
 *   3. Migration defines `fn_integration_health_snapshot` (STABLE
 *      SECURITY DEFINER, platform_admin-gated with 42501, window clamped).
 *   4. Migration defines `fn_integration_connected_counts` for the
 *      dashboard `connected` block.
 *   5. Migration self-test covers writer/cleanup/clamping.
 *   6. Retention registered conditional on audit_logs_retention_config
 *      existing.
 *   7. Shared helper `integration_telemetry.ts` present and exports
 *      `logIntegrationEvent` + the provider/event-type unions.
 *   8. `strava-webhook`, `trainingpeaks-oauth`, `trainingpeaks-sync`
 *      import the helper and emit events on at least the documented
 *      points (webhook_received, token_refresh_*, session_imported,
 *      sync_success, sync_failure, oauth_start, oauth_callback_*).
 *   9. Portal route `/api/platform/integrations/health` calls both
 *      RPCs, gates on platform_admins membership, maps 42501 to 403,
 *      and uses `withErrorHandler`.
 *
 * Usage: npm run audit:integration-telemetry
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

// ── 1. Migration ───────────────────────────────────────────────────────────

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421530000_l16_06_integration_telemetry.sql",
);
const mig = safeRead(migPath, "L16-06 migration present");
if (mig) {
  push(
    "creates integration_events table",
    /CREATE TABLE IF NOT EXISTS public\.integration_events/.test(mig),
  );
  push(
    "provider CHECK restricts to known set",
    /chk_integration_provider[\s\S]{0,400}'strava'[\s\S]{0,60}'trainingpeaks'[\s\S]{0,60}'garmin'/.test(
      mig,
    ),
  );
  push(
    "event_type CHECK includes key events",
    /'oauth_start'[\s\S]{0,200}'token_refresh_failure'[\s\S]{0,200}'session_imported'[\s\S]{0,200}'sync_failure'/.test(
      mig,
    ),
  );
  push(
    "status CHECK enum",
    /chk_integration_status[\s\S]{0,120}'success','error','skipped','ignored'/.test(
      mig,
    ),
  );
  push(
    "error_code length clamp CHECK",
    /chk_integration_error_code_length[\s\S]{0,120}length\(error_code\) <= 64/.test(
      mig,
    ),
  );
  push(
    "external_id length clamp CHECK",
    /chk_integration_external_id_length[\s\S]{0,120}length\(external_id\) <= 128/.test(
      mig,
    ),
  );
  push(
    "latency CHECK bounded",
    /chk_integration_latency[\s\S]{0,200}latency_ms >= 0[\s\S]{0,80}latency_ms < 600000/.test(
      mig,
    ),
  );
  push(
    "user_id FK ON DELETE SET NULL",
    /user_id\s+uuid REFERENCES auth\.users\(id\) ON DELETE SET NULL/.test(mig),
  );
  push(
    "RLS enabled on integration_events",
    /ALTER TABLE public\.integration_events ENABLE ROW LEVEL SECURITY/.test(
      mig,
    ),
  );
  push(
    "policy: own-user + platform_admin read",
    /user_id = auth\.uid\(\)[\s\S]{0,200}platform_role = 'admin'/.test(mig),
  );
  push(
    "idx provider+type+time",
    /idx_integration_events_provider_type_time[\s\S]{0,200}\(provider, event_type, created_at DESC\)/.test(
      mig,
    ),
  );
  push(
    "idx partial on errors",
    /idx_integration_events_errors[\s\S]{0,200}WHERE status = 'error'/.test(mig),
  );
  push(
    "idx user+time partial",
    /idx_integration_events_user_time[\s\S]{0,200}WHERE user_id IS NOT NULL/.test(
      mig,
    ),
  );

  push(
    "defines fn_log_integration_event",
    /CREATE OR REPLACE FUNCTION public\.fn_log_integration_event/.test(mig),
  );
  push(
    "fn_log_integration_event is SECURITY DEFINER",
    /fn_log_integration_event[\s\S]{0,800}SECURITY DEFINER/.test(mig),
  );
  push(
    "fn_log_integration_event execute granted to service_role only",
    /REVOKE ALL ON FUNCTION public\.fn_log_integration_event[\s\S]{0,400}GRANT EXECUTE ON FUNCTION public\.fn_log_integration_event[\s\S]{0,200}TO service_role/.test(
      mig,
    ),
  );
  push(
    "fn_log_integration_event rejects empty provider (22023)",
    /INVALID_PROVIDER/.test(mig),
  );
  push(
    "fn_log_integration_event clamps latency",
    /v_latency := 599999/.test(mig),
  );

  push(
    "defines fn_integration_health_snapshot",
    /CREATE OR REPLACE FUNCTION public\.fn_integration_health_snapshot/.test(
      mig,
    ),
  );
  push(
    "snapshot is STABLE + SECURITY DEFINER",
    /fn_integration_health_snapshot[\s\S]{0,600}STABLE[\s\S]{0,200}SECURITY DEFINER/.test(
      mig,
    ),
  );
  push(
    "snapshot window clamped to [1, 720]",
    /greatest\(1, least\(coalesce\(p_window_hours, 24\), 720\)\)/.test(mig),
  );
  push(
    "snapshot raises 42501 on non-admin",
    /ERRCODE = '42501'[\s\S]{0,80}'FORBIDDEN'/.test(mig),
  );
  push(
    "snapshot computes p50/p95 latency",
    /percentile_cont\(0\.5\)[\s\S]{0,200}percentile_cont\(0\.95\)/.test(mig),
  );
  push(
    "snapshot emits error_rate",
    /'error_rate'/.test(mig) && /errors[\s\S]{0,80}total/.test(mig),
  );

  push(
    "defines fn_integration_connected_counts",
    /CREATE OR REPLACE FUNCTION public\.fn_integration_connected_counts/.test(
      mig,
    ),
  );
  push(
    "connected_counts is admin-gated",
    /fn_integration_connected_counts[\s\S]{0,800}'FORBIDDEN'/.test(mig),
  );

  push(
    "registers retention (90 days, conditional)",
    /audit_logs_retention_config[\s\S]{0,400}'integration_events'[\s\S]{0,80}90/.test(
      mig,
    ) && /IF EXISTS[\s\S]{0,200}audit_logs_retention_config/.test(mig),
  );

  push(
    "self-test: writer happy path",
    /writer returned NULL id/.test(mig),
  );
  push(
    "self-test: empty provider raises 22023",
    /empty provider should have raised 22023/.test(mig),
  );
  push(
    "self-test: invalid enum rejected",
    /bogus event_type should have been rejected/.test(mig),
  );
  push(
    "self-test: latency clamp verified",
    /latency clamping failed/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

// ── 2. Shared helper ───────────────────────────────────────────────────────

const helperPath = resolve(
  ROOT,
  "supabase/functions/_shared/integration_telemetry.ts",
);
const helper = safeRead(helperPath, "integration_telemetry.ts present");
if (helper) {
  push(
    "helper exports logIntegrationEvent",
    /export async function logIntegrationEvent/.test(helper),
  );
  push(
    "helper exports provider union",
    /export type IntegrationProvider/.test(helper) &&
      /"strava"[\s\S]{0,80}"trainingpeaks"/.test(helper),
  );
  push(
    "helper exports event_type union",
    /export type IntegrationEventType/.test(helper) &&
      /"webhook_received"[\s\S]{0,500}"sync_failure"/.test(helper),
  );
  push(
    "helper calls fn_log_integration_event RPC",
    /db\.rpc\("fn_log_integration_event"/.test(helper),
  );
  push(
    "helper swallows errors (never throws)",
    /catch[\s\S]{0,80}console\.error/.test(helper),
  );
}

// ── 3. Edge function instrumentation ───────────────────────────────────────

const stravaPath = resolve(
  ROOT,
  "supabase/functions/strava-webhook/index.ts",
);
const strava = safeRead(stravaPath, "strava-webhook/index.ts present");
if (strava) {
  push(
    "strava-webhook imports telemetry helper",
    /from\s+"\.\.\/_shared\/integration_telemetry\.ts"/.test(strava),
  );
  push(
    "strava-webhook emits webhook_received on success",
    /event_type:\s*"webhook_received",\s*status:\s*"success"/.test(strava),
  );
  push(
    "strava-webhook emits webhook_dedup on duplicate",
    /event_type:\s*"webhook_dedup"/.test(strava),
  );
  push(
    "strava-webhook emits session_imported",
    /event_type:\s*"session_imported"/.test(strava),
  );
  push(
    "strava-webhook emits session_ignored reason branches",
    /event_type:\s*"session_ignored"/.test(strava),
  );
  push(
    "strava-webhook emits token_refresh_success / failure",
    /"token_refresh_success"/.test(strava) &&
      /"token_refresh_failure"/.test(strava),
  );
}

const tpOAuthPath = resolve(
  ROOT,
  "supabase/functions/trainingpeaks-oauth/index.ts",
);
const tpOAuth = safeRead(tpOAuthPath, "trainingpeaks-oauth/index.ts present");
if (tpOAuth) {
  push(
    "trainingpeaks-oauth imports telemetry helper",
    /from\s+"\.\.\/_shared\/integration_telemetry\.ts"/.test(tpOAuth),
  );
  push(
    "trainingpeaks-oauth emits oauth_start on authorize",
    /event_type:\s*"oauth_start"/.test(tpOAuth),
  );
  push(
    "trainingpeaks-oauth emits oauth_callback_success",
    /event_type:\s*"oauth_callback_success"/.test(tpOAuth),
  );
  push(
    "trainingpeaks-oauth emits oauth_callback_error on failure",
    /event_type:\s*"oauth_callback_error"/.test(tpOAuth),
  );
  push(
    "trainingpeaks-oauth emits token_refresh events",
    /"token_refresh_success"/.test(tpOAuth) &&
      /"token_refresh_failure"/.test(tpOAuth),
  );
}

const tpSyncPath = resolve(
  ROOT,
  "supabase/functions/trainingpeaks-sync/index.ts",
);
const tpSync = safeRead(tpSyncPath, "trainingpeaks-sync/index.ts present");
if (tpSync) {
  push(
    "trainingpeaks-sync imports telemetry helper",
    /from\s+"\.\.\/_shared\/integration_telemetry\.ts"/.test(tpSync),
  );
  push(
    "trainingpeaks-sync emits sync_success on push ok",
    /event_type:\s*"sync_success"/.test(tpSync),
  );
  push(
    "trainingpeaks-sync emits sync_failure on push fail",
    /event_type:\s*"sync_failure"/.test(tpSync),
  );
}

// ── 4. Portal route ────────────────────────────────────────────────────────

const routePath = resolve(
  ROOT,
  "portal/src/app/api/platform/integrations/health/route.ts",
);
const route = safeRead(routePath, "integrations health route present");
if (route) {
  push(
    "route wrapped in withErrorHandler",
    /withErrorHandler\(\s*_get/.test(route),
  );
  push(
    "route gates on platform_admins membership",
    /from\("platform_admins"\)/.test(route),
  );
  push(
    "route validates query with zod",
    /QuerySchema\.safeParse/.test(route) &&
      /z\.enum\(\[[\s\S]{0,200}"strava"[\s\S]{0,200}"google_fit"[\s\S]{0,40}\]\)/.test(
        route,
      ),
  );
  push(
    "route bounds window_hours to [1, 720]",
    /n >= 1 && n <= 720/.test(route),
  );
  push(
    "route calls fn_integration_health_snapshot",
    /supabase\.rpc\("fn_integration_health_snapshot"/.test(route),
  );
  push(
    "route calls fn_integration_connected_counts",
    /supabase\.rpc\("fn_integration_connected_counts"/.test(route),
  );
  push(
    "route maps 42501 to 403",
    /42501[\s\S]{0,400}403/.test(route) || /isForbidden[\s\S]{0,400}403/.test(route),
  );
}

// ── 5. Finding cross-references ────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L16-06-strava-trainingpeaks-oauth-sem-telemetria-de-uso.md",
);
const finding = safeRead(findingPath, "L16-06 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421530000_l16_06_integration_telemetry\.sql/.test(finding),
  );
  push(
    "finding references telemetry helper",
    /supabase\/functions\/_shared\/integration_telemetry\.ts/.test(finding),
  );
  push(
    "finding references platform route",
    /api\/platform\/integrations\/health/.test(finding),
  );
}

// ── Report ────────────────────────────────────────────────────────────────

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} integration-telemetry checks passed.`,
);
if (failed > 0) {
  console.error("\nL16-06 invariants broken.");
  process.exit(1);
}
