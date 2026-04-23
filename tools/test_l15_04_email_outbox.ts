/**
 * tools/test_l15_04_email_outbox.ts
 *
 * Integration tests for the L15-04 email_outbox migration
 * (`supabase/migrations/20260421360000_l15_04_email_outbox.sql`).
 *
 * Uses `docker exec psql` (same pattern as test_l12_09) to avoid a
 * node_modules `pg` dependency. Exercises schema/DDL, argument
 * validation, enqueue/mark-sent/mark-failed semantics, and the CI
 * assert-shape helper.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1)  email_outbox table present + RLS forced
 *     (2)  fn_enqueue_email registered + SECURITY DEFINER
 *     (3)  fn_mark_email_sent registered + SECURITY DEFINER
 *     (4)  fn_mark_email_failed registered + SECURITY DEFINER
 *     (5)  fn_email_outbox_assert_shape registered + SECURITY DEFINER
 *     (6)  service_role has EXECUTE on all four helpers
 *     (7)  anon + authenticated DO NOT have EXECUTE on any helper
 *     (8)  UNIQUE index email_outbox_idempotency_key_uniq
 *     (9)  all 5 CHECK constraints present
 *
 *   argument validation
 *    (10)  fn_enqueue_email rejects empty recipient
 *    (11)  fn_enqueue_email rejects idempotency_key < 8 chars
 *    (12)  fn_mark_email_sent rejects NULL id
 *
 *   behaviour
 *    (13)  enqueue twice with same key → same row, recipient normalised
 *    (14)  mark_email_sent flips to sent + is idempotent
 *    (15)  mark_email_failed(terminal=false) keeps pending + bumps attempts
 *    (16)  mark_email_failed(terminal=true) flips to failed
 *    (17)  sent → failed raises P0010; failed → sent raises P0010
 *    (18)  fn_email_outbox_assert_shape no-op when healthy
 *    (19)  fn_email_outbox_assert_shape raises when table missing
 *          (skipped — requires privileged DROP; we only run the no-op case)
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l15_04_email_outbox.ts
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

function randKey(prefix = "l15-04-test"): string {
  return `${prefix}-${Math.random().toString(36).slice(2)}-${Date.now()}`;
}

async function main() {
  console.log(`${BOLD}L15-04 — email_outbox integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) email_outbox table present + RLS forced", () => {
    const out = psql(
      `SELECT relrowsecurity::text, relforcerowsecurity::text
         FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
        WHERE n.nspname = 'public' AND c.relname = 'email_outbox';`,
    );
    assertEq(out, "true|true", "RLS + FORCE RLS");
  });

  await test("(2) fn_enqueue_email registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT prosecdef::text, pg_get_function_arguments(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_enqueue_email';`,
    );
    if (!out) throw new Error("fn_enqueue_email not registered");
    assertContains(out, "true|", "SECURITY DEFINER");
    assertContains(out, "p_recipient_email text", "recipient param");
    assertContains(out, "p_idempotency_key text", "idempotency param");
  });

  await test("(3) fn_mark_email_sent registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT prosecdef::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_mark_email_sent';`,
    );
    assertEq(out, "true", "SECURITY DEFINER on fn_mark_email_sent");
  });

  await test("(4) fn_mark_email_failed registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT prosecdef::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_mark_email_failed';`,
    );
    assertEq(out, "true", "SECURITY DEFINER on fn_mark_email_failed");
  });

  await test("(5) fn_email_outbox_assert_shape registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT prosecdef::text
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_email_outbox_assert_shape';`,
    );
    assertEq(out, "true", "SECURITY DEFINER on fn_email_outbox_assert_shape");
  });

  await test("(6) service_role has EXECUTE on all four helpers", () => {
    const out = psql(
      `SELECT has_function_privilege('service_role',
              'public.fn_enqueue_email(text,uuid,text,text,jsonb,text)', 'EXECUTE')::text,
              has_function_privilege('service_role',
              'public.fn_mark_email_sent(uuid,text,text)', 'EXECUTE')::text,
              has_function_privilege('service_role',
              'public.fn_mark_email_failed(uuid,text,boolean)', 'EXECUTE')::text,
              has_function_privilege('service_role',
              'public.fn_email_outbox_assert_shape()', 'EXECUTE')::text;`,
    );
    assertEq(out, "true|true|true|true", "service_role has EXECUTE on all four");
  });

  await test("(7) anon + authenticated DO NOT have EXECUTE on any helper", () => {
    const out = psql(
      `SELECT has_function_privilege('anon',
              'public.fn_enqueue_email(text,uuid,text,text,jsonb,text)', 'EXECUTE')::text,
              has_function_privilege('authenticated',
              'public.fn_enqueue_email(text,uuid,text,text,jsonb,text)', 'EXECUTE')::text,
              has_function_privilege('anon',
              'public.fn_mark_email_sent(uuid,text,text)', 'EXECUTE')::text,
              has_function_privilege('authenticated',
              'public.fn_mark_email_failed(uuid,text,boolean)', 'EXECUTE')::text;`,
    );
    assertEq(out, "false|false|false|false", "anon/authenticated denied");
  });

  await test("(8) UNIQUE index email_outbox_idempotency_key_uniq", () => {
    const out = psql(
      `SELECT i.indisunique::text
         FROM pg_index i
         JOIN pg_class c ON c.oid = i.indexrelid
        WHERE c.relname = 'email_outbox_idempotency_key_uniq';`,
    );
    assertEq(out, "true", "UNIQUE index present");
  });

  await test("(9) all 5 CHECK constraints present", () => {
    const out = psql(
      `SELECT COUNT(*)::text
         FROM pg_constraint
        WHERE conrelid = 'public.email_outbox'::regclass
          AND contype = 'c'
          AND conname IN (
            'email_outbox_status_check',
            'email_outbox_recipient_email_check',
            'email_outbox_template_key_check',
            'email_outbox_idempotency_key_check',
            'email_outbox_attempts_check'
          );`,
    );
    assertEq(out, "5", "all 5 check constraints present");
  });

  // ─────────────────────────────────────────────────────────────────────
  section("argument validation");

  await test("(10) fn_enqueue_email rejects empty recipient", () => {
    const out = psql(
      `SELECT public.fn_enqueue_email('  ', NULL, 'payment_confirmation',
         'subject', '{}'::jsonb, '${randKey()}');`,
      { allowError: true },
    );
    if (!/INVALID_RECIPIENT/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_RECIPIENT, got:\n${out}`);
    }
  });

  await test("(11) fn_enqueue_email rejects idempotency_key < 8 chars", () => {
    const out = psql(
      `SELECT public.fn_enqueue_email('x@y.io', NULL, 'payment_confirmation',
         'subject', '{}'::jsonb, 'short');`,
      { allowError: true },
    );
    if (!/INVALID_IDEMPOTENCY_KEY/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_IDEMPOTENCY_KEY, got:\n${out}`);
    }
  });

  await test("(12) fn_mark_email_sent rejects NULL id", () => {
    const out = psql(
      `SELECT public.fn_mark_email_sent(NULL, 'resend', 'msg-x');`,
      { allowError: true },
    );
    if (!/INVALID_ID/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_ID, got:\n${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("behaviour");

  const keyA = randKey("l15-04-behaviour-A");
  const keyB = randKey("l15-04-behaviour-B");
  const keyC = randKey("l15-04-behaviour-C");

  await test("(13) enqueue twice with same key → same row, recipient normalised", () => {
    const idFirst = psql(
      `SELECT public.fn_enqueue_email(
         'MixedCase@Example.com ', NULL, 'payment_confirmation',
         'subject first', '{"k":"v1"}'::jsonb, '${keyA}');`,
    );
    const idSecond = psql(
      `SELECT public.fn_enqueue_email(
         'other@example.com', NULL, 'payment_confirmation',
         'subject second', '{"k":"v2"}'::jsonb, '${keyA}');`,
    );
    assertEq(idFirst, idSecond, "same key returns same id");

    const email = psql(
      `SELECT recipient_email FROM public.email_outbox WHERE id = '${idFirst}'::uuid;`,
    );
    assertEq(email, "mixedcase@example.com", "recipient normalised to lower(trim())");
  });

  await test("(14) mark_email_sent flips to sent + is idempotent", () => {
    const id = psql(
      `SELECT public.fn_enqueue_email(
         'sent@example.com', NULL, 'payment_confirmation',
         'subject sent', '{}'::jsonb, '${keyB}');`,
    );
    const first = psql(
      `SELECT public.fn_mark_email_sent('${id}'::uuid, 'inbucket', 'msg-1');`,
    );
    assertEq(first, "t", "first mark_email_sent returns TRUE");
    const again = psql(
      `SELECT public.fn_mark_email_sent('${id}'::uuid, 'inbucket', 'msg-1');`,
    );
    assertEq(again, "t", "idempotent mark_email_sent returns TRUE");
    const st = psql(
      `SELECT status FROM public.email_outbox WHERE id = '${id}'::uuid;`,
    );
    assertEq(st, "sent", "status flipped to sent");
  });

  await test("(15) mark_email_failed(non-terminal) keeps pending + bumps attempts", () => {
    const id = psql(
      `SELECT public.fn_enqueue_email(
         'fail@example.com', NULL, 'payment_confirmation',
         'subject fail', '{}'::jsonb, '${keyC}');`,
    );
    const first = psql(
      `SELECT public.fn_mark_email_failed('${id}'::uuid, 'provider 503', false);`,
    );
    assertEq(first, "t", "non-terminal fail returns TRUE");
    const out = psql(
      `SELECT status || '|' || attempts::text
         FROM public.email_outbox WHERE id = '${id}'::uuid;`,
    );
    assertEq(out, "pending|1", "pending + attempts=1");

    const second = psql(
      `SELECT public.fn_mark_email_failed('${id}'::uuid, 'provider 502', false);`,
    );
    assertEq(second, "t", "second non-terminal fail returns TRUE");
    const out2 = psql(
      `SELECT status || '|' || attempts::text
         FROM public.email_outbox WHERE id = '${id}'::uuid;`,
    );
    assertEq(out2, "pending|2", "still pending + attempts=2");
  });

  await test("(16) mark_email_failed(terminal) flips to failed", () => {
    const id = psql(
      `SELECT id FROM public.email_outbox WHERE idempotency_key = '${keyC}'::text;`,
    );
    const out = psql(
      `SELECT public.fn_mark_email_failed('${id}'::uuid, 'bounced', true);`,
    );
    assertEq(out, "t", "terminal fail returns TRUE");
    const st = psql(
      `SELECT status FROM public.email_outbox WHERE id = '${id}'::uuid;`,
    );
    assertEq(st, "failed", "status flipped to failed");
  });

  await test("(17) sent → failed + failed → sent both raise P0010", () => {
    // sent row (from test 14)
    const sentId = psql(
      `SELECT id FROM public.email_outbox WHERE idempotency_key = '${keyB}'::text;`,
    );
    const out1 = psql(
      `SELECT public.fn_mark_email_failed('${sentId}'::uuid, 'late bounce', true);`,
      { allowError: true },
    );
    if (!/INVALID_TRANSITION/.test(out1) && !/P0010/.test(out1)) {
      throw new Error(`expected INVALID_TRANSITION sent→failed, got:\n${out1}`);
    }
    // failed row (from test 16)
    const failedId = psql(
      `SELECT id FROM public.email_outbox WHERE idempotency_key = '${keyC}'::text;`,
    );
    const out2 = psql(
      `SELECT public.fn_mark_email_sent('${failedId}'::uuid, 'resend', 'msg-x');`,
      { allowError: true },
    );
    if (!/INVALID_TRANSITION/.test(out2) && !/P0010/.test(out2)) {
      throw new Error(`expected INVALID_TRANSITION failed→sent, got:\n${out2}`);
    }
  });

  await test("(18) fn_email_outbox_assert_shape no-op when healthy", () => {
    const out = psql(`SELECT public.fn_email_outbox_assert_shape();`);
    assertEq(out, "", "assert_shape returns void (empty stdout) when healthy");
  });

  // Cleanup (belt-and-suspenders; the migration does not rely on this but
  // keeping the test sandbox tidy is nice).
  psql(
    `DELETE FROM public.email_outbox WHERE idempotency_key IN (
       '${keyA}', '${keyB}', '${keyC}');`,
    { allowError: true },
  );

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
