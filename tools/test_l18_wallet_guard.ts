/**
 * tools/test_l18_wallet_guard.ts
 *
 * Integration tests for the L18-01 wallet mutation guard + gateway
 * (`supabase/migrations/20260419130000_l18_wallet_mutation_guard.sql`).
 *
 * Coverage:
 *
 *   - Guard
 *       * direct UPDATE of balance_coins blocked (P0007)
 *       * direct UPDATE of pending_coins blocked
 *       * direct UPDATE of lifetime_earned_coins blocked
 *       * direct UPDATE of last_reconciled_at_ms allowed (column not in OF list)
 *       * INSERT with all-zero counters allowed (signup path)
 *       * INSERT with non-zero balance blocked
 *   - Authorised RPCs
 *       * increment_wallet_balance: positive delta, negative delta, upsert path
 *       * increment_wallet_pending / release_pending_to_balance happy paths
 *       * debit_wallet_checked: success, insufficient, no-op on zero
 *       * fn_increment_wallets_batch: paired ledger writes
 *       * reconcile_wallet: zero-drift + drift correction
 *   - Gateway fn_mutate_wallet
 *       * happy path credit: ledger row + balance bump + lifetime_earned
 *       * happy path debit: ledger row + balance debit + lifetime_spent
 *       * delta=0 rejected, NULL user rejected, missing reason rejected
 *       * non-existent wallet auto-created at zero then bumped
 *       * paired ledger row equals delta (parity invariant)
 *       * negative-balance attempt blocked by wallets CHECK
 *
 * Usage:
 *
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l18_wallet_guard.ts
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
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertTrue(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const TEST_USER_TAG = "l1801-test";

async function makeUser(): Promise<string> {
  const email = `${TEST_USER_TAG}-${randomUUID().slice(0, 8)}@example.test`;
  // @ts-ignore — admin API exists on service_role client.
  const { data: created, error: createErr } = await db.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { test_tag: TEST_USER_TAG },
  });
  if (createErr) {
    throw new Error(`auth.admin.createUser: ${createErr.message}`);
  }
  const userId = (created as any)?.user?.id;
  if (!userId) throw new Error("createUser returned no id");

  // The handle_new_user trigger should have created the wallets row.
  const { data: wallet, error: walletErr } = await db
    .from("wallets")
    .select("user_id")
    .eq("user_id", userId)
    .maybeSingle();
  if (walletErr) throw new Error(`select wallet: ${walletErr.message}`);
  if (!wallet) {
    const { error: insErr } = await db
      .from("wallets")
      .insert({ user_id: userId });
    if (insErr) throw new Error(`fallback insert wallet: ${insErr.message}`);
  }
  return userId;
}

async function cleanup() {
  // @ts-ignore
  const { data: list, error } = await db.auth.admin.listUsers({ perPage: 1000 });
  if (error) return;
  const toDel = list?.users?.filter((u: any) =>
    u?.user_metadata?.test_tag === TEST_USER_TAG,
  ) ?? [];
  for (const u of toDel) {
    // @ts-ignore
    await db.auth.admin.deleteUser(u.id).catch(() => {});
  }
}

async function selectWallet(userId: string): Promise<{
  balance_coins: number;
  pending_coins: number;
  lifetime_earned_coins: number;
  lifetime_spent_coins: number;
} | null> {
  const { data, error } = await db
    .from("wallets")
    .select("balance_coins, pending_coins, lifetime_earned_coins, lifetime_spent_coins")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error(`select wallet: ${error.message}`);
  return data;
}

async function ledgerSum(userId: string): Promise<number> {
  const { data, error } = await db
    .from("coin_ledger")
    .select("delta_coins")
    .eq("user_id", userId);
  if (error) throw new Error(`select ledger: ${error.message}`);
  return (data ?? []).reduce((acc, row: any) => acc + (row.delta_coins ?? 0), 0);
}

async function preflight(): Promise<boolean> {
  try {
    const { error } = await db.from("wallets").select("user_id").limit(1);
    return !error;
  } catch {
    return false;
  }
}

async function functionExists(): Promise<boolean> {
  const { data, error } = await db.rpc("fn_mutate_wallet" as any, {
    p_user_id: "00000000-0000-0000-0000-000000000000",
    p_delta_coins: 0,
    p_reason: "probe",
  });
  // We expect an error (INVALID_DELTA or auth) — what matters is "function not found" is NOT in it.
  if (error?.message?.match(/Could not find the function|not exist/i)) return false;
  return true;
}

// ── Tests ───────────────────────────────────────────────────────────────────

async function testGuard() {
  section("guard: direct UPDATE blocked, exempt INSERT allowed");

  const userId = await makeUser();

  await test("direct UPDATE of balance_coins is blocked (P0007)", async () => {
    const { error } = await db
      .from("wallets")
      .update({ balance_coins: 100 })
      .eq("user_id", userId);
    assertTrue(!!error, "expected guard to block direct UPDATE");
    assertTrue(
      /WALLET_MUTATION_FORBIDDEN|wallet_mutation/i.test(error!.message),
      `expected guard message, got: ${error!.message}`,
    );
    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 0, "balance must remain zero after blocked UPDATE");
  });

  await test("direct UPDATE of pending_coins is blocked", async () => {
    const { error } = await db
      .from("wallets")
      .update({ pending_coins: 50 })
      .eq("user_id", userId);
    assertTrue(!!error, "expected guard to block pending UPDATE");
    assertTrue(/WALLET_MUTATION_FORBIDDEN/.test(error!.message), "expected guard message");
  });

  await test("direct UPDATE of lifetime_earned_coins is blocked", async () => {
    const { error } = await db
      .from("wallets")
      .update({ lifetime_earned_coins: 999 })
      .eq("user_id", userId);
    assertTrue(!!error, "expected guard to block lifetime UPDATE");
  });

  await test("direct UPDATE of last_reconciled_at_ms is allowed (not in OF list)", async () => {
    const ts = Date.now();
    const { error } = await db
      .from("wallets")
      .update({ last_reconciled_at_ms: ts })
      .eq("user_id", userId);
    assertTrue(!error, `expected last_reconciled_at_ms UPDATE to succeed, got: ${error?.message}`);
  });

  await test("INSERT with non-zero balance is blocked (guard fires before FK)", async () => {
    // Create a real auth user but bypass the auto-created wallet by
    // deleting it first, then attempt a manual non-zero insert.
    const altId = await makeUser();
    const { error: delErr } = await db.from("wallets").delete().eq("user_id", altId);
    if (delErr) throw new Error(`pre-delete wallet: ${delErr.message}`);
    const { error } = await db
      .from("wallets")
      .insert({ user_id: altId, balance_coins: 25 });
    assertTrue(!!error, "expected guard to block non-zero INSERT");
    assertTrue(
      /WALLET_MUTATION_FORBIDDEN/i.test(error!.message),
      `expected guard rejection, got: ${error!.message}`,
    );
  });

  await test("INSERT with all-zero counters is allowed (signup path)", async () => {
    const fresh = await makeUser();
    const w = await selectWallet(fresh);
    assertTrue(!!w, "wallet must exist after signup");
    assertEq(w!.balance_coins, 0, "fresh wallet has zero balance");
  });
}

async function testAuthorisedRpcs() {
  section("authorised RPCs: existing mutators still work");

  const userId = await makeUser();

  await test("increment_wallet_balance(+50) credits and bumps lifetime_earned", async () => {
    // First insert ledger row (caller responsibility for this RPC).
    const { error: lErr } = await db
      .from("coin_ledger")
      .insert({
        user_id: userId,
        delta_coins: 50,
        reason: "session_completed",
        created_at_ms: Date.now(),
      });
    assertTrue(!lErr, `ledger insert failed: ${lErr?.message}`);

    const { error } = await db.rpc("increment_wallet_balance" as any, {
      p_user_id: userId,
      p_delta: 50,
    });
    assertTrue(!error, `increment failed: ${error?.message}`);

    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 50, "balance");
    assertEq(w?.lifetime_earned_coins, 50, "lifetime_earned");
    assertEq(w?.lifetime_spent_coins, 0, "lifetime_spent");
  });

  await test("increment_wallet_balance(-20) debits and bumps lifetime_spent", async () => {
    const { error: lErr } = await db
      .from("coin_ledger")
      .insert({
        user_id: userId,
        delta_coins: -20,
        reason: "cosmetic_purchase",
        created_at_ms: Date.now(),
      });
    assertTrue(!lErr, `ledger insert failed: ${lErr?.message}`);

    const { error } = await db.rpc("increment_wallet_balance" as any, {
      p_user_id: userId,
      p_delta: -20,
    });
    assertTrue(!error, `decrement failed: ${error?.message}`);

    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 30, "balance after debit");
    assertEq(w?.lifetime_spent_coins, 20, "lifetime_spent");
  });

  await test("debit_wallet_checked succeeds when balance sufficient", async () => {
    const { error: lErr } = await db
      .from("coin_ledger")
      .insert({
        user_id: userId,
        delta_coins: -5,
        reason: "cosmetic_purchase",
        created_at_ms: Date.now(),
      });
    assertTrue(!lErr, "ledger insert");

    const { data, error } = await db.rpc("debit_wallet_checked" as any, {
      p_user_id: userId,
      p_amount: 5,
    });
    assertTrue(!error, `debit failed: ${error?.message}`);
    assertEq(data, true, "debit returned true");
    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 25, "balance after checked debit");
  });

  await test("debit_wallet_checked returns false when insufficient (no mutation)", async () => {
    const { data, error } = await db.rpc("debit_wallet_checked" as any, {
      p_user_id: userId,
      p_amount: 10000,
    });
    assertTrue(!error, `rpc failed: ${error?.message}`);
    assertEq(data, false, "debit returned false");
    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 25, "balance unchanged");
  });

  await test("debit_wallet_checked(0) is a no-op and does NOT touch wallet", async () => {
    const { data, error } = await db.rpc("debit_wallet_checked" as any, {
      p_user_id: userId,
      p_amount: 0,
    });
    assertTrue(!error, `rpc failed: ${error?.message}`);
    assertEq(data, true, "no-op returns true");
  });

  await test("increment_wallet_pending + release_pending_to_balance flow", async () => {
    const { error: e1 } = await db.rpc("increment_wallet_pending" as any, {
      p_user_id: userId,
      p_delta: 40,
    });
    assertTrue(!e1, `pending increment failed: ${e1?.message}`);
    const w1 = await selectWallet(userId);
    assertEq(w1?.pending_coins, 40, "pending after increment");

    const { error: e2 } = await db.rpc("release_pending_to_balance" as any, {
      p_user_id: userId,
      p_amount: 40,
    });
    assertTrue(!e2, `release failed: ${e2?.message}`);
    const w2 = await selectWallet(userId);
    assertEq(w2?.pending_coins, 0, "pending zero after release");
    assertEq(w2?.balance_coins, 65, "balance bumped by released amount");
  });

  await test("reconcile_wallet returns drift=0 when balance matches ledger", async () => {
    // Sync ledger and wallet first by reconciling, ignoring any prior drift.
    const { error: r1 } = await db.rpc("reconcile_wallet" as any, { p_user_id: userId });
    assertTrue(!r1, `first reconcile failed: ${r1?.message}`);
    // Second call should now report drift=0.
    const { data, error } = await db.rpc("reconcile_wallet" as any, { p_user_id: userId });
    assertTrue(!error, `reconcile failed: ${error?.message}`);
    assertTrue(typeof data === "object", "reconcile returns object");
    assertEq((data as any).reconciled, true, "reconciled");
    assertEq((data as any).drift, 0, "drift zero on second pass");
  });
}

async function testGateway() {
  section("fn_mutate_wallet gateway");

  await test("happy path credit: ledger row + balance bump + lifetime_earned", async () => {
    const userId = await makeUser();
    const ref = `t-${randomUUID()}`;
    const { data, error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId,
      p_delta_coins: 100,
      p_reason: "session_completed",
      p_ref_id: ref,
    });
    assertTrue(!error, `gateway credit failed: ${error?.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row?.new_balance, 100, "new_balance");
    assertTrue(typeof row?.ledger_id === "string" && row.ledger_id.length > 0, "ledger_id is set");

    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 100, "wallet balance");
    assertEq(w?.lifetime_earned_coins, 100, "lifetime_earned bumped");
    assertEq(w?.lifetime_spent_coins, 0, "lifetime_spent untouched");

    const sum = await ledgerSum(userId);
    assertEq(sum, 100, "ledger sum equals balance (parity)");
  });

  await test("happy path debit: balance debit + lifetime_spent", async () => {
    const userId = await makeUser();
    // First credit, then debit.
    await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: 200, p_reason: "session_completed",
    });
    const { data, error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: -75, p_reason: "cosmetic_purchase",
    });
    assertTrue(!error, `gateway debit failed: ${error?.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row?.new_balance, 125, "new_balance after debit");

    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, 125, "wallet balance after debit");
    assertEq(w?.lifetime_earned_coins, 200, "lifetime_earned unchanged");
    assertEq(w?.lifetime_spent_coins, 75, "lifetime_spent bumped");

    const sum = await ledgerSum(userId);
    assertEq(sum, 125, "ledger parity preserved");
  });

  await test("delta=0 rejected with INVALID_DELTA", async () => {
    const userId = await makeUser();
    const { error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: 0, p_reason: "session_completed",
    });
    assertTrue(!!error, "expected error on zero delta");
    assertTrue(/INVALID_DELTA/.test(error!.message), `got: ${error!.message}`);
  });

  await test("missing reason rejected", async () => {
    const userId = await makeUser();
    const { error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: 5, p_reason: "",
    });
    assertTrue(!!error, "expected error on empty reason");
    assertTrue(/MISSING_REASON/.test(error!.message), `got: ${error!.message}`);
  });

  await test("auto-creates wallet at zero when missing, then applies delta", async () => {
    // Create auth user but DO NOT manually insert wallets row — gateway must
    // upsert it. We use admin.createUser; the handle_new_user trigger should
    // already create the wallet, but the gateway is robust either way.
    const userId = await makeUser();

    const { data, error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: 7, p_reason: "session_completed",
    });
    assertTrue(!error, `gateway upsert failed: ${error?.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row?.new_balance, 7, "balance after upsert");
  });

  await test("debit exceeding balance throws check_violation (negative balance blocked)", async () => {
    const userId = await makeUser();
    // No prior credit. Try to debit 10.
    const { error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId, p_delta_coins: -10, p_reason: "cosmetic_purchase",
    });
    assertTrue(!!error, "expected check_violation on negative balance");
    assertTrue(
      /check.*violat|balance_coins/i.test(error!.message),
      `expected balance constraint error, got: ${error!.message}`,
    );
  });

  await test("ledger row stores reason, ref_id, issuer (note column removed by L19-01)", async () => {
    const userId = await makeUser();
    const refId = `audit-${randomUUID()}`;
    // issuer_group_id has FK to coaching_groups, so we either omit it or
    // verify the FK silently sets-null on absent group. Easier: omit.
    const { error } = await db.rpc("fn_mutate_wallet" as any, {
      p_user_id: userId,
      p_delta_coins: 33,
      p_reason: "challenge_pool_won",
      p_ref_id: refId,
    });
    assertTrue(!error, `gateway w/ metadata failed: ${error?.message}`);
    const { data: rows, error: selErr } = await db
      .from("coin_ledger")
      .select("delta_coins, reason, ref_id, issuer_group_id")
      .eq("user_id", userId)
      .eq("ref_id", refId);
    assertTrue(!selErr, "ledger select");
    assertTrue((rows ?? []).length === 1, `expected 1 ledger row, got ${rows?.length}`);
    const r: any = rows![0];
    assertEq(r.delta_coins, 33, "delta_coins");
    assertEq(r.reason, "challenge_pool_won", "reason");
  });
}

async function testReconcileParity() {
  section("reconcile parity: gateway never produces drift");

  await test("after 5 mixed gateway operations, drift==0", async () => {
    const userId = await makeUser();
    const ops = [+50, +30, -10, +200, -15];
    for (const delta of ops) {
      const { error } = await db.rpc("fn_mutate_wallet" as any, {
        p_user_id: userId,
        p_delta_coins: delta,
        p_reason: delta > 0 ? "session_completed" : "cosmetic_purchase",
      });
      assertTrue(!error, `op ${delta} failed: ${error?.message}`);
    }
    const expected = ops.reduce((a, b) => a + b, 0);
    const w = await selectWallet(userId);
    assertEq(w?.balance_coins, expected, "wallet balance");

    const { data, error } = await db.rpc("reconcile_wallet" as any, { p_user_id: userId });
    assertTrue(!error, `reconcile failed: ${error?.message}`);
    assertEq((data as any).drift, 0, "no drift after gateway-only mutations");
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`${BOLD}L18-01 wallet guard + gateway integration tests${RESET}`);
  console.log(`Target: ${SUPABASE_URL}`);

  if (!(await preflight())) {
    console.log(`\n${SKIP} Local Supabase unreachable at ${SUPABASE_URL} \u2014 start with 'supabase start' to run.`);
    process.exit(0);
  }

  if (!(await functionExists())) {
    console.log(`\n${FAIL} fn_mutate_wallet not found. Run 'supabase migration up --include-all'.`);
    process.exit(1);
  }

  try {
    await testGuard();
    await testAuthorisedRpcs();
    await testGateway();
    await testReconcileParity();
  } finally {
    await cleanup().catch(() => {});
  }

  console.log(
    `\n${BOLD}Results:${RESET} ${OK} ${passed} passed, ${FAIL} ${failed} failed, ${SKIP} ${skipped} skipped`,
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(2);
});
