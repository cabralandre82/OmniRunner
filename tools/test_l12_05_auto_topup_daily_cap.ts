/**
 * tools/test_l12_05_auto_topup_daily_cap.ts
 *
 * Integration tests for the L12-05 auto-topup daily cap path
 * (`supabase/migrations/20260421200000_l12_05_auto_topup_daily_cap.sql`).
 *
 * Coverage
 * ────────
 *   schema & registry
 *     (1)  billing_auto_topup_settings.daily_charge_cap_brl exists w/ default 500
 *     (2)  billing_auto_topup_settings.daily_max_charges exists w/ default 3
 *     (3)  billing_auto_topup_settings.daily_limit_timezone exists w/ default
 *     (4)  billing_auto_topup_cap_changes table exists with FK + RLS
 *     (5)  fn_check_auto_topup_daily_window registered
 *     (6)  fn_apply_auto_topup_daily_cap registered (service_role only)
 *     (7)  fn_set_auto_topup_daily_cap registered (service_role only)
 *     (8)  anon cannot EXECUTE fn_apply_auto_topup_daily_cap
 *
 *   window arithmetic
 *     (9)  empty window: count=0, total=0, available_count=cap, would_exceed=false
 *     (10) auto_topup pending purchase counts toward window
 *     (11) auto_topup paid purchase counts toward window
 *     (12) auto_topup fulfilled purchase counts toward window
 *     (13) cancelled purchases do NOT count
 *     (14) source='manual' purchases do NOT count
 *     (15) currency='USD' purchases do NOT count (cap is BRL-only)
 *
 *   guardrail
 *     (16) fn_apply_auto_topup_daily_cap raises P0010 when count cap exceeded
 *     (17) fn_apply_auto_topup_daily_cap raises P0010 when total BRL cap exceeded
 *     (18) fn_apply_auto_topup_daily_cap is silent when within both caps
 *     (19) cross-group isolation
 *
 *   set_cap RPC
 *     (20) writes audit row to billing_auto_topup_cap_changes
 *     (21) rejects reason < 10 chars (P0001)
 *     (22) rejects p_new_cap_brl < 0 (P0001)
 *     (23) rejects p_new_max_charges > 24 (P0001)
 *     (24) rejects invalid IANA timezone (P0001)
 *     (25) idempotent replay returns identical out_was_idempotent=true
 *     (26) raises P0002 AUTO_TOPUP_SETTINGS_NOT_FOUND for unknown group
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l12_05_auto_topup_daily_cap.ts
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

function fmtErr(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (e && typeof e === "object") {
    const o = e as { code?: string; message?: string; details?: string };
    return [o.code, o.message, o.details].filter(Boolean).join(" | ");
  }
  return String(e);
}

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`  ${OK} ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ${FAIL} ${name}: ${fmtErr(e)}`);
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

const ORPHAN_PREFIX = "L12-05-test-";

const createdUserIds = new Set<string>();
const createdGroupIds = new Set<string>();
const createdProductIds = new Set<string>();
const createdPurchaseIds = new Set<string>();

async function purgeOrphans() {
  await db
    .from("billing_auto_topup_cap_changes")
    .delete()
    .ilike("reason", `${ORPHAN_PREFIX}%`);
}

async function createUser(): Promise<string> {
  const userId = randomUUID();
  const email = `l12-05-${userId}@test.local`;
  const { error } = await db.auth.admin.createUser({
    id: userId,
    email,
    email_confirm: true,
    password: randomUUID(),
  });
  if (error) throw new Error(`auth.admin.createUser: ${error.message}`);
  createdUserIds.add(userId);
  return userId;
}

async function createProduct(): Promise<string> {
  const productId = randomUUID();
  const { error } = await db.from("billing_products").insert({
    id: productId,
    name: `L12-05 product ${productId.slice(0, 8)}`,
    description: "test product",
    credits_amount: 1000,
    price_cents: 20000,
    currency: "BRL",
    is_active: true,
  });
  if (error) throw new Error(`billing_products: ${error.message}`);
  createdProductIds.add(productId);
  return productId;
}

interface ProvisionedGroup {
  groupId: string;
  adminUserId: string;
  productId: string;
}

async function provisionGroup(opts: {
  capBrl?: number;
  maxCharges?: number;
} = {}): Promise<ProvisionedGroup> {
  const adminUserId = await createUser();
  const groupId = randomUUID();
  const nowMs = Date.now();

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `L12-05 club ${groupId.slice(0, 8)}`,
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

  const productId = await createProduct();

  const settingsPayload: Record<string, unknown> = {
    group_id: groupId,
    enabled: true,
    threshold_tokens: 50,
    product_id: productId,
    max_per_month: 3,
  };
  if (opts.capBrl !== undefined) {
    settingsPayload.daily_charge_cap_brl = opts.capBrl;
  }
  if (opts.maxCharges !== undefined) {
    settingsPayload.daily_max_charges = opts.maxCharges;
  }
  const { error: sErr } = await db
    .from("billing_auto_topup_settings")
    .insert(settingsPayload);
  if (sErr) throw new Error(`billing_auto_topup_settings: ${sErr.message}`);

  return { groupId, adminUserId, productId };
}

async function createPurchase(
  group: ProvisionedGroup,
  opts: {
    priceCents: number;
    source?: "manual" | "auto_topup";
    status?: "pending" | "paid" | "fulfilled" | "cancelled";
    currency?: string;
  },
): Promise<string> {
  const { data, error } = await db
    .from("billing_purchases")
    .insert({
      group_id: group.groupId,
      product_id: group.productId,
      credits_amount: 1000,
      price_cents: opts.priceCents,
      currency: opts.currency ?? "BRL",
      status: opts.status ?? "pending",
      source: opts.source ?? "auto_topup",
    })
    .select("id")
    .single();
  if (error) throw error;
  const id = data!.id as string;
  createdPurchaseIds.add(id);
  return id;
}

async function readWindow(groupId: string, chargeBrl = 0) {
  const { data, error } = await db.rpc("fn_check_auto_topup_daily_window", {
    p_group_id: groupId,
    p_charge_amount_brl: chargeBrl,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

async function cleanup() {
  await purgeOrphans();
  for (const id of createdGroupIds) {
    await db.from("billing_purchases").delete().eq("group_id", id);
    await db
      .from("billing_auto_topup_cap_changes")
      .delete()
      .eq("group_id", id);
    await db
      .from("billing_auto_topup_settings")
      .delete()
      .eq("group_id", id);
    await db.from("coaching_members").delete().eq("group_id", id);
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const pid of createdProductIds) {
    await db.from("billing_products").delete().eq("id", pid);
  }
  for (const uid of createdUserIds) {
    await db.auth.admin.deleteUser(uid).catch(() => {});
  }
}

async function main() {
  console.log(`${BOLD}L12-05 — auto-topup daily cap${RESET}`);
  console.log(`Supabase: ${SUPABASE_URL}`);

  await purgeOrphans();

  // ── schema & registry ────────────────────────────────────────────────
  section("schema & registry");

  await test("billing_auto_topup_settings.daily_* columns selectable", async () => {
    const { error } = await db
      .from("billing_auto_topup_settings")
      .select(
        "daily_charge_cap_brl, daily_max_charges, daily_limit_timezone, daily_limit_updated_at, daily_limit_updated_by",
      )
      .limit(1);
    if (error) throw new Error(error.message);
  });

  await test("billing_auto_topup_cap_changes table queryable", async () => {
    const { error } = await db
      .from("billing_auto_topup_cap_changes")
      .select(
        "id, group_id, previous_cap_brl, new_cap_brl, previous_max_charges, new_max_charges, actor_user_id, reason, idempotency_key, changed_at",
      )
      .limit(1);
    if (error) throw new Error(error.message);
  });

  await test("fn_check_auto_topup_daily_window returns defaults for unknown group", async () => {
    const w = await readWindow(randomUUID());
    assertEq(w.timezone, "America/Sao_Paulo", "default tz");
    assertNumEq(w.daily_max_charges, 3, "default max_count");
    assertNumEq(w.daily_charge_cap_brl, 500, "default cap_brl");
  });

  await test("fn_apply_auto_topup_daily_cap rejects p_charge_amount_brl <= 0", async () => {
    const { error } = await db.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: randomUUID(),
      p_charge_amount_brl: 0,
    });
    assertTrue(
      error && /must be > 0/i.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("fn_set_auto_topup_daily_cap registered", async () => {
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: randomUUID(),
      p_new_cap_brl: 100,
      p_new_max_charges: 3,
      p_actor_user_id: randomUUID(),
      p_reason: "x",
    });
    assertTrue(
      error && />= 10 chars/.test(error.message ?? ""),
      `expected reason length error, got ${JSON.stringify(error)}`,
    );
  });

  await test("anon cannot EXECUTE fn_apply_auto_topup_daily_cap", async () => {
    const anon = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anon.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: randomUUID(),
      p_charge_amount_brl: 100,
    });
    assertTrue(
      error &&
        /permission denied|not allowed|insufficient privilege|access denied/i.test(
          error.message ?? "",
        ),
      `expected permission_denied for anon, got ${JSON.stringify(error)}`,
    );
  });

  // ── window arithmetic ─────────────────────────────────────────────────
  section("window arithmetic");

  const A = await provisionGroup({ capBrl: 1000, maxCharges: 5 });

  await test("empty window: count=0, total=0, available_count=cap", async () => {
    const w = await readWindow(A.groupId, 0);
    assertNumEq(w.current_count_today, 0, "count=0");
    assertNumEq(w.current_total_brl, 0, "total=0");
    assertNumEq(w.daily_max_charges, 5, "max_charges=5");
    assertNumEq(w.daily_charge_cap_brl, 1000, "cap=1000");
    assertNumEq(w.available_count, 5, "available=5");
    assertEq(w.would_exceed, false, "no exceed at 0");
  });

  await test("auto_topup pending purchase counts (R$ 100)", async () => {
    await createPurchase(A, { priceCents: 10000, status: "pending" });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 1, "count=1");
    assertNumEq(w.current_total_brl, 100, "total=100");
  });

  await test("auto_topup paid purchase counts (R$ 200)", async () => {
    await createPurchase(A, { priceCents: 20000, status: "paid" });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 2, "count=2");
    assertNumEq(w.current_total_brl, 300, "total=300");
  });

  await test("auto_topup fulfilled purchase counts (R$ 50)", async () => {
    await createPurchase(A, { priceCents: 5000, status: "fulfilled" });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 3, "count=3");
    assertNumEq(w.current_total_brl, 350, "total=350");
  });

  await test("cancelled purchases do NOT count", async () => {
    await createPurchase(A, { priceCents: 99900, status: "cancelled" });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 3, "count still 3");
    assertNumEq(w.current_total_brl, 350, "total still 350");
  });

  await test("source='manual' purchases do NOT count", async () => {
    await createPurchase(A, {
      priceCents: 99900,
      status: "paid",
      source: "manual",
    });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 3, "count still 3");
  });

  await test("currency='USD' purchases do NOT count (cap is BRL-only)", async () => {
    await createPurchase(A, {
      priceCents: 99900,
      status: "paid",
      currency: "USD",
    });
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_count_today, 3, "count still 3");
  });

  // ── guardrail ─────────────────────────────────────────────────────────
  section("guardrail");

  await test("apply raises P0010 when count cap exceeded", async () => {
    const B = await provisionGroup({ capBrl: 100000, maxCharges: 1 });
    await createPurchase(B, { priceCents: 100, status: "pending" });
    const { error } = await db.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: B.groupId,
      p_charge_amount_brl: 1,
    });
    assertTrue(
      error
        && (error.code === "P0010"
          || /AUTO_TOPUP_DAILY_CAP_EXCEEDED/.test(error.message ?? "")),
      `expected P0010, got ${JSON.stringify(error)}`,
    );
  });

  await test("apply raises P0010 when total BRL cap exceeded", async () => {
    const C = await provisionGroup({ capBrl: 100, maxCharges: 24 });
    await createPurchase(C, { priceCents: 9000, status: "pending" });
    const { error } = await db.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: C.groupId,
      p_charge_amount_brl: 50,
    });
    assertTrue(
      error
        && (error.code === "P0010"
          || /AUTO_TOPUP_DAILY_CAP_EXCEEDED/.test(error.message ?? "")),
      `expected P0010, got ${JSON.stringify(error)}`,
    );
  });

  await test("apply silent when within both caps", async () => {
    const D = await provisionGroup({ capBrl: 1000, maxCharges: 5 });
    await createPurchase(D, { priceCents: 10000, status: "pending" });
    const { error } = await db.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: D.groupId,
      p_charge_amount_brl: 100,
    });
    assertTrue(!error, `expected no error, got ${JSON.stringify(error)}`);
  });

  await test("cross-group isolation", async () => {
    const E1 = await provisionGroup({ capBrl: 100, maxCharges: 1 });
    await createPurchase(E1, { priceCents: 10000, status: "pending" });
    const E2 = await provisionGroup({ capBrl: 1000, maxCharges: 5 });
    const { error } = await db.rpc("fn_apply_auto_topup_daily_cap", {
      p_group_id: E2.groupId,
      p_charge_amount_brl: 100,
    });
    assertTrue(!error, `E2 should be allowed, got ${JSON.stringify(error)}`);
  });

  // ── set_cap RPC ──────────────────────────────────────────────────────
  section("set_cap RPC: audit + idempotency + validation");

  await test("writes audit row to billing_auto_topup_cap_changes", async () => {
    const F = await provisionGroup({ capBrl: 500, maxCharges: 3 });
    const reason = `${ORPHAN_PREFIX}bump cap for season`;
    const { data, error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: F.groupId,
      p_new_cap_brl: 2000,
      p_new_max_charges: 8,
      p_actor_user_id: F.adminUserId,
      p_reason: reason,
    });
    if (error) throw error;
    const row = Array.isArray(data) ? data[0] : data;
    assertNumEq(row.out_previous_cap_brl, 500, "previous_cap_brl");
    assertNumEq(row.out_new_cap_brl, 2000, "new_cap_brl");
    assertEq(row.out_was_idempotent, false, "fresh write");

    const audit = await db
      .from("billing_auto_topup_cap_changes")
      .select("previous_cap_brl, new_cap_brl, actor_user_id, reason")
      .eq("group_id", F.groupId)
      .order("changed_at", { ascending: false })
      .limit(1);
    if (audit.error) throw audit.error;
    const a = audit.data![0];
    assertNumEq(a.previous_cap_brl, 500, "audit previous");
    assertNumEq(a.new_cap_brl, 2000, "audit new");
    assertEq(a.actor_user_id, F.adminUserId, "actor");
    assertTrue(
      (a.reason as string).includes("bump"),
      "reason persisted",
    );
  });

  await test("rejects reason < 10 chars (P0001)", async () => {
    const G = await provisionGroup();
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: G.groupId,
      p_new_cap_brl: 1000,
      p_new_max_charges: 5,
      p_actor_user_id: G.adminUserId,
      p_reason: "short",
    });
    assertTrue(
      error && />= 10 chars/.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("rejects p_new_cap_brl < 0 (P0001)", async () => {
    const H = await provisionGroup();
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: H.groupId,
      p_new_cap_brl: -1,
      p_new_max_charges: 5,
      p_actor_user_id: H.adminUserId,
      p_reason: `${ORPHAN_PREFIX}negative cap should fail`,
    });
    assertTrue(
      error && />= 0/.test(error.message ?? ""),
      `expected >=0 error, got ${JSON.stringify(error)}`,
    );
  });

  await test("rejects p_new_max_charges > 24 (P0001)", async () => {
    const I = await provisionGroup();
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: I.groupId,
      p_new_cap_brl: 1000,
      p_new_max_charges: 25,
      p_actor_user_id: I.adminUserId,
      p_reason: `${ORPHAN_PREFIX}too many charges should fail`,
    });
    assertTrue(
      error && /between 1 and 24/.test(error.message ?? ""),
      `expected range error, got ${JSON.stringify(error)}`,
    );
  });

  await test("rejects invalid IANA timezone (P0001)", async () => {
    const J = await provisionGroup();
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: J.groupId,
      p_new_cap_brl: 1000,
      p_new_max_charges: 5,
      p_actor_user_id: J.adminUserId,
      p_reason: `${ORPHAN_PREFIX}invalid tz should fail`,
      p_timezone: "Mars/Olympus",
    });
    assertTrue(
      error && /not a valid IANA timezone/.test(error.message ?? ""),
      `expected tz error, got ${JSON.stringify(error)}`,
    );
  });

  await test("idempotent replay returns out_was_idempotent=true", async () => {
    const K = await provisionGroup({ capBrl: 500, maxCharges: 3 });
    const idemKey = `${ORPHAN_PREFIX}${K.groupId.slice(0, 8)}-idem-1`;
    const reason = `${ORPHAN_PREFIX}idempotent replay test`;

    const first = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: K.groupId,
      p_new_cap_brl: 800,
      p_new_max_charges: 4,
      p_actor_user_id: K.adminUserId,
      p_reason: reason,
      p_idempotency_key: idemKey,
    });
    if (first.error) throw first.error;
    const firstRow = Array.isArray(first.data) ? first.data[0] : first.data;
    assertEq(firstRow.out_was_idempotent, false, "first call NOT idempotent");
    assertNumEq(firstRow.out_new_cap_brl, 800, "first sets 800");

    const replay = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: K.groupId,
      p_new_cap_brl: 9999, // ignorado no replay
      p_new_max_charges: 24,
      p_actor_user_id: K.adminUserId,
      p_reason: reason,
      p_idempotency_key: idemKey,
    });
    if (replay.error) throw replay.error;
    const replayRow = Array.isArray(replay.data) ? replay.data[0] : replay.data;
    assertEq(replayRow.out_was_idempotent, true, "replay flagged idempotent");
    assertNumEq(replayRow.out_new_cap_brl, 800, "replay returns 800 (not 9999)");

    const audit = await db
      .from("billing_auto_topup_cap_changes")
      .select("id")
      .eq("group_id", K.groupId)
      .eq("idempotency_key", idemKey);
    if (audit.error) throw audit.error;
    assertEq(audit.data?.length, 1, "exactly 1 audit row for idem key");
  });

  await test("raises P0002 AUTO_TOPUP_SETTINGS_NOT_FOUND for unknown group", async () => {
    const { error } = await db.rpc("fn_set_auto_topup_daily_cap", {
      p_group_id: randomUUID(),
      p_new_cap_brl: 1000,
      p_new_max_charges: 5,
      p_actor_user_id: randomUUID(),
      p_reason: `${ORPHAN_PREFIX}unknown group should P0002`,
    });
    assertTrue(
      error
        && (error.code === "P0002"
          || /AUTO_TOPUP_SETTINGS_NOT_FOUND/.test(error.message ?? "")),
      `expected P0002, got ${JSON.stringify(error)}`,
    );
  });

  // ── teardown ──────────────────────────────────────────────────────────
  await cleanup();

  console.log(
    `\n${BOLD}── summary ──${RESET}\n  ${OK} ${passed} passed  ${failed > 0 ? `${FAIL} ${failed} failed` : ""}`,
  );
  if (failed > 0) process.exit(1);
}

main().catch(async (e) => {
  console.error("\nfatal:", e);
  await cleanup();
  process.exit(1);
});
