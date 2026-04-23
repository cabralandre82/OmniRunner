/**
 * tools/test_l22_05_coaching_groups_nearby.ts
 *
 * L22-05 — integration tests for coaching_groups discovery RPCs
 * (`fn_groups_nearby`, `fn_group_set_base_location`, and the
 * `fn_coaching_groups_assert_discovery_shape` shape guard).
 *
 * Runs against the local supabase docker Postgres via
 * `docker exec psql`. All writes live in a helper schema /
 * sandboxed rows that are cleaned up at the end of the run.
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

// São Paulo downtown baseline — all fixtures sit within a few km.
const SP_LAT = -23.55052;
const SP_LNG = -46.633308;

const COACH_1 = "11111111-2222-3333-4444-555555555555";
const COACH_2 = "22222222-3333-4444-5555-666666666666";
const COACH_3 = "33333333-4444-5555-6666-777777777777";

const GROUP_1 = "00000000-0000-4000-8000-000000000001"; // SP center, discovery on
const GROUP_2 = "00000000-0000-4000-8000-000000000002"; // 3 km SW, discovery on
const GROUP_3 = "00000000-0000-4000-8000-000000000003"; // 12 km N, discovery on
const GROUP_4 = "00000000-0000-4000-8000-000000000004"; // SP, discovery OFF
const GROUP_5 = "00000000-0000-4000-8000-000000000005"; // SP, pending approval
const GROUP_6 = "00000000-0000-4000-8000-000000000006"; // 40 km E, discovery on

function setupFixtures(): void {
  // Ensure no residue from a prior run.
  psql(`
    DELETE FROM public.coaching_groups WHERE id IN (
      '${GROUP_1}','${GROUP_2}','${GROUP_3}','${GROUP_4}','${GROUP_5}','${GROUP_6}'
    );
    DELETE FROM auth.users WHERE id IN (
      '${COACH_1}'::uuid,'${COACH_2}'::uuid,'${COACH_3}'::uuid
    );
  `);

  // Seed auth.users + profiles (required by coaching_groups.coach_user_id FK)
  // + coaching_groups with varied (lat, lng, allow_discovery, approval_status).
  psql(`
    INSERT INTO auth.users (id, email, created_at, updated_at)
    VALUES
      ('${COACH_1}', 'c1@test.invalid', now(), now()),
      ('${COACH_2}', 'c2@test.invalid', now(), now()),
      ('${COACH_3}', 'c3@test.invalid', now(), now());

    INSERT INTO public.profiles (id, display_name, created_at, updated_at)
    VALUES
      ('${COACH_1}', 'Coach Um', now(), now()),
      ('${COACH_2}', 'Coach Dois', now(), now()),
      ('${COACH_3}', 'Coach Tres', now(), now())
    ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name;
  `);

  psql(`
    INSERT INTO public.coaching_groups (
      id, name, coach_user_id, city, created_at_ms,
      approval_status, base_lat, base_lng, location_precision_m, allow_discovery
    ) VALUES
      ('${GROUP_1}', 'Grupo SP Centro',     '${COACH_1}', 'São Paulo', 0,
        'approved',        ${SP_LAT},          ${SP_LNG},          1000, true),
      ('${GROUP_2}', 'Grupo SP SW 3km',     '${COACH_2}', 'São Paulo', 0,
        'approved',        ${SP_LAT - 0.02},   ${SP_LNG - 0.02},   500,  true),
      ('${GROUP_3}', 'Grupo SP Norte 12km', '${COACH_3}', 'São Paulo', 0,
        'approved',        ${SP_LAT + 0.108}, ${SP_LNG},           1000, true),
      ('${GROUP_4}', 'Grupo Privado',       '${COACH_1}', 'São Paulo', 0,
        'approved',        ${SP_LAT},          ${SP_LNG},          1000, false),
      ('${GROUP_5}', 'Grupo Pendente',      '${COACH_2}', 'São Paulo', 0,
        'pending_approval',${SP_LAT},          ${SP_LNG},          1000, true),
      ('${GROUP_6}', 'Grupo Longe',         '${COACH_3}', 'Campinas',  0,
        'approved',        ${SP_LAT},          ${SP_LNG + 0.4},    5000, true);
  `);
}

function teardownFixtures(): void {
  psql(`
    DELETE FROM public.coaching_groups WHERE id IN (
      '${GROUP_1}','${GROUP_2}','${GROUP_3}','${GROUP_4}','${GROUP_5}','${GROUP_6}'
    );
    DELETE FROM public.profiles WHERE id IN (
      '${COACH_1}'::uuid,'${COACH_2}'::uuid,'${COACH_3}'::uuid
    );
    DELETE FROM auth.users WHERE id IN (
      '${COACH_1}'::uuid,'${COACH_2}'::uuid,'${COACH_3}'::uuid
    );
  `);
}

async function main(): Promise<void> {
  console.log(`${BOLD}L22-05 — coaching_groups nearby discovery${RESET}`);

  setupFixtures();

  try {
    section("Schema / DDL");

    await test("base_lat, base_lng, allow_discovery, location_precision_m exist", () => {
      const out = psql(`
        SELECT string_agg(column_name, ',' ORDER BY column_name)
          FROM information_schema.columns
          WHERE table_schema='public'
            AND table_name='coaching_groups'
            AND column_name IN ('base_lat','base_lng','allow_discovery','location_precision_m');
      `);
      assertEq(out, "allow_discovery,base_lat,base_lng,location_precision_m", "columns");
    });

    await test("allow_discovery defaults to false + NOT NULL", () => {
      const nullable = psql(`
        SELECT is_nullable FROM information_schema.columns
          WHERE table_schema='public' AND table_name='coaching_groups'
            AND column_name='allow_discovery';
      `);
      assertEq(nullable, "NO", "allow_discovery is NOT NULL");
      const dflt = psql(`
        SELECT column_default FROM information_schema.columns
          WHERE table_schema='public' AND table_name='coaching_groups'
            AND column_name='allow_discovery';
      `);
      assert(dflt.toLowerCase().startsWith("false"), `default was ${dflt}`);
    });

    await test("idx_coaching_groups_discovery_lat exists as a partial btree", () => {
      const def = psql(`
        SELECT indexdef FROM pg_indexes
          WHERE schemaname='public'
            AND indexname='idx_coaching_groups_discovery_lat';
      `);
      assert(def.length > 0, "index not found");
      assert(def.includes("base_lat"), "index must reference base_lat");
      assert(def.includes("WHERE"), "index must be partial");
    });

    await test("4 CHECK constraints registered with L19-08 naming", () => {
      const out = psql(`
        SELECT string_agg(conname, ',' ORDER BY conname)
          FROM pg_constraint
          WHERE conname IN (
            'chk_coaching_groups_base_lat_range',
            'chk_coaching_groups_base_lng_range',
            'chk_coaching_groups_location_precision',
            'chk_coaching_groups_discovery_needs_coords'
          );
      `);
      assertEq(
        out,
        "chk_coaching_groups_base_lat_range,chk_coaching_groups_base_lng_range,chk_coaching_groups_discovery_needs_coords,chk_coaching_groups_location_precision",
        "all 4 CHECKs",
      );
    });

    await test("helpers registered with correct volatility + security posture", () => {
      const snapRow = psql(`
        SELECT provolatile::text || ':' || prosecdef::text
          FROM pg_proc
          WHERE oid = to_regprocedure('public.fn_groups_snap_coord(numeric,integer)');
      `);
      assertEq(snapRow, "i:false", "snap is IMMUTABLE, not SECURITY DEFINER");

      const nearRow = psql(`
        SELECT provolatile::text || ':' || prosecdef::text
          FROM pg_proc
          WHERE oid = to_regprocedure('public.fn_groups_nearby(numeric,numeric,integer)');
      `);
      assertEq(nearRow, "s:true", "fn_groups_nearby is STABLE + SECURITY DEFINER");

      const setRow = psql(`
        SELECT provolatile::text || ':' || prosecdef::text
          FROM pg_proc
          WHERE oid = to_regprocedure(
            'public.fn_group_set_base_location(uuid,numeric,numeric,integer,boolean)');
      `);
      assertEq(setRow, "v:true", "fn_group_set_base_location is VOLATILE + SECURITY DEFINER");
    });

    await test("anon denied, authenticated allowed for fn_groups_nearby", () => {
      const anonCan = psql(`
        SELECT has_function_privilege('anon',
          'public.fn_groups_nearby(numeric,numeric,integer)', 'EXECUTE');
      `);
      const authCan = psql(`
        SELECT has_function_privilege('authenticated',
          'public.fn_groups_nearby(numeric,numeric,integer)', 'EXECUTE');
      `);
      assertEq(anonCan, "f", "anon must NOT execute");
      assertEq(authCan, "t", "authenticated must execute");
    });

    section("fn_groups_snap_coord");

    await test("1km precision: rounds to ~0.009° (~1 km) grid", () => {
      const snapped = psql(`SELECT public.fn_groups_snap_coord(-23.55052::numeric, 1000);`);
      const n = Number(snapped);
      assert(Number.isFinite(n), `snap returned non-number: ${snapped}`);
      // Drift from input must be <= half a grid step (~0.0045°).
      assert(Math.abs(n - -23.55052) < 0.005, `drift ${n} from -23.55052 too large`);
    });

    await test("500 m precision: finer than 1 km", () => {
      const fine = Number(psql(`SELECT public.fn_groups_snap_coord(-23.5505234::numeric, 500);`));
      const coarse = Number(psql(`SELECT public.fn_groups_snap_coord(-23.5505234::numeric, 5000);`));
      assert(Math.abs(fine - -23.5505234) < Math.abs(coarse - -23.5505234) + 0.001,
        "500m should be at least as fine as 5km");
    });

    await test("rejects precision outside {500, 1000, 5000}", () => {
      const { out, ok } = psqlAllowError(`SELECT public.fn_groups_snap_coord(0::numeric, 200);`);
      assert(!ok, "must raise on precision=200");
      assert(out.includes("INVALID_PRECISION"), `unexpected error: ${out}`);
    });

    await test("NULL coord returns NULL", () => {
      const n = psql(`SELECT public.fn_groups_snap_coord(NULL::numeric, 1000);`);
      assertEq(n, "", "NULL passthrough");
    });

    section("fn_groups_nearby — behaviour");

    await test("finds both discoverable SP groups within 5 km", () => {
      const ids = psql(`
        SELECT string_agg(id::text, ',' ORDER BY id::text)
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 5);
      `);
      assert(ids.includes(GROUP_1), `must include GROUP_1; got ${ids}`);
      assert(ids.includes(GROUP_2), `must include GROUP_2; got ${ids}`);
    });

    await test("excludes allow_discovery=false even when close", () => {
      const ids = psql(`
        SELECT string_agg(id::text, ',' ORDER BY id::text)
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 5);
      `);
      assert(!ids.includes(GROUP_4), `GROUP_4 (discovery off) must NOT appear; got ${ids}`);
    });

    await test("excludes approval_status<>approved even when close", () => {
      const ids = psql(`
        SELECT string_agg(id::text, ',' ORDER BY id::text)
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 5);
      `);
      assert(!ids.includes(GROUP_5), `GROUP_5 (pending) must NOT appear; got ${ids}`);
    });

    await test("respects radius — 5 km does not include 12 km group", () => {
      const ids = psql(`
        SELECT string_agg(id::text, ',' ORDER BY id::text)
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 5);
      `);
      assert(!ids.includes(GROUP_3), `GROUP_3 (12 km) must NOT appear in 5 km; got ${ids}`);
    });

    await test("20 km radius picks up the 12 km group", () => {
      const ids = psql(`
        SELECT string_agg(id::text, ',' ORDER BY id::text)
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 20);
      `);
      assert(ids.includes(GROUP_3), `GROUP_3 must appear in 20 km; got ${ids}`);
    });

    await test("results ordered by ascending distance", () => {
      const ids = psql(`
        SELECT string_agg(id::text, '|')
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 20);
      `).split("|");
      // GROUP_1 (0 km) should come before GROUP_2 (~3 km), then GROUP_3 (~12 km).
      const idx1 = ids.indexOf(GROUP_1);
      const idx2 = ids.indexOf(GROUP_2);
      const idx3 = ids.indexOf(GROUP_3);
      assert(idx1 >= 0 && idx2 >= 0 && idx3 >= 0, "all three expected");
      assert(idx1 < idx2 && idx2 < idx3,
        `order drift: 1=${idx1} 2=${idx2} 3=${idx3}`);
    });

    await test("distance_km_approx is rounded to integer >= 1", () => {
      const line = psql(`
        SELECT distance_km_approx::text
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 2)
          WHERE id = '${GROUP_1}'
          LIMIT 1;
      `);
      assertEq(line, "1", "GROUP_1 is 0 km from itself, floored to 1");
    });

    await test("returns snapped coords, never raw base_lat/base_lng", () => {
      const raw = psql(`SELECT base_lat::text FROM public.coaching_groups WHERE id='${GROUP_2}';`);
      const snapped = psql(`
        SELECT base_lat_snapped::text
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 20)
          WHERE id='${GROUP_2}';
      `);
      // The 500m precision snap must differ from the raw 5-decimal coord.
      assert(raw !== snapped, `snap ${snapped} leaked raw ${raw}`);
    });

    await test("radius clamped to 100 km internally — 500 does not crash", () => {
      const out = psql(`
        SELECT count(*)::text
          FROM public.fn_groups_nearby(${SP_LAT}, ${SP_LNG}, 500);
      `);
      assert(/^\d+$/.test(out), `expected row count, got ${out}`);
    });

    section("fn_groups_nearby — validation");

    await test("rejects NULL lat/lng with 22023", () => {
      const { out, ok } = psqlAllowError(
        `SELECT public.fn_groups_nearby(NULL::numeric, NULL::numeric, 10);`,
      );
      assert(!ok, "must raise");
      assert(out.includes("INVALID_INPUT"), `unexpected: ${out}`);
    });

    await test("rejects lat out of range", () => {
      const { ok } = psqlAllowError(
        `SELECT public.fn_groups_nearby(91::numeric, 0::numeric, 10);`,
      );
      assert(!ok, "must raise on lat=91");
    });

    await test("rejects lng out of range", () => {
      const { ok } = psqlAllowError(
        `SELECT public.fn_groups_nearby(0::numeric, -181::numeric, 10);`,
      );
      assert(!ok, "must raise on lng=-181");
    });

    section("CHECK: discovery_needs_coords");

    await test("cannot enable discovery without coords", () => {
      const { ok, out } = psqlAllowError(`
        INSERT INTO public.coaching_groups (
          id, name, coach_user_id, city, created_at_ms,
          approval_status, allow_discovery
        ) VALUES (
          '00000000-0000-4000-8000-0000000000aa',
          'Bad Group', '${COACH_1}', 'X', 0, 'approved', true
        );
      `);
      assert(!ok, "must raise");
      assert(
        out.includes("chk_coaching_groups_discovery_needs_coords"),
        `unexpected: ${out}`,
      );
    });

    section("shape guard");

    await test("fn_coaching_groups_assert_discovery_shape is a no-op when healthy", () => {
      psql(`SELECT public.fn_coaching_groups_assert_discovery_shape();`);
    });

    await test("renaming one CHECK away triggers P0010 with markers", () => {
      psql(`
        ALTER TABLE public.coaching_groups
          RENAME CONSTRAINT chk_coaching_groups_discovery_needs_coords
                         TO tmp_chk_discovery_needs_coords_l2205;
      `);
      const { out, ok } = psqlAllowError(
        `SELECT public.fn_coaching_groups_assert_discovery_shape();`,
      );
      psql(`
        ALTER TABLE public.coaching_groups
          RENAME CONSTRAINT tmp_chk_discovery_needs_coords_l2205
                         TO chk_coaching_groups_discovery_needs_coords;
      `);
      assert(!ok, "must raise");
      assert(out.includes("L22-05"), `must name finding: ${out}`);
      assert(out.includes("discovery_needs_coords"), `must flag missing CHECK: ${out}`);
    });
  } finally {
    teardownFixtures();
  }

  console.log(
    `\n${BOLD}${passed === total ? GREEN : RED}${passed}/${total}${RESET} tests passed` +
      (failed > 0 ? `, ${RED}${failed}${RESET} failed` : ""),
  );
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
