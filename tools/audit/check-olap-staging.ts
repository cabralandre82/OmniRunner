/**
 * check-olap-staging.ts
 *
 * L08-06 — CI guard for the OLAP staging layer.
 *
 * Fails closed if any of the following drift:
 *
 *   1. Migration is missing or has been renamed.
 *   2. `public_olap` schema / grant posture regresses
 *      (anon/authenticated/PUBLIC getting any access would
 *      expose platform-wide aggregates).
 *   3. `mv_refresh_config` table shape regresses
 *      (RLS off, CHECK clamps loosened).
 *   4. `mv_refresh_runs` loses append-only registration.
 *   5. Materialized views missing OR lose their UNIQUE INDEX
 *      (which silently breaks REFRESH CONCURRENTLY and degrades
 *      refresh into a blocking lock — exactly what L08-06 prevents).
 *   6. `fn_refresh_mv` stops being SECURITY DEFINER OR stops
 *      setting `statement_timeout` locally OR stops using an
 *      advisory lock per MV.
 *   7. Dispatcher loses the global advisory lock or per-MV
 *      exception guard.
 *   8. pg_cron schedule `olap-refresh-all` missing.
 *   9. Runbook missing or no longer cross-links guard + finding.
 *  10. Finding frontmatter missing the runbook cross-link.
 *
 * Usage:
 *   npm run audit:olap-staging
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");
const MIGRATION_PATH = resolve(
  REPO_ROOT,
  "supabase/migrations/20260421410000_l08_06_olap_staging.sql",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/OLAP_STAGING_RUNBOOK.md",
);
const FINDING_PATH = resolve(
  REPO_ROOT,
  "docs/audit/findings/L08-06-sem-staging-de-data-warehouse-queries-olap-contra.md",
);
const L10_08_MIGRATION = resolve(
  REPO_ROOT,
  "supabase/migrations/20260421350000_l10_08_audit_logs_append_only.sql",
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

  // 1. Schema + grants
  push(
    "schema public_olap declared",
    /CREATE SCHEMA IF NOT EXISTS public_olap/.test(mig),
  );
  push(
    "schema revokes PUBLIC usage",
    /REVOKE ALL ON SCHEMA public_olap FROM PUBLIC/.test(mig),
  );
  push(
    "schema revokes anon usage",
    /REVOKE ALL ON SCHEMA public_olap FROM anon/.test(mig),
  );
  push(
    "schema revokes authenticated usage",
    /REVOKE ALL ON SCHEMA public_olap FROM authenticated/.test(mig),
  );
  push(
    "schema grants USAGE to service_role only",
    /GRANT USAGE ON SCHEMA public_olap TO service_role/.test(mig),
  );
  push(
    "tables revoke SELECT from anon",
    /REVOKE ALL ON ALL TABLES IN SCHEMA public_olap FROM anon/.test(mig),
  );
  push(
    "tables revoke SELECT from authenticated",
    /REVOKE ALL ON ALL TABLES IN SCHEMA public_olap FROM authenticated/.test(
      mig,
    ),
  );
  push(
    "default privileges revoke from authenticated",
    /ALTER DEFAULT PRIVILEGES IN SCHEMA public_olap[\s\S]+?REVOKE ALL ON TABLES FROM authenticated/.test(
      mig,
    ),
  );

  // 2. Config table
  push(
    "mv_refresh_config declared",
    /CREATE TABLE IF NOT EXISTS public_olap\.mv_refresh_config/.test(mig),
  );
  push(
    "refresh_interval_seconds CHECK clamps 60..86400",
    /refresh_interval_seconds[\s\S]+?BETWEEN 60\s+AND 86400/.test(mig),
  );
  push(
    "statement_timeout_ms CHECK clamps 1000..600000",
    /statement_timeout_ms[\s\S]+?BETWEEN 1000\s+AND 600000/.test(mig),
  );
  push(
    "config RLS forced",
    /mv_refresh_config FORCE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "config policy is service_role only",
    /CREATE POLICY mv_refresh_config_service_rw[\s\S]+?TO service_role/.test(
      mig,
    ),
  );
  push(
    "config has updated_at auto-touch trigger",
    /trg_mv_refresh_config_touch/.test(mig) &&
      /fn_mv_refresh_config_touch/.test(mig),
  );

  // 3. Runs table + append-only registration
  push(
    "mv_refresh_runs declared",
    /CREATE TABLE IF NOT EXISTS public_olap\.mv_refresh_runs/.test(mig),
  );
  push(
    "runs status CHECK whitelist present (ok / skipped_* / error)",
    /status IN \(\s*'ok'[\s\S]+?'skipped_disabled'[\s\S]+?'skipped_no_mv'[\s\S]+?'skipped_no_config'[\s\S]+?'skipped_locked'[\s\S]+?'skipped_too_soon'[\s\S]+?'error'/.test(
      mig,
    ),
  );
  push(
    "runs RLS forced",
    /mv_refresh_runs FORCE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "runs table installed in L10-08 append-only registry",
    /fn_audit_install_append_only_guard\(\s*'public_olap',\s*'mv_refresh_runs'/.test(
      mig,
    ),
  );
  push(
    "runs indexed on (mv_name, started_at DESC)",
    /idx_mv_refresh_runs_mv_started[\s\S]+?\(mv_name, started_at DESC\)/.test(
      mig,
    ),
  );

  // 4. Materialized Views
  const mvs = [
    "mv_sessions_completed_daily",
    "mv_coin_ledger_daily_by_reason",
    "mv_custody_accounts_snapshot",
  ];
  for (const mv of mvs) {
    push(
      `${mv} declared`,
      new RegExp(`CREATE MATERIALIZED VIEW IF NOT EXISTS public_olap\\.${mv}`).test(
        mig,
      ),
    );
    push(
      `${mv} has UNIQUE INDEX (required for REFRESH CONCURRENTLY)`,
      new RegExp(
        `CREATE UNIQUE INDEX IF NOT EXISTS ${mv}_pk\\s+ON public_olap\\.${mv}`,
      ).test(mig),
    );
    push(
      `${mv} created WITH NO DATA (idempotent migration)`,
      new RegExp(
        `public_olap\\.${mv}[\\s\\S]+?WITH NO DATA`,
      ).test(mig),
    );
    push(
      `${mv} seeded in mv_refresh_config`,
      new RegExp(`'${mv}',\\s*true,\\s*\\d+`).test(mig),
    );
  }

  // Specific domain rules for each MV
  push(
    "mv_sessions_completed_daily filters status >= 3",
    /mv_sessions_completed_daily[\s\S]+?WHERE status >= 3/.test(mig),
  );
  push(
    "mv_coin_ledger_daily_by_reason groups by (day, reason)",
    /mv_coin_ledger_daily_by_reason[\s\S]+?GROUP BY 1, 2, 3/.test(mig),
  );
  push(
    "mv_custody_accounts_snapshot reads from custody_accounts",
    /mv_custody_accounts_snapshot[\s\S]+?FROM public\.custody_accounts/.test(
      mig,
    ),
  );

  // 5. Refresh helper
  push(
    "fn_refresh_mv defined",
    /CREATE OR REPLACE FUNCTION public_olap\.fn_refresh_mv/.test(mig),
  );
  push(
    "fn_refresh_mv is SECURITY DEFINER",
    /fn_refresh_mv[\s\S]+?SECURITY DEFINER/.test(mig),
  );
  push(
    "fn_refresh_mv SETs search_path explicitly",
    /fn_refresh_mv[\s\S]+?SET search_path = public_olap, public, pg_catalog, pg_temp/.test(
      mig,
    ),
  );
  push(
    "fn_refresh_mv sets statement_timeout txn-locally",
    /set_config\(\s*'statement_timeout',\s*[\s\S]+?,\s*true\s*\)/.test(mig),
  );
  push(
    "fn_refresh_mv uses per-MV advisory lock",
    /pg_try_advisory_xact_lock\(\s*v_lock_key\s*\)/.test(mig),
  );
  push(
    "fn_refresh_mv honours refresh_interval_seconds (too-soon guard)",
    /skipped_too_soon/.test(mig) &&
      /refresh_interval_seconds/.test(mig) &&
      /make_interval\(\s*secs => v_cfg\.refresh_interval_seconds\s*\)/.test(
        mig,
      ),
  );
  push(
    "fn_refresh_mv detects ispopulated=false and avoids CONCURRENTLY first run",
    /pg_matviews[\s\S]+?ispopulated[\s\S]+?IF v_cfg\.concurrent AND v_is_populated/.test(
      mig,
    ),
  );
  push(
    "fn_refresh_mv always writes to mv_refresh_runs",
    (mig.match(/INSERT INTO public_olap\.mv_refresh_runs/g) ?? []).length >= 5,
  );
  push(
    "fn_refresh_mv grants EXECUTE to service_role only",
    /GRANT EXECUTE ON FUNCTION public_olap\.fn_refresh_mv\(text\) TO service_role/.test(
      mig,
    ),
  );
  push(
    "fn_refresh_mv revokes EXECUTE from authenticated",
    /REVOKE ALL ON FUNCTION public_olap\.fn_refresh_mv\(text\) FROM authenticated/.test(
      mig,
    ),
  );

  // 6. Dispatcher
  push(
    "fn_refresh_all defined",
    /CREATE OR REPLACE FUNCTION public_olap\.fn_refresh_all/.test(mig),
  );
  push(
    "fn_refresh_all is SECURITY DEFINER",
    /fn_refresh_all[\s\S]+?SECURITY DEFINER/.test(mig),
  );
  push(
    "dispatcher uses global advisory lock",
    /pg_try_advisory_xact_lock\([\s\S]+?'olap:refresh_all'/.test(mig),
  );
  push(
    "dispatcher iterates only enabled configs",
    /FROM public_olap\.mv_refresh_config[\s\S]+?WHERE enabled = true/.test(
      mig,
    ),
  );
  push(
    "dispatcher tolerates per-MV failures",
    /EXCEPTION WHEN OTHERS THEN[\s\S]+?INSERT INTO public_olap\.mv_refresh_runs[\s\S]+?'error'/.test(
      mig,
    ),
  );

  // 7. Assert helper
  push(
    "fn_olap_assert_shape defined",
    /CREATE OR REPLACE FUNCTION public_olap\.fn_olap_assert_shape/.test(mig),
  );
  push(
    "assert helper lists canonical MV set",
    /v_known := ARRAY\[[\s\S]+?'mv_sessions_completed_daily'[\s\S]+?'mv_coin_ledger_daily_by_reason'[\s\S]+?'mv_custody_accounts_snapshot'/.test(
      mig,
    ),
  );
  push(
    "assert helper verifies UNIQUE INDEX per MV",
    /CREATE UNIQUE INDEX[\s\S]+?v_no_idx/.test(mig),
  );
  push(
    "assert helper verifies append-only registration",
    /audit_append_only_config[\s\S]+?mv_refresh_runs/.test(mig),
  );

  // 8. Seed config
  push(
    "seeds 'mv_sessions_completed_daily'",
    /'mv_sessions_completed_daily',\s*true,\s*900,\s*30000/.test(mig),
  );
  push(
    "seeds 'mv_coin_ledger_daily_by_reason' with higher timeout (45s)",
    /'mv_coin_ledger_daily_by_reason',\s*true,\s*900,\s*45000/.test(mig),
  );
  push(
    "seeds 'mv_custody_accounts_snapshot' with tight timeout (15s)",
    /'mv_custody_accounts_snapshot',\s*true,\s*900,\s*15000/.test(mig),
  );

  // 9. pg_cron schedule
  push(
    "schedules 'olap-refresh-all'",
    /cron\.schedule\(\s*'olap-refresh-all'/.test(mig),
  );
  push(
    "olap-refresh-all runs every 15 minutes",
    /'olap-refresh-all',\s*'\*\/15 \* \* \* \*'/.test(mig),
  );
  push(
    "olap-refresh-all invokes fn_refresh_all",
    /'olap-refresh-all'[\s\S]+?public_olap\.fn_refresh_all/.test(mig),
  );

  // 10. Self-test
  push(
    "self-test block present",
    /DO \$L08_06_selftest\$[\s\S]+?\$L08_06_selftest\$;/.test(mig),
  );
  push(
    "self-test verifies unknown MV → skipped_no_config",
    /unknown mv should yield skipped_no_config/.test(mig),
  );
  push(
    "self-test verifies too-soon guard",
    /second immediate refresh should be skipped_too_soon/.test(mig),
  );
  push(
    "self-test verifies append-only DELETE is blocked",
    /DELETE on mv_refresh_runs should be blocked/.test(mig),
  );
  push(
    "self-test runs fn_olap_assert_shape",
    /PERFORM public_olap\.fn_olap_assert_shape\(\)/.test(mig),
  );
}

// 11. Runbook presence
const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links the CI guard",
    /npm run audit:olap-staging/.test(runbook),
  );
  push(
    "runbook cross-links the L08-06 finding",
    /L08-06/.test(runbook),
  );
  push(
    "runbook documents service_role-only grant posture",
    /service_role/.test(runbook) &&
      /(authenticated|anon)/.test(runbook),
  );
  push(
    "runbook documents the 15-min cron cadence",
    /(15.min|\*\/15|olap-refresh-all)/.test(runbook),
  );
  push(
    "runbook documents the refresh_interval_seconds too-soon guard",
    /refresh_interval_seconds|too.soon/.test(runbook),
  );
  push(
    "runbook documents CONCURRENTLY vs first-run non-concurrent",
    /CONCURRENTLY/.test(runbook),
  );
  push(
    "runbook references L10-08 append-only protection",
    /L10-08/.test(runbook),
  );
  push(
    "runbook names the three seed MVs",
    /mv_sessions_completed_daily/.test(runbook) &&
      /mv_coin_ledger_daily_by_reason/.test(runbook) &&
      /mv_custody_accounts_snapshot/.test(runbook),
  );
}

// 12. Finding cross-link sanity
const finding = safeRead(FINDING_PATH, "finding present");
if (finding) {
  push(
    "finding references the runbook",
    /OLAP_STAGING_RUNBOOK\.md/.test(finding) ||
      /docs\/runbooks\/OLAP_STAGING_RUNBOOK/.test(finding),
  );
}

// 13. L10-08 sibling still shipped (we depend on its installer)
const l1008 = safeRead(L10_08_MIGRATION, "L10-08 sibling migration present");
if (l1008) {
  push(
    "L10-08 installer still declared",
    /CREATE OR REPLACE FUNCTION public\.fn_audit_install_append_only_guard/.test(
      l1008,
    ),
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
  `\n${results.length - failed}/${results.length} olap-staging checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL08-06 invariants broken. See docs/runbooks/OLAP_STAGING_RUNBOOK.md.",
  );
  process.exit(1);
}
