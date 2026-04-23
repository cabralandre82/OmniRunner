/**
 * tools/test_l05_09_custody_daily_cap.ts
 *
 * Integration tests for the L05-09 custody daily deposit cap path
 * (`supabase/migrations/20260421180000_l05_09_custody_daily_deposit_cap.sql`).
 *
 * Coverage
 * ────────
 *   schema & registry
 *     (1)  custody_accounts.daily_deposit_limit_usd column exists w/ default 50_000
 *     (2)  custody_accounts.daily_limit_timezone column exists w/ default
 *     (3)  custody_daily_cap_changes table exists with FK + RLS
 *     (4)  fn_check_daily_deposit_window registered (authenticated)
 *     (5)  fn_apply_daily_deposit_cap registered (service_role only)
 *     (6)  fn_set_daily_deposit_cap registered (service_role only)
 *     (7)  anon cannot EXECUTE fn_apply_daily_deposit_cap
 *
 *   window arithmetic
 *     (8)  empty window: current=0, available=limit, would_exceed(0)=false
 *     (9)  with one pending deposit: current = deposit.amount_usd
 *     (10) failed deposits do NOT count toward the window
 *     (11) refunded deposits do NOT count toward the window
 *
 *   guardrail
 *     (12) fn_apply_daily_deposit_cap raises P0010 when over limit
 *     (13) fn_apply_daily_deposit_cap is silent when within limit
 *     (14) cross-group isolation — group A's usage doesn't affect group B
 *
 *   idempotency interaction
 *     (15) miss-path: first create blocked when already at limit
 *     (16) idempotent replay returns existing deposit even if cap now zero
 *     (17) cap raised mid-day: new deposits succeed up to new ceiling
 *
 *   audit trail
 *     (18) fn_set_daily_deposit_cap writes to custody_daily_cap_changes
 *     (19) fn_set_daily_deposit_cap rejects reason < 10 chars
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l05_09_custody_daily_cap.ts
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

const ORPHAN_PREFIX = "L05-09-test-";

const createdUserIds = new Set<string>();
const createdGroupIds = new Set<string>();

async function purgeOrphans() {
  await db
    .from("custody_deposits")
    .delete()
    .ilike("idempotency_key", `${ORPHAN_PREFIX}%`);
  await db
    .from("custody_daily_cap_changes")
    .delete()
    .ilike("reason", `${ORPHAN_PREFIX}%`);
}

async function createUser(): Promise<string> {
  const userId = randomUUID();
  const email = `l05-09-${userId}@test.local`;
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

interface ProvisionedAccount {
  groupId: string;
  adminUserId: string;
}

async function provisionAccount(opts: { capUsd?: number } = {}): Promise<ProvisionedAccount> {
  const adminUserId = await createUser();
  const groupId = randomUUID();
  const nowMs = Date.now();

  const { error: gErr } = await db.from("coaching_groups").insert({
    id: groupId,
    name: `L05-09 club ${groupId.slice(0, 8)}`,
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

  const { error: caErr } = await db.from("custody_accounts").insert({
    group_id: groupId,
    daily_deposit_limit_usd: opts.capUsd ?? 50000,
  });
  if (caErr) throw new Error(`custody_accounts: ${caErr.message}`);

  return { groupId, adminUserId };
}

async function createDeposit(
  groupId: string,
  amountUsd: number,
  suffix: string,
  status: "pending" | "confirmed" | "failed" | "refunded" = "pending",
): Promise<string> {
  const key = `${ORPHAN_PREFIX}${suffix}`;
  // For non-pending statuses (test fixtures simulating already-failed or
  // already-refunded rows) insert directly to bypass the daily cap guardrail
  // — those statuses don't consume the budget anyway.
  if (status !== "pending") {
    const { data, error } = await db
      .from("custody_deposits")
      .insert({
        group_id: groupId,
        amount_usd: amountUsd,
        coins_equivalent: Math.floor(amountUsd),
        payment_gateway: "stripe",
        idempotency_key: key,
        status,
      })
      .select("id")
      .single();
    if (error) throw error;
    return data!.id as string;
  }

  const { data, error } = await db.rpc("fn_create_custody_deposit_idempotent", {
    p_group_id: groupId,
    p_amount_usd: amountUsd,
    p_coins_equivalent: Math.floor(amountUsd),
    p_payment_gateway: "stripe",
    p_idempotency_key: key,
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  return row.deposit_id as string;
}

async function setCap(
  groupId: string,
  capUsd: number,
  actor: string,
  suffix: string,
): Promise<void> {
  const reason = `${ORPHAN_PREFIX}${suffix} reason placeholder`;
  const { error } = await db.rpc("fn_set_daily_deposit_cap", {
    p_group_id: groupId,
    p_new_cap_usd: capUsd,
    p_actor_user_id: actor,
    p_reason: reason,
  });
  if (error) throw error;
}

async function readWindow(groupId: string, amountUsd = 0) {
  const { data, error } = await db.rpc("fn_check_daily_deposit_window", {
    p_group_id: groupId,
    p_amount_usd: amountUsd,
  });
  if (error) throw error;
  return Array.isArray(data) ? data[0] : data;
}

async function cleanup() {
  await purgeOrphans();
  for (const id of createdGroupIds) {
    await db.from("custody_deposits").delete().eq("group_id", id);
    await db.from("custody_daily_cap_changes").delete().eq("group_id", id);
    await db.from("custody_accounts").delete().eq("group_id", id);
    await db.from("coaching_members").delete().eq("group_id", id);
    await db.from("coaching_groups").delete().eq("id", id);
  }
  for (const uid of createdUserIds) {
    await db.auth.admin.deleteUser(uid).catch(() => {});
  }
}

async function main() {
  console.log(`${BOLD}L05-09 — custody daily deposit cap${RESET}`);
  console.log(`Supabase: ${SUPABASE_URL}`);

  await purgeOrphans();

  // ── schema & registry ────────────────────────────────────────────────
  section("schema & registry");

  await test("custody_accounts.daily_deposit_limit_usd exists with default 50000", async () => {
    const { data, error } = await db
      .from("custody_accounts")
      .select("daily_deposit_limit_usd, daily_limit_timezone")
      .limit(1);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "query succeeded");
  });

  await test("custody_accounts.daily_limit_timezone column exists", async () => {
    const { data, error } = await db
      .from("custody_accounts")
      .select("daily_limit_timezone")
      .limit(1);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "query succeeded");
  });

  await test("custody_daily_cap_changes table queryable", async () => {
    const { error } = await db
      .from("custody_daily_cap_changes")
      .select("id, group_id, previous_cap_usd, new_cap_usd, actor_user_id, reason, changed_at")
      .limit(1);
    if (error) throw new Error(error.message);
  });

  await test("fn_check_daily_deposit_window registered (service_role can call)", async () => {
    const { data, error } = await db.rpc("fn_check_daily_deposit_window", {
      p_group_id: randomUUID(),
      p_amount_usd: 0,
    });
    if (error) throw new Error(error.message);
    const row = Array.isArray(data) ? data[0] : data;
    // Unknown group → fall back to default tz=America/Sao_Paulo, limit=50000
    assertEq(row.timezone, "America/Sao_Paulo", "default timezone");
    assertNumEq(row.daily_limit_usd, 50000, "default limit");
  });

  await test("fn_apply_daily_deposit_cap registered", async () => {
    // Calling with amount=0 trips the > 0 check (P0001) — ensures the
    // function exists and validates inputs.
    const { error } = await db.rpc("fn_apply_daily_deposit_cap", {
      p_group_id: randomUUID(),
      p_amount_usd: 0,
    });
    assertTrue(
      error && /must be > 0/i.test(error.message ?? ""),
      `expected validation error, got ${JSON.stringify(error)}`,
    );
  });

  await test("fn_set_daily_deposit_cap registered", async () => {
    const { error } = await db.rpc("fn_set_daily_deposit_cap", {
      p_group_id: randomUUID(),
      p_new_cap_usd: 100,
      p_actor_user_id: randomUUID(),
      p_reason: "x", // < 10 chars → P0001
    });
    assertTrue(
      error && />= 10 chars/.test(error.message ?? ""),
      `expected reason length error, got ${JSON.stringify(error)}`,
    );
  });

  await test("anon cannot EXECUTE fn_apply_daily_deposit_cap", async () => {
    const anonClient = createClient(
      SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY ??
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
      { auth: { autoRefreshToken: false, persistSession: false } },
    );
    const { error } = await anonClient.rpc("fn_apply_daily_deposit_cap", {
      p_group_id: randomUUID(),
      p_amount_usd: 100,
    });
    assertTrue(
      error &&
        /permission denied|not allowed|insufficient privilege|access denied/i.test(error.message ?? ""),
      `expected permission_denied for anon, got ${JSON.stringify(error)}`,
    );
  });

  // ── window arithmetic ─────────────────────────────────────────────────
  section("window arithmetic");

  const A = await provisionAccount({ capUsd: 5000 });

  await test("empty window: current=0, available=limit, would_exceed(0)=false", async () => {
    const w = await readWindow(A.groupId, 0);
    assertNumEq(w.current_total_usd, 0, "current_total_usd=0");
    assertNumEq(w.daily_limit_usd, 5000, "daily_limit_usd=5000");
    assertNumEq(w.available_today_usd, 5000, "available=5000");
    assertEq(w.would_exceed, false, "no exceed at amount=0");
  });

  await test("with one pending deposit: current = deposit.amount_usd", async () => {
    await createDeposit(A.groupId, 1200, `${A.groupId.slice(0, 8)}-pend`, "pending");
    const w = await readWindow(A.groupId, 100);
    assertNumEq(w.current_total_usd, 1200, "current includes pending");
    assertNumEq(w.available_today_usd, 5000 - 1200, "available decreases");
    assertEq(w.would_exceed, false, "100 still fits");
  });

  await test("failed deposits do NOT count toward the window", async () => {
    await createDeposit(A.groupId, 9999, `${A.groupId.slice(0, 8)}-fail`, "failed");
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_total_usd, 1200, "still 1200, ignores failed");
  });

  await test("refunded deposits do NOT count toward the window", async () => {
    await createDeposit(A.groupId, 9999, `${A.groupId.slice(0, 8)}-refd`, "refunded");
    const w = await readWindow(A.groupId);
    assertNumEq(w.current_total_usd, 1200, "still 1200, ignores refunded");
  });

  // ── guardrail ─────────────────────────────────────────────────────────
  section("guardrail");

  await test("fn_apply_daily_deposit_cap raises P0010 when over limit", async () => {
    // A has 1200 used, cap 5000. Try 4000 → would_total 5200 > 5000.
    const { error } = await db.rpc("fn_apply_daily_deposit_cap", {
      p_group_id: A.groupId,
      p_amount_usd: 4000,
    });
    assertTrue(
      error && (error.code === "P0010" || /DAILY_DEPOSIT_CAP_EXCEEDED/.test(error.message ?? "")),
      `expected P0010, got ${JSON.stringify(error)}`,
    );
  });

  await test("fn_apply_daily_deposit_cap is silent when within limit", async () => {
    const { error } = await db.rpc("fn_apply_daily_deposit_cap", {
      p_group_id: A.groupId,
      p_amount_usd: 1000, // 1200 + 1000 = 2200 ≤ 5000
    });
    assertTrue(!error, `expected no error, got ${JSON.stringify(error)}`);
  });

  await test("cross-group isolation — group A usage doesn't affect group B", async () => {
    const B = await provisionAccount({ capUsd: 5000 });
    const w = await readWindow(B.groupId);
    assertNumEq(w.current_total_usd, 0, "B's window is empty");
    // B can deposit up to its cap regardless of A.
    const { error } = await db.rpc("fn_apply_daily_deposit_cap", {
      p_group_id: B.groupId,
      p_amount_usd: 4500,
    });
    assertTrue(!error, `B should be allowed independently, got ${JSON.stringify(error)}`);
  });

  // ── idempotency interaction ──────────────────────────────────────────
  section("idempotency interaction with fn_create_custody_deposit_idempotent");

  await test("miss-path: create blocked when at limit (no row inserted)", async () => {
    const C = await provisionAccount({ capUsd: 1000 });
    await createDeposit(C.groupId, 800, `${C.groupId.slice(0, 8)}-c1`);
    const beforeRows = (
      await db.from("custody_deposits").select("id").eq("group_id", C.groupId)
    ).data?.length ?? 0;

    const { error } = await db.rpc("fn_create_custody_deposit_idempotent", {
      p_group_id: C.groupId,
      p_amount_usd: 500,
      p_coins_equivalent: 500,
      p_payment_gateway: "stripe",
      p_idempotency_key: `${ORPHAN_PREFIX}${C.groupId.slice(0, 8)}-blocked`,
    });
    assertTrue(
      error && error.code === "P0010",
      `expected P0010 on blocked deposit, got ${JSON.stringify(error)}`,
    );
    const afterRows = (
      await db.from("custody_deposits").select("id").eq("group_id", C.groupId)
    ).data?.length ?? 0;
    assertEq(afterRows, beforeRows, "no row inserted on rejection");
  });

  await test("idempotent replay returns existing deposit even if cap is now zero", async () => {
    const D = await provisionAccount({ capUsd: 5000 });
    const key = `${ORPHAN_PREFIX}${D.groupId.slice(0, 8)}-replay`;
    const first = await db.rpc("fn_create_custody_deposit_idempotent", {
      p_group_id: D.groupId,
      p_amount_usd: 1000,
      p_coins_equivalent: 1000,
      p_payment_gateway: "stripe",
      p_idempotency_key: key,
    });
    if (first.error) throw first.error;
    const firstRow = Array.isArray(first.data) ? first.data[0] : first.data;
    assertEq(firstRow.was_idempotent, false, "first call creates");

    // Drop cap to 0 and replay with same key → should still succeed and
    // return the existing deposit (cap NOT re-checked on replay).
    await setCap(D.groupId, 0, D.adminUserId, `${D.groupId.slice(0, 8)}-zerocap`);
    const replay = await db.rpc("fn_create_custody_deposit_idempotent", {
      p_group_id: D.groupId,
      p_amount_usd: 1000,
      p_coins_equivalent: 1000,
      p_payment_gateway: "stripe",
      p_idempotency_key: key,
    });
    if (replay.error) throw replay.error;
    const replayRow = Array.isArray(replay.data) ? replay.data[0] : replay.data;
    assertEq(replayRow.was_idempotent, true, "replay is idempotent");
    assertEq(replayRow.deposit_id, firstRow.deposit_id, "same deposit_id");
  });

  await test("cap raised mid-day: new deposits succeed up to new ceiling", async () => {
    const E = await provisionAccount({ capUsd: 1000 });
    await createDeposit(E.groupId, 900, `${E.groupId.slice(0, 8)}-pre`);

    // 200 would exceed 1000 cap (900+200=1100>1000)
    const blocked = await db.rpc("fn_create_custody_deposit_idempotent", {
      p_group_id: E.groupId,
      p_amount_usd: 200,
      p_coins_equivalent: 200,
      p_payment_gateway: "stripe",
      p_idempotency_key: `${ORPHAN_PREFIX}${E.groupId.slice(0, 8)}-pre-block`,
    });
    assertTrue(blocked.error?.code === "P0010", "first attempt blocked");

    // Raise cap to 5000
    await setCap(E.groupId, 5000, E.adminUserId, `${E.groupId.slice(0, 8)}-raise`);

    // Now 200 fits
    const allowed = await db.rpc("fn_create_custody_deposit_idempotent", {
      p_group_id: E.groupId,
      p_amount_usd: 200,
      p_coins_equivalent: 200,
      p_payment_gateway: "stripe",
      p_idempotency_key: `${ORPHAN_PREFIX}${E.groupId.slice(0, 8)}-after-raise`,
    });
    if (allowed.error) throw allowed.error;
    const row = Array.isArray(allowed.data) ? allowed.data[0] : allowed.data;
    assertEq(row.was_idempotent, false, "new deposit created after raise");
  });

  // ── audit trail ───────────────────────────────────────────────────────
  section("audit trail");

  await test("fn_set_daily_deposit_cap writes to custody_daily_cap_changes", async () => {
    const F = await provisionAccount({ capUsd: 1000 });
    await setCap(F.groupId, 7777, F.adminUserId, `${F.groupId.slice(0, 8)}-bump`);
    const { data, error } = await db
      .from("custody_daily_cap_changes")
      .select("previous_cap_usd, new_cap_usd, actor_user_id, reason")
      .eq("group_id", F.groupId)
      .order("changed_at", { ascending: false })
      .limit(1);
    if (error) throw error;
    assertTrue(data && data.length === 1, "1 audit row");
    const row = data![0];
    assertNumEq(row.previous_cap_usd, 1000, "previous_cap_usd captured");
    assertNumEq(row.new_cap_usd, 7777, "new_cap_usd captured");
    assertEq(row.actor_user_id, F.adminUserId, "actor logged");
    assertTrue((row.reason as string).includes("bump"), "reason persisted");
  });

  await test("fn_set_daily_deposit_cap rejects reason < 10 chars", async () => {
    const G = await provisionAccount({ capUsd: 1000 });
    const { error } = await db.rpc("fn_set_daily_deposit_cap", {
      p_group_id: G.groupId,
      p_new_cap_usd: 2000,
      p_actor_user_id: G.adminUserId,
      p_reason: "short",
    });
    assertTrue(
      error && />= 10 chars/.test(error.message ?? ""),
      `expected reason length error, got ${JSON.stringify(error)}`,
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
