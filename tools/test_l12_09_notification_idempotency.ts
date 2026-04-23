/**
 * tools/test_l12_09_notification_idempotency.ts
 *
 * Integration tests for the L12-09 notification idempotency migration
 * (`supabase/migrations/20260421240000_l12_09_notification_idempotency.sql`).
 *
 * Uses `docker exec psql` (same pattern as test_l04_07 / test_l06_05) to
 * avoid a node_modules `pg` dependency. The tests exercise the UNIQUE
 * constraint + RPC helpers against real inserts, seeding a throwaway
 * auth.users row so the FK on notification_log is satisfied.
 *
 * Coverage
 * ────────
 *   schema / DDL
 *     (1) notification_log_dedup_unique constraint present
 *     (2) fn_try_claim_notification registered + SECURITY DEFINER
 *     (3) fn_release_notification registered + SECURITY DEFINER
 *     (4) service_role has EXECUTE on both RPCs
 *
 *   argument validation
 *     (5) fn_try_claim_notification with NULL user → 22023
 *     (6) fn_try_claim_notification with empty rule → 22023
 *     (7) fn_release_notification with out-of-range max_age → 22023
 *
 *   behaviour (requires seeded auth.users row)
 *     (8) first claim returns TRUE, inserts audit row
 *     (9) duplicate claim returns FALSE, no extra row
 *    (10) release within 60s deletes the row
 *    (11) release of 10-min-old row with 30s bound returns FALSE
 *    (12) raw duplicate INSERT triggers 23505 unique_violation
 *
 * Usage
 * ─────
 *   npx tsx tools/test_l12_09_notification_idempotency.ts
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

function seedUser(): string | null {
  const uid = psql(`SELECT gen_random_uuid();`);
  // Attempt to insert — if auth.users isn't present, return null.
  const res = psql(
    `INSERT INTO auth.users (
       id, email, instance_id, aud, role,
       encrypted_password, email_confirmed_at, created_at, updated_at
     ) VALUES (
       '${uid}', 'l12-09-test-${uid}@test.local',
       '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', '', now(), now(), now()
     ) RETURNING id;`,
    { allowError: true },
  );
  if (/does not exist/.test(res) || res.includes("ERROR")) {
    return null;
  }
  return uid;
}

function cleanupUser(uid: string) {
  psql(
    `DELETE FROM public.notification_log WHERE user_id = '${uid}';
     DELETE FROM auth.users WHERE id = '${uid}';`,
    { allowError: true },
  );
}

async function main() {
  console.log(`${BOLD}L12-09 — notification_log idempotency integration tests${RESET}`);
  console.log(`container: ${CONTAINER}  db: ${DB_NAME}`);

  // ─────────────────────────────────────────────────────────────────────
  section("schema / DDL");

  await test("(1) notification_log_dedup_unique constraint present", () => {
    const out = psql(
      `SELECT conname, pg_get_constraintdef(oid)
         FROM pg_constraint
        WHERE conrelid = 'public.notification_log'::regclass
          AND conname  = 'notification_log_dedup_unique';`,
    );
    assertContains(out, "notification_log_dedup_unique", "constraint name");
    assertContains(out, "UNIQUE", "constraint type");
    assertContains(out, "user_id", "user_id column");
    assertContains(out, "rule", "rule column");
    assertContains(out, "context_id", "context_id column");
  });

  await test("(2) fn_try_claim_notification registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef, pg_get_function_arguments(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_try_claim_notification';`,
    );
    if (!out) throw new Error("fn_try_claim_notification not registered");
    assertContains(out, "t|", "SECURITY DEFINER");
    assertContains(out, "p_user_id uuid", "p_user_id param");
    assertContains(out, "p_rule text", "p_rule param");
    assertContains(out, "p_context_id text", "p_context_id param");
  });

  await test("(3) fn_release_notification registered + SECURITY DEFINER", () => {
    const out = psql(
      `SELECT p.prosecdef, pg_get_function_arguments(p.oid)
         FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public' AND p.proname = 'fn_release_notification';`,
    );
    if (!out) throw new Error("fn_release_notification not registered");
    assertContains(out, "t|", "SECURITY DEFINER");
    assertContains(out, "p_max_age_seconds integer", "p_max_age_seconds param");
  });

  await test("(4) service_role has EXECUTE on both RPCs", () => {
    const out = psql(
      `SELECT has_function_privilege('service_role',
         'public.fn_try_claim_notification(uuid,text,text)', 'EXECUTE'),
              has_function_privilege('service_role',
         'public.fn_release_notification(uuid,text,text,integer)', 'EXECUTE');`,
    );
    assertEq(out, "t|t", "service_role EXECUTE on both");
  });

  // ─────────────────────────────────────────────────────────────────────
  section("argument validation");

  await test("(5) fn_try_claim_notification with NULL user → 22023", () => {
    const out = psql(
      `SELECT public.fn_try_claim_notification(NULL, 'r', 'c');`,
      { allowError: true },
    );
    if (!/INVALID_USER_ID/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_USER_ID, got:\n${out}`);
    }
  });

  await test("(6) fn_try_claim_notification with empty rule → 22023", () => {
    const uid = psql(`SELECT gen_random_uuid();`);
    const out = psql(
      `SELECT public.fn_try_claim_notification('${uid}'::uuid, '', 'c');`,
      { allowError: true },
    );
    if (!/INVALID_RULE/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_RULE, got:\n${out}`);
    }
  });

  await test("(7) fn_release_notification with out-of-range max_age → 22023", () => {
    const uid = psql(`SELECT gen_random_uuid();`);
    const out = psql(
      `SELECT public.fn_release_notification('${uid}'::uuid, 'r', 'c', 9999);`,
      { allowError: true },
    );
    if (!/INVALID_MAX_AGE/.test(out) && !/22023/.test(out)) {
      throw new Error(`expected INVALID_MAX_AGE, got:\n${out}`);
    }
  });

  // ─────────────────────────────────────────────────────────────────────
  section("behaviour (requires seeded auth.users row)");

  const seededUid = seedUser();
  if (!seededUid) {
    console.log(`  ${BOLD}SKIP${RESET} auth.users unavailable — tests 8-12 skipped`);
  } else {
    try {
      await test("(8) first claim returns TRUE + inserts row", () => {
        const claimed = psql(
          `SELECT public.fn_try_claim_notification(
             '${seededUid}'::uuid, 'l12_09_test', 'ctx-A');`,
        );
        assertEq(claimed, "t", "first claim returns TRUE");

        const count = psql(
          `SELECT COUNT(*) FROM public.notification_log
            WHERE user_id = '${seededUid}'::uuid
              AND rule = 'l12_09_test'
              AND context_id = 'ctx-A';`,
        );
        assertEq(count, "1", "exactly 1 row inserted");
      });

      await test("(9) duplicate claim returns FALSE + no extra row", () => {
        const claimed = psql(
          `SELECT public.fn_try_claim_notification(
             '${seededUid}'::uuid, 'l12_09_test', 'ctx-A');`,
        );
        assertEq(claimed, "f", "duplicate claim returns FALSE");

        const count = psql(
          `SELECT COUNT(*) FROM public.notification_log
            WHERE user_id = '${seededUid}'::uuid
              AND rule = 'l12_09_test'
              AND context_id = 'ctx-A';`,
        );
        assertEq(count, "1", "still exactly 1 row");
      });

      await test("(10) release within 60s deletes the row", () => {
        const released = psql(
          `SELECT public.fn_release_notification(
             '${seededUid}'::uuid, 'l12_09_test', 'ctx-A', 60);`,
        );
        assertEq(released, "t", "release returns TRUE");

        const count = psql(
          `SELECT COUNT(*) FROM public.notification_log
            WHERE user_id = '${seededUid}'::uuid
              AND rule = 'l12_09_test'
              AND context_id = 'ctx-A';`,
        );
        assertEq(count, "0", "row deleted");
      });

      await test("(11) release of 10-min-old row with 30s bound returns FALSE", () => {
        // Re-claim and backdate the row.
        psql(
          `SELECT public.fn_try_claim_notification(
             '${seededUid}'::uuid, 'l12_09_test', 'ctx-B');
           UPDATE public.notification_log
              SET sent_at = now() - interval '10 minutes'
            WHERE user_id = '${seededUid}'::uuid
              AND rule = 'l12_09_test'
              AND context_id = 'ctx-B';`,
        );

        const released = psql(
          `SELECT public.fn_release_notification(
             '${seededUid}'::uuid, 'l12_09_test', 'ctx-B', 30);`,
        );
        assertEq(released, "f", "out-of-window release returns FALSE");

        const count = psql(
          `SELECT COUNT(*) FROM public.notification_log
            WHERE user_id = '${seededUid}'::uuid
              AND rule = 'l12_09_test'
              AND context_id = 'ctx-B';`,
        );
        assertEq(count, "1", "row still present");
      });

      await test("(12) raw duplicate INSERT triggers 23505 unique_violation", () => {
        const out = psql(
          `INSERT INTO public.notification_log (user_id, rule, context_id)
             VALUES ('${seededUid}'::uuid, 'l12_09_test', 'ctx-B');`,
          { allowError: true },
        );
        if (!/23505/.test(out) && !/duplicate key/.test(out) && !/notification_log_dedup_unique/.test(out)) {
          throw new Error(`expected unique_violation, got:\n${out}`);
        }
      });
    } finally {
      cleanupUser(seededUid);
    }
  }

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
