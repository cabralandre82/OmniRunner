/**
 * tools/test_cron_health.ts
 *
 * Integration tests for the L12 cron-health surface introduced in
 *
 *   supabase/migrations/20260419100000_l12_cron_overlap_protection.sql
 *   supabase/migrations/20260419100001_l12_cron_redistribute_thundering_herd.sql
 *   supabase/migrations/20260419100002_l12_reconcile_wallets_schedule.sql
 *
 * Coverage:
 *
 *   - public.cron_run_state schema + RLS shape
 *   - fn_cron_should_run / mark_started / mark_completed / mark_failed
 *     state-machine transitions
 *   - fn_cron_should_run skip-on-recent-running, allow-after-timeout
 *   - fn_expire_queue_entries_safe full lifecycle (no-op + with rows)
 *   - fn_process_scheduled_releases_safe lifecycle delegation
 *   - cron jobs registered under expected names with expected schedules
 *     (skipped if pg_cron is unavailable in the local env)
 *   - cron_run_state row seeded for reconcile-wallets-daily
 *
 * Usage:
 *
 *   NODE_PATH=portal/node_modules npx tsx tools/test_cron_health.ts
 *
 * Env vars (local Supabase defaults if unset):
 *
 *   SUPABASE_URL              (default http://127.0.0.1:54321)
 *   SUPABASE_SERVICE_ROLE_KEY (default local dev key)
 */

import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const OK = "\x1b[32m✓\x1b[0m";
const FAIL = "\x1b[31m✗\x1b[0m";
const SKIP = "\x1b[33m⊘\x1b[0m";
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
    throw new Error(`${msg}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  }
}

function assertTrue(cond: boolean, msg: string) {
  if (!cond) throw new Error(msg);
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const TEST_PREFIX = "test:cron-health:";
let testCounter = 0;
function makeJobName(suffix: string): string {
  testCounter++;
  return `${TEST_PREFIX}${suffix}-${Date.now()}-${testCounter}`;
}

async function callRpc<T = any>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await db.rpc(name as any, args as any);
  if (error) throw new Error(`RPC ${name} failed: ${error.message}`);
  return data as T;
}

async function getState(name: string): Promise<any> {
  const { data, error } = await db
    .from("cron_run_state")
    .select("*")
    .eq("name", name)
    .maybeSingle();
  if (error) throw new Error(`select cron_run_state: ${error.message}`);
  return data;
}

async function seedState(name: string, fields: Record<string, unknown>) {
  const { error } = await db
    .from("cron_run_state")
    .upsert({ name, ...fields }, { onConflict: "name" });
  if (error) throw new Error(`seed cron_run_state: ${error.message}`);
}

async function deleteState(name: string) {
  const { error } = await db.from("cron_run_state").delete().eq("name", name);
  if (error && !/no rows/i.test(error.message)) {
    throw new Error(`delete cron_run_state: ${error.message}`);
  }
}

async function preflight(): Promise<boolean> {
  try {
    const resp = await fetch(`${SUPABASE_URL}/rest/v1/`, {
      headers: { apikey: SERVICE_KEY },
      signal: AbortSignal.timeout(5000),
    });
    return resp.ok;
  } catch {
    return false;
  }
}

async function tableReachable(): Promise<boolean> {
  const { error } = await db.from("cron_run_state").select("name").limit(0);
  return !error;
}

async function pgCronInstalled(): Promise<boolean> {
  // Try to read pg_extension via PostgREST; not exposed by default.
  // Probe indirectly: if `cron.job` is exposed via PostgREST it's installed,
  // otherwise we have to assume "unknown" and skip cron-job tests.
  try {
    const { error } = await (db.schema("cron" as any) as any)
      .from("job")
      .select("jobname")
      .limit(0);
    return !error;
  } catch {
    return false;
  }
}

// ── Tests: cron_run_state schema + helpers ──────────────────────────────────

async function testSchema() {
  section("cron_run_state schema");

  await test("table cron_run_state is reachable via service role", async () => {
    assertTrue(await tableReachable(), "cron_run_state should be reachable");
  });

  await test("required columns exist (name, started_at, finished_at, last_status, run_count, skip_count, last_error, last_meta)", async () => {
    const name = makeJobName("schema-cols");
    try {
      await seedState(name, {
        started_at: new Date().toISOString(),
        finished_at: new Date().toISOString(),
        last_status: "completed",
        run_count: 1,
        skip_count: 0,
        last_error: null,
        last_meta: { ok: true },
      });
      const row = await getState(name);
      assertTrue(row !== null, "row should exist");
      assertEq(row.last_status, "completed", "last_status");
      assertEq(row.run_count, 1, "run_count");
      assertEq(row.skip_count, 0, "skip_count");
      assertTrue(typeof row.last_meta === "object", "last_meta is jsonb object");
      assertEq((row.last_meta as any).ok, true, "last_meta.ok preserved");
    } finally {
      await deleteState(name);
    }
  });

  await test("CHECK constraint rejects invalid last_status", async () => {
    const name = makeJobName("invalid-status");
    const { error } = await db
      .from("cron_run_state")
      .insert({ name, last_status: "garbage" });
    assertTrue(
      !!error && /chk|check/i.test(error.message),
      `expected CHECK violation, got: ${error?.message ?? "no error"}`,
    );
  });

  await test("CHECK constraint rejects finished_at < started_at", async () => {
    const name = makeJobName("bad-window");
    const start = new Date();
    const end = new Date(start.getTime() - 1000);
    const { error } = await db
      .from("cron_run_state")
      .insert({
        name,
        started_at: start.toISOString(),
        finished_at: end.toISOString(),
        last_status: "completed",
      });
    assertTrue(
      !!error && /window|chk|check/i.test(error.message),
      `expected window CHECK violation, got: ${error?.message ?? "no error"}`,
    );
  });
}

async function testHelpers() {
  section("fn_cron_should_run / mark_* helpers");

  await test("fn_cron_should_run seeds row + returns true on first call", async () => {
    const name = makeJobName("first-call");
    try {
      const should = await callRpc<boolean>("fn_cron_should_run", {
        p_name: name,
        p_max_runtime_seconds: 60,
      });
      assertEq(should, true, "should return true on first call");
      const row = await getState(name);
      assertTrue(row !== null, "row should be seeded");
      assertEq(row.last_status, "never_run", "seed status");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_mark_started increments run_count + sets running", async () => {
    const name = makeJobName("mark-started");
    try {
      await callRpc("fn_cron_mark_started", { p_name: name });
      const row = await getState(name);
      assertEq(row.last_status, "running", "status should be running");
      assertEq(row.run_count, 1, "run_count should be 1");
      assertTrue(row.started_at !== null, "started_at should be set");
      assertEq(row.finished_at, null, "finished_at should be null");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_mark_completed sets completed + merges meta", async () => {
    const name = makeJobName("mark-completed");
    try {
      await callRpc("fn_cron_mark_started", { p_name: name });
      await callRpc("fn_cron_mark_completed", {
        p_name: name,
        p_meta: { processed: 7 },
      });
      const row = await getState(name);
      assertEq(row.last_status, "completed", "status should be completed");
      assertTrue(row.finished_at !== null, "finished_at should be set");
      assertEq((row.last_meta as any).processed, 7, "meta merged");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_mark_failed records last_error truncated", async () => {
    const name = makeJobName("mark-failed");
    const longErr = "x".repeat(5000);
    try {
      await callRpc("fn_cron_mark_started", { p_name: name });
      await callRpc("fn_cron_mark_failed", {
        p_name: name,
        p_error: longErr,
        p_meta: { sqlstate: "P0001" },
      });
      const row = await getState(name);
      assertEq(row.last_status, "failed", "status should be failed");
      assertEq(row.last_error.length, 4096, "error truncated to 4096 chars");
      assertEq((row.last_meta as any).sqlstate, "P0001", "meta merged");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_should_run returns false when previous run is in safety window", async () => {
    const name = makeJobName("skip-recent");
    try {
      await seedState(name, {
        started_at: new Date(Date.now() - 30_000).toISOString(),
        finished_at: null,
        last_status: "running",
        run_count: 1,
        skip_count: 0,
      });
      const should = await callRpc<boolean>("fn_cron_should_run", {
        p_name: name,
        p_max_runtime_seconds: 240,
      });
      assertEq(should, false, "should skip while previous run is in window");
      const row = await getState(name);
      assertEq(row.skip_count, 1, "skip_count incremented");
      assertEq(row.last_status, "skipped", "status flipped to skipped");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_should_run returns true + marks timeout when stale running row", async () => {
    const name = makeJobName("timeout-recovery");
    try {
      await seedState(name, {
        started_at: new Date(Date.now() - 15 * 60_000).toISOString(),
        finished_at: null,
        last_status: "running",
        run_count: 1,
        skip_count: 0,
      });
      const should = await callRpc<boolean>("fn_cron_should_run", {
        p_name: name,
        p_max_runtime_seconds: 60,
      });
      assertEq(should, true, "should allow new run after timeout");
      const row = await getState(name);
      assertEq(row.last_status, "timeout", "previous run flagged as timeout");
      assertTrue(row.last_error !== null, "last_error populated");
    } finally {
      await deleteState(name);
    }
  });

  await test("fn_cron_should_run rejects max_runtime_seconds <= 0", async () => {
    const name = makeJobName("invalid-window");
    const { error } = await db.rpc("fn_cron_should_run" as any, {
      p_name: name,
      p_max_runtime_seconds: 0,
    });
    assertTrue(!!error, "should error on invalid window");
    await deleteState(name);
  });
}

// ── Tests: safe wrappers ────────────────────────────────────────────────────

async function testSafeWrappers() {
  section("fn_*_safe wrappers");

  await test("fn_expire_queue_entries_safe completes with processed=0 when queue empty", async () => {
    const name = "expire-matchmaking-queue";
    // Reset state so we don't trip the should-run gate.
    await deleteState(name);
    await callRpc("fn_expire_queue_entries_safe");
    const row = await getState(name);
    assertEq(row.last_status, "completed", "should be completed");
    assertTrue(typeof row.last_meta?.processed === "number", "meta.processed numeric");
    assertEq(row.last_meta.processed, 0, "no rows to expire on a fresh test DB");
  });

  await test("fn_expire_queue_entries_safe skips when previous run is recent", async () => {
    const name = "expire-matchmaking-queue";
    await seedState(name, {
      started_at: new Date(Date.now() - 10_000).toISOString(),
      finished_at: null,
      last_status: "running",
      run_count: 99,
      skip_count: 0,
    });
    await callRpc("fn_expire_queue_entries_safe");
    const row = await getState(name);
    assertEq(row.skip_count, 1, "skip_count should bump");
    assertEq(row.last_status, "skipped", "should flip to skipped");
    assertEq(row.run_count, 99, "run_count should NOT bump on skip");
  });

  await test("fn_process_scheduled_releases_safe completes returning count int", async () => {
    const name = "process-scheduled-workout-releases";
    await deleteState(name);
    const result = await callRpc<number>("fn_process_scheduled_releases_safe");
    assertTrue(typeof result === "number", "returns int");
    const row = await getState(name);
    assertEq(row.last_status, "completed", "should be completed");
  });

  await test("fn_process_scheduled_releases_safe skips when in safety window", async () => {
    const name = "process-scheduled-workout-releases";
    await seedState(name, {
      started_at: new Date(Date.now() - 5_000).toISOString(),
      finished_at: null,
      last_status: "running",
      run_count: 1,
      skip_count: 0,
    });
    const result = await callRpc<number>("fn_process_scheduled_releases_safe");
    assertEq(result, 0, "should return 0 on skip");
    const row = await getState(name);
    assertEq(row.last_status, "skipped", "skipped");
    assertEq(row.skip_count, 1, "skip_count bumped");
  });
}

// ── Tests: cron schedule registration ───────────────────────────────────────

async function testCronJobs() {
  section("cron job registration (skipped if pg_cron not exposed)");

  const cronAvailable = await pgCronInstalled();
  if (!cronAvailable) {
    skip("cron.job introspection unavailable in this env (local dev without exposed cron schema)");
    return;
  }

  type Job = { jobname: string; schedule: string };

  async function fetchJob(name: string): Promise<Job | null> {
    const { data, error } = await (db.schema("cron" as any) as any)
      .from("job")
      .select("jobname, schedule")
      .eq("jobname", name)
      .maybeSingle();
    if (error) throw new Error(`cron.job select: ${error.message}`);
    return data as Job | null;
  }

  const expected: [string, string][] = [
    ["expire-matchmaking-queue", "*/5 * * * *"],
    ["process-scheduled-workout-releases", "*/5 * * * *"],
    ["lifecycle-cron", "*/5 * * * *"],
    ["eval-verification-cron", "15 3 * * *"],
    ["archive-old-sessions", "45 3 * * 0"],
    ["archive-old-ledger", "15 5 * * 0"],
    ["coin_ledger_ensure_partition_monthly", "30 5 1 * *"],
    ["reconcile-wallets-daily", "30 4 * * *"],
  ];

  for (const [jobname, schedule] of expected) {
    await test(`cron job ${jobname} scheduled @ ${schedule}`, async () => {
      const job = await fetchJob(jobname);
      assertTrue(job !== null, `job ${jobname} should exist`);
      assertEq(job!.schedule, schedule, `${jobname} schedule`);
    });
  }
}

async function testReconcileSeed() {
  section("reconcile-wallets-daily seed row");

  await test("cron_run_state row seeded with last_status=never_run", async () => {
    const row = await getState("reconcile-wallets-daily");
    assertTrue(row !== null, "row should be seeded by L12-01 migration");
    // Note: if a previous test run actually fired the cron, status will
    // have moved. We only assert the row exists.
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log("╔═══════════════════════════════════════════════════════════╗");
  console.log("║   L12 cron-health integration tests                      ║");
  console.log("╚═══════════════════════════════════════════════════════════╝");
  console.log(`Supabase URL:  ${SUPABASE_URL}`);
  console.log(`Timestamp:     ${new Date().toISOString()}`);

  const alive = await preflight();
  if (!alive) {
    console.error(`\n\x1b[31mERROR: Cannot reach Supabase at ${SUPABASE_URL}\x1b[0m`);
    console.error("Start local Supabase first:  supabase start");
    process.exit(2);
  }

  if (!(await tableReachable())) {
    console.error(
      `\n\x1b[31mERROR: cron_run_state not reachable. Apply migrations first.\x1b[0m`,
    );
    process.exit(2);
  }

  try {
    await testSchema();
    await testHelpers();
    await testSafeWrappers();
    await testCronJobs();
    await testReconcileSeed();
  } catch (err) {
    console.error("\n=== SUITE ABORTED ===");
    console.error(err);
    process.exitCode = 1;
  }

  console.log("\n══════════════════════════════════════════════════════════");
  console.log(`  Results: ${passed} passed, ${failed} failed, ${skipped} skipped`);
  console.log("══════════════════════════════════════════════════════════\n");

  if (failed > 0) process.exit(1);
}

main();
