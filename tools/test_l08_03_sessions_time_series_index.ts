/**
 * tools/test_l08_03_sessions_time_series_index.ts
 *
 * L08-03 — integration tests for time-series indexes on public.sessions.
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
    console.log(`  ${RED}✗${RESET} ${name}\n      ${(e as Error).message}`);
  }
}

function assert(cond: boolean, msg: string): void {
  if (!cond) throw new Error(msg);
}

function assertEq<T>(got: T, want: T, msg: string): void {
  if (got !== want)
    throw new Error(`${msg}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}

async function main(): Promise<void> {
  console.log(`\n${BOLD}L08-03 — sessions time-series indexes integration tests${RESET}`);

  section("schema / DDL");

  await test("1. idx_sessions_start_time_brin exists and uses BRIN", () => {
    const out = psql(`
      SELECT am.amname
      FROM pg_index i
      JOIN pg_class c  ON c.oid = i.indexrelid
      JOIN pg_class t  ON t.oid = i.indrelid
      JOIN pg_am    am ON am.oid = c.relam
      WHERE t.relname = 'sessions'
        AND c.relname = 'idx_sessions_start_time_brin';
    `);
    assertEq(out, "brin", "idx_sessions_start_time_brin access method");
  });

  await test("2. BRIN index covers exactly start_time_ms", () => {
    const out = psql(`
      SELECT pg_get_indexdef(i.indexrelid)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'sessions'
        AND c.relname = 'idx_sessions_start_time_brin';
    `);
    assert(/USING brin \(start_time_ms\)/i.test(out), `definition drifted: ${out}`);
    assert(
      /pages_per_range\s*=\s*'?32'?/i.test(out),
      `pages_per_range reloption drifted: ${out}`,
    );
  });

  await test("3. idx_sessions_status_start_time exists and is btree", () => {
    const out = psql(`
      SELECT am.amname
      FROM pg_index i
      JOIN pg_class c  ON c.oid = i.indexrelid
      JOIN pg_class t  ON t.oid = i.indrelid
      JOIN pg_am    am ON am.oid = c.relam
      WHERE t.relname = 'sessions'
        AND c.relname = 'idx_sessions_status_start_time';
    `);
    assertEq(out, "btree", "idx_sessions_status_start_time access method");
  });

  await test("4. partial btree predicate is status>=3", () => {
    const out = psql(`
      SELECT pg_get_expr(i.indpred, i.indrelid)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'sessions'
        AND c.relname = 'idx_sessions_status_start_time';
    `);
    assert(/status\s*>=\s*3/i.test(out), `predicate drifted: ${out}`);
  });

  await test("5. partial btree columns are (status, start_time_ms DESC)", () => {
    const out = psql(`
      SELECT pg_get_indexdef(i.indexrelid)
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      WHERE t.relname = 'sessions'
        AND c.relname = 'idx_sessions_status_start_time';
    `);
    assert(
      /USING btree \(status, start_time_ms DESC\)/i.test(out),
      `index definition drifted: ${out}`,
    );
  });

  await test("6. fn_sessions_has_time_series_indexes registered (STABLE, SECURITY DEFINER)", () => {
    const out = psql(`
      SELECT p.provolatile::text || '|' || p.prosecdef::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'fn_sessions_has_time_series_indexes'
        AND p.pronargs = 0;
    `);
    assertEq(out, "s|true", "volatility/secdef");
  });

  await test("7. fn_sessions_assert_time_series_indexes registered (SECURITY DEFINER)", () => {
    const out = psql(`
      SELECT p.prosecdef::text
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = 'fn_sessions_assert_time_series_indexes'
        AND p.pronargs = 0;
    `);
    assertEq(out, "true", "prosecdef");
  });

  await test("8. service_role has EXECUTE on both helpers", () => {
    const out = psql(`
      SELECT
        has_function_privilege('service_role','public.fn_sessions_has_time_series_indexes()','EXECUTE')
        || '|' ||
        has_function_privilege('service_role','public.fn_sessions_assert_time_series_indexes()','EXECUTE');
    `);
    assertEq(out, "true|true", "service_role EXECUTE");
  });

  await test("9. anon does NOT have EXECUTE on helpers", () => {
    const out = psql(`
      SELECT
        has_function_privilege('anon','public.fn_sessions_has_time_series_indexes()','EXECUTE')
        || '|' ||
        has_function_privilege('anon','public.fn_sessions_assert_time_series_indexes()','EXECUTE');
    `);
    assertEq(out, "false|false", "anon EXECUTE denied");
  });

  section("behaviour");

  await test("10. fn_sessions_has_time_series_indexes() returns true", () => {
    const out = psql("SELECT public.fn_sessions_has_time_series_indexes();");
    assertEq(out, "t", "detector result");
  });

  await test("11. fn_sessions_assert_time_series_indexes() is a no-op when OK", () => {
    const r = psqlAllowError("SELECT public.fn_sessions_assert_time_series_indexes();");
    assert(r.ok, `assert raised unexpectedly: ${r.out}`);
  });

  await test("12. detector returns false when BRIN is (temporarily) missing", () => {
    psql("ALTER INDEX IF EXISTS public.idx_sessions_start_time_brin RENAME TO _l08_03_tmp_brin_parked;");
    try {
      const out = psql("SELECT public.fn_sessions_has_time_series_indexes();");
      assertEq(out, "f", "detector should return false when BRIN missing");

      const r = psqlAllowError("SELECT public.fn_sessions_assert_time_series_indexes();");
      assert(!r.ok, "assert should raise when BRIN missing");
      assert(
        /L08-03/i.test(r.out) && /idx_sessions_start_time_brin/i.test(r.out),
        `assert error missing expected markers: ${r.out}`,
      );
    } finally {
      psql("ALTER INDEX IF EXISTS public._l08_03_tmp_brin_parked RENAME TO idx_sessions_start_time_brin;");
    }
  });

  await test("13. detector returns false when partial btree is (temporarily) missing", () => {
    psql(
      "ALTER INDEX IF EXISTS public.idx_sessions_status_start_time RENAME TO _l08_03_tmp_btree_parked;",
    );
    try {
      const out = psql("SELECT public.fn_sessions_has_time_series_indexes();");
      assertEq(out, "f", "detector should return false when partial btree missing");

      const r = psqlAllowError("SELECT public.fn_sessions_assert_time_series_indexes();");
      assert(!r.ok, "assert should raise when btree missing");
      assert(
        /L08-03/i.test(r.out) && /idx_sessions_status_start_time/i.test(r.out),
        `assert error missing expected markers: ${r.out}`,
      );
    } finally {
      psql(
        "ALTER INDEX IF EXISTS public._l08_03_tmp_btree_parked RENAME TO idx_sessions_status_start_time;",
      );
    }
  });

  section("planner usage (EXPLAIN)");

  await test("14. planner can use idx_sessions_status_start_time for finalized window", () => {
    const out = psql(`
      SET LOCAL enable_seqscan = off;
      EXPLAIN (FORMAT JSON)
      SELECT id FROM public.sessions
      WHERE status >= 3
        AND start_time_ms BETWEEN 1700000000000 AND 1800000000000
      ORDER BY start_time_ms DESC
      LIMIT 10;
    `);
    assert(
      /idx_sessions_status_start_time/.test(out) ||
        /idx_sessions_start_time_brin/.test(out),
      `neither L08-03 index considered by planner: ${out.slice(0, 500)}`,
    );
  });

  await test("15. BRIN correctly prunes ranges on a synthetic populated table", () => {
    psql(`
      DROP SCHEMA IF EXISTS l08_03_test CASCADE;
      CREATE SCHEMA l08_03_test;
      CREATE TABLE l08_03_test.t (
        id bigserial PRIMARY KEY,
        start_time_ms bigint NOT NULL
      );
      INSERT INTO l08_03_test.t (start_time_ms)
      SELECT 1700000000000 + (g * 1000)::bigint
      FROM generate_series(1, 20000) AS g;
      CREATE INDEX t_brin ON l08_03_test.t USING BRIN (start_time_ms) WITH (pages_per_range = 8);
      ANALYZE l08_03_test.t;
    `);
    try {
      const out = psql(`
        SET LOCAL enable_seqscan = off;
        SET LOCAL enable_bitmapscan = on;
        EXPLAIN (FORMAT JSON)
        SELECT COUNT(*) FROM l08_03_test.t
        WHERE start_time_ms BETWEEN 1700000000000 AND 1700000001000;
      `);
      assert(
        /t_brin/.test(out) && /Bitmap Index Scan/i.test(out),
        `BRIN not used for narrow range: ${out.slice(0, 500)}`,
      );
    } finally {
      psql("DROP SCHEMA IF EXISTS l08_03_test CASCADE;");
    }
  });

  console.log(
    `\n${BOLD}Summary:${RESET} ${passed}/${total} passed${
      failed ? `, ${RED}${failed} failed${RESET}` : ""
    }.`,
  );

  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
