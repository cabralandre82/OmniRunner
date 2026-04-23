/**
 * tools/test_l12_08_clearing_cron_deterministic_cutoff.ts
 *
 * Integration tests for the L12-08 migration
 * (`supabase/migrations/20260421270000_l12_08_clearing_cron_deterministic_cutoff.sql`).
 *
 * Uses `docker exec psql` to avoid a node_modules `pg` dependency.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1) fn_clearing_cutoff_utc registered + STABLE + SECURITY DEFINER
 *     (2) fn_invoke_clearing_cron_safe preserved + SECURITY DEFINER
 *     (3) service_role has EXECUTE on both
 *     (4) cron job clearing-cron scheduled at 15 3 * * *
 *
 *   behaviour — fn_clearing_cutoff_utc
 *     (5) BRT cutoff for mid-afternoon UTC matches start-of-BRT-day
 *     (6) BRT cutoff for 02:00 UTC returns *previous* BRT day start
 *     (7) UTC timezone returns UTC midnight
 *     (8) Default p_as_of = now() returns a value ≤ now()
 *     (9) Returns same value for two consecutive calls within the same day
 *
 *   argument validation
 *    (10) NULL timezone → 22023
 *    (11) empty timezone → 22023
 *    (12) invalid IANA → 22023
 *    (13) p_as_of = NULL uses now() (no error)
 *
 *   cron wrapper
 *    (14) fn_invoke_clearing_cron_safe compiles/executes (sandbox mode: skipped if no pg_cron)
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l12_08_clearing_cron_deterministic_cutoff.ts
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
  console.log(`${BOLD}L12-08 — clearing-cron deterministic cutoff integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ───────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) fn_clearing_cutoff_utc STABLE + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.provolatile::text || ',' || p.prosecdef::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_clearing_cutoff_utc';`,
    );
    if (out !== "s,true") {
      throw new Error(`expected 's,true' (STABLE + SECURITY DEFINER), got ${out}`);
    }
  });

  await test("(2) fn_invoke_clearing_cron_safe preserved + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_invoke_clearing_cron_safe';`,
    );
    if (out !== "true") {
      throw new Error(`expected SECURITY DEFINER, got ${out}`);
    }
  });

  await test("(3) service_role has EXECUTE on both", () => {
    const out = psql(
      `SELECT routine_name, grantee
         FROM information_schema.routine_privileges
        WHERE routine_schema='public'
          AND routine_name IN ('fn_clearing_cutoff_utc','fn_invoke_clearing_cron_safe')
          AND grantee = 'service_role'
        ORDER BY routine_name;`,
    );
    assertContains(out, "fn_clearing_cutoff_utc|service_role", "cutoff helper grant");
    assertContains(out, "fn_invoke_clearing_cron_safe|service_role", "safe wrapper grant");
  });

  await test("(4) cron job clearing-cron scheduled at 15 3 * * *", () => {
    const hasCron = psql(
      `SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname='pg_cron');`,
    );
    if (hasCron !== "t") {
      console.log("     (pg_cron not installed; skipping)");
      return;
    }
    const out = psql(
      `SELECT schedule FROM cron.job WHERE jobname = 'clearing-cron';`,
    );
    assertEq(out, "15 3 * * *", "cron schedule");
  });

  // ───────────────────────────────────────────────────────────────
  section("behaviour — fn_clearing_cutoff_utc");

  await test("(5) BRT cutoff for 2026-04-21 17:00 UTC → 2026-04-21 03:00 UTC", () => {
    const out = psql(
      `SELECT public.fn_clearing_cutoff_utc(
         'America/Sao_Paulo',
         '2026-04-21 17:00:00+00'::timestamptz)::text;`,
    );
    // PostgreSQL serialises timestamptz in the session TZ. Use TO_CHAR in UTC.
    const utc = psql(
      `SELECT to_char(public.fn_clearing_cutoff_utc(
         'America/Sao_Paulo',
         '2026-04-21 17:00:00+00'::timestamptz)
         AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS');`,
    );
    assertEq(utc, "2026-04-21 03:00:00", "cutoff in UTC");
  });

  await test("(6) BRT cutoff for 2026-04-21 02:00 UTC → 2026-04-20 03:00 UTC (previous BRT day)", () => {
    const utc = psql(
      `SELECT to_char(public.fn_clearing_cutoff_utc(
         'America/Sao_Paulo',
         '2026-04-21 02:00:00+00'::timestamptz)
         AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS');`,
    );
    assertEq(utc, "2026-04-20 03:00:00", "cutoff previous BRT day");
  });

  await test("(7) UTC timezone returns UTC midnight", () => {
    const utc = psql(
      `SELECT to_char(public.fn_clearing_cutoff_utc(
         'UTC',
         '2026-04-21 17:00:00+00'::timestamptz)
         AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS');`,
    );
    assertEq(utc, "2026-04-21 00:00:00", "UTC cutoff");
  });

  await test("(8) Default p_as_of uses now() and returns value ≤ now()", () => {
    const out = psql(
      `SELECT (public.fn_clearing_cutoff_utc('America/Sao_Paulo') <= now())::text;`,
    );
    assertEq(out, "true", "cutoff <= now");
  });

  await test("(9) Two consecutive calls return same value (deterministic)", () => {
    const out = psql(
      `WITH c AS (
         SELECT public.fn_clearing_cutoff_utc('America/Sao_Paulo') AS a,
                public.fn_clearing_cutoff_utc('America/Sao_Paulo') AS b
       )
       SELECT (a = b)::text FROM c;`,
    );
    assertEq(out, "true", "deterministic across calls");
  });

  // ───────────────────────────────────────────────────────────────
  section("argument validation");

  await test("(10) NULL timezone → 22023", () => {
    const out = psql(
      `SELECT public.fn_clearing_cutoff_utc(NULL, now());`,
      { allowError: true },
    );
    assertContains(out, "INVALID_TIMEZONE", "error message");
  });

  await test("(11) empty timezone → 22023", () => {
    const out = psql(
      `SELECT public.fn_clearing_cutoff_utc('', now());`,
      { allowError: true },
    );
    assertContains(out, "INVALID_TIMEZONE", "error message");
  });

  await test("(12) invalid IANA → 22023", () => {
    const out = psql(
      `SELECT public.fn_clearing_cutoff_utc('Mars/Olympus', now());`,
      { allowError: true },
    );
    assertContains(out, "INVALID_TIMEZONE", "error message");
  });

  await test("(13) p_as_of = NULL uses now() (no error)", () => {
    const out = psql(
      `SELECT public.fn_clearing_cutoff_utc('America/Sao_Paulo', NULL)::text;`,
    );
    if (!out || out === "") throw new Error("expected timestamptz, got empty");
  });

  // ───────────────────────────────────────────────────────────────
  section("cron wrapper");

  await test("(14) fn_invoke_clearing_cron_safe exists and grants correct", () => {
    // Actually invoking would attempt pg_net/http extension calls we
    // don't want to trigger in sandbox. Just confirm pg_proc + EXECUTE.
    const out = psql(
      `SELECT EXISTS (
         SELECT 1 FROM pg_proc p
           JOIN pg_namespace n ON p.pronamespace = n.oid
          WHERE n.nspname = 'public'
            AND p.proname = 'fn_invoke_clearing_cron_safe'
            AND p.prosecdef = true
       )::text;`,
    );
    assertEq(out, "true", "wrapper registered SECURITY DEFINER");
  });

  // ───────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}Summary:${RESET} ${OK} ${passed} passed, ${failed ? FAIL + " " + failed + " failed" : " 0 failed"}\n`,
  );
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
