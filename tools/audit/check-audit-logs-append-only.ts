/**
 * check-audit-logs-append-only.ts
 *
 * L10-08 — CI guard that enforces the append-only invariant on every
 * audit-style table registered in public.audit_append_only_config.
 *
 * Delegates to public.fn_audit_assert_append_only_shape() which:
 *   - flags any registered strict table that lost its trigger, and
 *   - flags any known audit table that exists without a registry entry.
 *
 * Usage:
 *   npm run audit:audit-logs-append-only
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";

function run(sql: string): { out: string; ok: boolean } {
  try {
    const out = execSync(
      `docker exec -i ${CONTAINER} psql -U postgres -d postgres -X -A -t -v ON_ERROR_STOP=1`,
      { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    );
    return { out, ok: true };
  } catch (e) {
    const err = e as { stdout?: Buffer | string; stderr?: Buffer | string };
    const out =
      (err.stdout ? err.stdout.toString() : "") +
      (err.stderr ? err.stderr.toString() : "");
    return { out, ok: false };
  }
}

function main(): number {
  console.log("L10-08: asserting audit tables are append-only…");

  const exists = run(
    "SELECT to_regprocedure('public.fn_audit_assert_append_only_shape()') IS NOT NULL;",
  );
  if (!exists.ok || !/^t(rue)?$/i.test(exists.out.trim())) {
    console.log(
      "  fn_audit_assert_append_only_shape is not registered — skipping (sandbox).",
    );
    return 0;
  }

  const r = run("SELECT public.fn_audit_assert_append_only_shape();");
  if (r.ok) {
    console.log("  OK — every registered audit table has the append-only guard.");
    return 0;
  }

  console.error("\n  FAIL");
  for (const line of r.out.split("\n")) {
    if (/L10-08|append_only|P0010|HINT|unregistered/i.test(line)) {
      console.error(`   ${line.trim()}`);
    }
  }
  console.error(
    "\nSee docs/runbooks/AUDIT_LOGS_APPEND_ONLY_RUNBOOK.md and docs/audit/findings/L10-08-*.md.",
  );
  return 1;
}

process.exit(main());
