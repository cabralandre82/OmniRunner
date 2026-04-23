/**
 * check-duplicate-indexes.ts
 *
 * L19-04 — CI guard that fails if `public.fn_assert_no_duplicate_indexes`
 * finds any redundant plain btree indexes on the financial-critical tables.
 *
 * Why this exists:
 *   Ad-hoc CREATE INDEX landed across 2 years of migrations produced drift
 *   (idx_coin_ledger_user_created vs idx_ledger_user on same (user_id, created_at)
 *    semantics). Each redundant index costs ~5–20 % of INSERT WAL and blocks
 *    autovacuum when contention is high. This script short-circuits the CI
 *    before the migration lands.
 *
 * What it checks:
 *   For each schema/table listed below, invoke
 *     SELECT public.fn_assert_no_duplicate_indexes(p_schemas, p_tables);
 *   which raises P0010 with a structured list if any duplicates exist.
 *
 * Requirements:
 *   - Docker container `supabase_db_project-running` running with the migration
 *     20260421280000_l19_04_dedupe_ledger_indexes.sql applied.
 *   - Override via env: SUPABASE_DB_CONTAINER / SUPABASE_DB_USER / SUPABASE_DB_NAME.
 *
 * Usage:
 *   npm run audit:duplicate-indexes
 *
 * Exit 0 = clean, exit 1 = duplicates found OR function missing.
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

/**
 * Tables covered. Add here to expand coverage; the function is schema-aware.
 *
 * The set is intentionally conservative: tables that (a) have multiple
 * contributors adding indexes over time, and (b) are in the financial hot path.
 */
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
      "billing_purchases",
      "billing_auto_topup_settings",
      "wallets",
      "xp_transactions",
      "sessions",
      "audit_logs",
      "portal_audit_log",
      "notification_log",
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
  console.log("L19-04: checking duplicate indexes on financial-critical tables…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_assert_no_duplicate_indexes(text[],text[])') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_assert_no_duplicate_indexes(text[],text[]) is not registered.\n" +
        "Apply migration 20260421280000_l19_04_dedupe_ledger_indexes.sql first.\n",
    );
    return 1;
  }

  let hadFailure = false;

  for (const { schema, tables } of SCOPE) {
    const sql = `
      DO $$
      BEGIN
        PERFORM public.fn_assert_no_duplicate_indexes(
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
            /L19-04|índices duplicados|redundante|prefix_overlap|exact_duplicate|P0010|HINT/i.test(
              line,
            ),
        )
        .slice(0, 50)
        .join("\n");
      console.error(snippet || r.out.slice(0, 2000));
    }
  }

  if (hadFailure) {
    console.error(
      "\nSee docs/runbooks/LEDGER_INDEX_NAMING_RUNBOOK.md §3–4 for " +
        "how to resolve duplicates (merge vs differentiate via WHERE/INCLUDE vs drop).",
    );
    return 1;
  }

  console.log("\nOK — no duplicate indexes on any covered financial tables.");
  return 0;
}

process.exit(main());
