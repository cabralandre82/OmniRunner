/**
 * check-audit-logs-retention.ts
 *
 * L08-08 — CI guard for the audit_logs retention primitives.
 *
 * Fails closed if any of the following drift:
 *
 *   1. Migration is missing or has been renamed.
 *   2. `audit_logs_retention_config` table shape regresses (RLS off,
 *      CHECK loosened outside 30..3650 days, no batch_limit guard).
 *   3. `audit_logs_retention_runs` loses its append-only registration
 *      (would allow the trail to be silently rewritten).
 *   4. The L10-08 trigger function `fn_audit_reject_mutation` loses
 *      the bypass check OR makes the bypass wider than "DELETE with
 *      audit.retention_pass = 'on'" (would open UPDATE/TRUNCATE).
 *   5. Retention helper stops setting the bypass with SET LOCAL /
 *      set_config(..., true) — a session-wide SET would leak across
 *      connections and would be a real incident.
 *   6. Seed config loses one of the 7 canonical audit tables OR the
 *      consent_events row is no longer NULL retention.
 *   7. pg_cron schedules for `audit-logs-retention-daily` and
 *      `audit-logs-retention-next-month` missing.
 *   8. Runbook missing or no longer cross-links the guard + finding.
 *
 * Usage:
 *   npm run audit:audit-logs-retention
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");
const MIGRATION_PATH = resolve(
  REPO_ROOT,
  "supabase/migrations/20260421400000_l08_08_audit_logs_retention.sql",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md",
);
const L10_08_MIGRATION = resolve(
  REPO_ROOT,
  "supabase/migrations/20260421350000_l10_08_audit_logs_append_only.sql",
);
const FINDING_PATH = resolve(
  REPO_ROOT,
  "docs/audit/findings/L08-08-audit-logs-sem-retencao-particionamento.md",
);

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];
function push(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function safeRead(path: string, label: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    push(label, false, `file not found: ${path}`);
    return null;
  }
}

const mig = safeRead(MIGRATION_PATH, "migration present");
if (mig) {
  push("migration present", true);

  // 1. Config table
  push(
    "audit_logs_retention_config declared",
    /CREATE TABLE IF NOT EXISTS public\.audit_logs_retention_config/.test(mig),
  );
  push(
    "retention_days CHECK clamps 30..3650 (with NULL allowed)",
    /retention_days IS NULL[\s\S]+?BETWEEN 30 AND 3650/.test(mig),
  );
  push(
    "batch_limit CHECK clamps 100..100000",
    /batch_limit[\s\S]+?BETWEEN 100 AND 100000/.test(mig),
  );
  push(
    "max_iterations CHECK clamps 1..200",
    /max_iterations[\s\S]+?BETWEEN 1 AND 200/.test(mig),
  );
  push(
    "config RLS forced",
    /audit_logs_retention_config FORCE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "config policy is service_role only",
    /CREATE POLICY audit_logs_retention_config_service_rw[\s\S]+?TO service_role/.test(
      mig,
    ),
  );

  // 2. Runs table + append-only registration
  push(
    "audit_logs_retention_runs declared",
    /CREATE TABLE IF NOT EXISTS public\.audit_logs_retention_runs/.test(mig),
  );
  push(
    "runs status CHECK whitelist present (ok / skipped_* / error)",
    /status IN \(\s*'ok'[\s\S]+?'skipped_disabled'[\s\S]+?'skipped_no_retention'[\s\S]+?'skipped_no_table'[\s\S]+?'skipped_no_column'[\s\S]+?'skipped_locked'[\s\S]+?'error'/.test(
      mig,
    ),
  );
  push(
    "runs RLS forced",
    /audit_logs_retention_runs FORCE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "runs table installed in append-only registry",
    /fn_audit_install_append_only_guard\(\s*'public',\s*'audit_logs_retention_runs'/.test(
      mig,
    ),
  );
  push(
    "runs table added to fn_audit_assert_append_only_shape v_known",
    /v_known := ARRAY\[[\s\S]+?'audit_logs_retention_runs'/.test(mig),
  );

  // 3. Bypass trigger update
  push(
    "fn_audit_reject_mutation checks audit.retention_pass GUC",
    /current_setting\('audit\.retention_pass', true\)/.test(mig),
  );
  push(
    "bypass only applies to DELETE",
    /v_op = 'DELETE' AND v_bypass = 'on'/.test(mig),
  );
  const updateBlockedStill = /UPDATE blocked on append-only audit table[\s\S]+?append_only_update_blocked/.test(
    mig,
  );
  push("UPDATE still blocked even with bypass", updateBlockedStill);
  const truncateBlockedStill = /TRUNCATE blocked on append-only audit table[\s\S]+?append_only_truncate_blocked/.test(
    mig,
  );
  push("TRUNCATE still blocked even with bypass", truncateBlockedStill);
  // Strict literal: only 'on' (not 'true', not '1')
  push(
    "bypass accepts only the literal 'on'",
    /v_bypass = 'on'/.test(mig) && !/v_bypass IN \(/.test(mig),
  );

  // 4. Retention helper
  push(
    "fn_audit_retention_delete_batch defined",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_retention_delete_batch/.test(
      mig,
    ),
  );
  push(
    "helper is SECURITY DEFINER",
    /fn_audit_retention_delete_batch[\s\S]+?SECURITY DEFINER/.test(mig),
  );
  push(
    "helper SETs search_path explicitly",
    /fn_audit_retention_delete_batch[\s\S]+?SET search_path = public, pg_catalog, pg_temp/.test(
      mig,
    ),
  );
  push(
    "helper sets retention_pass via set_config(..., true) (txn-local only)",
    /set_config\('audit\.retention_pass', 'on', true\)/.test(mig),
  );
  // A session-wide set_config(..., false) would leak the bypass beyond the txn.
  push(
    "helper does NOT use session-wide set_config(..., false)",
    !/set_config\('audit\.retention_pass'[^)]*, false\)/.test(mig),
  );
  push(
    "helper batches deletes with LIMIT and a bounded iteration loop",
    /LIMIT %s/.test(mig) && /max_iterations/.test(mig),
  );
  push(
    "helper always writes to audit_logs_retention_runs (ok + errors)",
    (mig.match(/INSERT INTO public\.audit_logs_retention_runs/g) ?? []).length >=
      5,
  );
  push(
    "helper grants EXECUTE to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_audit_retention_delete_batch\(text, text\) TO service_role/.test(
      mig,
    ),
  );

  // 5. Dispatcher
  push(
    "fn_audit_retention_run_all defined",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_retention_run_all/.test(mig),
  );
  push(
    "dispatcher uses pg_try_advisory_xact_lock",
    /pg_try_advisory_xact_lock\(\s*\d+::bigint\)/.test(mig),
  );
  push(
    "dispatcher tolerates per-table failures",
    /EXCEPTION WHEN OTHERS THEN[\s\S]+?INSERT INTO public\.audit_logs_retention_runs[\s\S]+?'error'/.test(
      mig,
    ),
  );

  // 6. Partition helpers
  push(
    "fn_audit_ensure_monthly_partition defined",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_ensure_monthly_partition/.test(
      mig,
    ),
  );
  push(
    "partition helper rejects non-month-start dates",
    /date_trunc\('month', p_month_start\)::date <> p_month_start/.test(mig),
  );
  push(
    "partition helper returns skipped_not_partitioned for heap tables",
    /skipped_not_partitioned/.test(mig),
  );
  push(
    "partition helper requires RANGE strategy",
    /v_partstrat <> 'r'/.test(mig),
  );

  // 7. Seed config invariants
  push(
    "seeds 'public.audit_logs' with 730 days",
    /'public', 'audit_logs',\s*730,\s*true/.test(mig),
  );
  push(
    "seeds 'public.portal_audit_log' with 730 days",
    /'public', 'portal_audit_log',\s*730,\s*true/.test(mig),
  );
  push(
    "seeds 'public.cron_edge_retry_attempts' with 90 days",
    /'public', 'cron_edge_retry_attempts',\s*90,\s*true/.test(mig),
  );
  push(
    "seeds 'public.wallet_drift_events' with 365 days",
    /'public', 'wallet_drift_events',\s*365,\s*true/.test(mig),
  );
  push(
    "seeds 'public.custody_daily_cap_changes' with 1825 days",
    /'public', 'custody_daily_cap_changes',\s*1825,\s*true/.test(mig),
  );
  push(
    "seeds 'public.coin_ledger_pii_redactions' with 1825 days",
    /'public', 'coin_ledger_pii_redactions',\s*1825,\s*true/.test(mig),
  );
  push(
    "seeds 'public.consent_events' with NULL retention (keep forever)",
    /'public', 'consent_events',\s*NULL,\s*true/.test(mig),
  );

  // 8. cron schedules
  push(
    "schedules 'audit-logs-retention-daily'",
    /cron\.schedule\(\s*'audit-logs-retention-daily'/.test(mig),
  );
  push(
    "schedules 'audit-logs-retention-next-month'",
    /cron\.schedule\(\s*'audit-logs-retention-next-month'/.test(mig),
  );
  push(
    "daily cron invokes fn_audit_retention_run_all",
    /'audit-logs-retention-daily'[\s\S]+?fn_audit_retention_run_all/.test(mig),
  );
  push(
    "monthly cron invokes fn_audit_retention_ensure_next_month_all",
    /'audit-logs-retention-next-month'[\s\S]+?fn_audit_retention_ensure_next_month_all/.test(
      mig,
    ),
  );

  // 9. Assert helper
  push(
    "fn_audit_retention_assert_shape defined",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_retention_assert_shape/.test(
      mig,
    ),
  );
  push(
    "assert function validates consent_events keep-forever invariant",
    /consent_events[\s\S]+?retention_days IS NULL[\s\S]+?LGPD Art\. 8/.test(mig),
  );

  // 10. Self-test is present and exercises critical invariants
  push(
    "self-test block present",
    /DO \$L08_08_selftest\$[\s\S]+?\$L08_08_selftest\$;/.test(mig),
  );
  push(
    "self-test verifies UPDATE is never bypassable",
    /UPDATE on audit_logs_retention_runs must NEVER be bypassable/.test(mig),
  );
  push(
    "self-test verifies DELETE without bypass is blocked",
    /DELETE on audit_logs_retention_runs should have been blocked/.test(mig),
  );
}

// 11. Runbook presence
const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links the CI guard",
    /npm run audit:audit-logs-retention/.test(runbook),
  );
  push(
    "runbook cross-links the L08-08 finding",
    /L08-08/.test(runbook),
  );
  push(
    "runbook references the L10-08 trigger + bypass contract",
    /L10-08/.test(runbook) && /audit\.retention_pass/.test(runbook),
  );
  push(
    "runbook documents LGPD 'keep forever' for consent_events",
    /consent_events[\s\S]+?LGPD/.test(runbook),
  );
}

// 12. Finding cross-link sanity
const finding = safeRead(FINDING_PATH, "finding present");
if (finding) {
  push(
    "finding references the runbook",
    /AUDIT_LOGS_RETENTION_RUNBOOK\.md/.test(finding) ||
      /docs\/runbooks\/AUDIT_LOGS_RETENTION_RUNBOOK/.test(finding),
  );
}

// 13. L10-08 sibling migration still exists (we modified its function).
const l1008 = safeRead(L10_08_MIGRATION, "L10-08 sibling migration present");
if (l1008) {
  push(
    "L10-08 migration still declares the baseline trigger",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_reject_mutation/.test(l1008),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) {
    console.log(`[OK]   ${r.name}`);
  } else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}

console.log(
  `\n${results.length - failed}/${results.length} audit-logs-retention checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL08-08 invariants broken. See docs/runbooks/AUDIT_LOGS_RETENTION_RUNBOOK.md.",
  );
  process.exit(1);
}
