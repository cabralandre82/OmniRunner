/**
 * check-outbound-webhooks.ts
 *
 * L16-04 — CI guard for outbound webhooks primitives.
 *
 * Invariants:
 *   1. URL validator rejects http, loopback, RFC1918 (10, 192.168),
 *      link-local (169.254), and enforces length bounds.
 *   2. Events validator whitelists the 15 canonical outbox event
 *      types, rejects empty arrays and >20 entries.
 *   3. Secret generator returns 64-hex.
 *   4. Endpoints table: group_id FK to coaching_groups, URL CHECK via
 *      validator, secret shape CHECK, events shape CHECK, max_attempts
 *      CHECK 1..10, RLS admin-read, partial index on enabled.
 *   5. Deliveries table: endpoint_id FK with ON DELETE CASCADE, status
 *      enum, attempt 0..10 CHECK, status_code 0..599 CHECK,
 *      response/error length CHECKs, ready-partial index, dead-partial
 *      index, RLS platform_admin read only.
 *   6. Retention seeding is conditional (IF EXISTS).
 *   7. Register / rotate / enable / enqueue / claim / mark_delivered /
 *      mark_failed RPCs — security model, grants, error codes.
 *   8. claim uses FOR UPDATE SKIP LOCKED and enforces [1,500] limit +
 *      [5,3600] lease.
 *   9. mark_failed uses exponential backoff and promotes to dead on
 *      max_attempts.
 *  10. Self-test covers URL validator (5 cases) + events validator
 *      (3 cases) + secret length.
 *  11. Migration runs in a single transaction.
 *
 * Usage: npm run audit:outbound-webhooks
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

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421610000_l16_04_outbound_webhooks.sql",
);
const mig = safeRead(migPath, "L16-04 migration file present");

if (mig) {
  // URL validator.
  push(
    "defines fn_validate_webhook_url IMMUTABLE PARALLEL SAFE",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_webhook_url[\s\S]{0,400}IMMUTABLE[\s\S]{0,120}PARALLEL SAFE/.test(mig),
  );
  push(
    "URL validator enforces https://",
    /p_value !~ '\^https:\/\/'/.test(mig),
  );
  push(
    "URL validator enforces length <=500 and >=12",
    /length\(p_value\) > 500 OR length\(p_value\) < 12/.test(mig),
  );
  push(
    "URL validator rejects loopback",
    /localhost\|127\\.0\\.0\\.1\|0\\.0\\.0\\.0/.test(mig),
  );
  push(
    "URL validator rejects 10.0.0.0/8",
    /\\b10\\\./.test(mig),
  );
  push(
    "URL validator rejects 192.168.0.0/16",
    /\\b192\\\.168\\\./.test(mig),
  );
  push(
    "URL validator rejects 169.254.0.0/16",
    /\\b169\\\.254\\\./.test(mig),
  );
  push(
    "grants URL validator to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_validate_webhook_url\(TEXT\) TO PUBLIC/.test(mig),
  );

  // Events validator.
  push(
    "defines fn_validate_outbound_webhook_events",
    /CREATE OR REPLACE FUNCTION public\.fn_validate_outbound_webhook_events/.test(mig),
  );
  push(
    "events validator IMMUTABLE PARALLEL SAFE",
    /fn_validate_outbound_webhook_events[\s\S]{0,400}IMMUTABLE[\s\S]{0,120}PARALLEL SAFE/.test(mig),
  );
  push(
    "events validator whitelists session.verified",
    /'session\.verified'/.test(mig),
  );
  push(
    "events validator whitelists coin.distributed",
    /'coin\.distributed'/.test(mig),
  );
  push(
    "events validator whitelists championship.ended",
    /'championship\.ended'/.test(mig),
  );
  push(
    "events validator rejects >20 entries",
    /array_length\(p_events, 1\) > 20/.test(mig),
  );
  push(
    "events validator rejects null/empty arrays",
    /p_events IS NULL OR array_length\(p_events, 1\) IS NULL/.test(mig),
  );

  // Secret generator.
  push(
    "secret generator uses gen_random_bytes(32)",
    /encode\(gen_random_bytes\(32\), 'hex'\)/.test(mig),
  );

  // Endpoints table.
  push(
    "creates outbound_webhook_endpoints table",
    /CREATE TABLE IF NOT EXISTS public\.outbound_webhook_endpoints/.test(mig),
  );
  push(
    "endpoints references coaching_groups ON DELETE CASCADE",
    /outbound_webhook_endpoints[\s\S]{0,600}REFERENCES public\.coaching_groups\(id\) ON DELETE CASCADE/.test(mig),
  );
  push(
    "endpoints URL CHECK via validator",
    /CONSTRAINT outbound_webhook_endpoints_url_shape\s+CHECK \(public\.fn_validate_webhook_url\(url\)\)/.test(mig),
  );
  push(
    "endpoints secret shape CHECK",
    /outbound_webhook_endpoints_secret_shape[\s\S]{0,120}\^\[0-9a-f\]\{64\}\$/.test(mig),
  );
  push(
    "endpoints events CHECK via validator",
    /outbound_webhook_endpoints_events_shape[\s\S]{0,120}public\.fn_validate_outbound_webhook_events\(events\)/.test(mig),
  );
  push(
    "endpoints max_attempts CHECK 1..10",
    /outbound_webhook_endpoints_max_attempts_bound[\s\S]{0,120}BETWEEN 1 AND 10/.test(mig),
  );
  push(
    "endpoints enabled partial index",
    /CREATE INDEX IF NOT EXISTS outbound_webhook_endpoints_enabled_idx[\s\S]{0,200}WHERE enabled = TRUE/.test(mig),
  );
  push(
    "endpoints RLS enabled",
    /ALTER TABLE public\.outbound_webhook_endpoints ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "endpoints admin-read policy",
    /outbound_webhook_endpoints_admin_read[\s\S]{0,400}platform_role = 'admin'[\s\S]{0,400}admin_master/.test(mig),
  );

  // Deliveries table.
  push(
    "creates outbound_webhook_deliveries table",
    /CREATE TABLE IF NOT EXISTS public\.outbound_webhook_deliveries/.test(mig),
  );
  push(
    "deliveries references endpoints ON DELETE CASCADE",
    /outbound_webhook_deliveries[\s\S]{0,600}REFERENCES public\.outbound_webhook_endpoints\(id\) ON DELETE CASCADE/.test(mig),
  );
  push(
    "deliveries status enum CHECK",
    /CHECK \(status IN \('pending','processing','delivered','failed','dead'\)\)/.test(mig),
  );
  push(
    "deliveries attempt 0..10 CHECK",
    /outbound_webhook_deliveries_attempt_bound[\s\S]{0,120}attempt >= 0 AND attempt <= 10/.test(mig),
  );
  push(
    "deliveries status_code 0..599 CHECK",
    /outbound_webhook_deliveries_status_code_bound[\s\S]{0,120}BETWEEN 0 AND 599/.test(mig),
  );
  push(
    "deliveries response_excerpt length CHECK",
    /outbound_webhook_deliveries_response_len[\s\S]{0,120}length\(response_excerpt\) <= 500/.test(mig),
  );
  push(
    "deliveries error_message length CHECK",
    /outbound_webhook_deliveries_error_len[\s\S]{0,120}length\(error_message\) <= 500/.test(mig),
  );
  push(
    "deliveries ready-partial index",
    /CREATE INDEX IF NOT EXISTS outbound_webhook_deliveries_ready_idx[\s\S]{0,200}WHERE status = 'pending'/.test(mig),
  );
  push(
    "deliveries dead-partial index",
    /CREATE INDEX IF NOT EXISTS outbound_webhook_deliveries_dead_idx[\s\S]{0,200}WHERE status = 'dead'/.test(mig),
  );
  push(
    "deliveries RLS enabled",
    /ALTER TABLE public\.outbound_webhook_deliveries ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "deliveries platform_admin-only read",
    /outbound_webhook_deliveries_admin_read[\s\S]{0,400}platform_role = 'admin'/.test(mig),
  );

  // Retention.
  push(
    "retention seeding is conditional",
    /IF to_regclass\('public\.audit_logs_retention_config'\) IS NOT NULL THEN[\s\S]{0,400}'outbound_webhook_deliveries', 30/.test(mig),
  );

  // Admin lifecycle RPCs.
  push(
    "defines fn_outbound_webhook_register",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_register/.test(mig),
  );
  push(
    "register raises INVALID_URL for bad URL",
    /fn_outbound_webhook_register[\s\S]{0,1200}RAISE EXCEPTION 'INVALID_URL' USING ERRCODE = 'P0001'/.test(mig),
  );
  push(
    "register raises INVALID_EVENTS for bad events",
    /RAISE EXCEPTION 'INVALID_EVENTS' USING ERRCODE = 'P0001'/.test(mig),
  );
  push(
    "register raises FORBIDDEN 42501",
    /fn_outbound_webhook_register[\s\S]{0,2400}RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501'/.test(mig),
  );
  push(
    "register returns secret once",
    /fn_outbound_webhook_register[\s\S]{0,1800}'secret', v_row\.secret/.test(mig),
  );
  push(
    "register grants to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_outbound_webhook_register\(UUID, TEXT, TEXT\[\]\) TO authenticated, service_role/.test(mig),
  );

  push(
    "defines fn_outbound_webhook_rotate_secret",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_rotate_secret/.test(mig),
  );
  push(
    "rotate audits to portal_audit_log fail-open",
    /group\.webhook\.secret_rotated[\s\S]{0,400}EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'webhook rotate audit failed/.test(mig),
  );

  push(
    "defines fn_outbound_webhook_enable",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_enable/.test(mig),
  );

  // Worker RPCs.
  push(
    "defines fn_outbound_webhook_enqueue service-role-only",
    /fn_outbound_webhook_enqueue[\s\S]{0,600}current_setting\('role', true\) <> 'service_role'[\s\S]{0,200}SERVICE_ROLE_ONLY/.test(mig),
  );
  push(
    "enqueue fan-outs to enabled endpoints subscribed to event",
    /e\.enabled = TRUE[\s\S]{0,120}p_event_type = ANY \(e\.events\)/.test(mig),
  );
  push(
    "enqueue grants to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_outbound_webhook_enqueue\(TEXT, UUID, JSONB\) TO service_role/.test(mig),
  );

  push(
    "defines fn_outbound_webhook_claim",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_claim/.test(mig),
  );
  push(
    "claim uses FOR UPDATE SKIP LOCKED",
    /fn_outbound_webhook_claim[\s\S]{0,1200}FOR UPDATE SKIP LOCKED/.test(mig),
  );
  push(
    "claim clamps limit [1,500]",
    /GREATEST\(1, LEAST\(COALESCE\(p_limit, 50\), 500\)\)/.test(mig),
  );
  push(
    "claim clamps lease [5,3600]",
    /GREATEST\(5, LEAST\(COALESCE\(p_lease_seconds, 60\), 3600\)\)/.test(mig),
  );
  push(
    "claim bumps attempt on claim",
    /attempt = d\.attempt \+ 1/.test(mig),
  );

  push(
    "defines fn_outbound_webhook_mark_delivered",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_mark_delivered/.test(mig),
  );
  push(
    "mark_delivered grants to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_outbound_webhook_mark_delivered\(UUID, INT, TEXT\) TO service_role/.test(mig),
  );

  push(
    "defines fn_outbound_webhook_mark_failed",
    /CREATE OR REPLACE FUNCTION public\.fn_outbound_webhook_mark_failed/.test(mig),
  );
  push(
    "mark_failed uses exponential backoff clamped 6h",
    /LEAST\(30 \* \(2 \^ GREATEST\(v_delivery\.attempt - 1, 0\)\)::INT, 21600\)/.test(mig),
  );
  push(
    "mark_failed promotes to dead on max_attempts",
    /v_delivery\.attempt >= v_endpoint\.max_attempts THEN[\s\S]{0,80}v_new_status := 'dead'/.test(mig),
  );

  // Self-test.
  push(
    "self-test: URL validator rejects http",
    /self-test: fn_validate_webhook_url accepted http/.test(mig),
  );
  push(
    "self-test: URL validator rejects localhost",
    /self-test: fn_validate_webhook_url accepted localhost/.test(mig),
  );
  push(
    "self-test: URL validator rejects 10.0.0.0/8",
    /self-test: fn_validate_webhook_url accepted 10\.0\.0\.0\/8/.test(mig),
  );
  push(
    "self-test: URL validator rejects 192.168.0.0/16",
    /self-test: fn_validate_webhook_url accepted RFC1918/.test(mig),
  );
  push(
    "self-test: events validator rejects unknown events",
    /self-test: events validator accepted unknown event/.test(mig),
  );
  push(
    "self-test: events validator rejects empty",
    /self-test: events validator accepted empty array/.test(mig),
  );
  push(
    "self-test: secret length asserted",
    /self-test: secret length != 64 hex/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L16-04-sem-outbound-webhooks-para-parceiros.md",
);
const finding = safeRead(findingPath, "L16-04 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421610000_l16_04_outbound_webhooks\.sql/.test(finding),
  );
  push(
    "finding references outbound_webhook_endpoints / deliveries",
    /outbound_webhook_endpoints[\s\S]{0,400}outbound_webhook_deliveries/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} outbound-webhooks checks passed.`,
);
if (failed > 0) {
  console.error("\nL16-04 invariants broken.");
  process.exit(1);
}
