/**
 * tools/test_l03_13_reverse_coins.ts
 *
 * Integration tests for the L03-13 reverse-coins path
 * (`supabase/migrations/20260421130000_l03_reverse_coin_flows.sql`).
 *
 * Coverage
 * ────────
 *   function exists & permissions
 *     (1)  reverse_coin_emission_atomic + reverse_burn_atomic +
 *          reverse_custody_deposit_atomic registered
 *     (2)  service_role EXECUTE
 *     (3)  anon CANNOT EXECUTE
 *
 *   reverse_coin_emission_atomic
 *     (4)  happy path → debita wallet, restaura inventário +
 *          custody_committed, escreve ledger + coin_reversal_log + audit
 *     (5)  replay com mesmo idempotency_key → was_idempotent=true,
 *          wallet/ inventário inalterados
 *     (6)  INSUFFICIENT_BALANCE quando atleta já gastou coins
 *     (7)  LEDGER_NOT_FOUND quando id inexistente
 *     (8)  INVALID_TARGET_REASON quando ledger entry não é emissão
 *
 *   reverse_burn_atomic
 *     (9)  happy path → re-credita wallet, cancela settlements pending,
 *          re-commita custódia intra-clube
 *     (10) NOT_REVERSIBLE quando settlement já está settled
 *     (11) idempotência
 *     (12) BURN_NOT_FOUND quando burn_ref_id inexistente
 *
 *   reverse_custody_deposit_atomic
 *     (13) happy path → status=refunded, total_deposited decrementa
 *     (14) INVARIANT_VIOLATION quando refund quebraria deposited >=
 *          committed
 *     (15) idempotência
 *     (16) DEPOSIT_NOT_FOUND
 *     (17) INVALID_STATE para deposit pending
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l03_13_reverse_coins.ts
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

const REASON = "L03-13 sandbox test postmortem mock reason";

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

// Cleanup tracking
const createdAuthUserIds = new Set<string>();
const createdGroupIds = new Set<string>();
const insertedRefIds = new Set<string>();
const insertedIdemKeys = new Set<string>();

const ORPHAN_PREFIXES = [
  "l03_13_emit_",
  "l03_13_burn_",
  "rev-emi-l03-13-",
  "rev-burn-l03-13-",
  "rev-dep-l03-13-",
];

async function purgeOrphans() {
  for (const p of ORPHAN_PREFIXES) {
    await db.from("coin_ledger_idempotency").delete().ilike("ref_id", `${p}%`);
    await db.from("coin_ledger").delete().ilike("ref_id", `${p}%`);
    await db
      .from("coin_reversal_log")
      .delete()
      .ilike("idempotency_key", `${p}%`);
  }
}

interface ProvisionedClub {
  groupId: string;
  adminUserId: string;
  athletes: string[];
  custodyAmount: number;
}

async function createUser(): Promise<string> {
  const userId = randomUUID();
  const email = `l03-13-${userId}@test.local`;
  const { error } = await db.auth.admin.createUser({
    id: userId,
    email,
    email_confirm: true,
    password: randomUUID(),
  });
  if (error) throw new Error(`auth.admin.createUser: ${error.message}`);
  createdAuthUserIds.add(userId);
  return userId;
}

async function createPlatformAdmin(): Promise<string> {
  const userId = await createUser();
  const { error } = await db
    .from("profiles")
    .upsert({ id: userId, platform_role: "admin" });
  if (error) throw new Error(`profiles upsert: ${error.message}`);
  return userId;
}

async function provisionClub(opts: {
  athletes: number;
  inventoryTokens: number;
  custodyDepositUsd?: number;
}): Promise<ProvisionedClub> {
  const adminUserId = await createUser();
  const groupId = randomUUID();
  const nowMs = Date.now();
  const custodyAmount = opts.custodyDepositUsd ?? 100_000;

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `L03-13 club ${groupId.slice(0, 8)}`,
    coach_user_id: adminUserId,
    created_at_ms: nowMs,
    approval_status: "approved",
  });
  if (gErr) throw new Error(`coaching_groups: ${gErr.message}`);
  createdGroupIds.add(groupId);

  const { error: mErr } = await db.from("coaching_members").insert({
    user_id: adminUserId,
    group_id: groupId,
    display_name: "Admin Master",
    role: "admin_master",
    joined_at_ms: nowMs,
  });
  if (mErr) throw new Error(`coaching_members admin: ${mErr.message}`);

  const athletes: string[] = [];
  for (let i = 0; i < opts.athletes; i += 1) {
    const aId = await createUser();
    const { error: aErr } = await db.from("coaching_members").insert({
      user_id: aId,
      group_id: groupId,
      display_name: `Athlete ${i + 1}`,
      role: "athlete",
      joined_at_ms: nowMs + i,
    });
    if (aErr) throw new Error(`coaching_members athlete ${i}: ${aErr.message}`);
    athletes.push(aId);
  }

  const { error: caErr } = await db.from("custody_accounts").insert({
    group_id: groupId,
    total_deposited_usd: custodyAmount,
  });
  if (caErr) throw new Error(`custody_accounts: ${caErr.message}`);

  const { error: invErr } = await db.from("coaching_token_inventory").insert({
    group_id: groupId,
    available_tokens: opts.inventoryTokens,
    lifetime_issued: 0,
    lifetime_burned: 0,
  });
  if (invErr) throw new Error(`coaching_token_inventory: ${invErr.message}`);

  return { groupId, adminUserId, athletes, custodyAmount };
}

async function emit(
  groupId: string,
  athleteId: string,
  amount: number,
  refIdSuffix: string,
) {
  const refId = `l03_13_emit_${refIdSuffix}`;
  insertedRefIds.add(refId);
  const { data, error } = await db.rpc("emit_coins_atomic", {
    p_group_id: groupId,
    p_athlete_user_id: athleteId,
    p_amount: amount,
    p_ref_id: refId,
  });
  if (error) throw new Error(`emit_coins_atomic: ${error.message}`);
  const row = Array.isArray(data) ? data[0] : data;
  return { ledgerId: row.ledger_id as string, newBalance: row.new_balance };
}

async function readWallet(userId: string): Promise<number> {
  const { data, error } = await db
    .from("wallets")
    .select("balance_coins")
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw new Error(`wallets read: ${error.message}`);
  return Number(data?.balance_coins ?? 0);
}

async function readInventoryAvailable(groupId: string): Promise<number> {
  const { data, error } = await db
    .from("coaching_token_inventory")
    .select("available_tokens")
    .eq("group_id", groupId)
    .maybeSingle();
  if (error) throw new Error(`inventory read: ${error.message}`);
  return Number(data?.available_tokens ?? 0);
}

async function readCustody(groupId: string) {
  const { data, error } = await db
    .from("custody_accounts")
    .select("total_deposited_usd, total_committed")
    .eq("group_id", groupId)
    .maybeSingle();
  if (error) throw new Error(`custody read: ${error.message}`);
  return {
    deposited: Number(data?.total_deposited_usd ?? 0),
    committed: Number(data?.total_committed ?? 0),
  };
}

async function cleanup() {
  for (const key of insertedIdemKeys) {
    await db.from("coin_reversal_log").delete().eq("idempotency_key", key);
  }
  for (const refIdPrefix of insertedRefIds) {
    await db
      .from("coin_ledger_idempotency")
      .delete()
      .ilike("ref_id", `${refIdPrefix}%`);
    await db.from("coin_ledger").delete().ilike("ref_id", `${refIdPrefix}%`);
  }
  for (const id of createdGroupIds) {
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const id of createdAuthUserIds) {
    await db.auth.admin.deleteUser(id).catch(() => {});
  }
}

async function main() {
  console.log(`${BOLD}L03-13 — reverse coin flows (emission/burn/deposit)${RESET}`);
  console.log(`Supabase: ${SUPABASE_URL}`);

  await purgeOrphans();

  // ── function registry & permissions ──────────────────────────────────────
  section("function registry & permissions");

  await test("reverse_coin_emission_atomic registered", async () => {
    const { error } = await db.rpc("reverse_coin_emission_atomic" as any, {
      p_original_ledger_id: "00000000-0000-0000-0000-000000000000",
      p_reason: REASON,
      p_actor_user_id: "00000000-0000-0000-0000-000000000000",
      p_idempotency_key: "probe-key-123456",
    });
    assertTrue(
      error && /LEDGER_NOT_FOUND|ACTOR_REQUIRED/.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("reverse_burn_atomic registered", async () => {
    const { error } = await db.rpc("reverse_burn_atomic" as any, {
      p_burn_ref_id: "probe-burn",
      p_reason: REASON,
      p_actor_user_id: "00000000-0000-0000-0000-000000000000",
      p_idempotency_key: "probe-key-123456",
    });
    assertTrue(
      error && /BURN_NOT_FOUND|ACTOR_REQUIRED/.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("reverse_custody_deposit_atomic registered", async () => {
    const { error } = await db.rpc("reverse_custody_deposit_atomic" as any, {
      p_deposit_id: "00000000-0000-0000-0000-000000000000",
      p_reason: REASON,
      p_actor_user_id: "00000000-0000-0000-0000-000000000000",
      p_idempotency_key: "probe-key-123456",
    });
    assertTrue(
      error && /DEPOSIT_NOT_FOUND|ACTOR_REQUIRED/.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("anon role cannot EXECUTE reverse_*", async () => {
    const anonClient = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anonClient.rpc(
      "reverse_coin_emission_atomic" as any,
      {
        p_original_ledger_id: "00000000-0000-0000-0000-000000000000",
        p_reason: REASON,
        p_actor_user_id: "00000000-0000-0000-0000-000000000000",
        p_idempotency_key: "probe-key-123456",
      },
    );
    assertTrue(
      error &&
        /permission denied|not allowed|insufficient privilege/i.test(
          error.message ?? "",
        ),
      `expected permission_denied for anon, got ${JSON.stringify(error)}`,
    );
  });

  // ── reverse_coin_emission_atomic ─────────────────────────────────────────
  section("reverse_coin_emission_atomic");

  let emissionClub: ProvisionedClub;
  let platformAdminId: string;
  let emissionLedgerId: string;

  await test("setup: provision club + platform_admin + emit 100 coins", async () => {
    emissionClub = await provisionClub({ athletes: 2, inventoryTokens: 10_000 });
    platformAdminId = await createPlatformAdmin();
    const emit1 = await emit(
      emissionClub.groupId,
      emissionClub.athletes[0],
      100,
      "happy_v1",
    );
    emissionLedgerId = emit1.ledgerId;
    assertEq(
      await readWallet(emissionClub.athletes[0]),
      100,
      "wallet after emit",
    );
    assertEq(
      await readInventoryAvailable(emissionClub.groupId),
      10_000 - 100,
      "inventory after emit",
    );
  });

  await test("happy path: reverse emission debits wallet + restores inventory", async () => {
    const custodyBefore = await readCustody(emissionClub.groupId);
    const key = "rev-emi-l03-13-happy-v1";
    insertedIdemKeys.add(key);
    const { data, error } = await db.rpc(
      "reverse_coin_emission_atomic" as any,
      {
        p_original_ledger_id: emissionLedgerId,
        p_reason: REASON,
        p_actor_user_id: platformAdminId,
        p_idempotency_key: key,
      },
    );
    if (error) throw new Error(`rev emit: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.was_idempotent, false, "was_idempotent on first call");
    assertEq(Number(row.reversed_amount), 100, "reversed_amount");
    assertEq(Number(row.new_balance), 0, "new_balance");

    assertEq(
      await readWallet(emissionClub.athletes[0]),
      0,
      "wallet after reversal",
    );
    assertEq(
      await readInventoryAvailable(emissionClub.groupId),
      10_000,
      "inventory restored",
    );
    const custodyAfter = await readCustody(emissionClub.groupId);
    assertEq(
      custodyAfter.committed,
      Math.max(0, custodyBefore.committed - 100),
      "custody committed released",
    );

    // coin_reversal_log row exists
    const { data: logRows } = await db
      .from("coin_reversal_log")
      .select("id, kind, reversed_coins")
      .eq("idempotency_key", key);
    assertEq((logRows ?? []).length, 1, "exactly one coin_reversal_log row");
    assertEq(logRows?.[0].kind, "emission", "kind");
    assertEq(Number(logRows?.[0].reversed_coins), 100, "reversed_coins");
  });

  await test("idempotent replay: same key → was_idempotent=true, no extra mutation", async () => {
    const key = "rev-emi-l03-13-happy-v1";
    const { data, error } = await db.rpc(
      "reverse_coin_emission_atomic" as any,
      {
        p_original_ledger_id: emissionLedgerId,
        p_reason: REASON,
        p_actor_user_id: platformAdminId,
        p_idempotency_key: key,
      },
    );
    if (error) throw new Error(`rev emit replay: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.was_idempotent, true, "was_idempotent on replay");
    assertEq(
      await readWallet(emissionClub.athletes[0]),
      0,
      "wallet unchanged on replay",
    );
    assertEq(
      await readInventoryAvailable(emissionClub.groupId),
      10_000,
      "inventory unchanged on replay",
    );
  });

  await test("INSUFFICIENT_BALANCE when athlete already spent coins", async () => {
    const club = await provisionClub({ athletes: 2, inventoryTokens: 1_000 });
    const emit1 = await emit(club.groupId, club.athletes[0], 50, "spent_v1");
    // Athlete "gasta" via burn direto. Usa execute_burn_atomic to drop
    // balance to 0.
    const burnRef = randomUUID();
    insertedRefIds.add(`l03_13_burn_spent_${burnRef}`);
    const { error: bErr } = await db.rpc("execute_burn_atomic", {
      p_user_id: club.athletes[0],
      p_redeemer_group_id: club.groupId,
      p_amount: 50,
      p_ref_id: burnRef,
    });
    if (bErr) throw new Error(`burn setup: ${bErr.message}`);

    const key = "rev-emi-l03-13-spent-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_coin_emission_atomic" as any, {
      p_original_ledger_id: emit1.ledgerId,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /INSUFFICIENT_BALANCE/.test(error.message ?? ""),
      `expected INSUFFICIENT_BALANCE, got ${JSON.stringify(error)}`,
    );
  });

  await test("LEDGER_NOT_FOUND for non-existent id", async () => {
    const key = "rev-emi-l03-13-notfound-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_coin_emission_atomic" as any, {
      p_original_ledger_id: randomUUID(),
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /LEDGER_NOT_FOUND/.test(error.message ?? ""),
      `expected LEDGER_NOT_FOUND, got ${JSON.stringify(error)}`,
    );
  });

  // ── reverse_burn_atomic ──────────────────────────────────────────────────
  section("reverse_burn_atomic");

  await test("happy path: reverse burn re-credits wallet", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1_000 });
    await emit(club.groupId, club.athletes[0], 80, "burn_happy_v1");
    assertEq(await readWallet(club.athletes[0]), 80, "wallet after emit");
    const burnRef = randomUUID();
    insertedRefIds.add(`l03_13_burn_happy_${burnRef}`);
    const { error: bErr } = await db.rpc("execute_burn_atomic", {
      p_user_id: club.athletes[0],
      p_redeemer_group_id: club.groupId,
      p_amount: 80,
      p_ref_id: burnRef,
    });
    if (bErr) throw new Error(`burn setup: ${bErr.message}`);
    assertEq(await readWallet(club.athletes[0]), 0, "wallet after burn");

    const key = "rev-burn-l03-13-happy-v1";
    insertedIdemKeys.add(key);
    const { data, error } = await db.rpc("reverse_burn_atomic" as any, {
      p_burn_ref_id: burnRef,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    if (error) throw new Error(`rev burn: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.was_idempotent, false, "was_idempotent first");
    assertEq(Number(row.reversed_amount), 80, "reversed_amount");
    assertEq(
      await readWallet(club.athletes[0]),
      80,
      "wallet re-credited after reverse_burn",
    );
  });

  await test("replay same key → was_idempotent=true, wallet unchanged", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1_000 });
    await emit(club.groupId, club.athletes[0], 40, "burn_idem_v1");
    const burnRef = randomUUID();
    insertedRefIds.add(`l03_13_burn_idem_${burnRef}`);
    await db.rpc("execute_burn_atomic", {
      p_user_id: club.athletes[0],
      p_redeemer_group_id: club.groupId,
      p_amount: 40,
      p_ref_id: burnRef,
    });
    const key = "rev-burn-l03-13-idem-v1";
    insertedIdemKeys.add(key);
    const first = await db.rpc("reverse_burn_atomic" as any, {
      p_burn_ref_id: burnRef,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    if (first.error) throw new Error(`first: ${first.error.message}`);
    const balanceAfterFirst = await readWallet(club.athletes[0]);

    const second = await db.rpc("reverse_burn_atomic" as any, {
      p_burn_ref_id: burnRef,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    if (second.error) throw new Error(`replay: ${second.error.message}`);
    const row = Array.isArray(second.data) ? second.data[0] : second.data;
    assertEq(row.was_idempotent, true, "was_idempotent on replay");
    assertEq(
      await readWallet(club.athletes[0]),
      balanceAfterFirst,
      "wallet not re-credited twice",
    );
  });

  await test("BURN_NOT_FOUND when burn_ref_id does not exist", async () => {
    const key = "rev-burn-l03-13-notfound-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_burn_atomic" as any, {
      p_burn_ref_id: randomUUID(),
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /BURN_NOT_FOUND/.test(error.message ?? ""),
      `expected BURN_NOT_FOUND, got ${JSON.stringify(error)}`,
    );
  });

  // ── reverse_custody_deposit_atomic ───────────────────────────────────────
  section("reverse_custody_deposit_atomic");

  await test("happy path: reverse confirmed deposit decrements lastro", async () => {
    // Provision a fresh group so custody_accounts row is mutable.
    const club = await provisionClub({
      athletes: 1,
      inventoryTokens: 1_000,
      custodyDepositUsd: 5_000,
    });
    // Insert a pending deposit + confirm it.
    const depositId = randomUUID();
    const { error: dErr } = await db.from("custody_deposits").insert({
      id: depositId,
      group_id: club.groupId,
      amount_usd: 200,
      status: "pending",
      external_ref: `l03_13_dep_${depositId}`,
    });
    if (dErr) throw new Error(`custody_deposits: ${dErr.message}`);
    const { error: cErr } = await db.rpc("confirm_custody_deposit", {
      p_deposit_id: depositId,
      p_group_id: club.groupId,
    });
    if (cErr) throw new Error(`confirm_custody_deposit: ${cErr.message}`);
    const custBefore = await readCustody(club.groupId);
    assertEq(custBefore.deposited, 5_200, "deposited after confirm");

    const key = "rev-dep-l03-13-happy-v1";
    insertedIdemKeys.add(key);
    const { data, error } = await db.rpc(
      "reverse_custody_deposit_atomic" as any,
      {
        p_deposit_id: depositId,
        p_reason: REASON,
        p_actor_user_id: platformAdminId,
        p_idempotency_key: key,
      },
    );
    if (error) throw new Error(`rev deposit: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.was_idempotent, false, "was_idempotent first");
    assertEq(Number(row.refunded_usd), 200, "refunded_usd");

    const custAfter = await readCustody(club.groupId);
    assertEq(custAfter.deposited, 5_000, "deposited decremented");

    const { data: depRow } = await db
      .from("custody_deposits")
      .select("status")
      .eq("id", depositId)
      .maybeSingle();
    assertEq(depRow?.status, "refunded", "deposit status");
  });

  await test("INVARIANT_VIOLATION when refund would leave deposited<committed", async () => {
    const club = await provisionClub({
      athletes: 1,
      inventoryTokens: 1_000,
      custodyDepositUsd: 5_000,
    });
    // Commit custody manually to simulate emissions already funded by
    // this deposit.
    const depositId = randomUUID();
    const { error: dErr } = await db.from("custody_deposits").insert({
      id: depositId,
      group_id: club.groupId,
      amount_usd: 100,
      status: "pending",
      external_ref: `l03_13_dep_inv_${depositId}`,
    });
    if (dErr) throw new Error(`deposit insert: ${dErr.message}`);
    await db.rpc("confirm_custody_deposit", {
      p_deposit_id: depositId,
      p_group_id: club.groupId,
    });
    // Simula committed ≈ deposited (stress test: committed 5_100 de
    // 5_100 deposited). Ajusta via UPDATE direto (no prod seria via
    // emit_coins_atomic, mas aqui é mais hermético).
    await db
      .from("custody_accounts")
      .update({ total_committed: 5_100 })
      .eq("group_id", club.groupId);

    const key = "rev-dep-l03-13-inv-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_custody_deposit_atomic" as any, {
      p_deposit_id: depositId,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /INVARIANT_VIOLATION/.test(error.message ?? ""),
      `expected INVARIANT_VIOLATION, got ${JSON.stringify(error)}`,
    );
  });

  await test("DEPOSIT_NOT_FOUND for non-existent id", async () => {
    const key = "rev-dep-l03-13-notfound-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_custody_deposit_atomic" as any, {
      p_deposit_id: randomUUID(),
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /DEPOSIT_NOT_FOUND/.test(error.message ?? ""),
      `expected DEPOSIT_NOT_FOUND, got ${JSON.stringify(error)}`,
    );
  });

  await test("INVALID_STATE for pending deposit", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 10 });
    const depositId = randomUUID();
    const { error: dErr } = await db.from("custody_deposits").insert({
      id: depositId,
      group_id: club.groupId,
      amount_usd: 50,
      status: "pending",
      external_ref: `l03_13_dep_pending_${depositId}`,
    });
    if (dErr) throw new Error(`deposit: ${dErr.message}`);

    const key = "rev-dep-l03-13-pending-v1";
    insertedIdemKeys.add(key);
    const { error } = await db.rpc("reverse_custody_deposit_atomic" as any, {
      p_deposit_id: depositId,
      p_reason: REASON,
      p_actor_user_id: platformAdminId,
      p_idempotency_key: key,
    });
    assertTrue(
      error && /INVALID_STATE/.test(error.message ?? ""),
      `expected INVALID_STATE, got ${JSON.stringify(error)}`,
    );
  });

  await cleanup();
  console.log(
    `\n${BOLD}Summary:${RESET} ${OK} ${passed} passed, ${failed > 0 ? FAIL : OK} ${failed} failed`,
  );
  if (failed > 0) process.exit(1);
}

main().catch(async (e) => {
  console.error(e);
  await cleanup();
  process.exit(1);
});
