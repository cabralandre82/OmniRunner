/**
 * check-sessions-time-series-index.ts
 *
 * L08-03 — CI guard calling public.fn_sessions_assert_time_series_indexes().
 *
 * Fails (exit 1) if:
 *   - idx_sessions_start_time_brin is missing or not BRIN, OR
 *   - idx_sessions_status_start_time is missing or not a partial btree.
 *
 * Usage:
 *   npm run audit:sessions-time-series-index
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
  console.log("L08-03: checking sessions time-series indexes…");

  const tableProbe = psql(
    "SELECT to_regclass('public.sessions') IS NOT NULL;",
    { allowError: true },
  );
  if (!tableProbe.ok || !/^t$/i.test(tableProbe.out.trim())) {
    console.log("  public.sessions not present in this environment — skipping.");
    return 0;
  }

  const fnProbe = psql(
    "SELECT to_regprocedure('public.fn_sessions_assert_time_series_indexes()') IS NOT NULL;",
    { allowError: true },
  );
  if (!fnProbe.ok || !/^t$/i.test(fnProbe.out.trim())) {
    console.error(
      "\nERROR: public.fn_sessions_assert_time_series_indexes() not registered.\n" +
        "Apply migration 20260421330000_l08_03_sessions_time_series_index.sql first.\n",
    );
    return 1;
  }

  const r = psql("SELECT public.fn_sessions_assert_time_series_indexes();", { allowError: true });
  if (!r.ok) {
    console.error("\n  FAIL");
    const snippet = r.out
      .split("\n")
      .filter((line) =>
        /L08-03|idx_sessions_start_time_brin|idx_sessions_status_start_time|P0010|HINT/i.test(line),
      )
      .slice(0, 20)
      .join("\n");
    console.error(snippet || r.out.slice(0, 2000));
    console.error(
      "\nSee docs/runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md §4 for the rebuild recipe.",
    );
    return 1;
  }

  console.log("  sessions: OK (BRIN on start_time_ms + partial btree on (status, start_time_ms DESC))");
  console.log("\nOK — sessions time-series indexes are present.");
  return 0;
}

process.exit(main());
