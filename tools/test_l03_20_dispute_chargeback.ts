/**
 * tools/test_l03_20_dispute_chargeback.ts
 *
 * Integration tests for the L03-20 dispute/chargeback path
 * (`supabase/migrations/20260421160000_l03_dispute_chargeback_flow.sql`).
 *
 * Runs against a Supabase instance that has BOTH L03-13 and L03-20
 * applied. Exercises the orchestrator `fn_handle_custody_dispute_atomic`
 * end-to-end against real custody_deposits / custody_accounts rows.
 *
 * Coverage
 * ────────
 *   (1)  fn_handle_custody_dispute_atomic registered + service_role EXECUTE
 *   (2)  anon role cannot EXECUTE
 *   (3)  platform_webhook_system_user_id() returns the constant uuid
 *        AND auth.users row is present (seed is idempotent)
 *
 *   happy path
 *   (4)  dispute with committed=0 → outcome=reversed, state=RESOLVED_REVERSED
 *        → deposit.status=refunded, total_deposited decremented,
 *        coin_reversal_log row created, portal_audit_log entry written
 *
 *   idempotency
 *   (5)  replay same (gateway, event_id) → was_idempotent=true,
 *        no new custody_dispute_cases row, no additional reversal,
 *        custody_accounts unchanged
 *
 *   escalation
 *   (6)  committed > 0 (coins issued against the lastro) → outcome=escalated,
 *        state=ESCALATED_CFO, reversal_id NULL, deposit.status unchanged,
 *        custody_accounts unchanged, audit action=custody.dispute.escalated_cfo
 *
 *   deposit_not_found
 *   (7)  unknown payment_reference → outcome=deposit_not_found,
 *        state=DEPOSIT_NOT_FOUND, deposit_id NULL
 *
 *   dismissed
 *   (8)  dispute for already-refunded deposit → outcome=dismissed,
 *        state=DISMISSED (no reversal attempted)
 *   (9)  dispute for pending deposit → outcome=dismissed
 *
 *   validation
 *  (10)  invalid gateway / kind / blank event_id → raises P0001
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l03_20_dispute_chargeback.ts
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

const PLATFORM_WEBHOOK_USER = "11111111-1111-1111-1111-111111111111";

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

// ────────────────────────────────────────────────────────────────────────
// Setup / cleanup
// ────────────────────────────────────────────────────────────────────────

const createdUsers = new Set<string>();
const createdGroups = new Set<string>();
const createdDeposits = new Set<string>();
const createdEventIds = new Set<string>();

async function createUser(): Promise<string> {
  const id = randomUUID();
  const { error } = await db.auth.admin.createUser({
    id,
    email: `l03-20-${id}@test.local`,
    email_confirm: true,
    password: randomUUID(),
  });
  if (error) throw new Error(`auth.admin.createUser: ${error.message}`);
  createdUsers.add(id);
  return id;
}

async function provisionGroup(opts: {
  deposited: number;
  committed?: number;
}): Promise<{ groupId: string; adminId: string }> {
  const adminId = await createUser();
  const groupId = randomUUID();
  const nowMs = Date.now();

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `L03-20 club ${groupId.slice(0, 8)}`,
    coach_user_id: adminId,
    created_at_ms: nowMs,
    approval_status: "approved",
  });
  if (gErr) throw new Error(`coaching_groups: ${gErr.message}`);
  createdGroups.add(groupId);

  const { error: caErr } = await db.from("custody_accounts").insert({
    group_id: groupId,
    total_deposited_usd: opts.deposited,
    total_committed: opts.committed ?? 0,
  });
  if (caErr) throw new Error(`custody_accounts: ${caErr.message}`);

  return { groupId, adminId };
}

async function createConfirmedDeposit(
  groupId: string,
  amountUsd: number,
): Promise<{ id: string; paymentReference: string }> {
  const paymentReference = `pi_l03_20_${randomUUID().replace(/-/g, "").slice(0, 10)}`;
  const { data, error } = await db
    .from("custody_deposits")
    .insert({
      group_id: groupId,
      amount_usd: amountUsd,
      coins_equivalent: Math.floor(amountUsd),
      payment_gateway: "stripe",
      payment_reference: paymentReference,
      status: "confirmed",
    })
    .select("id")
    .single();

  if (error || !data) throw new Error(`custody_deposits: ${error?.message}`);
  createdDeposits.add(data.id);
  return { id: data.id, paymentReference };
}

async function readDeposit(id: string) {
  const { data, error } = await db
    .from("custody_deposits")
    .select("status, payment_reference, amount_usd")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(`read deposit: ${error.message}`);
  return data;
}

async function readAccount(groupId: string) {
  const { data, error } = await db
    .from("custody_accounts")
    .select("total_deposited_usd, total_committed")
    .eq("group_id", groupId)
    .maybeSingle();
  if (error) throw new Error(`read account: ${error.message}`);
  return data;
}

async function readCase(id: string) {
  const { data, error } = await db
    .from("custody_dispute_cases")
    .select("*")
    .eq("id", id)
    .maybeSingle();
  if (error) throw new Error(`read case: ${error.message}`);
  return data;
}

async function callDispute(args: {
  gateway: "stripe" | "mercadopago" | "asaas";
  eventId: string;
  disputeRef?: string | null;
  paymentReference: string | null;
  kind: "dispute" | "refund" | "chargeback";
  reasonCode: string;
  rawEvent?: Record<string, unknown>;
}) {
  createdEventIds.add(args.eventId);
  const { data, error } = await db.rpc(
    "fn_handle_custody_dispute_atomic" as unknown as never,
    {
      p_gateway: args.gateway,
      p_gateway_event_id: args.eventId,
      p_gateway_dispute_ref: args.disputeRef ?? null,
      p_payment_reference: args.paymentReference,
      p_kind: args.kind,
      p_reason_code: args.reasonCode,
      p_raw_event: args.rawEvent ?? {},
    },
  );
  return { data, error };
}

async function cleanup() {
  for (const id of createdEventIds) {
    await db.from("custody_dispute_cases").delete().eq("gateway_event_id", id);
  }
  for (const id of createdDeposits) {
    // reversal log may FK-reference the deposit target_ref — delete via idem-key
    // is handled by the coin_reversal_log deletion below.
    await db
      .from("coin_reversal_log")
      .delete()
      .eq("target_ref", id);
    await db.from("custody_deposits").delete().eq("id", id);
  }
  for (const id of createdGroups) {
    await db.from("custody_accounts").delete().eq("group_id", id);
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const id of createdUsers) {
    await db.auth.admin.deleteUser(id).catch(() => {});
  }
}

// ────────────────────────────────────────────────────────────────────────
// Main
// ────────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`${BOLD}L03-20 — dispute / chargeback flow${RESET}`);
  console.log(`Supabase: ${SUPABASE_URL}`);

  // ── registry & permissions ─────────────────────────────────────────────
  section("registry & permissions");

  await test("fn_handle_custody_dispute_atomic registered", async () => {
    // An empty event_id triggers EVENT_ID_REQUIRED — proves the function
    // exists and its validation block runs (without creating test rows).
    const { error } = await db.rpc(
      "fn_handle_custody_dispute_atomic" as unknown as never,
      {
        p_gateway: "stripe",
        p_gateway_event_id: "",
        p_gateway_dispute_ref: null,
        p_payment_reference: "probe",
        p_kind: "dispute",
        p_reason_code: "probe",
        p_raw_event: {},
      },
    );
    assertTrue(
      error && /EVENT_ID_REQUIRED/.test(error.message ?? ""),
      `expected EVENT_ID_REQUIRED, got ${JSON.stringify(error)}`,
    );
  });

  await test("platform_webhook_system_user_id() returns the seeded uuid", async () => {
    const { data, error } = await db.rpc(
      "platform_webhook_system_user_id" as unknown as never,
    );
    if (error) throw new Error(`rpc: ${error.message}`);
    assertEq(data, PLATFORM_WEBHOOK_USER, "platform_webhook_system_user_id");
  });

  await test("auth.users row for platform_webhook_system exists", async () => {
    // Ensures the migration seeded the sentinel row so FK'd actions
    // don't fail in production. We can't SELECT auth.users via the API,
    // so we verify INDIRECTLY via an action that will FK-reference it.
    const { groupId } = await provisionGroup({ deposited: 10, committed: 0 });
    const { paymentReference } = await createConfirmedDeposit(groupId, 10);
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId: `evt_seed_check_${randomUUID().slice(0, 8)}`,
      paymentReference,
      kind: "refund",
      reasonCode: "seed_check",
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.outcome, "reversed", "outcome");
    // The FK constraint on coin_reversal_log.actor_user_id is only
    // satisfied because the seed row exists — success here proves it.
  });

  await test("anon role cannot EXECUTE fn_handle_custody_dispute_atomic", async () => {
    const anonClient = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anonClient.rpc(
      "fn_handle_custody_dispute_atomic" as unknown as never,
      {
        p_gateway: "stripe",
        p_gateway_event_id: "probe",
        p_gateway_dispute_ref: null,
        p_payment_reference: "probe",
        p_kind: "dispute",
        p_reason_code: "probe",
        p_raw_event: {},
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

  // ── happy path ─────────────────────────────────────────────────────────
  section("happy path — auto-reverse a confirmed deposit");

  await test("dispute with committed=0 → reversed + deposit refunded + account debited", async () => {
    const { groupId } = await provisionGroup({ deposited: 100, committed: 0 });
    const { id: depositId, paymentReference } = await createConfirmedDeposit(
      groupId,
      100,
    );

    const eventId = `evt_happy_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId,
      disputeRef: "du_happy_1",
      paymentReference,
      kind: "chargeback",
      reasonCode: "fraudulent",
      rawEvent: { test: "happy" },
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;

    assertEq(row.outcome, "reversed", "outcome");
    assertEq(row.case_state, "RESOLVED_REVERSED", "case_state");
    assertEq(row.deposit_id, depositId, "deposit_id");
    assertTrue(row.reversal_id !== null, "reversal_id must be set");
    assertEq(Number(row.refunded_usd), 100, "refunded_usd");
    assertEq(row.was_idempotent, false, "was_idempotent");

    const dep = await readDeposit(depositId);
    assertEq(dep?.status, "refunded", "deposit.status");

    const acc = await readAccount(groupId);
    assertEq(Number(acc?.total_deposited_usd), 0, "account.total_deposited_usd after reverse");
    assertEq(Number(acc?.total_committed), 0, "account.total_committed unchanged");

    // coin_reversal_log row exists + is tagged with the right idem key
    const { data: rev } = await db
      .from("coin_reversal_log")
      .select("id, kind, idempotency_key, actor_user_id, reversed_usd")
      .eq("id", row.reversal_id)
      .maybeSingle();
    assertTrue(rev !== null, "coin_reversal_log row missing");
    assertEq(rev?.kind, "deposit", "coin_reversal_log.kind");
    assertEq(rev?.idempotency_key, `stripe:${eventId}`, "idempotency_key");
    assertEq(rev?.actor_user_id, PLATFORM_WEBHOOK_USER, "actor_user_id");
    assertEq(Number(rev?.reversed_usd), 100, "reversed_usd");

    // audit log entries
    const { data: auditRows } = await db
      .from("portal_audit_log")
      .select("action")
      .eq("target_id", row.case_id);
    const actions = (auditRows ?? []).map((r) => r.action);
    assertTrue(
      actions.includes("custody.dispute.reversed"),
      `audit missing custody.dispute.reversed (got ${actions.join(",")})`,
    );
  });

  // ── idempotency ────────────────────────────────────────────────────────
  section("idempotency — replay same (gateway, event_id)");

  await test("replay returns was_idempotent=true and preserves state", async () => {
    const { groupId } = await provisionGroup({ deposited: 50, committed: 0 });
    const { id: depositId, paymentReference } = await createConfirmedDeposit(
      groupId,
      50,
    );

    const eventId = `evt_replay_${randomUUID().slice(0, 8)}`;
    const { data: data1, error: e1 } = await callDispute({
      gateway: "stripe",
      eventId,
      paymentReference,
      kind: "refund",
      reasonCode: "duplicate",
    });
    if (e1) throw new Error(`first call: ${e1.message}`);
    const row1 = Array.isArray(data1) ? data1[0] : data1;
    assertEq(row1.outcome, "reversed", "first outcome");

    // Snapshot account + case to detect any drift on replay
    const accBefore = await readAccount(groupId);
    const caseBefore = await readCase(row1.case_id);

    const { data: data2, error: e2 } = await callDispute({
      gateway: "stripe",
      eventId,
      paymentReference,
      kind: "refund",
      reasonCode: "duplicate",
    });
    if (e2) throw new Error(`replay: ${e2.message}`);
    const row2 = Array.isArray(data2) ? data2[0] : data2;

    assertEq(row2.outcome, "idempotent_replay", "outcome");
    assertEq(row2.was_idempotent, true, "was_idempotent");
    assertEq(row2.case_id, row1.case_id, "replay returns ORIGINAL case_id");
    assertEq(row2.case_state, "RESOLVED_REVERSED", "case_state preserved");

    const accAfter = await readAccount(groupId);
    assertEq(
      Number(accAfter?.total_deposited_usd),
      Number(accBefore?.total_deposited_usd),
      "replay must not mutate total_deposited_usd",
    );

    const caseAfter = await readCase(row1.case_id);
    assertEq(caseAfter?.state, caseBefore?.state, "case.state preserved");

    // Also: only ONE row exists for (gateway, event_id).
    const { count } = await db
      .from("custody_dispute_cases")
      .select("id", { count: "exact", head: true })
      .eq("gateway", "stripe")
      .eq("gateway_event_id", eventId);
    assertEq(count, 1, "exactly one dispute case row");

    // Deposit still refunded once.
    const dep = await readDeposit(depositId);
    assertEq(dep?.status, "refunded", "deposit.status preserved");
  });

  // ── escalation path ────────────────────────────────────────────────────
  section("escalation — coins already spent against the lastro");

  await test("dispute with committed > 0 → ESCALATED_CFO, no reversal, account untouched", async () => {
    // Set committed=100 so any refund of a deposit of $100 would leave
    // deposited(0) < committed(100). reverse_custody_deposit_atomic
    // raises INVARIANT_VIOLATION, our handler catches it.
    const { groupId } = await provisionGroup({ deposited: 100, committed: 100 });
    const { id: depositId, paymentReference } = await createConfirmedDeposit(
      groupId,
      100,
    );

    const eventId = `evt_esc_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId,
      disputeRef: "du_esc_1",
      paymentReference,
      kind: "chargeback",
      reasonCode: "product_not_received",
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;

    assertEq(row.outcome, "escalated", "outcome");
    assertEq(row.case_state, "ESCALATED_CFO", "case_state");
    assertEq(row.reversal_id, null, "reversal_id must be null on escalate");

    // Deposit status UNCHANGED — lastro not moved.
    const dep = await readDeposit(depositId);
    assertEq(dep?.status, "confirmed", "deposit.status unchanged on escalate");

    const acc = await readAccount(groupId);
    assertEq(Number(acc?.total_deposited_usd), 100, "total_deposited_usd unchanged");
    assertEq(Number(acc?.total_committed), 100, "total_committed unchanged");

    const { data: auditRows } = await db
      .from("portal_audit_log")
      .select("action, metadata")
      .eq("target_id", row.case_id);
    const actions = (auditRows ?? []).map((r) => r.action);
    assertTrue(
      actions.includes("custody.dispute.escalated_cfo"),
      `expected escalated_cfo in audit, got ${actions.join(",")}`,
    );
  });

  // ── deposit_not_found ──────────────────────────────────────────────────
  section("deposit_not_found — unknown payment_reference");

  await test("no matching deposit → state=DEPOSIT_NOT_FOUND, reversal_id NULL", async () => {
    const eventId = `evt_dnf_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId,
      paymentReference: `pi_not_found_${randomUUID().slice(0, 6)}`,
      kind: "dispute",
      reasonCode: "fraudulent",
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.outcome, "deposit_not_found", "outcome");
    assertEq(row.case_state, "DEPOSIT_NOT_FOUND", "case_state");
    assertEq(row.deposit_id, null, "deposit_id");
    assertEq(row.reversal_id, null, "reversal_id");
  });

  await test("NULL payment_reference also routes to deposit_not_found", async () => {
    const eventId = `evt_dnf_null_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId,
      paymentReference: null,
      kind: "dispute",
      reasonCode: "fraudulent",
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.outcome, "deposit_not_found", "outcome");
  });

  // ── dismissed ──────────────────────────────────────────────────────────
  section("dismissed — deposit exists but not confirmed");

  await test("dispute on already-refunded deposit → outcome=dismissed", async () => {
    const { groupId } = await provisionGroup({ deposited: 30, committed: 0 });
    const { id: depositId, paymentReference } = await createConfirmedDeposit(
      groupId,
      30,
    );

    // Reverse the deposit first so it's in `refunded` state.
    const firstEvent = `evt_first_${randomUUID().slice(0, 8)}`;
    const { error: firstErr } = await callDispute({
      gateway: "stripe",
      eventId: firstEvent,
      paymentReference,
      kind: "refund",
      reasonCode: "first_refund",
    });
    if (firstErr) throw new Error(`first: ${firstErr.message}`);

    const dep = await readDeposit(depositId);
    assertEq(dep?.status, "refunded", "precondition: deposit refunded");

    // Now fire a SECOND dispute for the same deposit — should dismiss.
    const secondEvent = `evt_dism_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId: secondEvent,
      paymentReference,
      kind: "chargeback",
      reasonCode: "late_chargeback",
    });
    if (error) throw new Error(`second: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;

    assertEq(row.outcome, "dismissed", "outcome");
    assertEq(row.case_state, "DISMISSED", "case_state");
    assertEq(row.reversal_id, null, "reversal_id must be null on dismiss");
  });

  await test("dispute on pending deposit → outcome=dismissed", async () => {
    const { groupId } = await provisionGroup({ deposited: 0, committed: 0 });
    const paymentReference = `pi_pending_${randomUUID().slice(0, 8)}`;
    const { data: inserted, error: iErr } = await db
      .from("custody_deposits")
      .insert({
        group_id: groupId,
        amount_usd: 20,
        coins_equivalent: 20,
        payment_gateway: "stripe",
        payment_reference: paymentReference,
        status: "pending",
      })
      .select("id")
      .single();
    if (iErr || !inserted) throw new Error(`insert pending: ${iErr?.message}`);
    createdDeposits.add(inserted.id);

    const eventId = `evt_pending_dism_${randomUUID().slice(0, 8)}`;
    const { data, error } = await callDispute({
      gateway: "stripe",
      eventId,
      paymentReference,
      kind: "dispute",
      reasonCode: "fraudulent",
    });
    if (error) throw new Error(`dispute: ${error.message}`);
    const row = Array.isArray(data) ? data[0] : data;
    assertEq(row.outcome, "dismissed", "outcome");

    // Deposit status unchanged — still pending.
    const dep = await readDeposit(inserted.id);
    assertEq(dep?.status, "pending", "deposit.status unchanged");
  });

  // ── input validation ───────────────────────────────────────────────────
  section("input validation");

  await test("invalid gateway → INVALID_GATEWAY", async () => {
    const { error } = await callDispute({
      gateway: "paypal" as unknown as "stripe",
      eventId: `evt_val_${randomUUID().slice(0, 8)}`,
      paymentReference: null,
      kind: "dispute",
      reasonCode: "x",
    });
    assertTrue(
      error && /INVALID_GATEWAY/.test(error.message ?? ""),
      `expected INVALID_GATEWAY, got ${JSON.stringify(error)}`,
    );
  });

  await test("invalid kind → INVALID_KIND", async () => {
    const { error } = await callDispute({
      gateway: "stripe",
      eventId: `evt_val_${randomUUID().slice(0, 8)}`,
      paymentReference: null,
      kind: "bogus" as unknown as "dispute",
      reasonCode: "x",
    });
    assertTrue(
      error && /INVALID_KIND/.test(error.message ?? ""),
      `expected INVALID_KIND, got ${JSON.stringify(error)}`,
    );
  });

  await test("blank reason_code → REASON_REQUIRED", async () => {
    const { error } = await callDispute({
      gateway: "stripe",
      eventId: `evt_val_${randomUUID().slice(0, 8)}`,
      paymentReference: null,
      kind: "dispute",
      reasonCode: "",
    });
    assertTrue(
      error && /REASON_REQUIRED/.test(error.message ?? ""),
      `expected REASON_REQUIRED, got ${JSON.stringify(error)}`,
    );
  });

  // ── cleanup ────────────────────────────────────────────────────────────
  await cleanup();

  console.log(
    `\n${BOLD}Summary:${RESET} ${OK} ${passed} passed, ${failed > 0 ? FAIL : OK} ${failed} failed`,
  );
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
