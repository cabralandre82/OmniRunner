/**
 * check-pg-stat-statements.ts
 *
 * L19-07 — CI guard for the pg_stat_statements bootstrap migration
 * and the DBA_QUERY_TUNING runbook.
 *
 * Invariants:
 *   1. Migration `20260421450000_l19_07_pg_stat_statements.sql`
 *      installs the extension, creates the view + two helper
 *      functions, and asserts service_role-only grants.
 *   2. View uses security_invoker=on and filters mean_exec_time ≥
 *      100 ms.
 *   3. Both helper functions are SECURITY DEFINER with pinned
 *      search_path = public, pg_catalog.
 *   4. Self-test block asserts extension + view + both functions.
 *   5. Runbook covers monthly review, regression thresholds, reset
 *      policy, breach playbook, and cross-links.
 *
 * Usage: npm run audit:pg-stat-statements
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
  "supabase/migrations/20260421450000_l19_07_pg_stat_statements.sql",
);
const mig = safeRead(migPath, "L19-07 migration present");
if (mig) {
  push(
    "installs pg_stat_statements extension",
    /CREATE EXTENSION IF NOT EXISTS pg_stat_statements/i.test(mig),
  );
  push(
    "creates v_pg_stat_statements_top view",
    /CREATE OR REPLACE VIEW public\.v_pg_stat_statements_top/.test(mig),
  );
  push(
    "view uses security_invoker = on",
    /security_invoker\s*=\s*on/.test(mig),
  );
  push(
    "view filters mean_exec_time >= 100 ms",
    /mean_exec_time\s*>=\s*100/.test(mig),
  );
  push(
    "view ORDER BY total_exec_time DESC",
    /ORDER BY s\.total_exec_time DESC/.test(mig),
  );
  push(
    "view REVOKE from authenticated + anon",
    /REVOKE ALL ON public\.v_pg_stat_statements_top FROM anon/.test(mig) &&
      /REVOKE ALL ON public\.v_pg_stat_statements_top FROM authenticated/.test(mig),
  );
  push(
    "view GRANT SELECT to service_role",
    /GRANT SELECT ON public\.v_pg_stat_statements_top TO service_role/.test(mig),
  );

  push(
    "top helper is SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_pg_stat_statements_top\(p_limit int DEFAULT 20\)[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "top helper pins search_path",
    /fn_pg_stat_statements_top\(p_limit int DEFAULT 20\)[\s\S]{0,600}SET search_path = public, pg_catalog/.test(mig),
  );
  push(
    "top helper GRANT EXECUTE service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_pg_stat_statements_top\(int\) TO service_role/.test(mig),
  );
  push(
    "top helper REVOKE from anon + authenticated",
    /REVOKE ALL ON FUNCTION public\.fn_pg_stat_statements_top\(int\) FROM anon/.test(mig) &&
      /REVOKE ALL ON FUNCTION public\.fn_pg_stat_statements_top\(int\) FROM authenticated/.test(mig),
  );

  push(
    "reset helper is SECURITY DEFINER",
    /CREATE OR REPLACE FUNCTION public\.fn_pg_stat_statements_reset\(\)[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "reset helper pins search_path",
    /fn_pg_stat_statements_reset\(\)[\s\S]{0,600}SET search_path = public, pg_catalog/.test(mig),
  );
  push(
    "reset helper wraps pg_stat_statements_reset()",
    /pg_stat_statements_reset\(\)/.test(mig),
  );
  push(
    "reset helper GRANT EXECUTE service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_pg_stat_statements_reset\(\) TO service_role/.test(mig) &&
      /REVOKE ALL ON FUNCTION public\.fn_pg_stat_statements_reset\(\) FROM anon/.test(mig) &&
      /REVOKE ALL ON FUNCTION public\.fn_pg_stat_statements_reset\(\) FROM authenticated/.test(mig),
  );

  push(
    "self-test: extension presence",
    /pg_extension WHERE extname = 'pg_stat_statements'/.test(mig),
  );
  push(
    "self-test: view presence",
    /pg_views[\s\S]{0,120}v_pg_stat_statements_top/.test(mig),
  );
  push(
    "self-test: top helper SECURITY DEFINER",
    /fn_pg_stat_statements_top[\s\S]{0,160}prosecdef = true/.test(mig),
  );
  push(
    "self-test: reset helper SECURITY DEFINER",
    /fn_pg_stat_statements_reset[\s\S]{0,160}prosecdef = true/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const runbookPath = resolve(ROOT, "docs/runbooks/DBA_QUERY_TUNING.md");
const runbook = safeRead(runbookPath, "DBA_QUERY_TUNING runbook present");
if (runbook) {
  push("runbook declares monthly cadence", /monthly/i.test(runbook));
  push("runbook declares first-Tuesday cadence", /first Tuesday/i.test(runbook));
  push(
    "runbook declares 100 ms mean SLO",
    /100 ms/.test(runbook),
  );
  push(
    "runbook declares 400 ms finance-surface threshold",
    /400 ms/.test(runbook),
  );
  push(
    "runbook declares watch/breach classification",
    /\bwatch\b/i.test(runbook) && /\bbreach\b/i.test(runbook),
  );
  push(
    "runbook covers reset policy",
    /Reset policy/.test(runbook) && /fn_pg_stat_statements_reset/.test(runbook),
  );
  push(
    "runbook has breach playbook",
    /Breach playbook/.test(runbook) && /PagerDuty/.test(runbook),
  );
  push(
    "runbook has review log template",
    /Review log template/.test(runbook),
  );
  push(
    "runbook references migration",
    /20260421450000_l19_07_pg_stat_statements\.sql/.test(runbook),
  );
  push(
    "runbook references audit guard",
    /npm run audit:pg-stat-statements/.test(runbook),
  );
  push(
    "runbook cross-links to finding",
    /L19-07-pg-stat-statements-nao-referenciado-em-tuning\.md/.test(runbook),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L19-07-pg-stat-statements-nao-referenciado-em-tuning.md",
);
const finding = safeRead(findingPath, "L19-07 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421450000_l19_07_pg_stat_statements\.sql/.test(finding),
  );
  push(
    "finding references runbook",
    /DBA_QUERY_TUNING\.md/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} pg_stat_statements checks passed.`);
if (failed > 0) {
  console.error("\nL19-07 invariants broken. See docs/runbooks/DBA_QUERY_TUNING.md.");
  process.exit(1);
}
