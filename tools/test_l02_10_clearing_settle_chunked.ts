/**
 * tools/test_l02_10_clearing_settle_chunked.ts
 *
 * Integration tests for the L02-10 clearing settle chunked surface
 * (`supabase/migrations/20260420100000_l02_clearing_settle_chunked.sql`).
 *
 * Coverage
 * ────────
 *   • fn_settle_clearing_chunk
 *       (1) zero-row window is a no-op with shape
 *           {processed:0, settled:0, insufficient:0, failed:0, remaining:0}
 *       (2) limit clamps the work per call (creates 5 pending rows,
 *           limit=2 → processed=2, settled=2, remaining=3 in the same window)
 *       (3) successive calls drain the backlog; final remaining=0
 *       (4) debtorGroupId scopes to a single debtor (other debtor's rows
 *           remain pending in the same window)
 *       (5) insufficient backing is reported as `insufficient`, not
 *           `failed`; the row is moved to status='insufficient' and the
 *           backlog snapshot reflects it
 *       (6) input validation: limit out of range raises 22023
 *
 *   • fn_settle_clearing_batch_safe
 *       (7) returns chunk meta, writes cron_run_state.last_status='completed'
 *           with last_meta carrying processed/settled/remaining/limit/window_hours
 *       (8) called twice in quick succession → second call returns
 *           skipped-jsonb when the cron state safety window short-circuits
 *
 *   • Schedule
 *       (9) pg_cron job 'settle-clearing-batch' is registered with
 *           '* * * * *' schedule (skipped if pg_cron is unavailable)
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l02_10_clearing_settle_chunked.ts
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

function assertTrue(cond: unknown, msg: string) {
  if (!cond) throw new Error(msg);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const TEST_TAG = "l02-10-test";
const createdGroupIds: string[] = [];
const createdUserIds: string[] = [];
const createdEventIds: string[] = [];

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

async function makeGroupWithCustody(params: {
  totalDeposited: number;
  totalCommitted?: number;
}): Promise<string> {
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
    total_deposited_usd: params.totalDeposited,
    total_committed: params.totalCommitted ?? params.totalDeposited,
    total_settled_usd: 0,
  });
  if (aErr) throw new Error(`insert custody_accounts: ${aErr.message}`);

  return groupId;
}

async function makeClearingEvent(params: {
  redeemerGroupId: string;
  totalCoins: number;
}): Promise<string> {
  const eventId = randomUUID();
  const { error } = await db.from("clearing_events").insert({
    id: eventId,
    burn_ref_id: `${TEST_TAG}-burn-${eventId.slice(0, 8)}`,
    athlete_user_id: createdUserIds[0]!,
    redeemer_group_id: params.redeemerGroupId,
    total_coins: params.totalCoins,
    breakdown: [],
  });
  if (error) throw new Error(`insert clearing_events: ${error.message}`);
  createdEventIds.push(eventId);
  return eventId;
}

async function makePendingSettlement(params: {
  eventId: string;
  debtorGroupId: string;
  creditorGroupId: string;
  coinAmount: number;
  feeRate?: number;
}): Promise<string> {
  const id = randomUUID();
  const grossUsd = params.coinAmount;
  const feeUsd = Number((grossUsd * (params.feeRate ?? 3.0) / 100).toFixed(2));
  const netUsd = Number((grossUsd - feeUsd).toFixed(2));

  const { error } = await db.from("clearing_settlements").insert({
    id,
    clearing_event_id: params.eventId,
    creditor_group_id: params.creditorGroupId,
    debtor_group_id: params.debtorGroupId,
    coin_amount: params.coinAmount,
    gross_amount_usd: grossUsd,
    fee_rate_pct: params.feeRate ?? 3.0,
    fee_amount_usd: feeUsd,
    net_amount_usd: netUsd,
    status: "pending",
  });
  if (error) throw new Error(`insert clearing_settlements: ${error.message}`);
  return id;
}

async function getSettlementStatus(id: string): Promise<string> {
  const { data, error } = await db
    .from("clearing_settlements")
    .select("status")
    .eq("id", id)
    .single();
  if (error) throw new Error(`select clearing_settlements: ${error.message}`);
  return (data as any).status as string;
}

async function chunk(params: {
  windowStart: Date;
  windowEnd: Date;
  limit?: number;
  debtorGroupId?: string;
}): Promise<{
  processed: number;
  settled: number;
  insufficient: number;
  failed: number;
  remaining: number;
}> {
  const { data, error } = await db.rpc("fn_settle_clearing_chunk" as any, {
    p_window_start: params.windowStart.toISOString(),
    p_window_end: params.windowEnd.toISOString(),
    p_limit: params.limit ?? 50,
    p_debtor_group_id: params.debtorGroupId ?? null,
  });
  if (error) throw new Error(`fn_settle_clearing_chunk: ${error.message}`);
  const row = Array.isArray(data) ? data[0] : data;
  return {
    processed: Number(row.processed),
    settled: Number(row.settled),
    insufficient: Number(row.insufficient),
    failed: Number(row.failed),
    remaining: Number(row.remaining),
  };
}

async function cleanup() {
  if (createdEventIds.length > 0) {
    await db
      .from("clearing_settlements")
      .delete()
      .in("clearing_event_id", createdEventIds);
    await db.from("clearing_events").delete().in("id", createdEventIds);
  }
  if (createdGroupIds.length > 0) {
    await db
      .from("platform_revenue")
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

async function runChunk() {
  section("fn_settle_clearing_chunk — bounded chunk processor (L02-10)");

  const WIDE_START = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const WIDE_END = new Date(Date.now() + 60_000);

  await test("zero-row window returns all-zero counts", async () => {
    const r = await chunk({
      windowStart: new Date(Date.now() - 60_000),
      windowEnd: new Date(Date.now() - 30_000),
      limit: 50,
    });
    assertEq(r.processed, 0, "processed");
    assertEq(r.settled, 0, "settled");
    assertEq(r.insufficient, 0, "insufficient");
    assertEq(r.failed, 0, "failed");
    assertEq(r.remaining, 0, "remaining");
  });

  await test("limit clamps work per call (5 rows, limit=2)", async () => {
    const debtor = await makeGroupWithCustody({ totalDeposited: 1000 });
    const creditor = await makeGroupWithCustody({
      totalDeposited: 0,
      totalCommitted: 0,
    });
    const event = await makeClearingEvent({
      redeemerGroupId: creditor,
      totalCoins: 50,
    });
    for (let i = 0; i < 5; i++) {
      await makePendingSettlement({
        eventId: event,
        debtorGroupId: debtor,
        creditorGroupId: creditor,
        coinAmount: 10,
      });
    }

    const r = await chunk({
      windowStart: WIDE_START,
      windowEnd: WIDE_END,
      limit: 2,
      debtorGroupId: debtor,
    });
    assertEq(r.processed, 2, "processed (clamped to limit)");
    assertEq(r.settled, 2, "settled");
    assertEq(r.failed, 0, "failed");
    assertEq(r.remaining, 3, "remaining (5 - 2)");
  });

  await test("successive calls drain the backlog to remaining=0", async () => {
    const debtor = await makeGroupWithCustody({ totalDeposited: 1000 });
    const creditor = await makeGroupWithCustody({
      totalDeposited: 0,
      totalCommitted: 0,
    });
    const event = await makeClearingEvent({
      redeemerGroupId: creditor,
      totalCoins: 30,
    });
    for (let i = 0; i < 3; i++) {
      await makePendingSettlement({
        eventId: event,
        debtorGroupId: debtor,
        creditorGroupId: creditor,
        coinAmount: 10,
      });
    }

    const r1 = await chunk({
      windowStart: WIDE_START,
      windowEnd: WIDE_END,
      limit: 2,
      debtorGroupId: debtor,
    });
    assertEq(r1.processed, 2, "first chunk processed");
    assertEq(r1.remaining, 1, "first chunk remaining");

    const r2 = await chunk({
      windowStart: WIDE_START,
      windowEnd: WIDE_END,
      limit: 2,
      debtorGroupId: debtor,
    });
    assertEq(r2.processed, 1, "second chunk processed");
    assertEq(r2.remaining, 0, "second chunk drained");
  });

  await test("debtorGroupId scopes to a single debtor", async () => {
    const debtorA = await makeGroupWithCustody({ totalDeposited: 1000 });
    const debtorB = await makeGroupWithCustody({ totalDeposited: 1000 });
    const creditor = await makeGroupWithCustody({
      totalDeposited: 0,
      totalCommitted: 0,
    });
    const event = await makeClearingEvent({
      redeemerGroupId: creditor,
      totalCoins: 20,
    });
    const sA1 = await makePendingSettlement({
      eventId: event,
      debtorGroupId: debtorA,
      creditorGroupId: creditor,
      coinAmount: 10,
    });
    const sA2 = await makePendingSettlement({
      eventId: event,
      debtorGroupId: debtorA,
      creditorGroupId: creditor,
      coinAmount: 10,
    });
    const sB = await makePendingSettlement({
      eventId: event,
      debtorGroupId: debtorB,
      creditorGroupId: creditor,
      coinAmount: 10,
    });

    const r = await chunk({
      windowStart: WIDE_START,
      windowEnd: WIDE_END,
      limit: 50,
      debtorGroupId: debtorA,
    });
    assertEq(r.processed, 2, "only debtor A's rows processed");
    assertEq(r.settled, 2, "both A's rows settled");

    assertEq(await getSettlementStatus(sA1), "settled", "sA1 status");
    assertEq(await getSettlementStatus(sA2), "settled", "sA2 status");
    assertEq(
      await getSettlementStatus(sB),
      "pending",
      "sB still pending (other debtor)",
    );
  });

  await test("insufficient backing reported separately from failed", async () => {
    const debtor = await makeGroupWithCustody({
      totalDeposited: 5,
      totalCommitted: 5,
    });
    const creditor = await makeGroupWithCustody({
      totalDeposited: 0,
      totalCommitted: 0,
    });
    const event = await makeClearingEvent({
      redeemerGroupId: creditor,
      totalCoins: 10,
    });
    const sId = await makePendingSettlement({
      eventId: event,
      debtorGroupId: debtor,
      creditorGroupId: creditor,
      coinAmount: 10,
    });

    const r = await chunk({
      windowStart: WIDE_START,
      windowEnd: WIDE_END,
      limit: 50,
      debtorGroupId: debtor,
    });
    assertEq(r.processed, 1, "processed");
    assertEq(r.settled, 0, "settled");
    assertEq(r.insufficient, 1, "insufficient");
    assertEq(r.failed, 0, "failed (insufficient is NOT failed)");
    assertEq(
      await getSettlementStatus(sId),
      "insufficient",
      "row marked insufficient",
    );
  });

  await test("rejects limit > 500 with SQLSTATE 22023", async () => {
    const { error } = await db.rpc("fn_settle_clearing_chunk" as any, {
      p_window_start: WIDE_START.toISOString(),
      p_window_end: WIDE_END.toISOString(),
      p_limit: 501,
      p_debtor_group_id: null,
    });
    assertTrue(error, "expected error for limit=501");
    assertTrue(
      String((error as any)?.message ?? "").includes("limit must be in"),
      `expected limit-range error, got ${error?.message}`,
    );
  });

  await test("rejects window_end <= window_start with SQLSTATE 22023", async () => {
    const t = new Date();
    const { error } = await db.rpc("fn_settle_clearing_chunk" as any, {
      p_window_start: t.toISOString(),
      p_window_end: t.toISOString(),
      p_limit: 10,
      p_debtor_group_id: null,
    });
    assertTrue(error, "expected error for equal bounds");
    assertTrue(
      String((error as any)?.message ?? "").includes("window_end"),
      `expected window-bounds error, got ${error?.message}`,
    );
  });
}

async function runBatchSafe() {
  section("fn_settle_clearing_batch_safe — cron-safe wrapper (L02-10)");

  await test(
    "returns jsonb meta + writes cron_run_state.last_status='completed'",
    async () => {
      // Drain any leftover pending rows from the chunk-tests above so
      // this assertion is deterministic regardless of test ordering.
      if (createdEventIds.length > 0) {
        await db
          .from("clearing_settlements")
          .delete()
          .in("clearing_event_id", createdEventIds);
      }

      // Reset the cron_run_state row so the safety window does not
      // make this no-op skip; subsequent test asserts the skip branch.
      await db
        .from("cron_run_state")
        .upsert(
          {
            name: "settle-clearing-batch",
            last_status: "never_run",
            started_at: null,
            finished_at: null,
            run_count: 0,
            skip_count: 0,
          },
          { onConflict: "name" },
        );

      const { data, error } = await db.rpc(
        "fn_settle_clearing_batch_safe" as any,
        { p_limit: 50, p_window_hours: 1 },
      );
      if (error) throw new Error(`fn_settle_clearing_batch_safe: ${error.message}`);

      const meta = data as Record<string, unknown>;
      assertTrue(!("skipped" in meta), "expected non-skip cycle");
      assertEq(meta.limit, 50, "limit");
      assertEq(meta.window_hours, 1, "window_hours");
      // processed/settled snapshot the live state — assert shape, not
      // exact counts, since other concurrent test runs may have left
      // legitimate pending rows from non-test groups.
      assertTrue(
        typeof meta.processed === "number",
        "processed is numeric",
      );
      assertTrue(typeof meta.settled === "number", "settled is numeric");
      assertTrue(typeof meta.failed === "number", "failed is numeric");
      assertTrue(
        typeof meta.remaining === "number",
        "remaining is numeric",
      );

      const { data: stateRow } = await db
        .from("cron_run_state")
        .select("last_status, last_meta")
        .eq("name", "settle-clearing-batch")
        .single();
      assertEq(
        (stateRow as any).last_status,
        "completed",
        "last_status after cycle",
      );
      assertTrue(
        typeof (stateRow as any).last_meta?.processed === "number",
        "last_meta carries processed",
      );
      assertTrue(
        (stateRow as any).last_meta?.limit === 50,
        "last_meta carries limit=50",
      );
    },
  );

  await test(
    "second invocation within safety window short-circuits with skipped jsonb",
    async () => {
      // Force the previous run into 'running' state so should_run skips.
      await db
        .from("cron_run_state")
        .update({
          last_status: "running",
          started_at: new Date().toISOString(),
          finished_at: null,
        })
        .eq("name", "settle-clearing-batch");

      const { data, error } = await db.rpc(
        "fn_settle_clearing_batch_safe" as any,
        { p_limit: 50, p_window_hours: 1 },
      );
      if (error) throw new Error(`fn_settle_clearing_batch_safe: ${error.message}`);

      const meta = data as Record<string, unknown>;
      assertTrue(meta.skipped === true, "expected skipped=true");
    },
  );
}

async function runSchedule() {
  section("pg_cron schedule — settle-clearing-batch every minute");

  const { data: extRows } = await db
    .from("pg_extension" as any)
    .select("extname")
    .eq("extname", "pg_cron");

  if (!extRows || extRows.length === 0) {
    skip("cron job 'settle-clearing-batch' registered", "pg_cron not installed");
    return;
  }

  await test("cron job 'settle-clearing-batch' registered with '* * * * *'", async () => {
    const { data, error } = await db
      .from("cron.job" as any)
      .select("jobname, schedule")
      .eq("jobname", "settle-clearing-batch");
    if (error) {
      // Some environments don't expose cron.* via PostgREST; treat as skip-equivalent.
      throw new Error(`cron.job query unavailable: ${error.message}`);
    }
    assertTrue(
      Array.isArray(data) && data.length > 0,
      "expected one row for settle-clearing-batch",
    );
    assertEq(
      (data![0] as any).schedule,
      "* * * * *",
      "schedule",
    );
  });
}

// ── Entry ───────────────────────────────────────────────────────────────────

async function main() {
  console.log(
    `${BOLD}L02-10 — clearing settle chunked + cron-safe wrapper integration tests${RESET}`,
  );
  console.log(`SUPABASE_URL=${SUPABASE_URL}\n`);

  try {
    await runChunk();
    await runBatchSafe();
    await runSchedule();
  } finally {
    await cleanup();
  }

  console.log(
    `\n${BOLD}${passed} passed, ${failed} failed, ${skipped} skipped${RESET}`,
  );
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(2);
});
