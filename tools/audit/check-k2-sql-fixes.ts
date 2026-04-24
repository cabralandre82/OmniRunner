#!/usr/bin/env tsx
/**
 * Batch K2 — SQL/schema/RLS audit guards
 *
 * One CI check that asserts the structural invariants of all K2 SQL
 * fixes are present in the live migration set (parsed from disk —
 * we do not connect to a database from CI).
 *
 * Findings covered:
 *   L01-42  platform_fee_config RLS hardening
 *   L01-43  dead role 'professor' purge
 *   L01-49  portal_audit_log actor_kind
 *   L03-08  global conservation invariant
 *   L03-15  expire stale custody_deposits
 *   L05-10  swap_orders.visibility
 *   L05-16  workout_delivery_items reschedule flow
 *   L05-17  badge_awards.valid_until
 *   L18-09  audit_logs event_schema_version + event_domain
 */
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");
const MIG = path.join(ROOT, "supabase/migrations");

type Check = { id: string; mig: string; assertions: Array<[string, RegExp]> };

const CHECKS: Check[] = [
  {
    id: "L01-42",
    mig: "20260421760000_l01_42_platform_fee_config_rls.sql",
    assertions: [
      ["drops legacy USING(true)", /DROP POLICY[\s\S]+platform_fee_config_read"/],
      ["self-facing policy", /platform_fee_config_read_self_facing[\s\S]+fee_type IN \('clearing', 'swap'\)/],
      ["admin policy", /platform_fee_config_read_admin[\s\S]+platform_role = 'admin'/],
      ["self-test", /L01-42 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L01-43",
    mig: "20260421770000_l01_43_dead_role_audit.sql",
    assertions: [
      ["scans pg_policies", /pg_policies[\s\S]+'professor'/],
      ["raises on offenders", /RAISE EXCEPTION[\s\S]+L01-43/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L01-49",
    mig: "20260421780000_l01_49_audit_log_actor_kind.sql",
    assertions: [
      ["adds actor_kind", /ADD COLUMN IF NOT EXISTS actor_kind/],
      ["drops NOT NULL on actor_id", /ALTER COLUMN actor_id DROP NOT NULL/],
      ["CHECK constraint", /portal_audit_log_actor_kind_chk/],
      ["self-test", /L01-49 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L03-08",
    mig: "20260421790000_l03_08_global_conservation_check.sql",
    assertions: [
      ["check 3 label", /global_deposit_mismatch/],
      ["uses platform_revenue", /platform_revenue/],
      ["tolerance 0\\.01", /> 0\.01/],
      ["self-test", /L03-08 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L03-15",
    mig: "20260421840000_l03_15_expire_stale_deposits.sql",
    assertions: [
      ["adds 'expired' status", /'expired'/],
      ["fn_expire_stale_deposits", /fn_expire_stale_deposits/],
      ["48h default", /interval '48 hours'/],
      ["pg_cron schedule guarded", /SELECT 1 FROM cron\.job[\s\S]+l03_15_expire_stale_deposits/],
      ["self-test", /L03-15 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L05-10",
    mig: "20260421800000_l05_10_swap_orders_visibility.sql",
    assertions: [
      ["visibility column", /visibility text NOT NULL DEFAULT 'public'/],
      ["whitelist column", /whitelist_group_ids uuid\[\]/],
      ["CHECK 3 values", /'public','private','whitelist'/],
      ["new read policy", /CREATE POLICY "swap_orders_group_read"[\s\S]+visibility = 'public'/],
      ["self-test", /L05-10 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L05-16",
    mig: "20260421810000_l05_16_workout_reschedule.sql",
    assertions: [
      ["athlete_requested_date column", /athlete_requested_date\s+date/],
      ["fn_request_reschedule", /fn_request_reschedule/],
      ["fn_resolve_reschedule", /fn_resolve_reschedule/],
      ["coach_response CHECK", /accepted.*rejected|coach_response IS NULL OR coach_response IN/s],
      ["self-test", /L05-16 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L05-17",
    mig: "20260421820000_l05_17_badge_expiration.sql",
    assertions: [
      ["valid_until column", /valid_until timestamptz/],
      ["active view", /CREATE OR REPLACE VIEW public\.active_badge_awards/],
      ["partial index", /CREATE INDEX[\s\S]+idx_badge_awards_active[\s\S]+WHERE valid_until/],
      ["self-test", /L05-17 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
  {
    id: "L18-09",
    mig: "20260421830000_l18_09_audit_event_schema_version.sql",
    assertions: [
      ["event_schema_version column", /event_schema_version int NOT NULL DEFAULT 1/],
      ["event_domain column", /event_domain\s+text NOT NULL DEFAULT ''unknown''/],
      ["dotted CHECK", /action_dotted_chk/],
      ["self-test", /L18-09 self-test PASSED/],
      ["L04-07 marker", /L04-07-OK/],
    ],
  },
];

function main() {
  const failures: string[] = [];
  for (const c of CHECKS) {
    const fp = path.join(MIG, c.mig);
    if (!fs.existsSync(fp)) {
      failures.push(`[${c.id}] migration missing: ${c.mig}`);
      continue;
    }
    const text = fs.readFileSync(fp, "utf8");
    for (const [label, re] of c.assertions) {
      if (!re.test(text)) failures.push(`[${c.id}] ${c.mig}: assertion FAIL — ${label}`);
    }
  }

  if (failures.length > 0) {
    console.error(`[FAIL] ${failures.length} K2 SQL assertion(s) failed:`);
    for (const f of failures) console.error("  - " + f);
    process.exit(1);
  }
  console.log(`[OK] all ${CHECKS.length} K2 SQL fixes verified.`);
}

main();
