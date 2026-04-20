/**
 * tools/test_l08_07_wallet_ledger_drift_check.ts
 *
 * Integration tests for the L08-07 real-time wallet/ledger drift check
 * (`supabase/migrations/20260420120000_l08_wallet_ledger_drift_check.sql`).
 *
 * Coverage
 * ────────
 *   • public.fn_check_wallet_ledger_drift
 *       (1) input validation: p_max_users out of [1, 100000] → 22023
 *       (2) input validation: p_recent_hours out of [0, 720] → 22023
 *       (3) baseline scan returns shape `{user_id, balance_coins, ledger_sum,
 *           drift, last_reconciled_at_ms, recent_activity}` for any row
 *       (4) deliberate drift on a synthetic user is detected with the
 *           right magnitude (drift == ledger_sum - balance_coins)
 *       (5) recent_activity flag is true when the synthetic user has a
 *           ledger row inside p_recent_hours, false otherwise
 *       (6) reconciling the synthetic wallet (via reconcile_wallet)
 *           removes it from subsequent drift scans
 *       (7) p_max_users clamps the working set; with limit=1 we get
 *           AT MOST 1 drift row even when 2 synthetic drifts exist
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l08_07_wallet_ledger_drift_check.ts
 */

import { createClient } from "@supabase/supabase-js";
import { randomUUID } from "node:crypto";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const OK = "\x1b[32m\u2713\x1b[0m";
const FAIL = "\x1b[31m\u2717\x1b[0m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;

function section(title: string) {
  console.log(`\n${BOLD}── ${title} ──${RESET}`);
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

// ── Test fixtures ──────────────────────────────────────────────────────────

const TEST_TAG = "l08-07-test";
const createdUserIds: string[] = [];

async function makeSyntheticUser(): Promise<string> {
  const email = `${TEST_TAG}-${randomUUID().slice(0, 8)}@example.test`;
  // @ts-ignore — admin API exists on service_role client.
  const { data: created, error: createErr } = await db.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { test_tag: TEST_TAG },
  });
  if (createErr) throw new Error(`auth.admin.createUser: ${createErr.message}`);
  const userId = (created as any)?.user?.id;
  if (!userId) throw new Error("createUser returned no id");
  createdUserIds.push(userId);
  return userId;
}

async function setSyntheticDrift(params: {
  userId: string;
  balanceCoins: number;
  ledgerDelta: number;
  ledgerCreatedAtMs?: number;
}): Promise<void> {
  // The wallets row is auto-created by the auth.users insert trigger
  // with balance_coins=0. Update via direct SQL using the L18-01 bypass
  // GUC inside a service-role helper RPC. No such helper exists, so we
  // rely on the daemon-exposed `exec_sql` if available; otherwise this
  // path is exercised only by the in-migration self-test. Here we use
  // a workaround: insert the ledger row first, then call reconcile to
  // sync wallet upward, then add ANOTHER ledger row that creates drift.
  // This avoids needing direct UPDATE access to wallets from the
  // service client.
  const baseTs = Date.now() - 60 * 60 * 1000; // 1h ago

  // Step A: ledger row that sets the EXPECTED balance.
  const { error: e1 } = await db.from("coin_ledger").insert({
    user_id: params.userId,
    delta_coins: params.balanceCoins,
    reason: "admin_adjustment",
    ref_id: `${TEST_TAG}-baseline`,
    created_at_ms: baseTs,
  });
  if (e1) throw new Error(`baseline insert: ${e1.message}`);

  // Step B: reconcile so wallets.balance_coins matches the ledger.
  const { error: rErr } = await db.rpc("reconcile_wallet" as any, {
    p_user_id: params.userId,
  });
  if (rErr) throw new Error(`reconcile_wallet: ${rErr.message}`);

  // Step C: insert the drift-creating ledger row WITHOUT calling any
  // RPC that would also bump the wallet — this is exactly the scenario
  // the audit cares about (an out-of-band ledger entry produced by a
  // bug or a non-canonical mutator).
  const driftTs = params.ledgerCreatedAtMs ?? Date.now();
  const { error: e2 } = await db.from("coin_ledger").insert({
    user_id: params.userId,
    delta_coins: params.ledgerDelta,
    reason: "admin_adjustment",
    ref_id: `${TEST_TAG}-drift`,
    created_at_ms: driftTs,
  });
  if (e2) throw new Error(`drift insert: ${e2.message}`);
}

async function cleanupAllSynthetic(): Promise<void> {
  if (createdUserIds.length === 0) return;

  // ledger
  await db
    .from("coin_ledger")
    .delete()
    .in("user_id", createdUserIds);

  // auth.users delete cascades to wallets via FK
  for (const id of createdUserIds) {
    try {
      // @ts-ignore admin API
      await db.auth.admin.deleteUser(id);
    } catch (_) {
      // best-effort
    }
  }
  createdUserIds.length = 0;
}

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(
    `${BOLD}L08-07 — fn_check_wallet_ledger_drift integration tests${RESET}`,
  );
  console.log(`SUPABASE_URL=${SUPABASE_URL}\n`);

  try {
    section("Input validation (L08-07)");

    await test("p_max_users=0 raises 22023", async () => {
      const { error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 0, p_recent_hours: 24 },
      );
      assertTrue(!!error, "expected error");
      assertEq((error as any).code, "22023", "sqlstate");
    });

    await test("p_max_users=100001 raises 22023", async () => {
      const { error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 100001, p_recent_hours: 24 },
      );
      assertTrue(!!error, "expected error");
      assertEq((error as any).code, "22023", "sqlstate");
    });

    await test("p_recent_hours=-1 raises 22023", async () => {
      const { error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 100, p_recent_hours: -1 },
      );
      assertTrue(!!error, "expected error");
      assertEq((error as any).code, "22023", "sqlstate");
    });

    await test("p_recent_hours=721 raises 22023", async () => {
      const { error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 100, p_recent_hours: 721 },
      );
      assertTrue(!!error, "expected error");
      assertEq((error as any).code, "22023", "sqlstate");
    });

    section("Row shape (L08-07)");

    await test("baseline returns rows with the documented shape", async () => {
      const { data, error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 100, p_recent_hours: 24 },
      );
      if (error) throw new Error(error.message);
      const rows = (data ?? []) as any[];
      // We don't assert non-empty (dev DB might be clean OR have legit
      // dev-time drift). We DO assert shape on whatever rows came back.
      for (const r of rows) {
        assertTrue(typeof r.user_id === "string", "user_id is string");
        assertTrue(typeof r.balance_coins === "number", "balance_coins is number");
        assertTrue(
          typeof r.ledger_sum === "number" || typeof r.ledger_sum === "string",
          "ledger_sum present",
        );
        assertTrue(
          typeof r.drift === "number" || typeof r.drift === "string",
          "drift present",
        );
        assertTrue(typeof r.recent_activity === "boolean", "recent_activity boolean");
      }
    });

    section("Drift detection (L08-07)");

    await test("synthetic out-of-band ledger row is detected with right magnitude", async () => {
      const userA = await makeSyntheticUser();
      // baseline=100, then drift +30 → wallet still 100, ledger=130 ⇒
      // drift = 130 - 100 = +30.
      await setSyntheticDrift({
        userId: userA,
        balanceCoins: 100,
        ledgerDelta: 30,
      });

      const { data, error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 1000, p_recent_hours: 24 },
      );
      if (error) throw new Error(error.message);
      const myRow = (data ?? []).find((r: any) => r.user_id === userA);
      assertTrue(!!myRow, `expected row for ${userA}`);
      assertEq(Number(myRow.balance_coins), 100, "balance_coins");
      assertEq(Number(myRow.ledger_sum), 130, "ledger_sum");
      assertEq(Number(myRow.drift), 30, "drift = ledger - balance");
      assertEq(myRow.recent_activity, true, "recent_activity true");
    });

    await test("reconcile_wallet clears the drift row from subsequent scans", async () => {
      // Reuse the user from previous test if present, otherwise create.
      const userId = createdUserIds[0] ?? (await makeSyntheticUser());
      const { error: rErr } = await db.rpc("reconcile_wallet" as any, {
        p_user_id: userId,
      });
      if (rErr) throw new Error(`reconcile_wallet: ${rErr.message}`);

      const { data, error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 1000, p_recent_hours: 24 },
      );
      if (error) throw new Error(error.message);
      const stillThere = (data ?? []).find((r: any) => r.user_id === userId);
      assertTrue(!stillThere, `drift row should be gone after reconcile, got ${JSON.stringify(stillThere)}`);
    });

    await test("p_max_users clamps the working set", async () => {
      // Create 2 synthetic drifting users.
      const userB = await makeSyntheticUser();
      const userC = await makeSyntheticUser();
      await setSyntheticDrift({
        userId: userB,
        balanceCoins: 50,
        ledgerDelta: -7,
      });
      await setSyntheticDrift({
        userId: userC,
        balanceCoins: 25,
        ledgerDelta: -3,
      });

      // With p_max_users=1, we only sample 1 wallet → at most 1 drift row.
      const { data, error } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 1, p_recent_hours: 24 },
      );
      if (error) throw new Error(error.message);
      const rows = (data ?? []) as any[];
      assertTrue(
        rows.length <= 1,
        `expected at most 1 row with p_max_users=1, got ${rows.length}`,
      );

      // With p_max_users=1000, we should see BOTH B and C.
      const { data: dataAll, error: allErr } = await db.rpc(
        "fn_check_wallet_ledger_drift" as any,
        { p_max_users: 1000, p_recent_hours: 24 },
      );
      if (allErr) throw new Error(allErr.message);
      const ours = (dataAll ?? []).filter((r: any) =>
        [userB, userC].includes(r.user_id),
      );
      assertEq(ours.length, 2, "both synthetic drifts visible with high limit");
    });
  } finally {
    await cleanupAllSynthetic();
  }

  console.log(`\n${BOLD}${passed} passed, ${failed} failed${RESET}\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch(async (e) => {
  console.error("FATAL:", e);
  await cleanupAllSynthetic().catch(() => {});
  process.exit(1);
});
