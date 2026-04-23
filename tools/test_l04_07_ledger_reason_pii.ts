/**
 * tools/test_l04_07_ledger_reason_pii.ts
 *
 * Integration tests for the L04-07 hardening migration
 * (`supabase/migrations/20260421220000_l04_07_ledger_reason_pii_guard.sql`).
 *
 * Executa via `docker exec supabase_db_project-running psql` — assim não
 * depende do driver `pg` estar em node_modules e replica o fluxo das outras
 * suites do repo (p.ex. `tools/test_l09_09_legal_contracts.ts` que roda
 * via supabase-js contra a HTTP de Supabase local).
 *
 * Coverage
 * ────────
 *   schema / constraints
 *     (1) chk_coin_ledger_reason_length_guard installed
 *     (2) chk_coin_ledger_reason_pii_guard installed
 *     (3) coin_ledger_pii_redactions table exists + RLS service-role-only
 *     (4) coin_ledger_archive has mirror constraints if archive exists
 *
 *   CHECK enforcement (INSERT via psql)
 *     (5) canonical reason literal ('session_completed') is accepted
 *     (6) reason containing '@' is rejected (23514 check_violation)
 *     (7) reason containing 'by user <uuid>' is rejected
 *     (8) reason longer than 64 chars is rejected
 *
 *   CHECK enforcement (note column, só se coluna existir)
 *     (9) note with '@' is rejected
 *     (10) note longer than 200 chars is rejected
 *
 *   fn_redact_ledger_pii_for_user
 *     (11) function exists and returns jsonb
 *     (12) idempotent with zero PII rows returns zero counters
 *
 *   trg_ledger_pii_redact_on_erasure
 *     (13) trigger exists on audit_logs
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l04_07_ledger_reason_pii.ts
 */

import { execSync } from "node:child_process";
import { randomUUID } from "node:crypto";

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

function assertTrue(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

function expectCheckViolation(sql: string, label: string): void {
  const out = psql(sql, { allowError: true });
  // check_violation → SQLSTATE 23514. psql prints:
  //   ERROR:  new row for relation "coin_ledger" violates check constraint "..."
  if (!/violates check constraint|23514|check_violation/i.test(out)) {
    throw new Error(`${label}: expected check_violation, got:\n${out}`);
  }
}

function seedUser(label: string): string {
  const uid = randomUUID();
  psql(
    `INSERT INTO auth.users (id, email, instance_id, aud, role,
        encrypted_password, email_confirmed_at, created_at, updated_at)
       VALUES ('${uid}',
               'l04-07-${label}-${uid}@test.local',
               '00000000-0000-0000-0000-000000000000',
               'authenticated', 'authenticated', '', now(), now(), now())
       ON CONFLICT (id) DO NOTHING;`,
  );
  return uid;
}

function cleanupUser(uid: string): void {
  psql(
    `DELETE FROM public.coin_ledger WHERE user_id = '${uid}';
     DELETE FROM public.coin_ledger_pii_redactions WHERE user_id = '${uid}';
     DELETE FROM auth.users WHERE id = '${uid}';`,
    { allowError: true },
  );
}

async function main() {
  console.log(`${BOLD}L04-07 — coin_ledger reason/note PII guard integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ──────────────────────────────────────────────────────────────────────
  section("schema / constraints");

  await test("(1) chk_coin_ledger_reason_length_guard installed", () => {
    const out = psql(
      `SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.coin_ledger'::regclass
          AND conname  = 'chk_coin_ledger_reason_length_guard';`,
    );
    assertEq(out, "chk_coin_ledger_reason_length_guard", "constraint name");
  });

  await test("(2) chk_coin_ledger_reason_pii_guard installed", () => {
    const out = psql(
      `SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.coin_ledger'::regclass
          AND conname  = 'chk_coin_ledger_reason_pii_guard';`,
    );
    assertEq(out, "chk_coin_ledger_reason_pii_guard", "constraint name");
  });

  await test("(3) coin_ledger_pii_redactions table + RLS", () => {
    const rls = psql(
      `SELECT relrowsecurity::text FROM pg_class
        WHERE relnamespace = 'public'::regnamespace
          AND relname = 'coin_ledger_pii_redactions';`,
    );
    assertEq(rls, "true", "RLS enabled");
    const pol = psql(
      `SELECT policyname FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'coin_ledger_pii_redactions'
          AND policyname = 'coin_ledger_pii_redactions_service_role_only';`,
    );
    assertEq(pol, "coin_ledger_pii_redactions_service_role_only", "policy present");
  });

  await test("(4) coin_ledger_archive mirror constraints (if archive exists)", () => {
    const arch = psql(
      `SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace
         AND relname = 'coin_ledger_archive';`,
    );
    if (!arch) return;
    const rows = psql(
      `SELECT COUNT(*)::text FROM pg_constraint
        WHERE conrelid = 'public.coin_ledger_archive'::regclass
          AND conname IN (
            'coin_ledger_archive_reason_length_guard',
            'coin_ledger_archive_reason_pii_guard'
          );`,
    );
    assertEq(rows, "2", "archive guards count");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("CHECK enforcement — reason");

  const u1 = seedUser("check-reason");
  try {
    await test("(5) canonical reason literal accepted", () => {
      psql(
        `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
         VALUES ('${u1}', 10, 'session_completed', '${randomUUID()}', ${Date.now()});`,
      );
    });

    await test("(6) reason containing '@' rejected", () => {
      expectCheckViolation(
        `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
         VALUES ('${u1}', 1, 'leak john@x.com', '${randomUUID()}', ${Date.now()});`,
        "insert email in reason",
      );
    });

    await test("(7) reason with 'by user <uuid>' rejected", () => {
      expectCheckViolation(
        `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
         VALUES ('${u1}', 1, 'burn by user abcd1234ef01', '${randomUUID()}', ${Date.now()});`,
        "insert by-user pattern",
      );
    });

    await test("(8) reason > 64 chars rejected", () => {
      expectCheckViolation(
        `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, created_at_ms)
         VALUES ('${u1}', 1, '${"a".repeat(80)}', '${randomUUID()}', ${Date.now()});`,
        "insert 80-char reason",
      );
    });
  } finally {
    cleanupUser(u1);
  }

  // ──────────────────────────────────────────────────────────────────────
  section("CHECK enforcement — note");

  const noteColExists = psql(
    `SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'coin_ledger'
        AND column_name = 'note';`,
  ) === "1";

  if (noteColExists) {
    const u2 = seedUser("check-note");
    try {
      await test("(9) note with '@' rejected", () => {
        expectCheckViolation(
          `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, note, created_at_ms)
           VALUES ('${u2}', 0, 'admin_adjustment', '${randomUUID()}', 'ops contact ops@example.com', ${Date.now()});`,
          "insert email in note",
        );
      });
      await test("(10) note > 200 chars rejected", () => {
        expectCheckViolation(
          `INSERT INTO public.coin_ledger (user_id, delta_coins, reason, ref_id, note, created_at_ms)
           VALUES ('${u2}', 0, 'admin_adjustment', '${randomUUID()}', '${"x".repeat(250)}', ${Date.now()});`,
          "insert 250-char note",
        );
      });
    } finally {
      cleanupUser(u2);
    }
  } else {
    console.log(`  (skip) note column absent — tests 9-10 n/a`);
  }

  // ──────────────────────────────────────────────────────────────────────
  section("fn_redact_ledger_pii_for_user");

  await test("(11) function exists", () => {
    const out = psql(
      `SELECT proname FROM pg_proc
        WHERE proname = 'fn_redact_ledger_pii_for_user'
          AND pronamespace = 'public'::regnamespace;`,
    );
    assertEq(out, "fn_redact_ledger_pii_for_user", "proc presence");
  });

  await test("(12) call is idempotent (zero redactions for fresh user)", () => {
    const uid = randomUUID();
    const out = psql(
      `SELECT public.fn_redact_ledger_pii_for_user('${uid}', NULL)::text;`,
    );
    // {..."coin_ledger_reason_redacted": 0, "coin_ledger_note_redacted": 0, ...}
    assertTrue(/coin_ledger_reason_redacted/.test(out), `shape: ${out}`);
    assertTrue(/"coin_ledger_reason_redacted"\s*:\s*0/.test(out), `reason=0`);
  });

  // ──────────────────────────────────────────────────────────────────────
  section("trg_ledger_pii_redact_on_erasure");

  await test("(13) trigger exists on audit_logs", () => {
    const auditExists = psql(
      `SELECT 1 FROM pg_class WHERE relnamespace = 'public'::regnamespace
         AND relname = 'audit_logs';`,
    );
    if (!auditExists) {
      console.log(`    (note) audit_logs table absent; skipping trigger assertion`);
      return;
    }
    const out = psql(
      `SELECT tgname FROM pg_trigger
        WHERE tgname = 'trg_ledger_pii_redact_on_erasure'
          AND tgrelid = 'public.audit_logs'::regclass
          AND NOT tgisinternal;`,
    );
    assertEq(out, "trg_ledger_pii_redact_on_erasure", "trigger name");
  });

  console.log(
    `\n${BOLD}${passed + failed} tests · ${passed} passed · ${failed} failed${RESET}`,
  );

  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
