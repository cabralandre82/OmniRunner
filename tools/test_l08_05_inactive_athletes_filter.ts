/**
 * tools/test_l08_05_inactive_athletes_filter.ts
 *
 * L08-05 — integration tests for the inactive-athletes filter on
 * progression views.
 *
 * Scope:
 *   (1) fn_is_athlete_active_90d registered STABLE SECURITY DEFINER
 *   (2) EXECUTE privileges: authenticated+service_role yes, anon no
 *   (3) v_user_progression expanded with last_session_at + is_active_90d
 *   (4) 3 views have security_invoker=on (regression guard)
 *   (5) Fabricate profile + recent session → is_active_90d=true,
 *       last_session_at within 90d
 *   (6) Fabricate profile + session 200d ago → is_active_90d=false,
 *       last_session_at > 90d ago
 *   (7) Fabricate profile + NO sessions → is_active_90d=false,
 *       last_session_at NULL
 *   (8) v_user_progression_active_90d includes only active athletes
 *   (9) fn_is_athlete_active_90d matches the view's is_active_90d col
 *   (10) v_weekly_progress_active_90d excludes sessions > 90d ago
 *
 * Isolation:
 *   Users created under auth.users (UUID) + profiles + sessions with
 *   fabricated start_time_ms values. All rows tagged via a dedicated
 *   prefix so teardown is trivial.
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

// Fabrica 3 atletas: active (sessão 10 dias atrás), inactive (200 dias atrás), empty (zero sessões)
const ACTIVE_UID  = "11111111-1111-1111-1111-00000000a0a0";
const INACTIVE_UID = "11111111-1111-1111-1111-00000000b0b0";
const EMPTY_UID = "11111111-1111-1111-1111-00000000c0c0";

function setup(): void {
  teardown();
  // Criamos usuários em auth.users (FK de sessions) — sessions.user_id referencia auth.users.
  psql(`
    -- Tentar inserir em auth.users; se falhar por schema não existir, skip
    DO $$ BEGIN
      INSERT INTO auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES
        ('${ACTIVE_UID}'::uuid,   '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated','authenticated','l0805-active-${Date.now()}@test.invalid','', now(), now(), now()),
        ('${INACTIVE_UID}'::uuid, '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated','authenticated','l0805-inactive-${Date.now()}@test.invalid','', now(), now(), now()),
        ('${EMPTY_UID}'::uuid,    '00000000-0000-0000-0000-000000000000'::uuid, 'authenticated','authenticated','l0805-empty-${Date.now()}@test.invalid','', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    END $$;

    INSERT INTO public.profiles (id, display_name)
    VALUES
      ('${ACTIVE_UID}'::uuid,   'L0805 Active'),
      ('${INACTIVE_UID}'::uuid, 'L0805 Inactive'),
      ('${EMPTY_UID}'::uuid,    'L0805 Empty')
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.profile_progress (user_id, total_xp, level)
    VALUES
      ('${ACTIVE_UID}'::uuid, 1000, 4),
      ('${INACTIVE_UID}'::uuid, 5000, 10),
      ('${EMPTY_UID}'::uuid, 0, 0)
    ON CONFLICT (user_id) DO UPDATE SET total_xp = excluded.total_xp, level = excluded.level;

    INSERT INTO public.sessions (
      id, user_id, status, start_time_ms, end_time_ms, total_distance_m,
      moving_ms, is_verified, integrity_flags, is_synced, created_at, source
    )
    VALUES
      ( '11111111-1111-1111-1111-000000000aa1'::uuid,
        '${ACTIVE_UID}'::uuid, 1,
        (EXTRACT(EPOCH FROM (now() - interval '10 days')) * 1000)::bigint,
        (EXTRACT(EPOCH FROM (now() - interval '10 days' + interval '30 minutes')) * 1000)::bigint,
        5000, 1800000, true, '{}', true, now() - interval '10 days', 'app'
      ),
      ( '11111111-1111-1111-1111-000000000bb1'::uuid,
        '${INACTIVE_UID}'::uuid, 1,
        (EXTRACT(EPOCH FROM (now() - interval '200 days')) * 1000)::bigint,
        (EXTRACT(EPOCH FROM (now() - interval '200 days' + interval '30 minutes')) * 1000)::bigint,
        4000, 1800000, true, '{}', true, now() - interval '200 days', 'app'
      )
    ON CONFLICT (id) DO NOTHING;
  `);
}

function teardown(): void {
  psql(`
    DELETE FROM public.sessions WHERE user_id IN (
      '${ACTIVE_UID}'::uuid, '${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid
    );
    DELETE FROM public.profile_progress WHERE user_id IN (
      '${ACTIVE_UID}'::uuid, '${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid
    );
    DELETE FROM public.profiles WHERE id IN (
      '${ACTIVE_UID}'::uuid, '${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid
    );
    DO $$ BEGIN
      DELETE FROM auth.users WHERE id IN (
        '${ACTIVE_UID}'::uuid, '${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid
      );
    EXCEPTION WHEN undefined_table OR insufficient_privilege THEN NULL;
    END $$;
  `);
}

async function main(): Promise<void> {
  console.log(`${BOLD}L08-05 — inactive athletes filter integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  setup();

  // ──────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) fn_is_athlete_active_90d is STABLE SECURITY DEFINER", () => {
    const out = psql(`
      SELECT p.prosecdef::text || ',' || p.provolatile::text
        FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'fn_is_athlete_active_90d';
    `);
    assertEq(out, "true,s", "prosecdef,provolatile");
  });

  await test("(2) privileges: authenticated+service_role yes, anon no", () => {
    const out = psql(`
      SELECT string_agg(
        r.rolname || ':' || has_function_privilege(r.rolname, 'public.fn_is_athlete_active_90d(uuid)', 'EXECUTE')::text,
        ',' ORDER BY r.rolname)
      FROM pg_roles r WHERE r.rolname IN ('anon','authenticated','service_role');
    `);
    assert(out.includes("anon:false"), `anon: ${out}`);
    assert(out.includes("authenticated:true"), `authenticated: ${out}`);
    assert(out.includes("service_role:true"), `service_role: ${out}`);
  });

  await test("(3) v_user_progression has last_session_at + is_active_90d", () => {
    const out = psql(`
      SELECT string_agg(a.attname::text, ',' ORDER BY a.attname)
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relname = 'v_user_progression'
         AND a.attnum > 0
         AND a.attname IN ('last_session_at', 'is_active_90d');
    `);
    assertEq(out, "is_active_90d,last_session_at", "new columns");
  });

  await test("(4) 3 views com security_invoker=on", () => {
    const out = psql(`
      SELECT count(*)::int
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relkind = 'v'
         AND c.relname IN (
           'v_user_progression',
           'v_user_progression_active_90d',
           'v_weekly_progress_active_90d'
         )
         AND c.reloptions @> ARRAY['security_invoker=on']::text[];
    `);
    assertEq(out, "3", "security_invoker views");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("is_active_90d / last_session_at — fabricated fixtures");

  await test("(5) ativo (session 10d atrás) → is_active_90d=true, last_session_at within 90d", () => {
    const out = psql(`
      SELECT is_active_90d::text || ',' ||
             COALESCE((last_session_at > now() - interval '90 days')::text, 'null')
        FROM public.v_user_progression
       WHERE user_id = '${ACTIVE_UID}'::uuid;
    `);
    assertEq(out, "true,true", "active flags");
  });

  await test("(6) inativo (session 200d atrás) → is_active_90d=false, last_session_at > 90d ago", () => {
    const out = psql(`
      SELECT is_active_90d::text || ',' ||
             (last_session_at < now() - interval '90 days')::text
        FROM public.v_user_progression
       WHERE user_id = '${INACTIVE_UID}'::uuid;
    `);
    assertEq(out, "false,true", "inactive flags");
  });

  await test("(7) empty (zero sessions) → is_active_90d=false, last_session_at NULL", () => {
    const out = psql(`
      SELECT is_active_90d::text || ',' ||
             COALESCE(last_session_at::text, 'NULL')
        FROM public.v_user_progression
       WHERE user_id = '${EMPTY_UID}'::uuid;
    `);
    assertEq(out, "false,NULL", "empty flags");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("v_user_progression_active_90d — filter semantics");

  await test("(8) active user is present in v_user_progression_active_90d", () => {
    const out = psql(`
      SELECT user_id::text
        FROM public.v_user_progression_active_90d
       WHERE user_id = '${ACTIVE_UID}'::uuid;
    `);
    assertEq(out, ACTIVE_UID, "active user present");
  });

  await test("(9) inactive+empty users NOT in v_user_progression_active_90d", () => {
    const out = psql(`
      SELECT count(*)::int
        FROM public.v_user_progression_active_90d
       WHERE user_id IN ('${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid);
    `);
    assertEq(out, "0", "filtered out");
  });

  await test("(10) fn_is_athlete_active_90d matches view column", () => {
    const out = psql(`
      SELECT string_agg(
        user_id::text || '=' ||
        public.fn_is_athlete_active_90d(user_id)::text || '/' ||
        is_active_90d::text,
        '|' ORDER BY user_id)
        FROM public.v_user_progression
       WHERE user_id IN ('${ACTIVE_UID}'::uuid, '${INACTIVE_UID}'::uuid, '${EMPTY_UID}'::uuid);
    `);
    // All three: fn() result should equal view column
    const pairs = out.split("|");
    assertEq(pairs.length, 3, "pair count");
    for (const p of pairs) {
      const [, fnAndCol] = p.split("=");
      const [fnRes, colRes] = fnAndCol.split("/");
      assert(fnRes === colRes, `fn vs col mismatch: ${p}`);
    }
  });

  await test("(11) v_weekly_progress_active_90d exclui sessions > 90d", () => {
    const out = psql(`
      SELECT count(*)::int
        FROM public.v_weekly_progress_active_90d
       WHERE user_id = '${INACTIVE_UID}'::uuid;
    `);
    assertEq(out, "0", "inactive user filtered out");
  });

  await test("(12) v_weekly_progress_active_90d inclui sessions recentes com dist ≥ 200m", () => {
    // Active user tem 5000m em sessão de 10d — deve aparecer
    const out = psql(`
      SELECT count(*)::int
        FROM public.v_weekly_progress_active_90d
       WHERE user_id = '${ACTIVE_UID}'::uuid;
    `);
    assertEq(out, "1", "active user 1 week");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("backward compatibility");

  await test("(13) v_user_progression ainda tem as colunas originais", () => {
    const out = psql(`
      SELECT string_agg(a.attname::text, ',' ORDER BY a.attnum)
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public'
         AND c.relname = 'v_user_progression'
         AND a.attnum > 0
         AND a.attname IN (
           'user_id','display_name','avatar_url','total_xp','level',
           'xp_to_next_level','streak_current','streak_best','has_freeze_available'
         );
    `);
    assert(
      out.split(",").length === 9,
      `expected 9 original cols present, got: ${out}`,
    );
  });

  await test("(14) o SELECT canônico usado pelo mobile (streak+level+total_xp) funciona", () => {
    const out = psql(`
      SELECT user_id::text || ',' || COALESCE(total_xp::text,'NULL') || ',' ||
             COALESCE(level::text,'NULL') || ',' || COALESCE(streak_current::text,'NULL')
        FROM public.v_user_progression
       WHERE user_id = '${ACTIVE_UID}'::uuid;
    `);
    assert(
      out.startsWith(ACTIVE_UID + ",1000,4,"),
      `mobile-shape read: got ${out}`,
    );
  });

  teardown();

  console.log(
    `\n${BOLD}Summary${RESET}: ${passed} passed, ${failed} failed (${total} total)`,
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  teardown();
  process.exit(1);
});
