/**
 * tools/test_l03_02_freeze_clearing_fee.ts
 *
 * Integration tests for the L03-02 freeze-clearing-fee-at-emission path
 * (`supabase/migrations/20260421170000_l03_02_freeze_clearing_fee_at_emission.sql`).
 *
 * Coverage
 * ────────
 *   schema & registry
 *     (1)  coin_ledger.clearing_fee_rate_pct_snapshot column exists
 *     (2)  clearing_settlements.fee_rate_source column exists with CHECK
 *     (3)  fn_compute_clearing_fee_rate_for_issuer registered
 *     (4)  anon role cannot EXECUTE the helper
 *
 *   snapshot on emission
 *     (5)  emit_coins_atomic writes snapshot = current platform_fee_config.rate_pct
 *     (6)  changing platform_fee_config between emissions yields different snapshots
 *     (7)  idempotent replay does NOT overwrite the existing snapshot
 *
 *   weighted-avg helper
 *     (8)  single rate across multiple emissions → helper returns that rate
 *     (9)  two rates across emissions → helper returns weighted average, source=snapshot
 *     (10) no emissions → helper returns source=live_config_fallback with sample_count=0
 *     (11) rows with NULL snapshot only → helper falls back to live config
 *
 *   execute_burn_atomic freezing
 *     (12) intra-club burn: rate change between emission and burn does NOT affect
 *          anything (no settlement row created)
 *     (13) interclub burn with single frozen rate → clearing_settlements.fee_rate_pct
 *          matches the frozen emission rate (NOT the rate active at burn time)
 *     (14) interclub burn with weighted-avg → fee_rate_pct matches the wavg, and
 *          fee_rate_source='snapshot_weighted_avg'
 *     (15) interclub burn with legacy NULL snapshot → fee_rate_source='live_config_fallback'
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l03_02_freeze_clearing_fee.ts
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

function assertNumEq(
  actual: number | string | null | undefined,
  expected: number,
  msg: string,
) {
  const n = Number(actual);
  if (!Number.isFinite(n) || Math.abs(n - expected) > 1e-6) {
    throw new Error(
      `${msg}: expected ${expected}, got ${JSON.stringify(actual)}`,
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
const insertedLedgerIds = new Set<string>();

const ORPHAN_PREFIX = "l03_02_";

let ORIGINAL_RATE: number | null = null;

async function purgeOrphans() {
  await db
    .from("coin_ledger_idempotency")
    .delete()
    .ilike("ref_id", `${ORPHAN_PREFIX}%`);
  await db.from("coin_ledger").delete().ilike("ref_id", `${ORPHAN_PREFIX}%`);
}

async function readClearingRate(): Promise<number> {
  const { data, error } = await db
    .from("platform_fee_config")
    .select("rate_pct")
    .eq("fee_type", "clearing")
    .eq("is_active", true)
    .maybeSingle();
  if (error) throw new Error(`read clearing rate: ${error.message}`);
  return Number(data?.rate_pct ?? 3.0);
}

async function setClearingRate(rate: number): Promise<void> {
  const { error } = await db
    .from("platform_fee_config")
    .update({ rate_pct: rate })
    .eq("fee_type", "clearing");
  if (error) throw new Error(`set clearing rate: ${error.message}`);
}

async function createUser(): Promise<string> {
  const userId = randomUUID();
  const email = `l03-02-${userId}@test.local`;
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

interface ProvisionedClub {
  groupId: string;
  adminUserId: string;
  athletes: string[];
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
    name: `L03-02 club ${groupId.slice(0, 8)}`,
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

  return { groupId, adminUserId, athletes };
}

async function emit(
  groupId: string,
  athleteId: string,
  amount: number,
  refIdSuffix: string,
) {
  const refId = `${ORPHAN_PREFIX}emit_${refIdSuffix}`;
  insertedRefIds.add(refId);
  const { data, error } = await db.rpc("emit_coins_atomic", {
    p_group_id: groupId,
    p_athlete_user_id: athleteId,
    p_amount: amount,
    p_ref_id: refId,
  });
  if (error) throw new Error(`emit_coins_atomic: ${error.message}`);
  const row = Array.isArray(data) ? data[0] : data;
  insertedLedgerIds.add(row.ledger_id as string);
  return {
    ledgerId: row.ledger_id as string,
    newBalance: row.new_balance,
    refId,
  };
}

async function readLedgerRow(ledgerId: string) {
  const { data, error } = await db
    .from("coin_ledger")
    .select(
      "id, user_id, delta_coins, reason, issuer_group_id, clearing_fee_rate_pct_snapshot",
    )
    .eq("id", ledgerId)
    .maybeSingle();
  if (error) throw new Error(`ledger read: ${error.message}`);
  return data;
}

async function readSettlementForBurn(burnRefId: string) {
  const { data, error } = await db
    .from("clearing_settlements")
    .select(
      "id, fee_rate_pct, fee_rate_source, fee_amount_usd, gross_amount_usd, net_amount_usd, status, clearing_event_id",
    )
    .in(
      "clearing_event_id",
      await (async () => {
        const { data: evs } = await db
          .from("clearing_events")
          .select("id")
          .eq("burn_ref_id", burnRefId);
        return (evs ?? []).map((e) => e.id as string);
      })(),
    );
  if (error) throw new Error(`settlement read: ${error.message}`);
  return data ?? [];
}

async function cleanup() {
  for (const refIdPrefix of insertedRefIds) {
    await db
      .from("coin_ledger_idempotency")
      .delete()
      .ilike("ref_id", `${refIdPrefix}%`);
    await db.from("coin_ledger").delete().ilike("ref_id", `${refIdPrefix}%`);
  }
  for (const id of createdGroupIds) {
    await db.from("clearing_settlements").delete().in(
      "clearing_event_id",
      await (async () => {
        const { data: evs } = await db
          .from("clearing_events")
          .select("id")
          .eq("redeemer_group_id", id);
        return (evs ?? []).map((e) => e.id as string);
      })(),
    );
    await db.from("clearing_events").delete().eq("redeemer_group_id", id);
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const id of createdAuthUserIds) {
    await db.auth.admin.deleteUser(id).catch(() => {});
  }
  if (ORIGINAL_RATE !== null) {
    await setClearingRate(ORIGINAL_RATE);
  }
}

async function main() {
  console.log(
    `${BOLD}L03-02 — freeze clearing fee at emission${RESET}`,
  );
  console.log(`Supabase: ${SUPABASE_URL}`);

  await purgeOrphans();
  ORIGINAL_RATE = await readClearingRate();
  console.log(`Original clearing rate: ${ORIGINAL_RATE}%`);

  // ── schema & registry ────────────────────────────────────────────────────
  section("schema & registry");

  await test("coin_ledger.clearing_fee_rate_pct_snapshot column exists", async () => {
    const { data, error } = await db
      .from("coin_ledger")
      .select("clearing_fee_rate_pct_snapshot")
      .limit(1);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "query succeeded");
  });

  await test("clearing_settlements.fee_rate_source column exists", async () => {
    const { data, error } = await db
      .from("clearing_settlements")
      .select("fee_rate_source")
      .limit(1);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "query succeeded");
  });

  await test("fn_compute_clearing_fee_rate_for_issuer registered", async () => {
    const { data, error } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: randomUUID(),
        p_issuer_group_id: randomUUID(),
      },
    );
    if (error) throw new Error(error.message);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(
      row.source,
      "live_config_fallback",
      "fallback source when no emissions",
    );
    assertEq(Number(row.sample_count), 0, "sample_count=0");
    assertTrue(
      Number(row.rate_pct) >= 0 && Number(row.rate_pct) <= 100,
      "rate_pct bounded",
    );
  });

  await test("anon cannot EXECUTE fn_compute_clearing_fee_rate_for_issuer", async () => {
    const anonClient = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anonClient.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: randomUUID(),
        p_issuer_group_id: randomUUID(),
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

  // ── snapshot on emission ─────────────────────────────────────────────────
  section("snapshot on emission");

  await test("emit at 3% writes snapshot=3.00", async () => {
    await setClearingRate(3.0);
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    const e1 = await emit(club.groupId, club.athletes[0], 100, "snap_3pct");
    const row = await readLedgerRow(e1.ledgerId);
    assertNumEq(
      row?.clearing_fee_rate_pct_snapshot,
      3.0,
      "snapshot column on emission row",
    );
    assertEq(row?.reason, "institution_token_issue", "reason");
  });

  await test("changing rate between emissions yields different snapshots", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(3.0);
    const e1 = await emit(club.groupId, club.athletes[0], 100, "rate_change_3");
    await setClearingRate(5.0);
    const e2 = await emit(club.groupId, club.athletes[0], 100, "rate_change_5");
    const r1 = await readLedgerRow(e1.ledgerId);
    const r2 = await readLedgerRow(e2.ledgerId);
    assertNumEq(r1?.clearing_fee_rate_pct_snapshot, 3.0, "first snapshot=3");
    assertNumEq(r2?.clearing_fee_rate_pct_snapshot, 5.0, "second snapshot=5");
  });

  await test("idempotent replay does NOT overwrite existing snapshot", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(3.0);
    const e1 = await emit(club.groupId, club.athletes[0], 100, "replay_snap");

    await setClearingRate(7.0);
    // Same ref_id → idempotent replay.
    const { data: replayData, error: replayErr } = await db.rpc(
      "emit_coins_atomic",
      {
        p_group_id: club.groupId,
        p_athlete_user_id: club.athletes[0],
        p_amount: 100,
        p_ref_id: e1.refId,
      },
    );
    if (replayErr) throw new Error(replayErr.message);
    const replayRow = Array.isArray(replayData) ? replayData[0] : replayData;
    assertEq(replayRow.was_idempotent, true, "replay is idempotent");

    const row = await readLedgerRow(e1.ledgerId);
    assertNumEq(
      row?.clearing_fee_rate_pct_snapshot,
      3.0,
      "snapshot still 3.00 after rate changed to 7.00",
    );
  });

  // ── weighted-avg helper ──────────────────────────────────────────────────
  section("weighted-avg helper");

  await test("single rate across multiple emissions → returns that rate", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(4.0);
    await emit(club.groupId, club.athletes[0], 50, "wavg_single_a");
    await emit(club.groupId, club.athletes[0], 150, "wavg_single_b");

    const { data, error } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: club.athletes[0],
        p_issuer_group_id: club.groupId,
      },
    );
    if (error) throw new Error(error.message);
    const row = Array.isArray(data) ? data[0] : data;
    assertNumEq(row.rate_pct, 4.0, "rate_pct");
    assertEq(row.source, "snapshot_weighted_avg", "source");
    assertEq(Number(row.sample_count), 2, "sample_count");
    assertEq(Number(row.total_coins_emitted), 200, "total_coins_emitted");
  });

  await test("two rates, equal weights → weighted average", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(3.0);
    await emit(club.groupId, club.athletes[0], 100, "wavg_two_eq_3");
    await setClearingRate(5.0);
    await emit(club.groupId, club.athletes[0], 100, "wavg_two_eq_5");

    const { data } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: club.athletes[0],
        p_issuer_group_id: club.groupId,
      },
    );
    const row = Array.isArray(data) ? data[0] : data;
    assertNumEq(row.rate_pct, 4.0, "(3*100 + 5*100) / 200 = 4.00");
    assertEq(row.source, "snapshot_weighted_avg", "source");
  });

  await test("two rates, weighted 3:1 → weighted average skewed", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(2.0);
    await emit(club.groupId, club.athletes[0], 300, "wavg_skew_2");
    await setClearingRate(6.0);
    await emit(club.groupId, club.athletes[0], 100, "wavg_skew_6");

    const { data } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: club.athletes[0],
        p_issuer_group_id: club.groupId,
      },
    );
    const row = Array.isArray(data) ? data[0] : data;
    // (2*300 + 6*100) / 400 = 1200/400 = 3.00
    assertNumEq(row.rate_pct, 3.0, "weighted avg 3:1");
    assertEq(Number(row.total_coins_emitted), 400, "total_coins_emitted");
  });

  await test("no emissions → source=live_config_fallback with sample_count=0", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    const { data } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: club.athletes[0],
        p_issuer_group_id: club.groupId,
      },
    );
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.source, "live_config_fallback", "source");
    assertEq(Number(row.sample_count), 0, "sample_count=0");
  });

  await test("rows with NULL snapshot → fall back to live config", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(7.0);
    // Insert a synthetic legacy row with NULL snapshot (simulating pre-L03-02 data).
    const refId = `${ORPHAN_PREFIX}legacy_null_${randomUUID()}`;
    insertedRefIds.add(refId);
    const legacyLedgerId = randomUUID();
    const { error: insErr } = await db.from("coin_ledger").insert({
      id: legacyLedgerId,
      user_id: club.athletes[0],
      delta_coins: 100,
      reason: "institution_token_issue",
      ref_id: refId,
      issuer_group_id: club.groupId,
      created_at_ms: Date.now(),
      clearing_fee_rate_pct_snapshot: null,
    });
    if (insErr) throw new Error(`legacy row: ${insErr.message}`);
    insertedLedgerIds.add(legacyLedgerId);

    const { data } = await db.rpc(
      "fn_compute_clearing_fee_rate_for_issuer" as any,
      {
        p_user_id: club.athletes[0],
        p_issuer_group_id: club.groupId,
      },
    );
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.source, "live_config_fallback", "source");
    assertNumEq(row.rate_pct, 7.0, "live config rate used");
    assertEq(Number(row.sample_count), 1, "sample_count=1 (the legacy row)");
  });

  // ── execute_burn_atomic freezing ─────────────────────────────────────────
  section("execute_burn_atomic freezing (settlements.fee_rate_pct)");

  await test("intra-club burn: no settlement row, rate change irrelevant", async () => {
    const club = await provisionClub({ athletes: 1, inventoryTokens: 1000 });
    await setClearingRate(3.0);
    await emit(club.groupId, club.athletes[0], 100, "intra_burn_emit");
    // Rate change between emission and burn should be irrelevant
    // (intra-club = no fee, no settlement).
    await setClearingRate(9.0);
    const burnRef = randomUUID();
    const { error } = await db.rpc("execute_burn_atomic", {
      p_user_id: club.athletes[0],
      p_redeemer_group_id: club.groupId,
      p_amount: 100,
      p_ref_id: burnRef,
    });
    if (error) throw new Error(`burn: ${error.message}`);

    const settlements = await readSettlementForBurn(burnRef);
    assertEq(
      settlements.length,
      0,
      "no settlement rows for intra-club burn",
    );
  });

  await test("interclub burn, single frozen rate → settlement uses frozen rate not live", async () => {
    const issuer = await provisionClub({
      athletes: 1,
      inventoryTokens: 1000,
    });
    const redeemer = await provisionClub({
      athletes: 0,
      inventoryTokens: 100,
    });

    // Emit at 3%
    await setClearingRate(3.0);
    await emit(issuer.groupId, issuer.athletes[0], 100, "frozen_single_emit");

    // Change the platform rate to 9% — the frozen snapshot should still govern.
    await setClearingRate(9.0);

    const burnRef = randomUUID();
    const { error } = await db.rpc("execute_burn_atomic", {
      p_user_id: issuer.athletes[0],
      p_redeemer_group_id: redeemer.groupId,
      p_amount: 100,
      p_ref_id: burnRef,
    });
    if (error) throw new Error(`burn: ${error.message}`);

    const settlements = await readSettlementForBurn(burnRef);
    assertEq(settlements.length, 1, "one settlement row for interclub burn");
    assertNumEq(
      settlements[0].fee_rate_pct,
      3.0,
      "fee_rate_pct frozen at emission (3%) NOT burn-time (9%)",
    );
    assertEq(
      settlements[0].fee_rate_source,
      "snapshot_weighted_avg",
      "source=snapshot",
    );
    assertNumEq(
      settlements[0].fee_amount_usd,
      3.0,
      "fee_amount_usd = gross * 3% = 3.00",
    );
    assertNumEq(
      settlements[0].net_amount_usd,
      97.0,
      "net_amount_usd = 100 - 3 = 97",
    );
  });

  await test("interclub burn, weighted-avg between two rates", async () => {
    const issuer = await provisionClub({
      athletes: 1,
      inventoryTokens: 1000,
    });
    const redeemer = await provisionClub({
      athletes: 0,
      inventoryTokens: 100,
    });

    // Emit 100 at 2%, then 100 at 6% — weighted avg = 4%
    await setClearingRate(2.0);
    await emit(issuer.groupId, issuer.athletes[0], 100, "wavg_burn_2");
    await setClearingRate(6.0);
    await emit(issuer.groupId, issuer.athletes[0], 100, "wavg_burn_6");

    // Change to something else to prove live rate is not used.
    await setClearingRate(10.0);

    const burnRef = randomUUID();
    const { error } = await db.rpc("execute_burn_atomic", {
      p_user_id: issuer.athletes[0],
      p_redeemer_group_id: redeemer.groupId,
      p_amount: 200,
      p_ref_id: burnRef,
    });
    if (error) throw new Error(`burn: ${error.message}`);

    const settlements = await readSettlementForBurn(burnRef);
    assertEq(settlements.length, 1, "one settlement row");
    assertNumEq(
      settlements[0].fee_rate_pct,
      4.0,
      "weighted-avg (2*100 + 6*100)/200 = 4.00",
    );
    assertEq(
      settlements[0].fee_rate_source,
      "snapshot_weighted_avg",
      "source=snapshot",
    );
    assertNumEq(
      settlements[0].fee_amount_usd,
      8.0,
      "fee = 200 * 4% = 8.00",
    );
  });

  await test("interclub burn with legacy NULL snapshot → fee_rate_source=live_config_fallback", async () => {
    const issuer = await provisionClub({
      athletes: 1,
      inventoryTokens: 1000,
    });
    const redeemer = await provisionClub({
      athletes: 0,
      inventoryTokens: 100,
    });

    // Seed a legacy emission row (NULL snapshot) directly via SQL, bypassing
    // emit_coins_atomic. We still need to keep wallet + custody invariants
    // consistent for execute_burn_atomic to accept the burn.
    await setClearingRate(7.0);
    const legacyRefId = `${ORPHAN_PREFIX}legacy_burn_${randomUUID()}`;
    insertedRefIds.add(legacyRefId);
    const legacyLedgerId = randomUUID();
    insertedLedgerIds.add(legacyLedgerId);

    // Directly insert a NULL-snapshot emission row.
    const { error: insErr } = await db.from("coin_ledger").insert({
      id: legacyLedgerId,
      user_id: issuer.athletes[0],
      delta_coins: 100,
      reason: "institution_token_issue",
      ref_id: legacyRefId,
      issuer_group_id: issuer.groupId,
      created_at_ms: Date.now(),
      clearing_fee_rate_pct_snapshot: null,
    });
    if (insErr) throw new Error(`legacy ledger: ${insErr.message}`);

    // Mirror wallet + custody so execute_burn_atomic's balance check passes.
    // wallets is guarded by L18 mutation guard; use the authorised RPC instead.
    const { error: wErr } = await db.rpc("increment_wallet_balance", {
      p_user_id: issuer.athletes[0],
      p_delta: 100,
    });
    if (wErr) throw new Error(`wallet seed: ${wErr.message}`);

    // Inventory decrement + custody commit to match the legacy emission.
    await db
      .from("coaching_token_inventory")
      .update({ available_tokens: 900, lifetime_issued: 100 })
      .eq("group_id", issuer.groupId);
    await db
      .from("custody_accounts")
      .update({ total_committed: 100 })
      .eq("group_id", issuer.groupId);

    const burnRef = randomUUID();
    const { error: bErr } = await db.rpc("execute_burn_atomic", {
      p_user_id: issuer.athletes[0],
      p_redeemer_group_id: redeemer.groupId,
      p_amount: 100,
      p_ref_id: burnRef,
    });
    if (bErr) throw new Error(`burn: ${bErr.message}`);

    const settlements = await readSettlementForBurn(burnRef);
    assertEq(settlements.length, 1, "one settlement row");
    assertEq(
      settlements[0].fee_rate_source,
      "live_config_fallback",
      "source=live_config_fallback for NULL-snapshot issuer",
    );
    assertNumEq(
      settlements[0].fee_rate_pct,
      7.0,
      "uses current platform_fee_config rate (7.00)",
    );
  });

  // ── footer ───────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}${passed + failed} tests — ${OK} ${passed} · ${FAIL} ${failed}${RESET}`,
  );

  await cleanup();
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(`${FAIL} fatal: ${e instanceof Error ? e.stack : String(e)}`);
  cleanup().finally(() => process.exit(1));
});
