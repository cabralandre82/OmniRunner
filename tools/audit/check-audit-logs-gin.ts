/**
 * check-audit-logs-gin.ts
 *
 * L19-06 — CI guard that ensures public.audit_logs.metadata (jsonb) has a
 * GIN(metadata jsonb_path_ops) index registered, IF the table exists.
 *
 * When the table is absent in a sandbox (normal for local dev), this is a
 * no-op that returns exit code 0. Production CI against a reference schema
 * with audit_logs will flag missing/dropped indexes.
 *
 * Usage:
 *   npm run audit:audit-logs-gin
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

function psql(sql: string, opts: { allowError?: boolean } = {}): { out: string; ok: boolean } {
  try {
    const out = execSync(
      `docker exec -i ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At`,
      { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    ).trim();
    return { out, ok: true };
  } catch (e) {
    if (opts.allowError) {
      const err = e as { stderr?: string | Buffer; message?: string };
      return {
        out:
          (typeof err.stderr === "string" ? err.stderr : err.stderr?.toString?.() ?? "") +
          (err.message ?? ""),
        ok: false,
      };
    }
    throw e;
  }
}

function main(): number {
  console.log("L19-06: checking public.audit_logs GIN index on metadata…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_audit_logs_assert_metadata_gin()') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_audit_logs_assert_metadata_gin() is not registered.\n" +
        "Apply migration 20260421300000_l19_06_audit_logs_metadata_gin.sql first.\n",
    );
    return 1;
  }

  const hasTable = psql(
    "SELECT to_regclass('public.audit_logs') IS NOT NULL;",
    { allowError: true },
  );
  const tableExists = hasTable.ok && /^t$/i.test(hasTable.out.trim());

  if (!tableExists) {
    console.log("  public.audit_logs absent in this database → no-op (exit 0).");
    console.log("\nOK — no audit_logs table to guard.");
    return 0;
  }

  const r = psql(
    "SELECT public.fn_audit_logs_assert_metadata_gin();",
    { allowError: true },
  );
  if (!r.ok) {
    console.error("\n  FAIL");
    const snippet = r.out
      .split("\n")
      .filter(
        (line) =>
          /idx_audit_logs_metadata_gin|P0010|HINT|L19-06|CREATE INDEX/i.test(line),
      )
      .slice(0, 20)
      .join("\n");
    console.error(snippet || r.out.slice(0, 2000));
    console.error(
      "\nSee docs/runbooks/AUDIT_LOGS_METADATA_GIN_RUNBOOK.md for the " +
        "playbook to add the index in production (CONCURRENTLY).",
    );
    return 1;
  }

  console.log("  public.audit_logs: OK (GIN index on metadata present)");
  console.log("\nOK — audit_logs metadata GIN index is present.");
  return 0;
}

process.exit(main());
