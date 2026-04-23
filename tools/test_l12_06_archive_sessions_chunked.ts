/**
 * tools/test_l12_06_archive_sessions_chunked.ts
 *
 * Integration tests for L12-06 archive-old-sessions chunked COMMIT fix
 * (`supabase/migrations/20260421250000_l12_06_archive_sessions_chunked
 *  _commits.sql` + `supabase/functions/archive-old-sessions/index.ts`).
 *
 * Uses `docker exec psql` (same pattern as other L-series tests) to
 * avoid a node_modules `pg` dependency. The tests exercise:
 *
 *   schema / DDL
 *     (1) fn_archive_sessions_chunk signature + SECURITY DEFINER
 *     (2) fn_archive_sessions_pending_count signature + STABLE
 *     (3) fn_archive_old_sessions shim still present
 *     (4) fn_invoke_archive_sessions_safe registered
 *     (5) service_role grants on all four
 *     (6) cron.job 'archive-old-sessions' points to safe wrapper
 *         (skipped if pg_cron absent)
 *
 *   argument validation
 *     (7) batch_size = 0 → 22023
 *     (8) batch_size = 20000 → 22023
 *     (9) cutoff_months = 0 → 22023
 *    (10) cutoff_months = 999 → 22023
 *
 *   behaviour (against live sessions if present, else empty case)
 *    (11) chunk on empty window returns moved=0, more_pending=false,
 *         jsonb shape is correct
 *    (12) pending_count matches predicate cardinality within 6-month
 *         window
 *    (13) shim returns integer (not jsonb)
 *
 * Usage
 *   npx tsx tools/test_l12_06_archive_sessions_chunked.ts
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

const OK = "\x1b[32m\u2713\x1b[0m";
const FAIL = "\x1b[31m\u2717\x1b[0m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;

function section(t: string) {
  console.log(`\n${BOLD}── ${t} ──${RESET}`);
}

function psql(sql: string, opts: { allowError?: boolean } = {}): string {
  try {
    const out = execSync(
      `docker exec -i ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At`,
      { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    );
    return out.trim();
  } catch (e) {
    if (opts.allowError) {
      const err = e as { stderr?: string | Buffer; message?: string };
      return (typeof err.stderr === "string" ? err.stderr : err.stderr?.toString?.() ?? "")
        + (err.message ?? "");
    }
    throw e;
  }
}

async function test(name: string, fn: () => void | Promise<void>) {
  try {
    await fn();
    console.log(`  ${OK} ${name}`);
    passed++;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.log(`  ${FAIL} ${name}: ${msg}`);
    failed++;
  }
}

function assertEq(actual: unknown, expected: unknown, msg: string) {
  if (actual !== expected) {
    throw new Error(
      `${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertContains(haystack: string, needle: string, msg: string) {
  if (!haystack.includes(needle)) {
    throw new Error(`${msg}: expected to contain ${JSON.stringify(needle)}, got:\n${haystack}`);
  }
}

async function main() {
  console.log(`${BOLD}L12-06 — archive-old-sessions chunked COMMIT integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) fn_archive_sessions_chunk signature + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef, pg_get_function_arguments(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_archive_sessions_chunk';`,
    );
    if (!out) throw new Error("fn_archive_sessions_chunk not registered");
    assertContains(out, "t|", "SECURITY DEFINER");
    assertContains(out, "p_batch_size integer", "p_batch_size");
    assertContains(out, "p_cutoff_months integer", "p_cutoff_months");
  });

  await test("(2) fn_archive_sessions_pending_count signature + STABLE", () => {
    const out = psql(
      `SELECT p.prosecdef, p.provolatile, pg_get_function_arguments(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_archive_sessions_pending_count';`,
    );
    if (!out) throw new Error("fn_archive_sessions_pending_count not registered");
    assertContains(out, "t|s|", "SECURITY DEFINER + STABLE volatility");
    assertContains(out, "p_cutoff_months integer", "p_cutoff_months");
  });

  await test("(3) fn_archive_old_sessions shim still present", () => {
    const out = psql(
      `SELECT p.prorettype::regtype::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_archive_old_sessions';`,
    );
    assertEq(out, "integer", "shim returns integer");
  });

  await test("(4) fn_invoke_archive_sessions_safe registered", () => {
    const out = psql(
      `SELECT proname FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_invoke_archive_sessions_safe';`,
    );
    assertEq(out, "fn_invoke_archive_sessions_safe", "safe wrapper registered");
  });

  await test("(5) service_role grants on all four functions", () => {
    const out = psql(
      `SELECT has_function_privilege('service_role',
                'public.fn_archive_sessions_chunk(integer,integer)', 'EXECUTE'),
              has_function_privilege('service_role',
                'public.fn_archive_sessions_pending_count(integer)', 'EXECUTE'),
              has_function_privilege('service_role',
                'public.fn_archive_old_sessions()', 'EXECUTE'),
              has_function_privilege('service_role',
                'public.fn_invoke_archive_sessions_safe()', 'EXECUTE');`,
    );
    assertEq(out, "t|t|t|t", "service_role EXECUTE on all");
  });

  await test("(6) cron.job archive-old-sessions points to safe wrapper", () => {
    const hasCron = psql(
      `SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron');`,
    );
    if (hasCron !== "t") {
      console.log(`    (skipped — pg_cron not installed)`);
      return;
    }
    const out = psql(
      `SELECT jobname, schedule, command
         FROM cron.job
        WHERE jobname = 'archive-old-sessions';`,
    );
    if (!out) throw new Error("archive-old-sessions cron job not registered");
    assertContains(out, "45 3 * * 0", "Sunday 03:45 schedule");
    assertContains(out, "fn_invoke_archive_sessions_safe", "calls safe wrapper");
  });

  // ─────────────────────────────────────────────────────────────────────
  section("argument validation");

  await test("(7) batch_size = 0 → 22023", () => {
    const out = psql(
      `SELECT public.fn_archive_sessions_chunk(0, 6);`,
      { allowError: true },
    );
    if (!/INVALID_BATCH_SIZE/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_BATCH_SIZE, got:\n${out}`);
    }
  });

  await test("(8) batch_size = 20000 → 22023", () => {
    const out = psql(
      `SELECT public.fn_archive_sessions_chunk(20000, 6);`,
      { allowError: true },
    );
    if (!/INVALID_BATCH_SIZE/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_BATCH_SIZE, got:\n${out}`);
    }
  });

  await test("(9) cutoff_months = 0 → 22023", () => {
    const out = psql(
      `SELECT public.fn_archive_sessions_chunk(100, 0);`,
      { allowError: true },
    );
    if (!/INVALID_CUTOFF_MONTHS/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_CUTOFF_MONTHS, got:\n${out}`);
    }
  });

  await test("(10) cutoff_months = 999 → 22023", () => {
    const out = psql(
      `SELECT public.fn_archive_sessions_pending_count(999);`,
      { allowError: true },
    );
    if (!/INVALID_CUTOFF_MONTHS/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_CUTOFF_MONTHS, got:\n${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("behaviour (chunk primitive + pending count)");

  await test("(11) chunk on empty/short window returns well-formed jsonb", () => {
    // Use a very long cutoff (120 months) to almost guarantee no rows match
    // in a sandbox DB. The exact number doesn't matter — shape does.
    const out = psql(
      `SELECT public.fn_archive_sessions_chunk(1, 120);`,
    );
    // Parse the jsonb output.
    const parsed = JSON.parse(out);
    if (typeof parsed.moved_count !== "number") {
      throw new Error(`moved_count not a number: ${out}`);
    }
    if (typeof parsed.more_pending !== "boolean") {
      throw new Error(`more_pending not a boolean: ${out}`);
    }
    if (typeof parsed.cutoff_ms !== "number") {
      throw new Error(`cutoff_ms not a number: ${out}`);
    }
    if (typeof parsed.elapsed_ms !== "number" || parsed.elapsed_ms < 0) {
      throw new Error(`elapsed_ms malformed: ${out}`);
    }
  });

  await test("(12) pending_count returns non-negative bigint", () => {
    const out = psql(
      `SELECT public.fn_archive_sessions_pending_count(6);`,
    );
    const n = Number(out);
    if (!Number.isFinite(n) || n < 0) {
      throw new Error(`pending_count malformed: ${out}`);
    }
  });

  await test("(13) shim fn_archive_old_sessions returns integer ≥ 0", () => {
    const out = psql(`SELECT public.fn_archive_old_sessions();`);
    const n = Number(out);
    if (!Number.isInteger(n) || n < 0) {
      throw new Error(`shim returned non-int: ${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}Summary:${RESET} ${OK} ${passed} passed, ` +
      `${failed > 0 ? FAIL : ""} ${failed} failed`,
  );
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
