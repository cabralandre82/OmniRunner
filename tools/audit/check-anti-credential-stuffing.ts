/**
 * check-anti-credential-stuffing.ts
 *
 * L10-09 — CI guard calling public.fn_login_throttle_assert_shape().
 *
 * Fails (exit 1) if any of the anti-credential-stuffing primitives drift
 * (missing table/function, RLS relaxed, anon has EXECUTE, ...).
 *
 * Usage:
 *   npm run audit:anti-credential-stuffing
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
  console.log("L10-09: checking anti credential stuffing primitives…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_login_throttle_assert_shape()') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_login_throttle_assert_shape() not registered.\n" +
        "Apply migration 20260421340000_l10_09_anti_credential_stuffing.sql first.\n",
    );
    return 1;
  }

  const r = psql("SELECT public.fn_login_throttle_assert_shape();", { allowError: true });
  if (!r.ok) {
    console.error("\n  FAIL");
    const snippet = r.out
      .split("\n")
      .filter((line) =>
        /L10-09|auth_login|fn_login_throttle|P0010|HINT|RLS/i.test(line),
      )
      .slice(0, 20)
      .join("\n");
    console.error(snippet || r.out.slice(0, 2000));
    console.error(
      "\nSee docs/runbooks/ANTI_CREDENTIAL_STUFFING_RUNBOOK.md §3.",
    );
    return 1;
  }

  console.log("  primitives: OK (table + config + 4 helpers + RLS forced)");
  console.log("\nOK — anti credential stuffing primitives are in place.");
  return 0;
}

process.exit(main());
