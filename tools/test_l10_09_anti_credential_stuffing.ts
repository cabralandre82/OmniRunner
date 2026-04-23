/**
 * tools/test_l10_09_anti_credential_stuffing.ts
 *
 * L10-09 — integration tests for the email-scoped login throttle.
 */

import { execSync } from "node:child_process";
import { createHash } from "node:crypto";

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

function hashEmail(email: string): string {
  return createHash("sha256").update(email.toLowerCase().trim()).digest("hex");
}

const EMAIL = `l10.09.tests+${Date.now()}@test.invalid`;
const HASH = hashEmail(EMAIL);

function clearCounter(): void {
  psql(`DELETE FROM public.auth_login_attempts WHERE email_hash = '${HASH}';`);
}

function resetConfig(): void {
  psql(`
    UPDATE public.auth_login_throttle_config
    SET fail_threshold_captcha = 3,
        fail_threshold_block   = 10,
        window_seconds         = 900,
        block_seconds          = 900
    WHERE id = 1;
  `);
}

async function main(): Promise<void> {
  console.log(`\n${BOLD}L10-09 — anti credential stuffing integration tests${RESET}`);

  resetConfig();
  clearCounter();

  section("schema / DDL");

  await test("1. auth_login_attempts exists with RLS forced", () => {
    const out = psql(`
      SELECT relrowsecurity::text || '|' || relforcerowsecurity::text
      FROM pg_class WHERE oid = 'public.auth_login_attempts'::regclass;
    `);
    assertEq(out, "true|true", "RLS/forced flags");
  });

  await test("2. auth_login_attempts.email_hash has SHA-256 hex CHECK", () => {
    const out = psql(`
      SELECT count(*)::int
      FROM pg_constraint
      WHERE conrelid = 'public.auth_login_attempts'::regclass
        AND conname  = 'chk_auth_login_attempts_email_hash_shape';
    `);
    assertEq(out, "1", "CHECK constraint presence");
  });

  await test("3. auth_login_throttle_config is singleton (id=1)", () => {
    const out = psql(`
      SELECT count(*)::int FROM public.auth_login_throttle_config WHERE id = 1;
    `);
    assertEq(out, "1", "singleton row");

    const r = psqlAllowError(`
      INSERT INTO public.auth_login_throttle_config (id) VALUES (2);
    `);
    assert(!r.ok, "inserting id=2 should fail");
    assert(/check/i.test(r.out), `expected CHECK violation: ${r.out}`);
  });

  await test("4. throttle primitives registered as SECURITY DEFINER", () => {
    const out = psql(`
      SELECT string_agg(p.proname, ',' ORDER BY p.proname)
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosecdef
        AND p.proname IN (
          'fn_login_throttle_record_failure',
          'fn_login_throttle_record_success',
          'fn_login_throttle_probe',
          'fn_login_throttle_cleanup',
          'fn_login_throttle_assert_shape'
        );
    `);
    assertEq(
      out,
      "fn_login_throttle_assert_shape,fn_login_throttle_cleanup,fn_login_throttle_probe,fn_login_throttle_record_failure,fn_login_throttle_record_success",
      "SECURITY DEFINER set on all helpers",
    );
  });

  await test("5. service_role has EXECUTE on all primitives", () => {
    const out = psql(`
      SELECT
        has_function_privilege('service_role','public.fn_login_throttle_record_failure(text,inet)','EXECUTE') || '|' ||
        has_function_privilege('service_role','public.fn_login_throttle_record_success(text)','EXECUTE') || '|' ||
        has_function_privilege('service_role','public.fn_login_throttle_probe(text)','EXECUTE') || '|' ||
        has_function_privilege('service_role','public.fn_login_throttle_cleanup()','EXECUTE');
    `);
    assertEq(out, "true|true|true|true", "service_role grants");
  });

  await test("6. anon/authenticated do NOT have EXECUTE", () => {
    const out = psql(`
      SELECT
        has_function_privilege('anon','public.fn_login_throttle_record_failure(text,inet)','EXECUTE') || '|' ||
        has_function_privilege('authenticated','public.fn_login_throttle_probe(text)','EXECUTE');
    `);
    assertEq(out, "false|false", "anon/authenticated denied");
  });

  section("argument validation");

  await test("7. record_failure rejects non-hex email_hash", () => {
    const r = psqlAllowError(
      "SELECT public.fn_login_throttle_record_failure('not-a-hash', NULL);",
    );
    assert(!r.ok, "should raise on invalid hash");
    assert(
      /L10-09|email_hash/i.test(r.out),
      `expected L10-09 marker: ${r.out}`,
    );
  });

  await test("8. record_failure rejects NULL email_hash", () => {
    const r = psqlAllowError(
      "SELECT public.fn_login_throttle_record_failure(NULL, NULL);",
    );
    assert(!r.ok, "should raise on NULL hash");
  });

  await test("9. record_failure rejects uppercase hex", () => {
    const r = psqlAllowError(
      `SELECT public.fn_login_throttle_record_failure(upper('${HASH}'), NULL);`,
    );
    assert(!r.ok, "should raise on uppercase");
  });

  await test("10. probe rejects non-hex email_hash", () => {
    const r = psqlAllowError(
      "SELECT public.fn_login_throttle_probe('short');",
    );
    assert(!r.ok, "probe should raise on invalid hash");
  });

  await test("11. record_success rejects non-hex email_hash", () => {
    const r = psqlAllowError(
      "SELECT public.fn_login_throttle_record_success('zzz');",
    );
    assert(!r.ok, "record_success should raise on invalid hash");
  });

  section("behaviour");

  await test("12. first failure → attempts=1, no captcha, not locked", () => {
    clearCounter();
    const out = psql(
      `SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`,
    );
    const j = JSON.parse(out);
    assertEq(j.attempts, 1, "attempts");
    assertEq(j.requires_captcha, false, "requires_captcha");
    assertEq(j.locked, false, "locked");
  });

  await test("13. third failure → attempts=3, requires_captcha=true, not locked", () => {
    clearCounter();
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    const out = psql(
      `SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`,
    );
    const j = JSON.parse(out);
    assertEq(j.attempts, 3, "attempts");
    assertEq(j.requires_captcha, true, "requires_captcha");
    assertEq(j.locked, false, "locked");
  });

  await test("14. tenth failure → locked=true, locked_until in future", () => {
    clearCounter();
    for (let i = 0; i < 10; i++) {
      psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    }
    const out = psql(
      `SELECT public.fn_login_throttle_probe('${HASH}');`,
    );
    const j = JSON.parse(out);
    assertEq(j.attempts >= 10, true, "attempts>=10");
    assertEq(j.locked, true, "locked");
    assert(
      new Date(j.locked_until).getTime() > Date.now(),
      `locked_until should be future, got ${j.locked_until}`,
    );
  });

  await test("15. record_success clears all counters for email_hash", () => {
    clearCounter();
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    psql(`SELECT public.fn_login_throttle_record_success('${HASH}');`);
    const out = psql(
      `SELECT count(*)::int FROM public.auth_login_attempts WHERE email_hash = '${HASH}';`,
    );
    assertEq(out, "0", "counter rows after success");
    const probe = JSON.parse(
      psql(`SELECT public.fn_login_throttle_probe('${HASH}');`),
    );
    assertEq(probe.attempts, 0, "probe attempts after success");
    assertEq(probe.requires_captcha, false, "probe requires_captcha after success");
  });

  await test("16. probe does NOT mutate state", () => {
    clearCounter();
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    psql(`SELECT public.fn_login_throttle_probe('${HASH}');`);
    psql(`SELECT public.fn_login_throttle_probe('${HASH}');`);
    psql(`SELECT public.fn_login_throttle_probe('${HASH}');`);
    const out = psql(
      `SELECT COALESCE(SUM(attempts),0)::int FROM public.auth_login_attempts WHERE email_hash = '${HASH}';`,
    );
    assertEq(out, "1", "probe should not increment counter");
  });

  await test("17. record_failure accepts optional IP and stores it", () => {
    clearCounter();
    psql(
      `SELECT public.fn_login_throttle_record_failure('${HASH}', '203.0.113.42'::inet);`,
    );
    const out = psql(
      `SELECT host(last_ip) FROM public.auth_login_attempts WHERE email_hash = '${HASH}' LIMIT 1;`,
    );
    assertEq(out, "203.0.113.42", "last_ip recorded");
  });

  await test("18. cleanup purges old windows but preserves active lock", () => {
    clearCounter();
    psql(`
      INSERT INTO public.auth_login_attempts (email_hash, window_start, attempts, last_attempt_at)
      VALUES ('${HASH}', now() - interval '2 days', 5, now() - interval '2 days');
    `);
    const deleted = psql("SELECT public.fn_login_throttle_cleanup();");
    assert(parseInt(deleted, 10) >= 1, `cleanup should delete at least 1 row: ${deleted}`);
    const remaining = psql(
      `SELECT count(*)::int FROM public.auth_login_attempts WHERE email_hash = '${HASH}';`,
    );
    assertEq(remaining, "0", "old rows should be gone");
  });

  await test("19. cleanup keeps recent rows", () => {
    clearCounter();
    psql(`SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`);
    psql("SELECT public.fn_login_throttle_cleanup();");
    const remaining = psql(
      `SELECT count(*)::int FROM public.auth_login_attempts WHERE email_hash = '${HASH}';`,
    );
    assertEq(remaining, "1", "recent row should survive cleanup");
  });

  await test("20. config threshold changes take effect immediately", () => {
    clearCounter();
    psql(`
      UPDATE public.auth_login_throttle_config
      SET fail_threshold_captcha = 1
      WHERE id = 1;
    `);
    try {
      const out = psql(
        `SELECT public.fn_login_throttle_record_failure('${HASH}', NULL);`,
      );
      const j = JSON.parse(out);
      assertEq(j.requires_captcha, true, "captcha required at threshold=1");
    } finally {
      resetConfig();
    }
  });

  await test("21. fn_login_throttle_assert_shape() is a no-op when healthy", () => {
    const r = psqlAllowError("SELECT public.fn_login_throttle_assert_shape();");
    assert(r.ok, `assert raised unexpectedly: ${r.out}`);
  });

  clearCounter();

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
