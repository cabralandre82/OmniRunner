/**
 * tools/test_l08_04_sessions_coherence_check.ts
 *
 * L08-04 — integration tests for chk_sessions_coherence and its helpers.
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
  if (got !== want) throw new Error(`${msg}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}

const UID = "22222222-2222-2222-2222-000000008040";

function setup(): void {
  teardown();
  psql(`
    DO $$ BEGIN
      INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES ('${UID}'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated','authenticated','l0804-${Date.now()}@test.invalid','', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    END $$;
  `);
}

function teardown(): void {
  psql(`
    DELETE FROM public.sessions WHERE user_id = '${UID}'::uuid;
    DO $$ BEGIN
      DELETE FROM auth.users WHERE id = '${UID}'::uuid;
    EXCEPTION WHEN undefined_table OR insufficient_privilege THEN NULL;
    END $$;
  `);
}

function insertSession(
  id: string,
  status: number,
  dist: number,
  movingMs: number,
): { out: string; ok: boolean } {
  return psqlAllowError(`
    INSERT INTO public.sessions (
      id, user_id, status, start_time_ms, end_time_ms, total_distance_m,
      moving_ms, is_verified, integrity_flags, is_synced, created_at, source
    ) VALUES (
      '${id}'::uuid,
      '${UID}'::uuid,
      ${status},
      1000000, 2000000,
      ${dist}, ${movingMs},
      true, '{}', true, now(), 'app'
    );
  `);
}

async function main(): Promise<void> {
  console.log(`${BOLD}L08-04 — sessions coherence CHECK tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  setup();

  section("schema / DDL");

  await test("(1) chk_sessions_coherence registered, VALIDATED", () => {
    const out = psql(`
      SELECT con.conname || ':' || con.convalidated::text
        FROM pg_constraint con
        JOIN pg_class c ON c.oid = con.conrelid
       WHERE c.relname = 'sessions' AND con.conname = 'chk_sessions_coherence';
    `);
    assertEq(out, "chk_sessions_coherence:true", "constraint state");
  });

  await test("(2) fn_find_sessions_incoherent + fn_assert_sessions_coherence SECURITY DEFINER", () => {
    const out = psql(`
      SELECT count(*)::int FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname='public' AND p.prosecdef=true
        AND p.proname IN ('fn_find_sessions_incoherent','fn_assert_sessions_coherence');
    `);
    assertEq(out, "2", "SECURITY DEFINER fn count");
  });

  await test("(3) privileges: only service_role can EXECUTE", () => {
    const out = psql(`
      SELECT string_agg(
        r.rolname || ':' ||
        has_function_privilege(r.rolname, 'public.fn_assert_sessions_coherence()', 'EXECUTE')::text,
        ',' ORDER BY r.rolname)
      FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role');
    `);
    assert(out.includes("anon:false"), `anon: ${out}`);
    assert(out.includes("authenticated:false"), `authenticated: ${out}`);
    assert(out.includes("service_role:true"), `service_role: ${out}`);
  });

  section("accepted rows");

  await test("(4) status < 3 com qualquer combinação é aceito", () => {
    const r = insertSession(
      "deadbeef-0804-0000-0000-000000000001",
      1, // incomplete
      0, 0,
    );
    assert(r.ok, `unexpected fail: ${r.out}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000001';");
  });

  await test("(5) status=3 com (0,0) é aceito (sessão cancelada/drop)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000002", 3, 0, 0);
    assert(r.ok, `unexpected fail: ${r.out}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000002';");
  });

  await test("(6) status=3 com (150m, 90s) é aceito (real)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000003", 3, 150, 90000);
    assert(r.ok, `unexpected fail: ${r.out}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000003';");
  });

  await test("(7) status=3 com (100m, 60s) exatos (boundary) é aceito", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000004", 3, 100, 60000);
    assert(r.ok, `unexpected fail: ${r.out}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000004';");
  });

  section("rejected rows");

  await test("(8) status=3 com (5000m, 0ms) rejeitado (GPS zero moving)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000005", 3, 5000, 0);
    assert(!r.ok, `expected fail but succeeded`);
    assert(/chk_sessions_coherence|check_violation/i.test(r.out), `expected check err, got ${r.out.slice(0, 300)}`);
  });

  await test("(9) status=3 com (0m, 60000ms) rejeitado (zero dist com moving)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000006", 3, 0, 60000);
    assert(!r.ok, `expected fail but succeeded`);
    assert(/chk_sessions_coherence/i.test(r.out), `expected check err: ${r.out.slice(0, 300)}`);
  });

  await test("(10) status=3 com (99m, 60000ms) rejeitado (dist < 100)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000007", 3, 99, 60000);
    assert(!r.ok, `expected fail but succeeded`);
    assert(/chk_sessions_coherence/i.test(r.out), `expected check err: ${r.out.slice(0, 300)}`);
  });

  await test("(11) status=3 com (100m, 59999ms) rejeitado (moving < 60s)", () => {
    const r = insertSession("deadbeef-0804-0000-0000-000000000008", 3, 100, 59999);
    assert(!r.ok, `expected fail but succeeded`);
    assert(/chk_sessions_coherence/i.test(r.out), `expected check err: ${r.out.slice(0, 300)}`);
  });

  section("detector / assert helpers");

  await test("(12) fn_find_sessions_incoherent retorna 0 em estado limpo", () => {
    const out = psql("SELECT count(*)::int FROM public.fn_find_sessions_incoherent(1000);");
    assertEq(out, "0", "incoherent rows in clean state");
  });

  await test("(13) fn_assert_sessions_coherence retorna true em estado limpo", () => {
    const out = psql("SELECT public.fn_assert_sessions_coherence()::text;");
    assertEq(out, "true", "assert result");
  });

  await test("(14) UPDATE que deixaria coerente → permitido", () => {
    // Insere sessão válida
    const r1 = insertSession("deadbeef-0804-0000-0000-000000000009", 3, 200, 90000);
    assert(r1.ok, `setup fail: ${r1.out}`);
    // UPDATE para valores ainda válidos
    const r2 = psqlAllowError(`
      UPDATE public.sessions
         SET total_distance_m = 500, moving_ms = 300000
       WHERE id = 'deadbeef-0804-0000-0000-000000000009';
    `);
    assert(r2.ok, `unexpected UPDATE fail: ${r2.out}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000009';");
  });

  await test("(15) UPDATE que tornaria incoerente → rejeitado", () => {
    const r1 = insertSession("deadbeef-0804-0000-0000-000000000010", 3, 200, 90000);
    assert(r1.ok, `setup fail: ${r1.out}`);
    const r2 = psqlAllowError(`
      UPDATE public.sessions SET moving_ms = 0
       WHERE id = 'deadbeef-0804-0000-0000-000000000010';
    `);
    assert(!r2.ok, `expected UPDATE to fail`);
    assert(/chk_sessions_coherence/i.test(r2.out), `expected check err: ${r2.out.slice(0, 300)}`);
    psql("DELETE FROM public.sessions WHERE id = 'deadbeef-0804-0000-0000-000000000010';");
  });

  teardown();

  console.log(`\n${BOLD}Summary${RESET}: ${passed} passed, ${failed} failed (${total} total)`);
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  teardown();
  process.exit(1);
});
