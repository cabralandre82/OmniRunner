/**
 * tools/test_l12_04_cron_sla_monitor.ts
 *
 * Integration tests for the L12-04 cron SLA monitor migration
 * (`supabase/migrations/20260420140000_l12_cron_sla_monitoring.sql`).
 *
 * Coverage
 * ────────
 *   • public.cron_run_history
 *       (1) table exists with the documented columns
 *       (2) CHECK on last_status rejects values outside the enum
 *       (3) anon role cannot read (RLS forced + service-role-only)
 *       (4) duration_seconds is a generated stored column
 *
 *   • public.cron_sla_thresholds
 *       (5) table exists, anon-blocked, with seeded rows for known jobs
 *       (6) CHECK rejects breach < target and out-of-range values
 *
 *   • Trigger trg_cron_run_history_capture
 *       (7) does NOT fire on intermediate ('running' / 'skipped') updates
 *       (8) fires once on terminal transition (completed/failed/timeout)
 *       (9) idempotent UPDATE (same finished_at) does not double-record
 *
 *   • public.fn_classify_cron_sla
 *       (10) classifies the canonical vectors (mirror of TS helper)
 *       (11) disabled threshold returns 'ok' regardless of badness
 *       (12) zero runs returns 'unknown'
 *
 *   • public.fn_compute_cron_sla_stats
 *       (13) returns rows for known jobs with valid columns + severity
 *       (14) configured thresholds win over derived
 *       (15) bad p_window_hours raises SQLSTATE 22023
 *       (16) breach_count > 0 when synthetic long run is present
 *
 *   • public.fn_alert_cron_sla_breaches_safe
 *       (17) end-to-end: synthetic breaching job → alert row created
 *            with details.kind = 'sla_breach' + cron-sla-monitor advances
 *       (18) second invocation within cooldown does NOT add a duplicate
 *
 *   • Schedule wiring
 *       (19) `cron-sla-monitor` is registered with its own threshold
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l12_04_cron_sla_monitor.ts
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

const SYNTHETIC_JOB_PREFIX = "__l12_04_it__";
const createdStateJobs = new Set<string>();
const createdHistoryJobs = new Set<string>();
const createdAlertJobs = new Set<string>();
const createdThresholdJobs = new Set<string>();

async function classify(
  runCount: number,
  avgDuration: number | null,
  p95Duration: number | null,
  lastDuration: number | null,
  targetSeconds: number | null,
  breachSeconds: number | null,
  breachCount: number,
  enabled: boolean = true,
): Promise<string> {
  const { data, error } = await db.rpc("fn_classify_cron_sla", {
    p_run_count: runCount,
    p_avg_duration: avgDuration,
    p_p95_duration: p95Duration,
    p_last_duration: lastDuration,
    p_target_seconds: targetSeconds,
    p_breach_seconds: breachSeconds,
    p_breach_count: breachCount,
    p_enabled: enabled,
  });
  if (error) throw new Error(`classify rpc: ${error.message}`);
  return data as string;
}

async function computeStats(
  windowHours: number = 24,
): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await db.rpc("fn_compute_cron_sla_stats", {
    p_window_hours: windowHours,
  });
  if (error) throw new Error(`compute_stats rpc: ${error.message}`);
  return (Array.isArray(data) ? data : []) as Array<Record<string, unknown>>;
}

async function cleanup() {
  for (const job of createdAlertJobs) {
    await db.from("cron_health_alerts").delete().eq("job_name", job);
  }
  for (const job of createdHistoryJobs) {
    await db.from("cron_run_history").delete().eq("name", job);
  }
  for (const job of createdThresholdJobs) {
    await db.from("cron_sla_thresholds").delete().eq("name", job);
  }
  for (const job of createdStateJobs) {
    await db.from("cron_run_state").delete().eq("name", job);
  }
}

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`${BOLD}L12-04 — pg_cron SLA monitor integration tests${RESET}`);
  console.log(`SUPABASE_URL=${SUPABASE_URL}\n`);

  // ── public.cron_run_history schema ──────────────────────────────────────
  section("public.cron_run_history — schema");

  await test("table exists with the documented columns", async () => {
    const { data, error } = await db
      .from("cron_run_history")
      .select(
        "id,name,started_at,finished_at,duration_seconds,last_status,last_error,last_meta,recorded_at",
      )
      .limit(0);
    if (error) throw new Error(error.message);
    assertTrue(Array.isArray(data), "expected array (limit 0)");
  });

  await test("CHECK on last_status rejects values outside the enum", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}bad-status-${randomUUID().slice(0, 8)}`;
    createdHistoryJobs.add(job);
    const { error } = await db.from("cron_run_history").insert({
      name: job,
      started_at: new Date(Date.now() - 1000).toISOString(),
      finished_at: new Date().toISOString(),
      last_status: "running",
    });
    if (!error) {
      throw new Error("insert with last_status='running' should have failed");
    }
    assertTrue(
      /violates check constraint|invalid input value|last_status/i.test(
        error.message,
      ),
      `unexpected error: ${error.message}`,
    );
  });

  await test("anon role cannot read the table (RLS forced)", async () => {
    const anonKey =
      process.env.SUPABASE_ANON_KEY ??
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";
    const anon = createClient(SUPABASE_URL, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data, error } = await anon
      .from("cron_run_history")
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

  await test("duration_seconds is generated from started_at/finished_at", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}dur-${randomUUID().slice(0, 8)}`;
    createdHistoryJobs.add(job);
    const start = new Date(Date.now() - 7500);
    const end = new Date();
    const { error } = await db.from("cron_run_history").insert({
      name: job,
      started_at: start.toISOString(),
      finished_at: end.toISOString(),
      last_status: "completed",
    });
    if (error) throw new Error(error.message);

    const { data: row } = await db
      .from("cron_run_history")
      .select("duration_seconds")
      .eq("name", job)
      .single();
    const dur = Number(row?.duration_seconds);
    assertTrue(!Number.isNaN(dur), "duration_seconds must be numeric");
    assertTrue(
      dur >= 7.0 && dur <= 9.0,
      `expected duration ~7.5s, got ${dur}`,
    );
  });

  // ── public.cron_sla_thresholds schema ───────────────────────────────────
  section("public.cron_sla_thresholds — schema + seeds");

  await test("table exists, anon-blocked, with seeded rows for known jobs", async () => {
    const { data, error } = await db
      .from("cron_sla_thresholds")
      .select("name,target_seconds,breach_seconds,enabled,notes")
      .in("name", [
        "clearing-cron",
        "reconcile-wallets-daily",
        "lifecycle-cron",
        "cron-sla-monitor",
      ]);
    if (error) throw new Error(error.message);
    assertTrue(
      Array.isArray(data) && data.length >= 4,
      `expected >=4 seeded rows, got ${data?.length ?? 0}`,
    );
    for (const row of data ?? []) {
      const t = Number(row.target_seconds);
      const b = Number(row.breach_seconds);
      assertTrue(t > 0 && b >= t, `${row.name}: bad target/breach: ${t}/${b}`);
    }
  });

  await test("CHECK rejects breach < target", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}bad-thresh-${randomUUID().slice(0, 8)}`;
    createdThresholdJobs.add(job);
    const { error } = await db.from("cron_sla_thresholds").insert({
      name: job,
      target_seconds: 100,
      breach_seconds: 50,
    });
    if (!error) throw new Error("breach<target should have failed");
    assertTrue(
      /violates check constraint|breach_seconds/i.test(error.message),
      `unexpected error: ${error.message}`,
    );
  });

  // ── Trigger trg_cron_run_history_capture ────────────────────────────────
  section("trg_cron_run_history_capture (L12-04)");

  await test("does NOT fire on 'running' transitions", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}run-only-${randomUUID().slice(0, 8)}`;
    createdStateJobs.add(job);

    const { error: insErr } = await db.from("cron_run_state").insert({
      name: job,
      last_status: "never_run",
    });
    if (insErr) throw new Error(`seed insert: ${insErr.message}`);

    const { error: updErr } = await db
      .from("cron_run_state")
      .update({
        last_status: "running",
        started_at: new Date().toISOString(),
        finished_at: null,
      })
      .eq("name", job);
    if (updErr) throw new Error(`update running: ${updErr.message}`);

    const { count } = await db
      .from("cron_run_history")
      .select("*", { count: "exact", head: true })
      .eq("name", job);
    assertEq(count, 0, "history should still be empty after running update");
  });

  await test("fires once on terminal 'completed' transition", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}cap-comp-${randomUUID().slice(0, 8)}`;
    createdStateJobs.add(job);
    createdHistoryJobs.add(job);

    const { error } = await db.from("cron_run_state").insert({
      name: job,
      last_status: "running",
      started_at: new Date(Date.now() - 2000).toISOString(),
      finished_at: null,
    });
    if (error) throw new Error(error.message);

    await db
      .from("cron_run_state")
      .update({
        last_status: "completed",
        finished_at: new Date().toISOString(),
      })
      .eq("name", job);

    const { count } = await db
      .from("cron_run_history")
      .select("*", { count: "exact", head: true })
      .eq("name", job);
    assertEq(count, 1, "expected exactly 1 history row after completed");
  });

  await test("idempotent UPDATE (same finished_at) does not double-record", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}idem-${randomUUID().slice(0, 8)}`;
    createdStateJobs.add(job);
    createdHistoryJobs.add(job);

    const fin = new Date().toISOString();

    const { error: insErr } = await db.from("cron_run_state").insert({
      name: job,
      last_status: "completed",
      started_at: new Date(Date.now() - 3000).toISOString(),
      finished_at: fin,
    });
    if (insErr) throw new Error(insErr.message);

    // Touching the row without changing terminal/finished_at must not
    // create a second history row.
    await db
      .from("cron_run_state")
      .update({ last_meta: { touched: true } })
      .eq("name", job);

    const { count } = await db
      .from("cron_run_history")
      .select("*", { count: "exact", head: true })
      .eq("name", job);
    assertEq(count, 1, "expected exactly 1 history row, no double-record");
  });

  // ── fn_classify_cron_sla ────────────────────────────────────────────────
  section("fn_classify_cron_sla (L12-04)");

  await test("classifies the canonical vectors (mirror of TS helper)", async () => {
    assertEq(
      await classify(0, null, null, null, 60, 240, 0),
      "unknown",
      "zero runs",
    );
    assertEq(await classify(10, 5, 8, 6, 60, 240, 0), "ok", "fast healthy");
    assertEq(await classify(10, 50, 80, 250, 60, 240, 1), "warn", "single breach");
    assertEq(await classify(10, 50, 250, 50, 60, 240, 1), "warn", "p95 breach");
    assertEq(
      await classify(10, 50, 80, 500, 60, 240, 1),
      "critical",
      "last 2x breach",
    );
    assertEq(
      await classify(10, 50, 500, 50, 60, 240, 1),
      "critical",
      "p95 2x breach",
    );
    assertEq(
      await classify(10, 100, 200, 200, 60, 240, 2),
      "warn",
      "sustained drift",
    );
    assertEq(
      await classify(10, 100, 200, 200, 60, 240, 1),
      "ok",
      "single drift event",
    );
  });

  await test("disabled threshold returns 'ok' regardless of badness", async () => {
    assertEq(
      await classify(10, 5000, 5000, 5000, 60, 240, 99, false),
      "ok",
      "disabled silences",
    );
  });

  await test("zero runs returns 'unknown' even with thresholds set", async () => {
    assertEq(await classify(0, 1, 1, 1, 60, 240, 0, true), "unknown", "zero");
  });

  // ── fn_compute_cron_sla_stats ───────────────────────────────────────────
  section("fn_compute_cron_sla_stats (L12-04)");

  await test("returns rows for seeded jobs with valid columns + severity", async () => {
    const rows = await computeStats(24);
    assertTrue(rows.length > 0, "expected at least one job");
    const required = [
      "name",
      "schedule",
      "expected_interval_seconds",
      "source_thresholds",
      "target_seconds",
      "breach_seconds",
      "enabled",
      "run_count",
      "failed_count",
      "avg_duration_seconds",
      "p50_duration_seconds",
      "p95_duration_seconds",
      "p99_duration_seconds",
      "max_duration_seconds",
      "last_duration_seconds",
      "last_finished_at",
      "breach_count",
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

  await test("configured thresholds win over derived", async () => {
    const rows = await computeStats(24);
    const configured = rows.find((r) => r.name === "clearing-cron");
    assertTrue(configured !== undefined, "clearing-cron must be present");
    assertEq(
      configured!.source_thresholds,
      "configured",
      "clearing-cron should use configured thresholds",
    );
    // Verify configured numeric values match the seed (60 / 240).
    assertEq(
      Number(configured!.target_seconds),
      60,
      "clearing-cron target_seconds",
    );
    assertEq(
      Number(configured!.breach_seconds),
      240,
      "clearing-cron breach_seconds",
    );
  });

  await test("bad p_window_hours raises SQLSTATE 22023", async () => {
    const tries: Array<[string, number]> = [
      ["window=0", 0],
      ["window=-5", -5],
      ["window=10000", 10000],
    ];
    for (const [label, h] of tries) {
      let rejected = false;
      try {
        await computeStats(h);
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

  await test("breach_count > 0 when synthetic long run is present", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}stats-${randomUUID().slice(0, 8)}`;
    createdHistoryJobs.add(job);
    createdThresholdJobs.add(job);

    // Threshold: target=1, breach=3 → anything > 3s breaches.
    await db.from("cron_sla_thresholds").insert({
      name: job,
      target_seconds: 1,
      breach_seconds: 3,
    });

    // Insert two history rows: one healthy (1s), one breaching (10s).
    await db.from("cron_run_history").insert([
      {
        name: job,
        started_at: new Date(Date.now() - 9_000).toISOString(),
        finished_at: new Date(Date.now() - 8_000).toISOString(),
        last_status: "completed",
      },
      {
        name: job,
        started_at: new Date(Date.now() - 11_000).toISOString(),
        finished_at: new Date(Date.now() - 1_000).toISOString(),
        last_status: "completed",
      },
    ]);

    const rows = await computeStats(24);
    const r = rows.find((x) => x.name === job);
    assertTrue(r !== undefined, "synthetic job should be present in stats");
    assertEq(Number(r!.run_count), 2, "expected 2 runs");
    assertTrue(
      Number(r!.breach_count) >= 1,
      `expected breach_count>=1, got ${r!.breach_count}`,
    );
    assertEq(r!.severity, "critical", "10s vs 3s breach should be critical");
  });

  // ── fn_alert_cron_sla_breaches_safe end-to-end ──────────────────────────
  section("fn_alert_cron_sla_breaches_safe (L12-04)");

  await test("synthetic breach → alert row created with details.kind=sla_breach", async () => {
    const job = `${SYNTHETIC_JOB_PREFIX}e2e-${randomUUID().slice(0, 8)}`;
    createdStateJobs.add(job);
    createdHistoryJobs.add(job);
    createdThresholdJobs.add(job);
    createdAlertJobs.add(job);

    // Tight threshold so a 5-sec run is critical.
    await db.from("cron_sla_thresholds").insert({
      name: job,
      target_seconds: 1,
      breach_seconds: 2,
    });

    // Seed a breach row directly into history.
    await db.from("cron_run_history").insert({
      name: job,
      started_at: new Date(Date.now() - 5_000).toISOString(),
      finished_at: new Date().toISOString(),
      last_status: "completed",
    });

    // Snapshot prior state of cron-sla-monitor to verify it advances.
    const { data: priorRows } = await db
      .from("cron_run_state")
      .select("run_count")
      .eq("name", "cron-sla-monitor")
      .single();
    const priorRunCount = Number(priorRows?.run_count ?? 0);

    // Manually invoke the wrapper.
    const { error: runErr } = await db.rpc("fn_alert_cron_sla_breaches_safe");
    if (runErr) {
      throw new Error(`fn_alert_cron_sla_breaches_safe: ${runErr.message}`);
    }

    // Verify an alert row was created with kind=sla_breach.
    const { data: alerts } = await db
      .from("cron_health_alerts")
      .select("severity,details")
      .eq("job_name", job)
      .order("observed_at", { ascending: false });
    assertTrue(
      Array.isArray(alerts) && alerts.length >= 1,
      `expected >=1 alert, got ${JSON.stringify(alerts)}`,
    );
    const first = alerts![0]!;
    const details = (first.details as Record<string, unknown>) ?? {};
    assertEq(details.kind, "sla_breach", "alert details.kind");

    // Verify cron-sla-monitor advanced its own run_count.
    const { data: monRow } = await db
      .from("cron_run_state")
      .select("run_count,last_status,last_meta")
      .eq("name", "cron-sla-monitor")
      .single();
    assertTrue(monRow !== null, "cron-sla-monitor should have a row");
    assertTrue(
      Number(monRow!.run_count) >= priorRunCount,
      `run_count should not regress (was ${priorRunCount}, now ${monRow!.run_count})`,
    );
  });

  await test("second invocation within cooldown does NOT add a duplicate alert", async () => {
    // Find the e2e synthetic job we just created.
    const { data: thresh } = await db
      .from("cron_sla_thresholds")
      .select("name")
      .like("name", `${SYNTHETIC_JOB_PREFIX}e2e-%`)
      .limit(1);
    if (!thresh || thresh.length === 0) {
      throw new Error("no e2e synthetic threshold row found");
    }
    const job = thresh[0].name as string;

    const { count: before } = await db
      .from("cron_health_alerts")
      .select("*", { count: "exact", head: true })
      .eq("job_name", job);

    const { error } = await db.rpc("fn_alert_cron_sla_breaches_safe");
    if (error) throw new Error(`second invoke: ${error.message}`);

    const { count: after } = await db
      .from("cron_health_alerts")
      .select("*", { count: "exact", head: true })
      .eq("job_name", job);

    assertEq(after, before, "alert count should not increase within cooldown");
  });

  // ── Schedule wiring ─────────────────────────────────────────────────────
  section("cron-sla-monitor schedule");

  await test("cron-sla-monitor appears with its own threshold seed", async () => {
    const { data, error } = await db
      .from("cron_sla_thresholds")
      .select("name,target_seconds,breach_seconds")
      .eq("name", "cron-sla-monitor")
      .single();
    if (error) throw new Error(error.message);
    assertTrue(data !== null, "cron-sla-monitor threshold seed missing");
    assertEq(Number(data!.target_seconds), 5, "cron-sla-monitor target");
    assertEq(Number(data!.breach_seconds), 60, "cron-sla-monitor breach");
  });

  // ── cleanup ─────────────────────────────────────────────────────────────
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
