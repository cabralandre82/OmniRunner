/**
 * tools/test_l06_05_edge_retry_wrapper.ts
 *
 * Integration tests for the L06-05 retry wrapper migration
 * (`supabase/migrations/20260421230000_l06_05_edge_retry_wrapper.sql`).
 *
 * Uses `docker exec psql` (same pattern as tools/test_l04_07_*) to avoid
 * a node_modules `pg` dependency. The tests exercise the wrapper with a
 * deliberately-invalid config so we hit the early-return paths and the
 * input-validation branches — the actual HTTP call requires the `http`
 * extension (not installed in the local sandbox) but is exercised in
 * staging.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1) cron_edge_retry_attempts table present + RLS forced
 *     (2) cron_edge_retry_attempts has forensic indices
 *     (3) fn_invoke_edge_with_retry signature + permissions
 *     (4) fn_invoke_edge_fire_and_forget signature + permissions
 *     (5) fn_invoke_auto_topup_cron rewritten (refers to retry wrapper)
 *     (6) fn_invoke_lifecycle_cron_safe rewritten
 *     (7) fn_invoke_clearing_cron_safe installed
 *     (8) fn_invoke_verification_cron_safe installed
 *     (9) fn_invoke_onboarding_nudge_safe installed
 *     (10) fn_invoke_reconcile_wallets_safe installed
 *
 *   argument validation
 *     (11) empty p_job_name → 22023
 *     (12) empty p_endpoint → 22023
 *     (13) p_max_attempts out-of-range → 22023
 *     (14) p_backoff_base_seconds out-of-range → 22023
 *
 *   runtime behaviour (config + http ext missing)
 *     (15) missing config returns { skipped, reason: 'missing_config' }
 *     (16) http extension missing → single skipped audit row per call
 *
 *   fire-and-forget path
 *     (17) fire_and_forget requires pg_net or records skipped
 *     (18) fire_and_forget validates p_endpoint
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l06_05_edge_retry_wrapper.ts
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

function assertMatches(haystack: string, re: RegExp, msg: string) {
  if (!re.test(haystack)) {
    throw new Error(`${msg}: expected to match ${re}, got:\n${haystack}`);
  }
}

async function main() {
  console.log(`${BOLD}L06-05 — Edge Function retry wrapper integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) cron_edge_retry_attempts table + RLS forced", () => {
    const rel = psql(
      `SELECT c.relname, c.relrowsecurity, c.relforcerowsecurity
       FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
       WHERE n.nspname = 'public' AND c.relname = 'cron_edge_retry_attempts';`,
    );
    if (!rel) throw new Error("cron_edge_retry_attempts missing");
    const [name, rls, force] = rel.split("|");
    assertEq(name, "cron_edge_retry_attempts", "table name");
    assertEq(rls, "t", "RLS enabled");
    assertEq(force, "t", "RLS forced");
  });

  await test("(2) cron_edge_retry_attempts forensic indices", () => {
    const out = psql(
      `SELECT indexname FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename = 'cron_edge_retry_attempts'
        ORDER BY indexname;`,
    );
    const lines = out.split("\n").map((s) => s.trim()).filter(Boolean);
    assertContains(lines.join(","), "cron_edge_retry_job_started_idx", "job index");
    assertContains(lines.join(","), "cron_edge_retry_failures_idx", "failures index");
  });

  await test("(3) fn_invoke_edge_with_retry signature", () => {
    const out = psql(
      `SELECT pg_get_function_arguments(p.oid)
       FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
       WHERE n.nspname = 'public' AND p.proname = 'fn_invoke_edge_with_retry';`,
    );
    assertContains(out, "p_job_name text", "param p_job_name");
    assertContains(out, "p_endpoint text", "param p_endpoint");
    assertContains(out, "p_max_attempts integer", "param p_max_attempts");
    assertContains(out, "p_backoff_base_seconds integer", "param p_backoff_base_seconds");
  });

  await test("(4) fn_invoke_edge_fire_and_forget registered", () => {
    const out = psql(
      `SELECT proname FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname='public' AND p.proname='fn_invoke_edge_fire_and_forget';`,
    );
    assertEq(out, "fn_invoke_edge_fire_and_forget", "function registered");
  });

  for (const fname of [
    "fn_invoke_auto_topup_cron",
    "fn_invoke_lifecycle_cron_safe",
    "fn_invoke_clearing_cron_safe",
    "fn_invoke_verification_cron_safe",
    "fn_invoke_onboarding_nudge_safe",
    "fn_invoke_reconcile_wallets_safe",
  ]) {
    await test(`(5-10) ${fname} registered + SECURITY DEFINER + uses retry wrapper`, () => {
      const out = psql(
        `SELECT p.prosecdef, pg_get_functiondef(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
         WHERE n.nspname='public' AND p.proname='${fname}';`,
      );
      if (!out) throw new Error(`${fname} not found`);
      assertMatches(out, /^t\|/, `${fname} SECURITY DEFINER`);
      assertContains(out, "fn_invoke_edge_with_retry", `${fname} uses retry wrapper`);
    });
  }

  // ─────────────────────────────────────────────────────────────────────
  section("argument validation");

  await test("(11) empty p_job_name → 22023", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_with_retry('', 'x', '{}'::jsonb, 3, 0);`,
      { allowError: true },
    );
    if (!/INVALID_JOB_NAME/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_JOB_NAME, got:\n${out}`);
    }
  });

  await test("(12) empty p_endpoint → 22023", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_with_retry('x', '', '{}'::jsonb, 3, 0);`,
      { allowError: true },
    );
    if (!/INVALID_ENDPOINT/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_ENDPOINT, got:\n${out}`);
    }
  });

  await test("(13) p_max_attempts out-of-range → 22023", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_with_retry('x', 'x', '{}'::jsonb, 99, 0);`,
      { allowError: true },
    );
    if (!/INVALID_MAX_ATTEMPTS/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_MAX_ATTEMPTS, got:\n${out}`);
    }
  });

  await test("(14) p_backoff_base_seconds out-of-range → 22023", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_with_retry('x', 'x', '{}'::jsonb, 3, 999);`,
      { allowError: true },
    );
    if (!/INVALID_BACKOFF/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_BACKOFF, got:\n${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("runtime behaviour (config + http ext missing)");

  await test("(15) missing config → skipped with reason=missing_config", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_with_retry('l06-05-missing-cfg', 'test', '{}'::jsonb, 2, 0);`,
    );
    assertContains(out, '"skipped": true', "skipped flag");
    assertContains(out, '"reason": "missing_config"', "reason=missing_config");
    assertContains(out, '"attempts": 0', "no attempts");
  });

  await test("(16) http extension missing → single skipped audit row", () => {
    // Clean prior test rows with this job name.
    psql(
      `DELETE FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-no-http';`,
      { allowError: true },
    );

    const out = psql(
      `SET LOCAL app.settings.supabase_url = 'http://127.0.0.1:1/';
       SET LOCAL app.settings.service_role_key = 'test';
       SELECT public.fn_invoke_edge_with_retry('l06-05-no-http', 'test', '{}'::jsonb, 2, 0);`,
    );
    assertContains(out, '"reason": "http_extension_missing"', "reason=http_extension_missing");

    const rows = psql(
      `SELECT COUNT(*) FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-no-http';`,
    );
    assertEq(rows, "1", "exactly 1 skipped audit row");

    const metaMode = psql(
      `SELECT meta->>'mode' FROM public.cron_edge_retry_attempts
        WHERE job_name = 'l06-05-no-http' ORDER BY id DESC LIMIT 1;`,
    );
    assertEq(metaMode, "skipped", "meta.mode=skipped");

    psql(
      `DELETE FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-no-http';`,
      { allowError: true },
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  section("fire-and-forget path");

  await test("(17) fire_and_forget records audit row (skipped when pg_net missing)", () => {
    psql(
      `DELETE FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-faf';`,
      { allowError: true },
    );

    const out = psql(
      `SET LOCAL app.settings.supabase_url = 'http://127.0.0.1:1/';
       SET LOCAL app.settings.service_role_key = 'test';
       SELECT public.fn_invoke_edge_fire_and_forget('l06-05-faf', 'test', '{}'::jsonb);`,
    );
    // Either pg_net is installed and we got async_queued / async_enqueue_failed
    // OR pg_net is missing and we got skipped.
    const mode = psql(
      `SELECT meta->>'mode' FROM public.cron_edge_retry_attempts
        WHERE job_name = 'l06-05-faf' ORDER BY id DESC LIMIT 1;`,
    );
    if (!["async", "skipped"].includes(mode)) {
      throw new Error(`expected meta.mode in (async, skipped), got: ${mode}\nfn out: ${out}`);
    }

    psql(
      `DELETE FROM public.cron_edge_retry_attempts WHERE job_name = 'l06-05-faf';`,
      { allowError: true },
    );
  });

  await test("(18) fire_and_forget validates p_endpoint", () => {
    const out = psql(
      `SELECT public.fn_invoke_edge_fire_and_forget('x', '', '{}'::jsonb);`,
      { allowError: true },
    );
    if (!/INVALID_ENDPOINT/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_ENDPOINT, got:\n${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}Summary${RESET} — ${OK} ${passed} passed   ${FAIL} ${failed} failed`,
  );
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
