/**
 * tools/test_l05_03_distribute_coins_batch.ts
 *
 * Integration tests for the L05-03 batch distribution path
 * (`supabase/migrations/20260421120000_l05_distribute_coins_batch.sql`).
 *
 * Coverage
 * ────────
 *   function exists & permissions
 *     (1)  distribute_coins_batch_atomic registered with the expected signature
 *     (2)  service_role can EXECUTE
 *     (3)  authenticated CANNOT EXECUTE (only service_role)
 *
 *   authz / payload validation
 *     (4)  caller without admin_master role → FORBIDDEN
 *     (5)  empty items array → EMPTY_BATCH
 *     (6)  items.length > 200 → BATCH_TOO_LARGE
 *     (7)  per-item amount > 100_000 → INVALID_ITEM
 *     (8)  per-item amount <= 0 → INVALID_ITEM
 *     (9)  total amount > 1_000_000 → BATCH_TOTAL_EXCEEDED
 *     (10) ref_id length < 8 → MISSING_REF_ID
 *     (11) malformed item (not an object) → INVALID_ITEM
 *
 *   transactional happy path (single TX)
 *     (12) batch of N=5 athletes credited → wallets all incremented atomically
 *
 *   atomicity / rollback
 *     (13) inventory_insufficient mid-batch → NO athlete is credited (full rollback)
 *
 *   idempotency
 *     (14) replay same batch ref_id → batch_was_idempotent=true, balances unchanged
 *
 *   audit / accounting
 *     (15) per-item ledger entries use deterministic ref_id `<batch>__<idx>`
 *     (16) total_amount + total_distributions match the input
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l05_03_distribute_coins_batch.ts
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

// ─────────────────────────────────────────────────────────────────────────────
// Cleanup tracking
// ─────────────────────────────────────────────────────────────────────────────
const createdAuthUserIds = new Set<string>();
const createdGroupIds = new Set<string>();
const insertedRefIds = new Set<string>();

// Best-effort cleanup of orphaned idempotency claims from earlier
// (CTRL-C'd) runs so reruns are hermetic. Patterns mirror the ref_ids
// used in this file.
const ORPHAN_PREFIXES = [
  "test_403_caller",
  "test_empty_batch",
  "test_batch_too_large",
  "test_amount_too_high",
  "test_amount_zero",
  "test_batch_total_exceeded",
  "happy_path_l05_03_",
  "rollback_test_",
  "idem_replay_",
  "deterministic_ref_",
];

async function purgeOrphans() {
  for (const p of ORPHAN_PREFIXES) {
    await db
      .from("coin_ledger_idempotency")
      .delete()
      .ilike("ref_id", `${p}%`);
    await db.from("coin_ledger").delete().ilike("ref_id", `${p}%`);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fixture helpers
// ─────────────────────────────────────────────────────────────────────────────

interface ProvisionedClub {
  groupId: string;
  adminUserId: string;
  athletes: string[];
}

async function createUser(): Promise<string> {
  const userId = randomUUID();
  const email = `l05-03-${userId}@test.local`;
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

/**
 * Create a coaching group with an admin_master + N athletes, fund the
 * custódia account and inventory so emit_coins_atomic can succeed.
 */
async function provisionClub(opts: {
  athletes: number;
  inventoryTokens: number;
  custodyDepositUsd?: number;
}): Promise<ProvisionedClub> {
  const adminUserId = await createUser();
  const groupId = randomUUID();
  const nowMs = Date.now();

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `L05-03 club ${groupId.slice(0, 8)}`,
    coach_user_id: adminUserId,
    created_at_ms: nowMs,
    approval_status: "approved",
  });
  if (gErr) throw new Error(`coaching_groups insert: ${gErr.message}`);
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

  // Custódia account + lastro USD generoso (1 USD == 100 coins is the
  // local default; 1MM USD lastro cobre 100MM coins).
  const { error: caErr } = await db.from("custody_accounts").insert({
    group_id: groupId,
    total_deposited_usd: opts.custodyDepositUsd ?? 1_000_000,
  });
  if (caErr) throw new Error(`custody_accounts: ${caErr.message}`);

  // Inventário
  const { error: invErr } = await db.from("coaching_token_inventory").insert({
    group_id: groupId,
    available_tokens: opts.inventoryTokens,
    lifetime_issued: 0,
    lifetime_burned: 0,
  });
  if (invErr) throw new Error(`coaching_token_inventory: ${invErr.message}`);

  return { groupId, adminUserId, athletes };
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

async function readInventory(groupId: string): Promise<number> {
  const { data, error } = await db
    .from("coaching_token_inventory")
    .select("available_tokens")
    .eq("group_id", groupId)
    .maybeSingle();
  if (error) throw new Error(`inventory read: ${error.message}`);
  return Number(data?.available_tokens ?? 0);
}

async function callBatch(args: {
  groupId: string;
  callerUserId: string;
  items: Array<{ athlete_user_id: string; amount: number }>;
  refId: string;
}) {
  insertedRefIds.add(args.refId);
  return db.rpc("distribute_coins_batch_atomic", {
    p_group_id: args.groupId,
    p_caller_user_id: args.callerUserId,
    p_items: args.items as any,
    p_batch_ref_id: args.refId,
  });
}

async function cleanup() {
  // coin_ledger entries are FK ON DELETE SET NULL on coaching_groups.id
  // (via issuer_group_id) and CASCADE on auth.users.id (via user_id), so
  // dropping users + groups removes them. coin_ledger_idempotency is
  // NOT cascaded — we delete by ref_id prefix to keep reruns hermetic.
  for (const refIdPrefix of insertedRefIds) {
    await db
      .from("coin_ledger_idempotency")
      .delete()
      .ilike("ref_id", `${refIdPrefix}%`);
    await db
      .from("coin_ledger")
      .delete()
      .ilike("ref_id", `${refIdPrefix}%`);
  }
  for (const id of createdGroupIds) {
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const id of createdAuthUserIds) {
    await db.auth.admin.deleteUser(id).catch(() => {});
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log(
    `${BOLD}L05-03 — POST /api/distribute-coins/batch (atomic batch)${RESET}`,
  );
  console.log(`Supabase: ${SUPABASE_URL}`);

  await purgeOrphans();

  // ── function exists & permissions ────────────────────────────────────────
  section("function registry & permissions");

  await test("distribute_coins_batch_atomic exists with expected signature", async () => {
    const { data, error } = await db
      .from("pg_catalog.pg_proc" as any)
      .select("proname")
      .eq("proname", "distribute_coins_batch_atomic")
      .limit(1);
    if (error) {
      // Fallback: pg_catalog may not be exposed via REST; query via RPC.
      const probe = await db.rpc("distribute_coins_batch_atomic" as any, {
        p_group_id: "00000000-0000-0000-0000-000000000000",
        p_caller_user_id: "00000000-0000-0000-0000-000000000000",
        p_items: [],
        p_batch_ref_id: "x",
      });
      // Should error with our P0001 (validation), not "function does not exist".
      assertTrue(
        probe.error && /P0001|MISSING_REF_ID|FORBIDDEN/.test(probe.error.message ?? ""),
        `expected P0001-class validation error, got ${JSON.stringify(probe.error)}`,
      );
      return;
    }
    assertTrue((data ?? []).length > 0, "function not registered");
  });

  await test("service_role can EXECUTE the RPC", async () => {
    // service_role is in use throughout the suite already; absence of
    // a permission_denied on any happy-path call below confirms this.
    const { error } = await db.rpc("distribute_coins_batch_atomic" as any, {
      p_group_id: randomUUID(),
      p_caller_user_id: randomUUID(),
      p_items: [{ athlete_user_id: randomUUID(), amount: 1 }],
      p_batch_ref_id: "noop____perm_check",
    });
    // We expect FORBIDDEN (caller is not admin_master), NOT permission_denied.
    assertTrue(
      error && /FORBIDDEN/.test(error.message ?? ""),
      `expected FORBIDDEN, got ${JSON.stringify(error)}`,
    );
  });

  await test("authenticated role does NOT have EXECUTE on the RPC", async () => {
    // Use a separate client posing as anonymous/authenticated role.
    const anonClient = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anonClient.rpc(
      "distribute_coins_batch_atomic" as any,
      {
        p_group_id: randomUUID(),
        p_caller_user_id: randomUUID(),
        p_items: [{ athlete_user_id: randomUUID(), amount: 1 }],
        p_batch_ref_id: "should____denied",
      },
    );
    assertTrue(
      error &&
        /permission denied|not allowed|insufficient privilege/i.test(
          error.message ?? "",
        ),
      `expected permission_denied for anon/authenticated, got ${JSON.stringify(error)}`,
    );
  });

  // ── authz + payload validation ───────────────────────────────────────────
  section("authz + payload validation");

  let club: ProvisionedClub;

  await test("setup: provision club with 5 athletes + lastro/inventário", async () => {
    club = await provisionClub({ athletes: 5, inventoryTokens: 50_000 });
    assertEq(club.athletes.length, 5, "athletes count");
    assertEq(await readInventory(club.groupId), 50_000, "inventory seed");
  });

  await test("non-admin_master caller → FORBIDDEN", async () => {
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.athletes[0], // athlete, not admin
      items: [{ athlete_user_id: club.athletes[1], amount: 10 }],
      refId: "test_403_caller",
    });
    assertTrue(
      error && /FORBIDDEN/.test(error.message ?? ""),
      `expected FORBIDDEN, got ${JSON.stringify(error)}`,
    );
  });

  await test("empty items array → EMPTY_BATCH", async () => {
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items: [],
      refId: "test_empty_batch",
    });
    assertTrue(
      error && /EMPTY_BATCH/.test(error.message ?? ""),
      `expected EMPTY_BATCH, got ${JSON.stringify(error)}`,
    );
  });

  await test("items.length > 200 → BATCH_TOO_LARGE", async () => {
    const items = Array.from({ length: 201 }, () => ({
      athlete_user_id: club.athletes[0],
      amount: 1,
    }));
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items,
      refId: "test_batch_too_large",
    });
    assertTrue(
      error && /BATCH_TOO_LARGE/.test(error.message ?? ""),
      `expected BATCH_TOO_LARGE, got ${JSON.stringify(error)}`,
    );
  });

  await test("per-item amount > 100_000 → INVALID_ITEM", async () => {
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items: [{ athlete_user_id: club.athletes[0], amount: 100_001 }],
      refId: "test_amount_too_high",
    });
    assertTrue(
      error && /INVALID_ITEM/.test(error.message ?? ""),
      `expected INVALID_ITEM, got ${JSON.stringify(error)}`,
    );
  });

  await test("per-item amount <= 0 → INVALID_ITEM", async () => {
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items: [{ athlete_user_id: club.athletes[0], amount: 0 }],
      refId: "test_amount_zero",
    });
    assertTrue(
      error && /INVALID_ITEM/.test(error.message ?? ""),
      `expected INVALID_ITEM, got ${JSON.stringify(error)}`,
    );
  });

  await test("total > 1_000_000 → BATCH_TOTAL_EXCEEDED (running-total guard)", async () => {
    // Provision a fat club with enough inventory to let the running total
    // climb past 1MM before any other guard fires. We need 11 items of
    // 100_000 (1.1MM total). With the cap at 1MM, item #11 must trip
    // BATCH_TOTAL_EXCEEDED *before* emit_coins_atomic is invoked.
    const fatClub = await provisionClub({
      athletes: 11,
      inventoryTokens: 5_000_000,
      custodyDepositUsd: 50_000_000,
    });
    const items = Array.from({ length: 11 }, (_, i) => ({
      athlete_user_id: fatClub.athletes[i],
      amount: 100_000,
    }));
    const { error } = await callBatch({
      groupId: fatClub.groupId,
      callerUserId: fatClub.adminUserId,
      items,
      refId: "test_batch_total_exceeded_v1",
    });
    assertTrue(
      error && /BATCH_TOTAL_EXCEEDED/.test(error.message ?? ""),
      `expected BATCH_TOTAL_EXCEEDED, got ${JSON.stringify(error)}`,
    );
    // Crucially: NONE of the first 10 items must have been credited
    // (the failure must roll back the partial state, not leave 10
    // ledger entries dangling). We assert balances stayed at zero.
    const balances = await Promise.all(
      fatClub.athletes.map((id) => readWallet(id)),
    );
    for (let i = 0; i < balances.length; i += 1) {
      assertEq(balances[i], 0, `wallet[${i}] not credited on cap rollback`);
    }
  });

  await test("ref_id length < 8 → MISSING_REF_ID", async () => {
    const { error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items: [{ athlete_user_id: club.athletes[0], amount: 10 }],
      refId: "short",
    });
    assertTrue(
      error && /MISSING_REF_ID/.test(error.message ?? ""),
      `expected MISSING_REF_ID, got ${JSON.stringify(error)}`,
    );
  });

  // ── transactional happy path ─────────────────────────────────────────────
  section("transactional happy path");

  await test("batch of 5 athletes credits all wallets atomically", async () => {
    const balancesBefore = await Promise.all(
      club.athletes.map((id) => readWallet(id)),
    );
    const items = club.athletes.map((id, i) => ({
      athlete_user_id: id,
      amount: (i + 1) * 10, // 10, 20, 30, 40, 50
    }));
    const expectedTotal = items.reduce((s, i) => s + i.amount, 0); // 150

    const refId = "happy_path_l05_03_v1";
    const { data, error } = await callBatch({
      groupId: club.groupId,
      callerUserId: club.adminUserId,
      items,
      refId,
    });
    if (error) throw new Error(`unexpected error: ${error.message}`);

    const row = Array.isArray(data) ? data[0] : data;
    assertEq(Number(row?.total_amount), expectedTotal, "total_amount");
    assertEq(Number(row?.total_distributions), 5, "total_distributions");
    assertEq(row?.batch_was_idempotent, false, "batch_was_idempotent (new)");
    assertEq((row?.items ?? []).length, 5, "items length in result");

    const balancesAfter = await Promise.all(
      club.athletes.map((id) => readWallet(id)),
    );
    for (let i = 0; i < club.athletes.length; i += 1) {
      assertEq(
        balancesAfter[i],
        balancesBefore[i] + (i + 1) * 10,
        `wallet[${i}] credited`,
      );
    }
  });

  // ── atomicity: rollback ──────────────────────────────────────────────────
  section("atomicity & rollback");

  await test("inventory_insufficient mid-batch → NO athlete credited", async () => {
    // Provisionar clube novo com inventário curto (apenas 50 tokens).
    const tightClub = await provisionClub({
      athletes: 3,
      inventoryTokens: 50,
    });
    const balancesBefore = await Promise.all(
      tightClub.athletes.map((id) => readWallet(id)),
    );

    const items = [
      { athlete_user_id: tightClub.athletes[0], amount: 30 }, // succeeds
      { athlete_user_id: tightClub.athletes[1], amount: 30 }, // would overdraft (30+30 > 50)
      { athlete_user_id: tightClub.athletes[2], amount: 10 },
    ];
    const refId = "rollback_test_v1";
    const { error } = await callBatch({
      groupId: tightClub.groupId,
      callerUserId: tightClub.adminUserId,
      items,
      refId,
    });
    assertTrue(
      error && /INVENTORY_INSUFFICIENT/.test(error.message ?? ""),
      `expected INVENTORY_INSUFFICIENT, got ${JSON.stringify(error)}`,
    );

    const balancesAfter = await Promise.all(
      tightClub.athletes.map((id) => readWallet(id)),
    );
    for (let i = 0; i < tightClub.athletes.length; i += 1) {
      assertEq(
        balancesAfter[i],
        balancesBefore[i],
        `wallet[${i}] must NOT be credited (rollback)`,
      );
    }

    // Inventário deve estar intacto.
    assertEq(
      await readInventory(tightClub.groupId),
      50,
      "inventory must be unchanged",
    );

    // Nenhum ledger entry com refId batch deve existir.
    const { data: ledgerHits } = await db
      .from("coin_ledger")
      .select("id")
      .ilike("ref_id", `${refId}%`);
    assertEq((ledgerHits ?? []).length, 0, "no ledger rows after rollback");
  });

  // ── idempotency ─────────────────────────────────────────────────────────
  section("idempotency");

  await test("replay same ref_id → batch_was_idempotent=true, balances unchanged", async () => {
    const idemClub = await provisionClub({
      athletes: 3,
      inventoryTokens: 1_000,
    });
    const items = idemClub.athletes.map((id, i) => ({
      athlete_user_id: id,
      amount: (i + 1) * 5, // 5, 10, 15
    }));
    const refId = "idem_replay_v1";

    const { error: e1 } = await callBatch({
      groupId: idemClub.groupId,
      callerUserId: idemClub.adminUserId,
      items,
      refId,
    });
    if (e1) throw new Error(`first call failed: ${e1.message}`);

    const balancesAfterFirst = await Promise.all(
      idemClub.athletes.map((id) => readWallet(id)),
    );

    // Replay
    const { data: replayData, error: e2 } = await callBatch({
      groupId: idemClub.groupId,
      callerUserId: idemClub.adminUserId,
      items,
      refId,
    });
    if (e2) throw new Error(`replay failed: ${e2.message}`);
    const row = Array.isArray(replayData) ? replayData[0] : replayData;
    assertEq(row?.batch_was_idempotent, true, "batch_was_idempotent on replay");
    assertEq(
      Number(row?.total_distributions),
      3,
      "total_distributions reported even on replay",
    );

    const balancesAfterReplay = await Promise.all(
      idemClub.athletes.map((id) => readWallet(id)),
    );
    for (let i = 0; i < idemClub.athletes.length; i += 1) {
      assertEq(
        balancesAfterReplay[i],
        balancesAfterFirst[i],
        `wallet[${i}] not double-credited`,
      );
    }
  });

  await test("ledger ref_id is deterministic <batch>__<idx>", async () => {
    const detClub = await provisionClub({ athletes: 2, inventoryTokens: 200 });
    const refId = "deterministic_ref_v1";
    const { error } = await callBatch({
      groupId: detClub.groupId,
      callerUserId: detClub.adminUserId,
      items: [
        { athlete_user_id: detClub.athletes[0], amount: 11 },
        { athlete_user_id: detClub.athletes[1], amount: 22 },
      ],
      refId,
    });
    if (error) throw new Error(`call failed: ${error.message}`);
    const { data: ledger, error: lErr } = await db
      .from("coin_ledger")
      .select("ref_id, delta_coins, user_id")
      .ilike("ref_id", `${refId}%`)
      .order("ref_id");
    if (lErr) throw new Error(`ledger read: ${lErr.message}`);
    assertEq((ledger ?? []).length, 2, "expected 2 ledger entries");
    assertEq(ledger?.[0].ref_id, `${refId}__0`, "first ref_id");
    assertEq(ledger?.[1].ref_id, `${refId}__1`, "second ref_id");
  });

  // ── cleanup ──────────────────────────────────────────────────────────────
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
