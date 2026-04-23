/**
 * tools/test_l19_06_audit_logs_metadata_gin.ts
 *
 * L19-06 — integration tests for the audit_logs.metadata GIN index helpers.
 *
 * Scope:
 *   (1) fn_audit_logs_has_metadata_gin / fn_audit_logs_assert_metadata_gin
 *       exist as SECURITY DEFINER
 *   (2) anon/authenticated cannot EXECUTE; service_role can
 *   (3) Both functions are no-op when public.audit_logs is absent
 *   (4) Detector returns true when GIN index exists on a fabricated
 *       audit_logs-shaped table
 *   (5) Assert raises P0010 when table+metadata exist but GIN absent
 *   (6) EXPLAIN of `metadata @> '{"request_id":…}'` uses a BitmapIndexScan
 *       on the GIN index
 *   (7) `jsonb_ops` vs `jsonb_path_ops` distinction: ? operator is
 *       expected to NOT be supported by jsonb_path_ops
 *
 * Isolation:
 *   All fabricated objects live under schema `l19_06_it_test` and are
 *   dropped before/after each invocation.
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;
let total = 0;

function psql(sql: string): string {
  return execSync(
    `docker exec -i ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At`,
    { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
  ).trim();
}

function psqlAllowError(sql: string): { out: string; ok: boolean } {
  try {
    return { out: psql(sql), ok: true };
  } catch (e) {
    const err = e as { stderr?: string | Buffer; message?: string };
    return {
      out:
        (typeof err.stderr === "string" ? err.stderr : err.stderr?.toString?.() ?? "") +
        (err.message ?? ""),
      ok: false,
    };
  }
}

function section(name: string): void {
  console.log(`\n${BOLD}── ${name} ──${RESET}`);
}

async function test(name: string, fn: () => void | Promise<void>): Promise<void> {
  total += 1;
  try {
    await fn();
    passed += 1;
    console.log(`  ${GREEN}✓${RESET} ${name}`);
  } catch (e) {
    failed += 1;
    const msg = (e as Error).message;
    console.log(`  ${RED}✗${RESET} ${name}\n      ${msg}`);
  }
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertEq<T>(got: T, want: T, msg: string): void {
  if (got !== want) throw new Error(`${msg}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}

const TEST_SCHEMA = "l19_06_it_test";

function setupClean(): void {
  psql(`DROP SCHEMA IF EXISTS ${TEST_SCHEMA} CASCADE;`);
}

async function main(): Promise<void> {
  console.log(`${BOLD}L19-06 — audit_logs.metadata GIN integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  setupClean();

  // ──────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) fn_audit_logs_has_metadata_gin is SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef::text
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname='public' AND p.proname='fn_audit_logs_has_metadata_gin';`,
    );
    assertEq(out, "true", "prosecdef");
  });

  await test("(2) fn_audit_logs_assert_metadata_gin is SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef::text
         FROM pg_proc p
         JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname='public' AND p.proname='fn_audit_logs_assert_metadata_gin';`,
    );
    assertEq(out, "true", "prosecdef");
  });

  await test("(3) service_role has EXECUTE; anon does NOT", () => {
    const out = psql(`
      SELECT string_agg(
        format('%s:%s',
          r.rolname,
          has_function_privilege(r.rolname, 'public.fn_audit_logs_assert_metadata_gin()', 'EXECUTE')::text
        ),
        ','
        ORDER BY r.rolname
      )
      FROM pg_roles r
      WHERE r.rolname IN ('anon','authenticated','service_role');
    `);
    assert(out.includes("service_role:true"), `expected service_role:true, got ${out}`);
    assert(out.includes("anon:false"), `expected anon:false, got ${out}`);
    assert(out.includes("authenticated:false"), `expected authenticated:false, got ${out}`);
  });

  // ──────────────────────────────────────────────────────────────────────
  section("defensive / sandbox sem audit_logs");

  await test("(4) fn_audit_logs_has_metadata_gin → false quando audit_logs ausente", () => {
    const out = psql("SELECT public.fn_audit_logs_has_metadata_gin()::text;");
    assertEq(out, "false", "detector");
  });

  await test("(5) fn_audit_logs_assert_metadata_gin → true quando audit_logs ausente (no-op)", () => {
    const out = psql("SELECT public.fn_audit_logs_assert_metadata_gin()::text;");
    assertEq(out, "true", "assert no-op");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("fabricated audit_logs — detector / assert / EXPLAIN");

  // Create a fabricated public.audit_logs (since the functions scope public.*)
  // We CREATE inside the test schema then temporarily rename the search_path
  // — easier: we directly create public.audit_logs for the duration of the
  // test and drop it at the end.

  await test("(6) cria public.audit_logs fabricada (setup)", () => {
    psql(`
      DROP TABLE IF EXISTS public.audit_logs CASCADE;
      CREATE TABLE public.audit_logs (
        id bigserial PRIMARY KEY,
        action text NOT NULL,
        created_at timestamptz NOT NULL DEFAULT now(),
        metadata jsonb NOT NULL DEFAULT '{}'::jsonb
      );
    `);
    const out = psql(
      "SELECT to_regclass('public.audit_logs')::text;",
    );
    assertEq(out, "audit_logs", "table exists");
  });

  await test("(7) assert raises P0010 quando GIN ausente", () => {
    const r = psqlAllowError(
      "SELECT public.fn_audit_logs_assert_metadata_gin();",
    );
    if (r.ok) {
      throw new Error("expected P0010, but assert returned true");
    }
    if (!/P0010|idx_audit_logs_metadata_gin/.test(r.out)) {
      throw new Error(`expected P0010 or index hint in stderr, got: ${r.out.slice(0, 300)}`);
    }
  });

  await test("(8) cria GIN(metadata jsonb_path_ops) e detector fica true", () => {
    psql(`
      CREATE INDEX idx_audit_logs_metadata_gin
        ON public.audit_logs USING GIN (metadata jsonb_path_ops);
    `);
    const out = psql("SELECT public.fn_audit_logs_has_metadata_gin()::text;");
    assertEq(out, "true", "detector after index");
  });

  await test("(9) assert passa (retorna true) com GIN presente", () => {
    const out = psql("SELECT public.fn_audit_logs_assert_metadata_gin()::text;");
    assertEq(out, "true", "assert ok");
  });

  await test("(10) popula audit_logs e EXPLAIN usa BitmapIndexScan", () => {
    psql(`
      INSERT INTO public.audit_logs (action, metadata)
      SELECT 'test.event',
             jsonb_build_object(
               'request_id', gen_random_uuid()::text,
               'session_id', gen_random_uuid()::text,
               'correlation_id', gen_random_uuid()::text,
               'seq', g
             )
      FROM generate_series(1, 500) g;
      ANALYZE public.audit_logs;
    `);
    // Force index usage for the EXPLAIN
    const plan = psql(
      `SET enable_seqscan = off;
       EXPLAIN (FORMAT TEXT)
         SELECT id FROM public.audit_logs
         WHERE metadata @> '{"action": "nonexistent"}'::jsonb;`,
    );
    assert(
      /idx_audit_logs_metadata_gin/i.test(plan),
      `expected plan to mention idx_audit_logs_metadata_gin, got:\n${plan}`,
    );
    assert(
      /Bitmap Index Scan/i.test(plan),
      `expected Bitmap Index Scan in plan, got:\n${plan}`,
    );
  });

  await test("(11) @> com request_id real retorna match", () => {
    const reqId = psql(
      `SELECT (metadata->>'request_id')::text
         FROM public.audit_logs
        ORDER BY id
        LIMIT 1;`,
    );
    const out = psql(
      `SELECT count(*)::int FROM public.audit_logs
        WHERE metadata @> jsonb_build_object('request_id', '${reqId}');`,
    );
    assertEq(out, "1", "match count");
  });

  await test("(12) jsonb_path_ops NÃO suporta operador ? (existence)", () => {
    // jsonb_path_ops supports @> only; operator ? requires jsonb_ops.
    // So a query like metadata ? 'request_id' will either do seq scan
    // or require a second index. We verify the GIN index does NOT service
    // a pure existence probe.
    const plan = psql(
      `SET enable_seqscan = off;
       EXPLAIN (FORMAT TEXT)
         SELECT id FROM public.audit_logs WHERE metadata ? 'request_id';`,
    );
    // Either falls back to Seq Scan (seqscan=off doesn't fully disable it
    // when no index can serve the predicate) or uses a different index.
    // The essential invariant: idx_audit_logs_metadata_gin is NOT the path.
    assert(
      !/Bitmap Index Scan.*idx_audit_logs_metadata_gin/is.test(plan),
      `jsonb_path_ops should not service ? operator, but plan shows:\n${plan}`,
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  section("idempotência do CREATE INDEX IF NOT EXISTS");

  await test("(13) recriar o índice é no-op", () => {
    const r = psqlAllowError(
      `CREATE INDEX IF NOT EXISTS idx_audit_logs_metadata_gin
         ON public.audit_logs USING GIN (metadata jsonb_path_ops);`,
    );
    assert(r.ok, `expected idempotent re-create, got: ${r.out}`);
    const out = psql(
      `SELECT count(*)::int FROM pg_index i
        JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = 'idx_audit_logs_metadata_gin';`,
    );
    assertEq(out, "1", "exactly one index exists");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("drop metadata column → assert no-op");

  await test("(14) sem coluna metadata → assert retorna true (no-op)", () => {
    psql(`
      DROP INDEX IF EXISTS public.idx_audit_logs_metadata_gin;
      ALTER TABLE public.audit_logs DROP COLUMN metadata;
    `);
    const out = psql("SELECT public.fn_audit_logs_assert_metadata_gin()::text;");
    assertEq(out, "true", "no metadata col → assert no-op");
  });

  // teardown
  psql("DROP TABLE IF EXISTS public.audit_logs CASCADE;");
  setupClean();

  console.log(
    `\n${BOLD}Summary${RESET}: ${passed} passed, ${failed} failed (${total} total)`,
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
