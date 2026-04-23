/**
 * tools/test_l19_08_check_constraint_naming.ts
 *
 * Integration tests for the L19-08 migration
 * (`supabase/migrations/20260421290000_l19_08_check_constraint_naming.sql`).
 *
 * Uses `docker exec psql` to avoid a node_modules `pg` dependency.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1) fn_find_nonstandard_check_constraints STABLE + SECURITY DEFINER
 *     (2) fn_assert_check_constraints_standardized SECURITY DEFINER
 *     (3) service_role EXECUTE; anon NÃO
 *
 *   rename of ad-hoc constraints
 *     (4) old name clearing_settlements.different_groups NÃO existe
 *     (5) new name chk_clearing_settlements_distinct_groups existe
 *     (6) old name swap_orders.swap_different_groups NÃO existe
 *     (7) new name chk_swap_orders_distinct_groups existe
 *     (8) CHECK definition preservada no rename
 *
 *   detector behaviour
 *     (9) clearing_settlements + swap_orders agora têm 0 nonstandard
 *    (10) <table>_<col>_check (pg default) é aceito
 *    (11) chk_<table>_<rule> é aceito
 *    (12) nome ad-hoc sem prefixo → flaggado
 *    (13) suggested_name começa com chk_<table>_
 *
 *   assert wrapper
 *    (14) NULL schemas → 22023
 *    (15) nonstandard → P0010
 *    (16) scope por tables[]
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l19_08_check_constraint_naming.ts
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

function assertEq<T>(actual: T, expected: T, label?: string): void {
  if (actual !== expected) {
    throw new Error(
      `${label ?? "assertEq"}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function setupSandbox() {
  psql(`
    DROP SCHEMA IF EXISTS l19_08_itests CASCADE;
    CREATE SCHEMA l19_08_itests;
  `);
}

function teardownSandbox() {
  psql(`DROP SCHEMA IF EXISTS l19_08_itests CASCADE;`);
}

async function run() {
  console.log(`${BOLD}L19-08 integration tests${RESET}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");
  // ─────────────────────────────────────────────────────────────────────

  await test("(1) fn_find_nonstandard_check_constraints STABLE SECURITY DEFINER", () => {
    const r = psql(`
      SELECT p.provolatile::text || '|' || p.prosecdef::text
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='fn_find_nonstandard_check_constraints';
    `);
    assertEq(r, "s|true");
  });

  await test("(2) fn_assert_check_constraints_standardized SECURITY DEFINER", () => {
    const r = psql(`
      SELECT p.prosecdef::text
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='fn_assert_check_constraints_standardized';
    `);
    assertEq(r, "true");
  });

  await test("(3) service_role EXECUTE; anon NÃO", () => {
    const sr = psql(`
      SELECT
        has_function_privilege('service_role', 'public.fn_find_nonstandard_check_constraints(text, text)', 'EXECUTE')::text
        || '|' ||
        has_function_privilege('service_role', 'public.fn_assert_check_constraints_standardized(text[], text[])', 'EXECUTE')::text;
    `);
    assertEq(sr, "true|true");
    const anon = psql(`
      SELECT
        has_function_privilege('anon', 'public.fn_find_nonstandard_check_constraints(text, text)', 'EXECUTE')::text
        || '|' ||
        has_function_privilege('anon', 'public.fn_assert_check_constraints_standardized(text[], text[])', 'EXECUTE')::text;
    `);
    assertEq(anon, "false|false");
  });

  // ─────────────────────────────────────────────────────────────────────
  section("rename of ad-hoc constraints");
  // ─────────────────────────────────────────────────────────────────────

  await test("(4) clearing_settlements.different_groups NÃO existe", () => {
    const r = psql(`
      SELECT count(*)::text FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname='clearing_settlements' AND con.conname='different_groups';
    `);
    assertEq(r, "0");
  });

  await test("(5) chk_clearing_settlements_distinct_groups existe", () => {
    const r = psql(`
      SELECT count(*)::text FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname='clearing_settlements'
         AND con.conname='chk_clearing_settlements_distinct_groups';
    `);
    assertEq(r, "1");
  });

  await test("(6) swap_orders.swap_different_groups NÃO existe", () => {
    const r = psql(`
      SELECT count(*)::text FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname='swap_orders' AND con.conname='swap_different_groups';
    `);
    assertEq(r, "0");
  });

  await test("(7) chk_swap_orders_distinct_groups existe", () => {
    const r = psql(`
      SELECT count(*)::text FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname='swap_orders' AND con.conname='chk_swap_orders_distinct_groups';
    `);
    assertEq(r, "1");
  });

  await test("(8) definição CHECK preservada no rename", () => {
    const r = psql(`
      SELECT pg_get_constraintdef(con.oid) FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname='clearing_settlements'
         AND con.conname='chk_clearing_settlements_distinct_groups';
    `);
    if (!/creditor_group_id/.test(r) || !/debtor_group_id/.test(r)) {
      throw new Error(`definition mismatch: ${r}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("detector behaviour");
  // ─────────────────────────────────────────────────────────────────────

  setupSandbox();

  await test("(9) clearing_settlements + swap_orders têm 0 nonstandard", () => {
    const cs = psql(
      `SELECT count(*)::text FROM public.fn_find_nonstandard_check_constraints('public','clearing_settlements');`,
    );
    assertEq(cs, "0");
    const so = psql(
      `SELECT count(*)::text FROM public.fn_find_nonstandard_check_constraints('public','swap_orders');`,
    );
    assertEq(so, "0");
  });

  await test("(10) <table>_<col>_check pg default é aceito", () => {
    psql(`
      CREATE TABLE l19_08_itests.u (a int CHECK (a > 0));
    `);
    const r = psql(
      `SELECT count(*)::text FROM public.fn_find_nonstandard_check_constraints('l19_08_itests','u');`,
    );
    assertEq(r, "0");
  });

  await test("(11) chk_<table>_<rule> é aceito", () => {
    psql(`
      CREATE TABLE l19_08_itests.v (
        b int,
        CONSTRAINT chk_v_b_positive CHECK (b > 0)
      );
    `);
    const r = psql(
      `SELECT count(*)::text FROM public.fn_find_nonstandard_check_constraints('l19_08_itests','v');`,
    );
    assertEq(r, "0");
  });

  await test("(12) nome ad-hoc sem prefixo é flaggado", () => {
    psql(`
      CREATE TABLE l19_08_itests.w (
        c int,
        CONSTRAINT badly_named CHECK (c > 0)
      );
    `);
    const r = psql(`
      SELECT constraint_name
        FROM public.fn_find_nonstandard_check_constraints('l19_08_itests','w');
    `);
    assertEq(r, "badly_named");
  });

  await test("(13) suggested_name começa com chk_<table>_", () => {
    const r = psql(`
      SELECT suggested_name
        FROM public.fn_find_nonstandard_check_constraints('l19_08_itests','w');
    `);
    if (!r.startsWith("chk_w_")) {
      throw new Error(`expected chk_w_ prefix, got: ${r}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("assert wrapper");
  // ─────────────────────────────────────────────────────────────────────

  await test("(14) NULL schemas → 22023", () => {
    const out = psql(
      `SELECT public.fn_assert_check_constraints_standardized(NULL::text[], NULL::text[]);`,
      { allowError: true },
    );
    if (!/22023|must be non-empty/.test(out)) {
      throw new Error(`expected 22023/non-empty, got: ${out.slice(0, 200)}`);
    }
  });

  await test("(15) nonstandard raises P0010 com HINT", () => {
    const out = psql(
      `SELECT public.fn_assert_check_constraints_standardized(ARRAY['l19_08_itests']::text[], NULL::text[]);`,
      { allowError: true },
    );
    if (!/P0010|fora da convenção/.test(out)) {
      throw new Error(`expected P0010, got: ${out.slice(0, 200)}`);
    }
    if (!/chk_<table>_<rule>|ALTER TABLE/.test(out)) {
      throw new Error(`expected HINT, got: ${out.slice(0, 200)}`);
    }
  });

  await test("(16) scope por tables[] filtra", () => {
    // v tem só chk_v_b_positive (conforme), u tem u_a_check auto (conforme) → pass
    const r = psql(
      `SELECT public.fn_assert_check_constraints_standardized(ARRAY['l19_08_itests']::text[], ARRAY['v']::text[]);`,
    );
    assertEq(r, "t");
    // w tem badly_named → fail
    const out = psql(
      `SELECT public.fn_assert_check_constraints_standardized(ARRAY['l19_08_itests']::text[], ARRAY['w']::text[]);`,
      { allowError: true },
    );
    if (!/fora da convenção|P0010/.test(out)) {
      throw new Error(`expected raise for w, got: ${out.slice(0, 200)}`);
    }
  });

  teardownSandbox();

  // ─────────────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}Summary${RESET}: ${passed} passed, ${failed} failed (${passed + failed} total)`,
  );
  if (failed > 0) process.exit(1);
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
