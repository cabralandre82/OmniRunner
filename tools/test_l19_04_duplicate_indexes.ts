/**
 * tools/test_l19_04_duplicate_indexes.ts
 *
 * Integration tests for the L19-04 migration
 * (`supabase/migrations/20260421280000_l19_04_dedupe_ledger_indexes.sql`).
 *
 * Uses `docker exec psql` to avoid a node_modules `pg` dependency.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1) fn_find_duplicate_indexes registered + STABLE + SECURITY DEFINER
 *     (2) fn_assert_no_duplicate_indexes registered + SECURITY DEFINER
 *     (3) service_role has EXECUTE on both; anon does NOT
 *     (4) legacy phantoms (idx_coin_ledger_user_created, idx_coin_ledger_ref_reason,
 *         idx_ledger_user_monolithic, idx_ledger_issuer_monolithic) NÃO existem
 *
 *   behaviour — fn_find_duplicate_indexes
 *     (5) on clean coin_ledger: returns 0 rows
 *     (6) prefix overlap in sandbox schema: 1 row, kind='prefix_overlap'
 *     (7) exact duplicate in sandbox: 1 row, kind='exact_duplicate',
 *         canonical is lexicographically smaller
 *     (8) UNIQUE and PRIMARY KEY indexes are ignored (no false positives)
 *     (9) different WHERE predicate → not redundant (two partial indexes coexist)
 *    (10) different INCLUDE → not redundant
 *    (11) expression-based btree still scanned but matched by sig (covered by #6/#7 semantics)
 *
 *   argument validation
 *    (12) fn_assert_* with NULL schemas → 22023
 *    (13) fn_assert_* with duplicates raises P0010
 *    (14) fn_assert_* scoped to tables[] filters correctly
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l19_04_duplicate_indexes.ts
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
    DROP SCHEMA IF EXISTS l19_04_itests CASCADE;
    CREATE SCHEMA l19_04_itests;
    CREATE TABLE l19_04_itests.t (
      a int, b int, c int, d text
    );
  `);
}

function teardownSandbox() {
  psql(`DROP SCHEMA IF EXISTS l19_04_itests CASCADE;`);
}

async function run() {
  console.log(`${BOLD}L19-04 integration tests${RESET}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");
  // ─────────────────────────────────────────────────────────────────────

  await test("(1) fn_find_duplicate_indexes registered STABLE SECURITY DEFINER", () => {
    const r = psql(`
      SELECT p.provolatile::text || '|' || p.prosecdef::text
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='fn_find_duplicate_indexes';
    `);
    assertEq(r, "s|true");
  });

  await test("(2) fn_assert_no_duplicate_indexes registered + SECURITY DEFINER", () => {
    const r = psql(`
      SELECT p.prosecdef::text
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname='public' AND p.proname='fn_assert_no_duplicate_indexes';
    `);
    assertEq(r, "true");
  });

  await test("(3) service_role has EXECUTE on both; anon does NOT", () => {
    const sr = psql(`
      SELECT
        has_function_privilege('service_role', 'public.fn_find_duplicate_indexes(text, text)', 'EXECUTE')::text
        || '|' ||
        has_function_privilege('service_role', 'public.fn_assert_no_duplicate_indexes(text[], text[])', 'EXECUTE')::text;
    `);
    assertEq(sr, "true|true");
    const anon = psql(`
      SELECT
        has_function_privilege('anon', 'public.fn_find_duplicate_indexes(text, text)', 'EXECUTE')::text
        || '|' ||
        has_function_privilege('anon', 'public.fn_assert_no_duplicate_indexes(text[], text[])', 'EXECUTE')::text;
    `);
    assertEq(anon, "false|false");
  });

  await test("(4) legacy phantoms NÃO existem em public", () => {
    const r = psql(`
      SELECT count(*)::text FROM pg_indexes
       WHERE schemaname='public'
         AND indexname IN (
           'idx_coin_ledger_user_created',
           'idx_coin_ledger_ref_reason',
           'idx_ledger_user_monolithic',
           'idx_ledger_issuer_monolithic'
         );
    `);
    assertEq(r, "0");
  });

  // ─────────────────────────────────────────────────────────────────────
  section("behaviour — fn_find_duplicate_indexes");
  // ─────────────────────────────────────────────────────────────────────

  setupSandbox();

  await test("(5) coin_ledger limpo → 0 duplicatas", () => {
    const r = psql(`SELECT count(*)::text FROM public.fn_find_duplicate_indexes('public', 'coin_ledger');`);
    assertEq(r, "0");
  });

  await test("(6) prefix overlap: idx(a) redundante vs idx(a,b)", () => {
    psql(`
      CREATE INDEX t_a_idx   ON l19_04_itests.t (a);
      CREATE INDEX t_a_b_idx ON l19_04_itests.t (a, b);
    `);
    const r = psql(`
      SELECT redundant_index || '|' || canonical_index || '|' || kind
        FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');
    `);
    assertEq(r, "t_a_idx|t_a_b_idx|prefix_overlap");
    psql(`DROP INDEX l19_04_itests.t_a_idx; DROP INDEX l19_04_itests.t_a_b_idx;`);
  });

  await test("(7) exact duplicate: canonical é lex menor", () => {
    psql(`
      CREATE INDEX t_z_idx ON l19_04_itests.t (a);
      CREATE INDEX t_a_idx ON l19_04_itests.t (a);
    `);
    const r = psql(`
      SELECT redundant_index || '|' || canonical_index || '|' || kind
        FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');
    `);
    assertEq(r, "t_z_idx|t_a_idx|exact_duplicate");
    psql(`DROP INDEX l19_04_itests.t_z_idx; DROP INDEX l19_04_itests.t_a_idx;`);
  });

  await test("(8) UNIQUE e PRIMARY KEY não são flaggados", () => {
    psql(`
      CREATE UNIQUE INDEX t_unq_a ON l19_04_itests.t (a);
      CREATE INDEX t_plain_a ON l19_04_itests.t (a);
    `);
    // UNIQUE tem valor próprio (enforcement de unicidade), não é redundante com plain
    const r = psql(`SELECT count(*)::text FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');`);
    assertEq(r, "0");
    psql(`DROP INDEX l19_04_itests.t_unq_a; DROP INDEX l19_04_itests.t_plain_a;`);
  });

  await test("(9) WHERE predicates diferentes → NÃO redundante", () => {
    psql(`
      CREATE INDEX t_a_pos ON l19_04_itests.t (a) WHERE a > 0;
      CREATE INDEX t_a_neg ON l19_04_itests.t (a) WHERE a < 0;
    `);
    const r = psql(`SELECT count(*)::text FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');`);
    assertEq(r, "0");
    psql(`DROP INDEX l19_04_itests.t_a_pos; DROP INDEX l19_04_itests.t_a_neg;`);
  });

  await test("(10) INCLUDE columns diferentes → NÃO redundante", () => {
    psql(`
      CREATE INDEX t_a_inc_b ON l19_04_itests.t (a) INCLUDE (b);
      CREATE INDEX t_a_inc_c ON l19_04_itests.t (a) INCLUDE (c);
    `);
    const r = psql(`SELECT count(*)::text FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');`);
    assertEq(r, "0");
    psql(`DROP INDEX l19_04_itests.t_a_inc_b; DROP INDEX l19_04_itests.t_a_inc_c;`);
  });

  await test("(11) same WHERE + same INCLUDE + same cols → exact_duplicate", () => {
    psql(`
      CREATE INDEX t_both_1 ON l19_04_itests.t (a, b) INCLUDE (c) WHERE b IS NOT NULL;
      CREATE INDEX t_both_2 ON l19_04_itests.t (a, b) INCLUDE (c) WHERE b IS NOT NULL;
    `);
    const r = psql(`
      SELECT redundant_index || '|' || canonical_index || '|' || kind
        FROM public.fn_find_duplicate_indexes('l19_04_itests', 't');
    `);
    assertEq(r, "t_both_2|t_both_1|exact_duplicate");
    psql(`DROP INDEX l19_04_itests.t_both_1; DROP INDEX l19_04_itests.t_both_2;`);
  });

  // ─────────────────────────────────────────────────────────────────────
  section("argument validation + assert wrapper");
  // ─────────────────────────────────────────────────────────────────────

  await test("(12) fn_assert_no_duplicate_indexes NULL schemas → 22023", () => {
    const out = psql(
      `SELECT public.fn_assert_no_duplicate_indexes(NULL::text[], NULL::text[]);`,
      { allowError: true },
    );
    if (!/22023/.test(out) && !/must be non-empty/.test(out)) {
      throw new Error(`expected 22023/non-empty, got: ${out.slice(0, 200)}`);
    }
  });

  await test("(13) fn_assert_no_duplicate_indexes raises P0010 quando há duplicatas", () => {
    psql(`
      CREATE INDEX t_a_idx   ON l19_04_itests.t (a);
      CREATE INDEX t_a_b_idx ON l19_04_itests.t (a, b);
    `);
    const out = psql(
      `SELECT public.fn_assert_no_duplicate_indexes(ARRAY['l19_04_itests']::text[], NULL::text[]);`,
      { allowError: true },
    );
    if (!/P0010|índices duplicados/.test(out)) {
      throw new Error(`expected P0010/duplicates, got: ${out.slice(0, 200)}`);
    }
    psql(`DROP INDEX l19_04_itests.t_a_idx; DROP INDEX l19_04_itests.t_a_b_idx;`);
  });

  await test("(14) fn_assert_* scoped to tables[] filtra corretamente", () => {
    // Criar duplicata em OUTRA tabela do mesmo schema; assertar que filtro por
    // table=['t'] (tabela sem duplicatas) NÃO raises.
    psql(`
      CREATE TABLE l19_04_itests.u (x int);
      CREATE INDEX u_x_idx_a ON l19_04_itests.u (x);
      CREATE INDEX u_x_idx_b ON l19_04_itests.u (x);
    `);
    // Escopado a 't' (sem duplicatas) — passa
    const r1 = psql(
      `SELECT public.fn_assert_no_duplicate_indexes(ARRAY['l19_04_itests']::text[], ARRAY['t']::text[]);`,
    );
    assertEq(r1, "t");
    // Escopado a 'u' (com duplicata) — raise
    const r2 = psql(
      `SELECT public.fn_assert_no_duplicate_indexes(ARRAY['l19_04_itests']::text[], ARRAY['u']::text[]);`,
      { allowError: true },
    );
    if (!/P0010|duplicad/.test(r2)) {
      throw new Error(`expected raise for u, got: ${r2.slice(0, 200)}`);
    }
    psql(`DROP TABLE l19_04_itests.u CASCADE;`);
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
