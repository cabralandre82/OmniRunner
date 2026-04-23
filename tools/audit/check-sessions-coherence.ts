/**
 * check-sessions-coherence.ts
 *
 * L08-04 — CI guard calling public.fn_assert_sessions_coherence().
 *
 * Fails if any finalized session (status >= 3) has incoherent
 * (total_distance_m, moving_ms) values that would bypass the
 * chk_sessions_coherence CHECK (e.g., rows predating the constraint that
 * were added NOT VALID and never backfilled).
 *
 * Usage:
 *   npm run audit:sessions-coherence
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
  console.log("L08-04: checking sessions coherence (status>=3)…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_assert_sessions_coherence()') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_assert_sessions_coherence() not registered.\n" +
        "Apply migration 20260421320000_l08_04_sessions_coherence_check.sql first.\n",
    );
    return 1;
  }

  const r = psql("SELECT public.fn_assert_sessions_coherence();", { allowError: true });
  if (!r.ok) {
    console.error("\n  FAIL");
    const snippet = r.out
      .split("\n")
      .filter((line) =>
        /incoherentes|sessions incoerentes|P0010|HINT|reason=|L08-04/i.test(line),
      )
      .slice(0, 50)
      .join("\n");
    console.error(snippet || r.out.slice(0, 2000));
    console.error("\nSee docs/runbooks/SESSIONS_COHERENCE_RUNBOOK.md §3 for the backfill playbook.");
    return 1;
  }

  console.log("  sessions: OK (chk_sessions_coherence satisfied)");
  console.log("\nOK — all finalized sessions are coherent.");
  return 0;
}

process.exit(main());
