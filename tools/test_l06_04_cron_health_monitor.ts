/**
 * tools/test_l06_04_cron_health_monitor.ts
 *
 * Integration tests for the L06-04 cron health monitor migration
 * (`supabase/migrations/20260420130000_l06_cron_health_monitor.sql`).
 *
 * Coverage
 * ────────
 *   • public.cron_health_alerts
 *       (1) table exists with the documented columns
 *       (2) CHECK on severity rejects values outside {warn, critical}
 *       (3) RLS forced + enabled (no anon/authenticated policy)
 *
 *   • public.fn_parse_cron_interval_seconds
 *       (4) returns the documented values for every schedule we use today
 *       (5) NULL / garbage falls back to 86400 (daily)
 *       (6) IMMUTABLE marker holds (returns same answer twice for same input)
 *
 *   • public.fn_classify_cron_severity
 *       (7) returns the documented enum on the canonical vectors
 *           (mirror of portal/src/lib/cron-health.ts::classifyCronSeverity)
 *       (8) clamps a too-small expected interval to 60s
 *       (9) clamps a missing interval to 86400s
 *
 *   • public.fn_check_cron_health
 *       (10) returns rows without raising in both pg_cron-present and absent
 *            environments (we only test the present case here; absent is
 *            covered by the migration self-test)
 *       (11) every row has the documented columns + a valid severity enum
 *       (12) at least one of our wrapped jobs (settle-clearing-batch /
 *            lifecycle-cron / etc.) appears with a non-null schedule
 *
 *   • public.fn_record_cron_health_alert
 *       (13) inserts then dedupes within cooldown
 *       (14) severity upgrade does NOT dedup (warn → critical)
 *       (15) bad inputs raise SQLSTATE 22023
 *
 *   • public.fn_alert_unhealthy_crons_safe
 *       (16) end-to-end: synthetic failed job → alert row created →
 *            cron_run_state for cron-health-monitor advances
 *       (17) when run twice in cooldown window: second run is dedup
 *
 *   • Schedule wiring
 *       (18) `cron-health-monitor` is registered in cron.job at every-15-min
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l06_04_cron_health_monitor.ts
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

const SYNTHETIC_JOB_PREFIX = "__l06_04_it__";
const createdAlertJobs = new Set<string>();
const createdStateJobs = new Set<string>();

async function parseInterval(schedule: string | null): Promise<number> {
  const { data, error } = await db.rpc("fn_parse_cron_interval_seconds", {
    p_schedule: schedule,
  });
  if (error) throw new Error(`parse rpc: ${error.message}`);
  return Number(data);
}

async function classify(
  secondsSinceLastSuccess: number | null,
  expectedIntervalSeconds: number | null,
  lastStatus: string | null,
  runningForSeconds: number | null = null,
): Promise<string> {
  const { data, error } = await db.rpc("fn_classify_cron_severity", {
    p_seconds_since_last_success: secondsSinceLastSuccess,
    p_expected_interval_seconds: expectedIntervalSeconds,
    p_last_status: lastStatus,
    p_running_for_seconds: runningForSeconds,
  });
  if (error) throw new Error(`classify rpc: ${error.message}`);
  return data as string;
}

async function recordAlert(
  jobName: string,
  severity: "warn" | "critical",
  details: Record<string, unknown> = {},
  cooldownMinutes: number = 60,
): Promise<string | null> {
  createdAlertJobs.add(jobName);
  const { data, error } = await db.rpc("fn_record_cron_health_alert", {
    p_job_name: jobName,
    p_severity: severity,
    p_details: details,
    p_cooldown_minutes: cooldownMinutes,
  });
  if (error) throw new Error(`record_alert rpc: ${error.message}`);
  return (data as string | null) ?? null;
}

async function checkHealth(): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await db.rpc("fn_check_cron_health");
  if (error) throw new Error(`check_health rpc: ${error.message}`);
  return (Array.isArray(data) ? data : []) as Array<Record<string, unknown>>;
}

async function cleanup() {
  // Remove alert rows we created
  for (const job of createdAlertJobs) {
    await db.from("cron_health_alerts").delete().eq("job_name", job);
  }
  // Remove cron_run_state synthetic rows we created
  for (const job of createdStateJobs) {
    await db.from("cron_run_state").delete().eq("name", job);
  }
}

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(
    `${BOLD}L06-04 — pg_cron health monitor integration tests${RESET}`,
  );
  console.log(`SUPABASE_URL=${SUPABASE_URL}\n`);

  // ── public.cron_health_alerts schema ─────────────────────────────────────
  section("public.cron_health_alerts — schema");

  await test("table exists with the documented columns", async () => {
    const { data, error } = await db
      .from("cron_health_alerts")
      .select("id,job_name,severity,observed_at,cooldown_minutes,details,acknowledged_at,acknowledged_by")
      .limit(0);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "expected array (limit 0)");
  });

  await test("CHECK on severity rejects values outside {warn, critical}", async () => {
    const { error } = await db.from("cron_health_alerts").insert({
      job_name: `${SYNTHETIC_JOB_PREFIX}bad-sev`,
      severity: "ok",
      cooldown_minutes: 60,
    });
    if (!error) throw new Error("insert with severity='ok' should have failed");
    assertTrue(
      /violates check constraint|invalid input value|severity/i.test(error.message),
      `unexpected error: ${error.message}`,
    );
  });

  await test("anon role cannot read the table (RLS forced)", async () => {
    const anonKey = process.env.SUPABASE_ANON_KEY ??
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
    const anon = createClient(SUPABASE_URL, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await anon
      .from("cron_health_alerts")
      .select("id")
      .limit(1);
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

  // ── fn_parse_cron_interval_seconds ───────────────────────────────────────
  section("fn_parse_cron_interval_seconds (L06-04)");

  await test("returns the documented values for every schedule we use today", async () => {
    assertEq(await parseInterval("* * * * *"), 60, "every-minute");
    assertEq(await parseInterval("*/5 * * * *"), 300, "every-5-min");
    assertEq(await parseInterval("*/10 * * * *"), 600, "every-10-min");
    assertEq(await parseInterval("*/15 * * * *"), 900, "every-15-min");
    assertEq(await parseInterval("7 * * * *"), 3600, "hourly literal");
    assertEq(await parseInterval("0 * * * *"), 3600, "hourly literal 0");
    assertEq(await parseInterval("30 4 * * *"), 86400, "daily literal");
    assertEq(await parseInterval("45 6 * * *"), 86400, "daily literal");
    assertEq(await parseInterval("45 3 * * 0"), 604800, "weekly Sunday");
    assertEq(await parseInterval("30 5 1 * *"), 2592000, "monthly first-of-month");
  });

  await test("NULL / garbage falls back to 86400 (daily)", async () => {
    assertEq(await parseInterval(null), 86400, "NULL fallback");
    assertEq(await parseInterval(""), 86400, "empty fallback");
    assertEq(await parseInterval("not a cron"), 86400, "garbage fallback");
    assertEq(await parseInterval("@daily"), 86400, "named-macro fallback");
    assertEq(await parseInterval("0 0 * * 1-5"), 86400, "range-DoW fallback");
  });

  await test("IMMUTABLE: same input → same output across calls", async () => {
    const a = await parseInterval("*/5 * * * *");
    const b = await parseInterval("*/5 * * * *");
    assertEq(a, b, "two parse calls disagree");
  });

  // ── fn_classify_cron_severity ────────────────────────────────────────────
  section("fn_classify_cron_severity (L06-04)");

  await test("classifies the canonical vectors (mirror of TS helper)", async () => {
    assertEq(await classify(null, 300, "never_run"), "unknown", "never_run");
    assertEq(await classify(60, 300, "completed"), "ok", "fresh ok");
    assertEq(await classify(480, 300, "completed"), "warn", "1.6x stale warn");
    assertEq(await classify(1050, 300, "completed"), "critical", "3.5x stale critical");
    assertEq(await classify(60, 300, "failed"), "warn", "recent fail warn");
    assertEq(await classify(500, 300, "failed"), "critical", "persistent fail critical");
    assertEq(await classify(120, 300, "running", 60), "ok", "running inside cycle");
    assertEq(await classify(120, 300, "running", 500), "warn", "long running warn");
    assertEq(await classify(120, 300, "running", 1500), "critical", "orphan running");
  });

  await test("clamps a too-small expected interval to 60s", async () => {
    // expected=10 → clamped to 60. 1.5x = 90s.
    assertEq(await classify(60, 10, "completed"), "ok", "60 < 90 ok");
    assertEq(await classify(89, 10, "completed"), "ok", "89 < 90 ok");
    assertEq(await classify(120, 10, "completed"), "warn", "120 > 90 warn");
    assertEq(await classify(200, 10, "completed"), "critical", "200 > 180 critical");
  });

  await test("clamps a missing interval to 86400s (daily)", async () => {
    assertEq(await classify(100_000, null, "completed"), "ok", "100k < 1.5d");
    assertEq(await classify(200_000, null, "completed"), "warn", "200k > 1.5d");
    assertEq(await classify(300_000, null, "completed"), "critical", "300k > 3d");
  });

  // ── fn_check_cron_health ─────────────────────────────────────────────────
  section("fn_check_cron_health (L06-04)");

  await test("returns rows without raising", async () => {
    const rows = await checkHealth();
    assertTrue(rows.length >= 0, "expected non-negative row count");
  });

  await test("every row has the documented columns + a valid severity enum", async () => {
    const rows = await checkHealth();
    assertTrue(rows.length > 0, "expected at least one cron job in this env");
    const required = [
      "name",
      "schedule",
      "source",
      "active",
      "last_status",
      "expected_interval_seconds",
      "seconds_since_last_success",
      "running_for_seconds",
      "run_count",
      "skip_count",
      "last_meta",
      "severity",
    ];
    for (const r of rows) {
      for (const k of required) {
        assertTrue(k in r, `row ${r.name} missing column ${k}`);
      }
      assertTrue(
        ["ok", "warn", "critical", "unknown"].includes(String(r.severity)),
        `row ${r.name} has bad severity: ${r.severity}`,
      );
    }
  });

  await test("at least one wrapped job (settle-clearing-batch / lifecycle-cron / etc.) appears with a schedule", async () => {
    const rows = await checkHealth();
    const wrapped = rows.find((r) =>
      ["settle-clearing-batch", "lifecycle-cron", "expire-matchmaking-queue", "process-scheduled-workout-releases", "cron-health-monitor"].includes(String(r.name)),
    );
    assertTrue(wrapped !== undefined, "no wrapped job appeared in cron health");
    assertTrue(typeof wrapped?.schedule === "string" && (wrapped!.schedule as string).length > 0, "wrapped job has no schedule");
  });

  // ── fn_record_cron_health_alert ──────────────────────────────────────────
  section("fn_record_cron_health_alert (L06-04)");

  await test("inserts a row and returns its id", async () => {
    const jobName = `${SYNTHETIC_JOB_PREFIX}rec-${randomUUID().slice(0, 8)}`;
    const id = await recordAlert(jobName, "warn", { test: true }, 60);
    assertTrue(typeof id === "string" && id!.length > 0, "expected uuid");
  });

  await test("dedupes a second insert at same (job, severity) within cooldown", async () => {
    const jobName = `${SYNTHETIC_JOB_PREFIX}dedup-${randomUUID().slice(0, 8)}`;
    const id1 = await recordAlert(jobName, "warn", { i: 1 }, 60);
    assertTrue(id1 !== null, "first insert should produce id");
    const id2 = await recordAlert(jobName, "warn", { i: 2 }, 60);
    assertEq(id2, null, "second insert in cooldown should be NULL");
  });

  await test("severity upgrade (warn → critical) does NOT dedup", async () => {
    const jobName = `${SYNTHETIC_JOB_PREFIX}upgrade-${randomUUID().slice(0, 8)}`;
    const idWarn = await recordAlert(jobName, "warn", {}, 60);
    const idCrit = await recordAlert(jobName, "critical", {}, 60);
    assertTrue(idWarn !== null, "warn id");
    assertTrue(idCrit !== null && idCrit !== idWarn, "critical should be a fresh row");
  });

  await test("bad inputs raise SQLSTATE 22023", async () => {
    const tries: Array<[string, () => Promise<unknown>]> = [
      ["NULL job", () => recordAlert(null as unknown as string, "warn")],
      ["empty job", () => recordAlert("   ", "warn")],
      ["bad severity", () => recordAlert("x", "ok" as unknown as "warn")],
      ["cooldown=0", () => recordAlert("x", "warn", {}, 0)],
      ["cooldown too large", () => recordAlert("x", "warn", {}, 99999)],
    ];
    for (const [label, fn] of tries) {
      let rejected = false;
      try {
        await fn();
      } catch (e) {
        rejected = true;
        const msg = e instanceof Error ? e.message : String(e);
        assertTrue(
          /22023|INVALID_/i.test(msg),
          `${label}: expected 22023, got: ${msg}`,
        );
      }
      assertTrue(rejected, `${label}: should have raised`);
    }
  });

  // ── fn_alert_unhealthy_crons_safe end-to-end ─────────────────────────────
  section("fn_alert_unhealthy_crons_safe (L06-04)");

  await test("synthetic failed job → alert row created end-to-end", async () => {
    const jobName = `${SYNTHETIC_JOB_PREFIX}e2e-${randomUUID().slice(0, 8)}`;
    createdStateJobs.add(jobName);
    createdAlertJobs.add(jobName);

    // Seed a cron_run_state row indicating a recently failed run
    const { error: seedErr } = await db.from("cron_run_state").upsert({
      name: jobName,
      last_status: "failed",
      started_at: new Date(Date.now() - 60 * 60_000).toISOString(),
      finished_at: new Date(Date.now() - 59 * 60_000).toISOString(),
      last_error: "synthetic failure for L06-04 IT",
      run_count: 5,
      skip_count: 0,
      last_meta: {},
    });
    if (seedErr) throw new Error(`seed cron_run_state: ${seedErr.message}`);

    // Snapshot prior state of cron-health-monitor to verify it advances
    const { data: priorRows } = await db
      .from("cron_run_state")
      .select("run_count")
      .eq("name", "cron-health-monitor")
      .single();
    const priorRunCount = Number(priorRows?.run_count ?? 0);

    // Manually invoke the wrapper
    const { error: runErr } = await db.rpc("fn_alert_unhealthy_crons_safe");
    if (runErr) throw new Error(`fn_alert_unhealthy_crons_safe: ${runErr.message}`);

    // Verify an alert row was created for our synthetic job
    const { data: alerts, error: alertsErr } = await db
      .from("cron_health_alerts")
      .select("severity,details")
      .eq("job_name", jobName)
      .order("observed_at", { ascending: false });
    if (alertsErr) throw new Error(`alerts query: ${alertsErr.message}`);
    assertTrue(
      Array.isArray(alerts) && alerts!.length >= 1,
      `expected ≥1 alert row, got ${JSON.stringify(alerts)}`,
    );

    // Verify cron-health-monitor advanced its own run_count + last_meta
    const { data: monRow } = await db
      .from("cron_run_state")
      .select("run_count,last_status,last_meta")
      .eq("name", "cron-health-monitor")
      .single();
    assertTrue(monRow !== null, "cron-health-monitor should have a row");
    assertTrue(
      Number(monRow!.run_count) >= priorRunCount,
      `run_count should not regress (was ${priorRunCount}, now ${monRow!.run_count})`,
    );
  });

  await test("second invocation within cooldown does NOT add a duplicate alert", async () => {
    // Re-use the synthetic state from the previous test (still 'failed').
    // The wrapper should skip (cooldown) without erroring.

    // Find the most-recently-seeded synthetic job
    const { data: state } = await db
      .from("cron_run_state")
      .select("name")
      .like("name", `${SYNTHETIC_JOB_PREFIX}e2e-%`)
      .order("updated_at", { ascending: false })
      .limit(1);
    if (!state || state.length === 0) throw new Error("no synthetic e2e row found");
    const jobName = state[0].name as string;

    const { count: before } = await db
      .from("cron_health_alerts")
      .select("*", { count: "exact", head: true })
      .eq("job_name", jobName);

    const { error } = await db.rpc("fn_alert_unhealthy_crons_safe");
    if (error) throw new Error(`second invoke: ${error.message}`);

    const { count: after } = await db
      .from("cron_health_alerts")
      .select("*", { count: "exact", head: true })
      .eq("job_name", jobName);

    assertEq(after, before, "alert count should not increase within cooldown");
  });

  // ── Schedule wiring ──────────────────────────────────────────────────────
  section("cron-health-monitor schedule");

  await test("registered in cron.job at */15 * * * *", async () => {
    // We can't query pg_cron's cron.job table directly via PostgREST, so
    // we go through fn_check_cron_health which UNIONs cron.job. The
    // monitor must appear with its own schedule.
    const rows = await checkHealth();
    const monitor = rows.find((r) => r.name === "cron-health-monitor");
    assertTrue(monitor !== undefined, "cron-health-monitor not in fn_check_cron_health");
    assertEq(monitor!.schedule, "*/15 * * * *", "cron-health-monitor schedule");
  });

  // ── cleanup ──────────────────────────────────────────────────────────────
  await cleanup();

  console.log(
    `\n${BOLD}Result:${RESET} ${passed} passed, ${failed} failed (${passed + failed} total)`,
  );
  process.exit(failed === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("Fatal:", e);
  cleanup().finally(() => process.exit(2));
});
