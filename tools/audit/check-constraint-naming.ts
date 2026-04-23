/**
 * check-constraint-naming.ts
 *
 * L19-08 — CI guard that flags CHECK constraints whose name doesn't match
 * one of the two accepted patterns:
 *   (A) <table>_<col>_check   — Postgres auto-generated default (informativo)
 *   (B) chk_<table>_<rule>    — convenção ad-hoc explícita
 *
 * Everything else (e.g., historical ad-hoc names like `different_groups` on
 * clearing_settlements, or `peg_1_to_1` on custody_accounts) is flagged and
 * must be renamed via ALTER TABLE … RENAME CONSTRAINT.
 *
 * Scope: financial-critical tables (same set as L19-04 duplicate-indexes).
 *
 * Usage:
 *   npm run audit:constraint-naming
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

const SCOPE: Array<{ schema: string; tables: string[] }> = [
  {
    schema: "public",
    tables: [
      "coin_ledger",
      "coin_ledger_idempotency",
      "clearing_settlements",
      "clearing_events",
      "custody_deposits",
      "custody_withdrawals",
      "custody_accounts",
      "platform_revenue",
      "platform_fee_config",
      "billing_purchases",
      "billing_auto_topup_settings",
      "wallets",
      "xp_transactions",
      "swap_orders",
      "consent_events",
      "consent_policy_versions",
    ],
  },
];

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

function toPgTextArrayLit(items: string[]): string {
  const safe = items.map((s) => s.replace(/'/g, "''"));
  return `ARRAY[${safe.map((s) => `'${s}'`).join(", ")}]::text[]`;
}

function main(): number {
  console.log("L19-08: checking CHECK constraint naming on financial tables…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_assert_check_constraints_standardized(text[],text[])') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_assert_check_constraints_standardized(text[],text[]) is not registered.\n" +
        "Apply migration 20260421290000_l19_08_check_constraint_naming.sql first.\n",
    );
    return 1;
  }

  let hadFailure = false;

  for (const { schema, tables } of SCOPE) {
    const sql = `
      DO $$
      BEGIN
        PERFORM public.fn_assert_check_constraints_standardized(
          p_schemas => ARRAY['${schema}']::text[],
          p_tables  => ${toPgTextArrayLit(tables)}
        );
      END $$;
    `;
    const r = psql(sql, { allowError: true });
    if (r.ok) {
      console.log(`  ${schema}: OK (${tables.length} tables)`);
    } else {
      hadFailure = true;
      console.error(`\n  ${schema}: FAIL`);
      const snippet = r.out
        .split("\n")
        .filter(
          (line) =>
            /fora da convenção|sugerido chk_|ALTER TABLE|L19-08|P0010|HINT/i.test(line),
        )
        .slice(0, 50)
        .join("\n");
      console.error(snippet || r.out.slice(0, 2000));
    }
  }

  if (hadFailure) {
    console.error(
      "\nSee docs/runbooks/DB_CHECK_CONSTRAINT_NAMING_RUNBOOK.md §3–4 for " +
        "the naming convention and rename procedure.",
    );
    return 1;
  }

  console.log("\nOK — all CHECK constraints follow naming convention.");
  return 0;
}

process.exit(main());
