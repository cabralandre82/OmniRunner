/**
 * tools/test_l02_realtime_rls_guard.ts
 *
 * Integration tests for L02-08 (realtime RLS guard + DDL event trigger),
 * implemented in `supabase/migrations/20260419160000_l02_realtime_rls_guard.sql`.
 *
 * Coverage:
 *
 *   - Diagnostic
 *       * fn_realtime_publication_unsafe_tables returns [] for a
 *         baseline-clean publication
 *       * Same function flags a freshly-added unsafe table
 *       * Allow-listed tables are excluded from the report
 *   - Assertion
 *       * fn_assert_realtime_publication_safe is a no-op when clean
 *       * Raises P0009 REALTIME_RLS_VIOLATION on offender
 *   - Event trigger
 *       * ALTER PUBLICATION ADD TABLE without RLS is rolled back
 *       * ALTER PUBLICATION ADD TABLE with proper RLS is accepted
 *       * Allow-listed table can be added without RLS
 *
 * Usage:
 *
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l02_realtime_rls_guard.ts
 *
 * The tests require a local Supabase instance (`supabase start`) plus the
 * migration applied (`tools/validate-migrations.sh`). They use direct SQL
 * over the service role to exercise the DDL event trigger — this is one of
 * the rare cases where PostgREST is the wrong tool because the catalog
 * mutations are not exposed.
 */

import { createClient } from "@supabase/supabase-js";
import { spawnSync } from "node:child_process";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

const PG_CONTAINER =
  process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_omni_runner";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

/**
 * Run raw SQL via `docker exec ... psql`. Returns stdout on success,
 * throws an Error whose `.code` is the SQLSTATE (when available) and
 * whose `.message` includes the psql ERROR line(s). Mirrors the style
 * already in use by `tools/validate-migrations.sh` so we add zero new
 * Node dependencies (pg / postgres / etc.).
 */
function psql(sql: string): { stdout: string; stderr: string } {
  const r = spawnSync(
    "docker",
    ["exec", "-i", PG_CONTAINER, "psql", "-U", "postgres", "-d", "postgres",
     "-v", "ON_ERROR_STOP=1", "-X", "-q", "-A", "-t"],
    { input: sql, encoding: "utf8" },
  );
  if (r.error) throw r.error;
  if (r.status !== 0) {
    const err: Error & { code?: string; stderr?: string } = new Error(
      (r.stderr || "").trim() || `psql exit ${r.status}`,
    );
    const m = (r.stderr || "").match(/SQLSTATE:?\s*([A-Z0-9]{5})/);
    if (m) err.code = m[1];
    err.stderr = r.stderr;
    throw err;
  }
  return { stdout: r.stdout, stderr: r.stderr };
}

const OK = "\x1b[32m\u2713\x1b[0m";
const FAIL = "\x1b[31m\u2717\x1b[0m";
const SKIP = "\x1b[33m\u2298\x1b[0m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;
let skipped = 0;

function section(title: string) {
  console.log(`\n${BOLD}\u2500\u2500 ${title} \u2500\u2500${RESET}`);
}

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`  ${OK} ${name}`);
    passed++;
  } catch (e: any) {
    console.log(`  ${FAIL} ${name}: ${e?.message ?? e}`);
    failed++;
  }
}

function skip(name: string, reason?: string) {
  console.log(`  ${SKIP} ${name}${reason ? ` \u2014 ${reason}` : ""}`);
  skipped++;
}

function assertEq(actual: unknown, expected: unknown, msg: string) {
  if (actual !== expected) {
    throw new Error(
      `${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertTrue(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

// ── Test fixture: temporary table we add/remove from the publication ────────

const TEST_TABLE_PREFIX = "l0208_test_";

function uniqueTableName(): string {
  const suffix = Math.random().toString(36).slice(2, 10);
  return `${TEST_TABLE_PREFIX}${suffix}`;
}

function dropTestTable(name: string): void {
  // Best-effort: also remove from publication and allowlist if present.
  try {
    psql(
      `ALTER PUBLICATION supabase_realtime DROP TABLE IF EXISTS public.${name};`,
    );
  } catch {
    // already dropped or never added
  }
  try {
    psql(
      `DELETE FROM public.realtime_publication_allowlist WHERE table_schema = 'public' AND table_name = '${name}';`,
    );
  } catch {
    // ignore
  }
  try {
    psql(`DROP TABLE IF EXISTS public.${name};`);
  } catch {
    // ignore
  }
}

async function preflight(): Promise<boolean> {
  try {
    const { error } = await db.rpc(
      "fn_assert_realtime_publication_safe" as any,
      { p_publication: "supabase_realtime" },
    );
    if (
      error?.message?.match(/Could not find the function|not exist/i)
    ) {
      console.log(
        `\n${FAIL} preflight: fn_assert_realtime_publication_safe not found.`,
      );
      console.log(
        "  → did you apply migration 20260419160000_l02_realtime_rls_guard.sql?",
      );
      return false;
    }
    return true;
  } catch (e: any) {
    console.log(`\n${FAIL} preflight: ${e?.message ?? e}`);
    return false;
  }
}

// ── Tests ───────────────────────────────────────────────────────────────────

async function testDiagnostic() {
  section("diagnostic: fn_realtime_publication_unsafe_tables");

  await test("returns no rows for the baseline (clean) publication", async () => {
    const { data, error } = await db.rpc(
      "fn_realtime_publication_unsafe_tables" as any,
      { p_publication: "supabase_realtime" },
    );
    if (error) throw new Error(error.message);
    // Either empty array or no rows is acceptable — what matters is no
    // unexpected violations exist when the suite starts.
    assertTrue(
      Array.isArray(data) && data.length === 0,
      `expected zero offenders at baseline, got ${JSON.stringify(data)}`,
    );
  });

  await test("flags a table added to the publication without RLS", async () => {
    const tname = uniqueTableName();
    try {
      psql(
        `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);`,
      );
      let threw = false;
      try {
        psql(
          `ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
        );
      } catch (err: any) {
        threw = true;
        assertTrue(
          /REALTIME_RLS_VIOLATION/.test(err.message),
          `expected REALTIME_RLS_VIOLATION, got: ${err.message}`,
        );
      }
      assertTrue(threw, "expected DDL event trigger to abort the ADD");

      // Confirm the diagnostic reports it when we bypass the trigger
      // inside a SAVEPOINT'd transaction (rolled back at the end so
      // production posture is preserved).
      const r = psql(
        `BEGIN;
         ALTER EVENT TRIGGER trg_block_unsafe_realtime_publication DISABLE;
         ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};
         SELECT reason FROM public.fn_realtime_publication_unsafe_tables('supabase_realtime') WHERE table_name = '${tname}';
         ROLLBACK;`,
      );
      assertTrue(
        /rls_disabled/.test(r.stdout),
        `expected diagnostic to report rls_disabled, got: ${r.stdout}`,
      );
    } finally {
      dropTestTable(tname);
    }
  });

  await test("excludes allow-listed tables from the report", async () => {
    const tname = uniqueTableName();
    try {
      psql(
        `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);
         INSERT INTO public.realtime_publication_allowlist (table_schema, table_name, reason)
         VALUES ('public', '${tname}', 'integration test fixture — global broadcast intentional');
         ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
      );
      const r = psql(
        `SELECT count(*) FROM public.fn_realtime_publication_unsafe_tables('supabase_realtime') WHERE table_name = '${tname}';`,
      );
      assertEq(
        r.stdout.trim(),
        "0",
        "allow-listed table must not appear in report",
      );
    } finally {
      dropTestTable(tname);
    }
  });
}

async function testAssertion() {
  section("assertion: fn_assert_realtime_publication_safe");

  await test("returns void on a clean publication", async () => {
    const { error } = await db.rpc(
      "fn_assert_realtime_publication_safe" as any,
      { p_publication: "supabase_realtime" },
    );
    assertTrue(!error, `expected no error on clean publication: ${error?.message}`);
  });

  await test(
    "raises P0009 REALTIME_RLS_VIOLATION when an offender exists",
    async () => {
      const tname = uniqueTableName();
      try {
        psql(
          `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);`,
        );
        // Bypass the DDL trigger so we can observe the assertion in isolation.
        // Wrap in a single transaction that rolls back so production posture
        // (event trigger ENABLED) is restored.
        let threw = false;
        try {
          psql(
            `BEGIN;
             ALTER EVENT TRIGGER trg_block_unsafe_realtime_publication DISABLE;
             ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};
             SELECT public.fn_assert_realtime_publication_safe('supabase_realtime');
             ROLLBACK;`,
          );
        } catch (err: any) {
          threw = true;
          assertTrue(
            /REALTIME_RLS_VIOLATION/.test(err.message),
            `expected REALTIME_RLS_VIOLATION in message, got: ${err.message}`,
          );
          assertTrue(
            /P0009/.test(err.stderr ?? err.message ?? ""),
            `expected SQLSTATE P0009, got: ${err.stderr ?? err.message}`,
          );
        }
        assertTrue(threw, "expected assertion to raise");
      } finally {
        dropTestTable(tname);
      }
    },
  );
}

async function testEventTrigger() {
  section("event trigger: trg_block_unsafe_realtime_publication");

  await test(
    "accepts ADD TABLE when RLS + restrictive SELECT policy exist",
    async () => {
      const tname = uniqueTableName();
      try {
        psql(
          `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);
           ALTER TABLE public.${tname} ENABLE ROW LEVEL SECURITY;
           CREATE POLICY user_owns_row ON public.${tname}
             FOR SELECT TO authenticated
             USING (user_id = auth.uid());
           ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
        );
      } finally {
        dropTestTable(tname);
      }
    },
  );

  await test(
    "rejects ADD TABLE when SELECT policy is USING (true) (tautological)",
    async () => {
      const tname = uniqueTableName();
      try {
        psql(
          `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);
           ALTER TABLE public.${tname} ENABLE ROW LEVEL SECURITY;
           CREATE POLICY open_to_all ON public.${tname}
             FOR SELECT TO authenticated
             USING (true);`,
        );
        let threw = false;
        try {
          psql(
            `ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
          );
        } catch (err: any) {
          threw = true;
          assertTrue(
            /REALTIME_RLS_VIOLATION/.test(err.message),
            `expected REALTIME_RLS_VIOLATION, got: ${err.message}`,
          );
          assertTrue(
            /tautological_select_policy_using_true/.test(err.message),
            `expected reason in message, got: ${err.message}`,
          );
        }
        assertTrue(
          threw,
          "expected DDL event trigger to abort ADD with USING (true) policy",
        );
      } finally {
        dropTestTable(tname);
      }
    },
  );

  await test(
    "rejects ADD TABLE when RLS enabled but no SELECT policy exists",
    async () => {
      const tname = uniqueTableName();
      try {
        psql(
          `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);
           ALTER TABLE public.${tname} ENABLE ROW LEVEL SECURITY;`,
        );
        let threw = false;
        try {
          psql(
            `ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
          );
        } catch (err: any) {
          threw = true;
          assertTrue(
            /no_select_policy/.test(err.message),
            `expected no_select_policy reason, got: ${err.message}`,
          );
        }
        assertTrue(threw, "expected event trigger to abort ADD");
      } finally {
        dropTestTable(tname);
      }
    },
  );

  await test(
    "accepts ADD TABLE when table is allow-listed even without RLS",
    async () => {
      const tname = uniqueTableName();
      try {
        psql(
          `CREATE TABLE public.${tname} (id uuid PRIMARY KEY, user_id uuid NOT NULL);
           INSERT INTO public.realtime_publication_allowlist (table_schema, table_name, reason)
           VALUES ('public', '${tname}', 'integration test — broadcast intentional');
           ALTER PUBLICATION supabase_realtime ADD TABLE public.${tname};`,
        );
      } finally {
        dropTestTable(tname);
      }
    },
  );
}

async function main() {
  console.log(`${BOLD}L02-08 — Realtime RLS guard integration tests${RESET}`);

  if (!(await preflight())) {
    process.exit(2);
  }

  await testDiagnostic();
  await testAssertion();
  await testEventTrigger();

  console.log(
    `\n${BOLD}Result:${RESET} ${OK} ${passed} passed, ${FAIL} ${failed} failed, ${SKIP} ${skipped} skipped`,
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("fatal:", e);
  process.exit(2);
});
