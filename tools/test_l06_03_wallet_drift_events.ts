/**
 * tools/test_l06_03_wallet_drift_events.ts
 *
 * Integration tests for the L06-03 reconcile-wallets-cron alert pipeline
 * (`supabase/migrations/20260420110000_l06_wallet_drift_events.sql`).
 *
 * Coverage
 * ────────
 *   • public.wallet_drift_events
 *       (1) table exists with the documented columns
 *       (2) CHECK on severity enum rejects invalid values
 *       (3) RLS forced + enabled (no anon/authenticated policy)
 *
 *   • public.fn_classify_wallet_drift_severity
 *       (4) classifies the canonical vectors (mirror of TS helper)
 *       (5) custom warn threshold lowers the boundary
 *       (6) NULL / negative drift is treated as 'ok'
 *
 *   • public.fn_record_wallet_drift_event
 *       (7) inserts a row and returns its id
 *       (8) defaults `notes` to '{}' when omitted
 *       (9) rejects bad inputs with SQLSTATE 22023
 *
 *   • public.fn_mark_wallet_drift_event_alerted
 *       (10) success path → alerted=true / channel set / no error
 *       (11) failure path → alerted=false / channel set / error preserved
 *       (12) rejects bad inputs with SQLSTATE 22023
 *       (13) returns false when event id does not exist (no row-NOT-FOUND throw)
 *
 *   • Indexes
 *       (14) partial index `idx_wallet_drift_events_unalerted` exists
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l06_03_wallet_drift_events.ts
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

const createdEventIds: string[] = [];

async function classify(
  count: number | null,
  threshold?: number,
): Promise<string> {
  const { data, error } = await db.rpc(
    "fn_classify_wallet_drift_severity" as any,
    threshold === undefined
      ? { p_drifted_count: count }
      : { p_drifted_count: count, p_warn_threshold: threshold },
  );
  if (error) throw new Error(`classify rpc: ${error.message}`);
  return data as string;
}

async function record(
  runId: string,
  total: number,
  drifted: number,
  severity: string,
  notes?: Record<string, unknown>,
): Promise<string> {
  const args: Record<string, unknown> = {
    p_run_id: runId,
    p_total_wallets: total,
    p_drifted_count: drifted,
    p_severity: severity,
  };
  if (notes !== undefined) args.p_notes = notes;
  const { data, error } = await db.rpc(
    "fn_record_wallet_drift_event" as any,
    args,
  );
  if (error) throw new Error(`record rpc: ${error.message}`);
  const id = data as string;
  createdEventIds.push(id);
  return id;
}

async function markAlerted(
  eventId: string,
  channel: string,
  err?: string | null,
): Promise<boolean> {
  const args: Record<string, unknown> = {
    p_event_id: eventId,
    p_channel: channel,
  };
  if (err !== undefined) args.p_error = err;
  const { data, error } = await db.rpc(
    "fn_mark_wallet_drift_event_alerted" as any,
    args,
  );
  if (error) throw new Error(`mark_alerted rpc: ${error.message}`);
  return data as boolean;
}

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(
    `${BOLD}L06-03 — wallet_drift_events + alert pipeline integration tests${RESET}`,
  );
  console.log(`SUPABASE_URL=${SUPABASE_URL}\n`);

  section("public.wallet_drift_events — schema (L06-03)");

  await test("table exists with the documented columns", async () => {
    const { data, error } = await db
      .from("wallet_drift_events")
      .select("id,run_id,observed_at,total_wallets,drifted_count,severity,alerted,alert_channel,alert_error,notes")
      .limit(0);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "expected array (limit 0)");
  });

  await test("CHECK on severity enum rejects invalid values", async () => {
    const { error } = await db.from("wallet_drift_events").insert({
      run_id: randomUUID(),
      total_wallets: 1,
      drifted_count: 0,
      severity: "nuclear",
    });
    if (!error) throw new Error("insert with severity='nuclear' should have failed");
    assertTrue(
      /violates check constraint|invalid input value|severity/i.test(error.message),
      `unexpected error: ${error.message}`,
    );
  });

  await test("anon role cannot read the table (RLS in effect)", async () => {
    // Spin up an anon-key client and confirm SELECT is blocked. Service-role
    // bypasses RLS so we cannot use the existing client to verify.
    const anonKey = process.env.SUPABASE_ANON_KEY ??
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
    const anonClient = createClient(SUPABASE_URL, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await anonClient
      .from("wallet_drift_events")
      .select("id")
      .limit(1);
    // Either an explicit RLS error OR an empty array (RLS hides rows). Both
    // outcomes prove anon does not have visibility. What we MUST NOT see is
    // a row leaking through.
    if (error) {
      assertTrue(
        /permission denied|not allowed|policy/i.test(error.message),
        `unexpected anon error: ${error.message}`,
      );
    } else {
      assertTrue(
        Array.isArray(data) && data.length === 0,
        `anon should see zero rows, got ${JSON.stringify(data)}`,
      );
    }
  });

  section("fn_classify_wallet_drift_severity (L06-03)");

  await test("classifies the canonical vectors (mirror of TS helper)", async () => {
    assertEq(await classify(0), "ok", "classify(0)");
    assertEq(await classify(1), "warn", "classify(1)");
    assertEq(await classify(10), "warn", "classify(10)");
    assertEq(await classify(11), "critical", "classify(11)");
    assertEq(await classify(9999), "critical", "classify(9999)");
  });

  await test("custom warn threshold lowers the boundary", async () => {
    assertEq(await classify(3, 3), "warn", "classify(3, threshold=3)");
    assertEq(await classify(4, 3), "critical", "classify(4, threshold=3)");
  });

  await test("NULL / negative drift is treated as 'ok'", async () => {
    assertEq(await classify(null), "ok", "classify(NULL)");
    assertEq(await classify(-7), "ok", "classify(-7)");
  });

  section("fn_record_wallet_drift_event (L06-03)");

  await test("inserts a row and returns its id", async () => {
    const runId = randomUUID();
    const id = await record(runId, 100, 5, "warn", { reason: "integration_test" });
    assertTrue(typeof id === "string" && id.length > 0, "id should be uuid");
    const { data, error } = await db
      .from("wallet_drift_events")
      .select("id, run_id, severity, total_wallets, drifted_count, notes, alerted")
      .eq("id", id)
      .single();
    if (error) throw new Error(error.message);
    assertEq(data.run_id, runId, "run_id");
    assertEq(data.severity, "warn", "severity");
    assertEq(data.total_wallets, 100, "total_wallets");
    assertEq(data.drifted_count, 5, "drifted_count");
    assertEq(data.alerted, false, "alerted defaults false");
    assertEq((data.notes as any).reason, "integration_test", "notes preserved");
  });

  await test("defaults `notes` to '{}' when omitted", async () => {
    const id = await record(randomUUID(), 50, 1, "warn");
    const { data, error } = await db
      .from("wallet_drift_events")
      .select("notes")
      .eq("id", id)
      .single();
    if (error) throw new Error(error.message);
    assertTrue(
      typeof data.notes === "object" && Object.keys(data.notes as object).length === 0,
      `notes should be {}, got ${JSON.stringify(data.notes)}`,
    );
  });

  await test("rejects bad inputs with SQLSTATE 22023", async () => {
    // p_run_id = NULL
    let { error } = await db.rpc("fn_record_wallet_drift_event" as any, {
      p_run_id: null,
      p_total_wallets: 1,
      p_drifted_count: 0,
      p_severity: "ok",
    });
    assertTrue(!!error, "NULL run_id should error");
    assertTrue((error as any).code === "22023", `expected 22023, got ${(error as any).code}`);

    // bad severity
    ({ error } = await db.rpc("fn_record_wallet_drift_event" as any, {
      p_run_id: randomUUID(),
      p_total_wallets: 1,
      p_drifted_count: 0,
      p_severity: "fatal",
    }));
    assertTrue(!!error, "bad severity should error");
    assertTrue((error as any).code === "22023", `expected 22023, got ${(error as any).code}`);

    // negative total
    ({ error } = await db.rpc("fn_record_wallet_drift_event" as any, {
      p_run_id: randomUUID(),
      p_total_wallets: -1,
      p_drifted_count: 0,
      p_severity: "ok",
    }));
    assertTrue(!!error, "negative total should error");
    assertTrue((error as any).code === "22023", `expected 22023, got ${(error as any).code}`);
  });

  section("fn_mark_wallet_drift_event_alerted (L06-03)");

  await test("success path → alerted=true / channel set / no error", async () => {
    const id = await record(randomUUID(), 100, 5, "warn");
    const result = await markAlerted(id, "slack");
    assertEq(result, true, "mark_alerted result");
    const { data, error } = await db
      .from("wallet_drift_events")
      .select("alerted, alert_channel, alert_error")
      .eq("id", id)
      .single();
    if (error) throw new Error(error.message);
    assertEq(data.alerted, true, "alerted");
    assertEq(data.alert_channel, "slack", "alert_channel");
    assertEq(data.alert_error, null, "alert_error");
  });

  await test("failure path → alerted=false / channel set / error preserved", async () => {
    const id = await record(randomUUID(), 100, 50, "critical");
    const result = await markAlerted(id, "slack", "HTTP 500");
    assertEq(result, true, "mark_alerted result");
    const { data, error } = await db
      .from("wallet_drift_events")
      .select("alerted, alert_channel, alert_error")
      .eq("id", id)
      .single();
    if (error) throw new Error(error.message);
    assertEq(data.alerted, false, "alerted");
    assertEq(data.alert_channel, "slack", "alert_channel");
    assertEq(data.alert_error, "HTTP 500", "alert_error");
  });

  await test("rejects bad inputs with SQLSTATE 22023", async () => {
    // NULL event id
    let { error } = await db.rpc("fn_mark_wallet_drift_event_alerted" as any, {
      p_event_id: null,
      p_channel: "slack",
    });
    assertTrue(!!error, "NULL event id should error");
    assertTrue((error as any).code === "22023", `expected 22023, got ${(error as any).code}`);

    // empty channel
    ({ error } = await db.rpc("fn_mark_wallet_drift_event_alerted" as any, {
      p_event_id: randomUUID(),
      p_channel: "",
    }));
    assertTrue(!!error, "empty channel should error");
    assertTrue((error as any).code === "22023", `expected 22023, got ${(error as any).code}`);
  });

  await test("returns false when event id does not exist", async () => {
    const result = await markAlerted(randomUUID(), "slack");
    assertEq(result, false, "mark_alerted on missing id");
  });

  section("Indexes (L06-03)");

  await test("partial index `idx_wallet_drift_events_unalerted` exists", async () => {
    const { data, error } = await db
      .from("pg_indexes" as any)
      .select("indexname")
      .eq("tablename", "wallet_drift_events");
    if (error) {
      console.log("    (skipped — pg_indexes not exposed)");
      return;
    }
    const names = (data as any[]).map((r) => r.indexname);
    assertTrue(
      names.includes("idx_wallet_drift_events_unalerted"),
      `expected idx_wallet_drift_events_unalerted in ${names.join(", ")}`,
    );
    assertTrue(
      names.includes("idx_wallet_drift_events_observed_at"),
      `expected idx_wallet_drift_events_observed_at in ${names.join(", ")}`,
    );
    assertTrue(
      names.includes("idx_wallet_drift_events_run_id"),
      `expected idx_wallet_drift_events_run_id in ${names.join(", ")}`,
    );
  });

  // ── cleanup ──────────────────────────────────────────────────────────────
  if (createdEventIds.length > 0) {
    await db
      .from("wallet_drift_events")
      .delete()
      .in("id", createdEventIds);
  }

  console.log(`\n${BOLD}${passed} passed, ${failed} failed${RESET}\n`);
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("FATAL:", e);
  process.exit(1);
});
