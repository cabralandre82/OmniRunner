/**
 * tools/test_l03_03_provider_fee_revenue_track.ts
 *
 * Integration tests for the L03-03 provider_fee revenue tracking
 * (`supabase/migrations/20260420090000_l03_provider_fee_revenue_track.sql`).
 *
 * Coverage
 * ────────
 *   • execute_withdrawal
 *       (1) provider_fee=0 + fx_spread=0  → no platform_revenue rows,
 *           total_deposited_usd debited by GROSS amount_usd
 *       (2) provider_fee=0 + fx_spread>0  → only fx_spread row inserted
 *       (3) provider_fee>0 + fx_spread=0  → only provider_fee row inserted
 *       (4) provider_fee>0 + fx_spread>0  → BOTH rows inserted, distinct
 *           descriptions, source_ref_id = withdrawal id
 *   • fail_withdrawal
 *       (5) reverses BOTH platform_revenue rows in the same TX,
 *           refunds total_deposited_usd, audit log carries breakdown
 *       (6) idempotent on re-call against an already-failed row
 *   • Schema invariants
 *       (7) platform_revenue.fee_type CHECK accepts 'provider_fee'
 *       (8) platform_fee_config.fee_type CHECK still rejects 'provider_fee'
 *           (deliberate divergence — pass-through is not configurable)
 *       (9) _enqueue_fiscal_receipt trigger short-circuits on provider_fee
 *           (no fiscal_receipts row created, no WARNING)
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l03_03_provider_fee_revenue_track.ts
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

function skip(name: string, reason?: string) {
  console.log(`  ${SKIP} ${name}${reason ? ` — ${reason}` : ""}`);
  skipped++;
}

function assertEq(actual: unknown, expected: unknown, msg: string) {
  if (actual !== expected) {
    throw new Error(
      `${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertNum(actual: unknown, expected: number, msg: string) {
  const n = typeof actual === "string" ? Number(actual) : (actual as number);
  if (Number.isNaN(n) || Math.abs(n - expected) > 0.001) {
    throw new Error(
      `${msg}: expected ${expected}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertTrue(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const TEST_TAG = "l03-03-test";
const createdGroupIds: string[] = [];
const createdUserIds: string[] = [];

async function makeUser(): Promise<string> {
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

async function makeGroupWithCustody(
  initialDepositedUsd: number,
): Promise<{ groupId: string; userId: string }> {
  const userId = await makeUser();
  const groupId = randomUUID();
  const nowMs = Date.now();

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `${TEST_TAG}-grp-${groupId.slice(0, 8)}`,
    coach_user_id: userId,
    description: "",
    city: "",
    created_at_ms: nowMs,
  });
  if (gErr) throw new Error(`insert coaching_groups: ${gErr.message}`);
  createdGroupIds.push(groupId);

  const { error: aErr } = await db.from("custody_accounts").insert({
    group_id: groupId,
    total_deposited_usd: initialDepositedUsd,
    total_committed: 0,
    total_settled_usd: 0,
  });
  if (aErr) throw new Error(`insert custody_accounts: ${aErr.message}`);

  return { groupId, userId };
}

async function makePendingWithdrawal(params: {
  groupId: string;
  amountUsd: number;
  fxSpreadUsd: number;
  providerFeeUsd: number;
}): Promise<string> {
  const id = randomUUID();
  const fxRate = 5.1;
  const spreadPct = 0.6;
  const netLocal =
    (params.amountUsd - params.providerFeeUsd) * fxRate * (1 - spreadPct / 100);

  const { error } = await db.from("custody_withdrawals").insert({
    id,
    group_id: params.groupId,
    amount_usd: params.amountUsd,
    target_currency: "BRL",
    fx_rate: fxRate,
    fx_spread_pct: spreadPct,
    fx_spread_usd: params.fxSpreadUsd,
    provider_fee_usd: params.providerFeeUsd,
    net_local_amount: netLocal,
    status: "pending",
  });
  if (error) throw new Error(`insert custody_withdrawals: ${error.message}`);
  return id;
}

async function getCustodyDeposited(groupId: string): Promise<number> {
  const { data, error } = await db
    .from("custody_accounts")
    .select("total_deposited_usd")
    .eq("group_id", groupId)
    .single();
  if (error) throw new Error(`select custody_accounts: ${error.message}`);
  return Number(data!.total_deposited_usd);
}

async function getRevenueRows(
  withdrawalId: string,
): Promise<Array<{ fee_type: string; amount_usd: number; description: string | null }>> {
  const { data, error } = await db
    .from("platform_revenue")
    .select("fee_type, amount_usd, description")
    .eq("source_ref_id", withdrawalId)
    .order("fee_type", { ascending: true });
  if (error) throw new Error(`select platform_revenue: ${error.message}`);
  return (data ?? []).map((r: any) => ({
    fee_type: r.fee_type,
    amount_usd: Number(r.amount_usd),
    description: r.description,
  }));
}

async function getFiscalReceiptRowsByWithdrawal(
  withdrawalId: string,
): Promise<Array<{ fee_type: string; source_ref_id: string }>> {
  const { data, error } = await db
    .from("fiscal_receipts")
    .select("fee_type, source_ref_id")
    .eq("source_ref_id", withdrawalId);
  if (error) throw new Error(`select fiscal_receipts: ${error.message}`);
  return data ?? [];
}

async function cleanup() {
  // Delete in dependency order. custody_withdrawals + custody_accounts
  // cascade from coaching_groups via their FKs. platform_revenue is
  // not cascaded — wipe it by group_id first.
  if (createdGroupIds.length > 0) {
    await db
      .from("platform_revenue")
      .delete()
      .in("group_id", createdGroupIds);
    await db
      .from("custody_withdrawals")
      .delete()
      .in("group_id", createdGroupIds);
    await db.from("custody_accounts").delete().in("group_id", createdGroupIds);
    await db.from("coaching_groups").delete().in("id", createdGroupIds);
  }
  for (const u of createdUserIds) {
    // @ts-ignore
    await db.auth.admin.deleteUser(u).catch(() => {});
  }
}

// ── Suites ──────────────────────────────────────────────────────────────────

async function runExecuteWithdrawal() {
  section("execute_withdrawal — platform_revenue ledger trail (L03-03)");

  await test("provider_fee=0 + fx_spread=0: no revenue rows, custody debited gross", async () => {
    const { groupId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 100,
      fxSpreadUsd: 0,
      providerFeeUsd: 0,
    });

    const { error } = await db.rpc("execute_withdrawal" as any, {
      p_withdrawal_id: wid,
    });
    if (error) throw new Error(`execute_withdrawal: ${error.message}`);

    const after = await getCustodyDeposited(groupId);
    assertNum(after, 4900, "total_deposited_usd after execute (gross debit)");

    const rows = await getRevenueRows(wid);
    assertEq(rows.length, 0, "no platform_revenue rows expected");
  });

  await test("provider_fee=0 + fx_spread>0: only fx_spread row, custody debited gross", async () => {
    const { groupId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 100,
      fxSpreadUsd: 3,
      providerFeeUsd: 0,
    });

    const { error } = await db.rpc("execute_withdrawal" as any, {
      p_withdrawal_id: wid,
    });
    if (error) throw new Error(`execute_withdrawal: ${error.message}`);

    assertNum(await getCustodyDeposited(groupId), 4900, "gross debit");

    const rows = await getRevenueRows(wid);
    assertEq(rows.length, 1, "exactly one platform_revenue row");
    assertEq(rows[0].fee_type, "fx_spread", "fee_type=fx_spread");
    assertNum(rows[0].amount_usd, 3, "amount_usd=3");
  });

  await test("provider_fee>0 + fx_spread=0: only provider_fee row, custody debited gross", async () => {
    const { groupId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 100,
      fxSpreadUsd: 0,
      providerFeeUsd: 5,
    });

    const { error } = await db.rpc("execute_withdrawal" as any, {
      p_withdrawal_id: wid,
    });
    if (error) throw new Error(`execute_withdrawal: ${error.message}`);

    assertNum(await getCustodyDeposited(groupId), 4900, "gross debit");

    const rows = await getRevenueRows(wid);
    assertEq(rows.length, 1, "exactly one platform_revenue row");
    assertEq(rows[0].fee_type, "provider_fee", "fee_type=provider_fee");
    assertNum(rows[0].amount_usd, 5, "amount_usd=5");
    assertTrue(
      (rows[0].description ?? "").includes("pass-through"),
      `description should mark pass-through, got: ${rows[0].description}`,
    );
  });

  await test("provider_fee>0 + fx_spread>0: BOTH rows present, distinct types", async () => {
    const { groupId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 1000,
      fxSpreadUsd: 30,
      providerFeeUsd: 100,
    });

    const { error } = await db.rpc("execute_withdrawal" as any, {
      p_withdrawal_id: wid,
    });
    if (error) throw new Error(`execute_withdrawal: ${error.message}`);

    assertNum(await getCustodyDeposited(groupId), 4000, "gross debit (1000)");

    const rows = await getRevenueRows(wid);
    assertEq(rows.length, 2, "two platform_revenue rows expected");
    const fx = rows.find((r) => r.fee_type === "fx_spread");
    const pf = rows.find((r) => r.fee_type === "provider_fee");
    assertTrue(!!fx, "fx_spread row must exist");
    assertTrue(!!pf, "provider_fee row must exist");
    assertNum(fx!.amount_usd, 30, "fx_spread amount");
    assertNum(pf!.amount_usd, 100, "provider_fee amount");
  });
}

async function runFailWithdrawal() {
  section("fail_withdrawal — reverses BOTH revenue rows + restores custody (L03-03)");

  await test("reverses fx_spread + provider_fee + refunds custody + audit breakdown", async () => {
    const { groupId, userId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 1000,
      fxSpreadUsd: 30,
      providerFeeUsd: 100,
    });

    {
      const { error } = await db.rpc("execute_withdrawal" as any, {
        p_withdrawal_id: wid,
      });
      if (error) throw new Error(`execute_withdrawal: ${error.message}`);
    }

    assertNum(await getCustodyDeposited(groupId), 4000, "post-execute balance");
    assertEq((await getRevenueRows(wid)).length, 2, "two revenue rows");

    const { data: failResult, error } = await db.rpc("fail_withdrawal" as any, {
      p_withdrawal_id: wid,
      p_reason: "gateway_rejected_test",
      p_actor_user_id: userId,
    });
    if (error) throw new Error(`fail_withdrawal: ${error.message}`);

    // RETURN TABLE shape preserved (L02-06 contract).
    const row = Array.isArray(failResult) ? failResult[0] : failResult;
    assertEq(row?.status, "failed", "returned status");
    assertEq(row?.was_terminal, false, "was_terminal=false on first fail");
    assertNum(row?.refunded_usd, 1000, "refunded_usd");
    assertNum(row?.revenue_reversed_usd, 130, "revenue_reversed_usd = 30 + 100");

    assertNum(
      await getCustodyDeposited(groupId),
      5000,
      "custody restored to original",
    );
    assertEq(
      (await getRevenueRows(wid)).length,
      0,
      "BOTH revenue rows deleted",
    );

    // Audit log breakdown.
    const { data: logs, error: logErr } = await db
      .from("portal_audit_log")
      .select("metadata")
      .eq("target_id", wid)
      .eq("action", "custody.withdrawal.failed")
      .order("created_at", { ascending: false })
      .limit(1);
    if (logErr) throw new Error(`select audit_log: ${logErr.message}`);
    assertEq(logs?.length, 1, "audit log row created");
    const meta = (logs as any)[0].metadata;
    assertNum(meta.refunded_usd, 1000, "audit refunded_usd");
    assertNum(meta.fx_spread_reversed_usd, 30, "audit fx_spread_reversed_usd");
    assertNum(
      meta.provider_fee_reversed_usd,
      100,
      "audit provider_fee_reversed_usd",
    );
    assertNum(meta.revenue_reversed_usd, 130, "audit revenue_reversed_usd total");
  });

  await test("idempotent on second call against already-failed row", async () => {
    const { groupId, userId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 100,
      fxSpreadUsd: 3,
      providerFeeUsd: 5,
    });

    {
      const { error } = await db.rpc("execute_withdrawal" as any, {
        p_withdrawal_id: wid,
      });
      if (error) throw new Error(`execute_withdrawal: ${error.message}`);
    }
    {
      const { error } = await db.rpc("fail_withdrawal" as any, {
        p_withdrawal_id: wid,
        p_reason: "test_first",
        p_actor_user_id: userId,
      });
      if (error) throw new Error(`fail_withdrawal first: ${error.message}`);
    }

    const balanceAfterFirst = await getCustodyDeposited(groupId);

    const { data: secondResult, error: secondErr } = await db.rpc(
      "fail_withdrawal" as any,
      {
        p_withdrawal_id: wid,
        p_reason: "test_second",
        p_actor_user_id: userId,
      },
    );
    if (secondErr) throw new Error(`fail_withdrawal second: ${secondErr.message}`);

    const row = Array.isArray(secondResult) ? secondResult[0] : secondResult;
    assertEq(row?.was_terminal, true, "second call must report was_terminal=true");
    assertNum(row?.refunded_usd, 0, "no double-refund");
    assertNum(
      await getCustodyDeposited(groupId),
      balanceAfterFirst,
      "balance unchanged on idempotent re-call",
    );
  });
}

async function runSchemaInvariants() {
  section("Schema CHECKs + trigger short-circuit (L03-03)");

  await test("platform_revenue accepts fee_type='provider_fee'", async () => {
    const { groupId } = await makeGroupWithCustody(100);
    const { error } = await db.from("platform_revenue").insert({
      fee_type: "provider_fee",
      amount_usd: 1.23,
      source_ref_id: `test-accept-${randomUUID()}`,
      group_id: groupId,
      description: "L03-03 schema accept test",
    });
    assertTrue(!error, `expected no error, got: ${error?.message}`);
  });

  await test("platform_fee_config rejects fee_type='provider_fee' (deliberate divergence)", async () => {
    const { error } = await db.from("platform_fee_config").insert({
      fee_type: "provider_fee",
      rate_pct: 0.1,
      is_active: false,
    });
    assertTrue(
      !!error,
      "expected CHECK violation on platform_fee_config.fee_type='provider_fee'",
    );
    assertTrue(
      /check.*violat|fee_type/i.test(error!.message),
      `expected CHECK error, got: ${error!.message}`,
    );
    // Defensive cleanup if it accidentally inserted.
    await db.from("platform_fee_config").delete().eq("fee_type", "provider_fee");
  });

  await test("_enqueue_fiscal_receipt trigger short-circuits on provider_fee", async () => {
    const { groupId } = await makeGroupWithCustody(5000);
    const wid = await makePendingWithdrawal({
      groupId,
      amountUsd: 50,
      fxSpreadUsd: 0,
      providerFeeUsd: 7,
    });

    const { error } = await db.rpc("execute_withdrawal" as any, {
      p_withdrawal_id: wid,
    });
    if (error) throw new Error(`execute_withdrawal: ${error.message}`);

    const fiscal = await getFiscalReceiptRowsByWithdrawal(wid);
    // fiscal_receipts.source_ref_id is the same value we pass.
    // No row should exist for a provider_fee-only withdrawal.
    assertEq(fiscal.length, 0, "no fiscal_receipts row created for provider_fee");
  });
}

// ── Entry ───────────────────────────────────────────────────────────────────

(async () => {
  console.log(`${BOLD}L03-03 — provider_fee revenue tracking integration tests${RESET}`);
  console.log(`Supabase: ${SUPABASE_URL}\n`);

  try {
    await runExecuteWithdrawal();
    await runFailWithdrawal();
    await runSchemaInvariants();
  } catch (e: any) {
    console.error(`\n${FAIL} fatal: ${e?.message ?? e}`);
    failed++;
  } finally {
    await cleanup().catch((e) => {
      console.error(`cleanup warning: ${e?.message ?? e}`);
    });
  }

  console.log(
    `\n${BOLD}Summary:${RESET} ${OK} ${passed} passed  ${FAIL} ${failed} failed  ${SKIP} ${skipped} skipped`,
  );

  process.exit(failed === 0 ? 0 : 1);
})();
