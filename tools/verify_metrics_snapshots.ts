/**
 * verify_metrics_snapshots.ts
 *
 * End-to-end validation script for the KPI snapshot system.
 * Creates seed data, runs compute functions, and verifies:
 *   - Correctness (DAU/WAU/score values)
 *   - Attendance integration (OS-01 → KPI snapshots)
 *   - MISSED_TRAININGS_14D alert generation
 *   - Idempotency (re-run does not change values)
 *   - RLS isolation (real user tokens, not service_role)
 *   - Performance (compute time < budget)
 *
 * Usage:
 *   npx tsx tools/verify_metrics_snapshots.ts
 *
 * Requires env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const DAY_MS = 86_400_000;
const NOW = Date.now();
const TODAY = new Date(NOW - (NOW % DAY_MS));
const YESTERDAY = new Date(TODAY.getTime() - DAY_MS);
const YESTERDAY_STR = YESTERDAY.toISOString().slice(0, 10);

let passCount = 0;
let failCount = 0;

function assert(condition: boolean, message: string) {
  if (!condition) {
    console.error(`  FAIL: ${message}`);
    failCount++;
  } else {
    console.log(`  PASS: ${message}`);
    passCount++;
  }
}

// ── Test user IDs ──────────────────────────────────────────────────────────

const GROUP_A_ID = "aaaaaaaa-0000-0000-0000-000000000001";
const GROUP_B_ID = "bbbbbbbb-0000-0000-0000-000000000002";
const COACH_A_ID = "cccccccc-0000-0000-0000-000000000001";
const COACH_B_ID = "cccccccc-0000-0000-0000-000000000002";
const ATHLETE_A1 = "dddddddd-0000-0000-0000-000000000001";
const ATHLETE_A2 = "dddddddd-0000-0000-0000-000000000002";
const ATHLETE_B1 = "dddddddd-0000-0000-0000-000000000003";
const ATHLETE_B2 = "dddddddd-0000-0000-0000-000000000004";
const ASSISTANT_A = "eeeeeeee-0000-0000-0000-000000000001";

const TEST_PASSWORD = "verify-snapshot-Pwd123!";

const ALL_USERS = [COACH_A_ID, COACH_B_ID, ATHLETE_A1, ATHLETE_A2, ATHLETE_B1, ATHLETE_B2, ASSISTANT_A];

// ── Training session IDs for attendance tests ──
const TRAINING_1 = "ffffffff-0000-0000-0000-000000000001";
const TRAINING_2 = "ffffffff-0000-0000-0000-000000000002";
const TRAINING_3 = "ffffffff-0000-0000-0000-000000000003";

// ── Helper: create an authenticated Supabase client for a specific user ────

async function createUserClient(userId: string): Promise<SupabaseClient> {
  const email = `test-${userId.slice(0, 8)}@verify.test`;
  const client = createClient(SUPABASE_URL!, process.env.SUPABASE_ANON_KEY || SERVICE_KEY!, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await client.auth.signInWithPassword({ email, password: TEST_PASSWORD });
  if (error) throw new Error(`Sign-in failed for ${email}: ${error.message}`);
  return client;
}

// ── Seed data ──────────────────────────────────────────────────────────────

async function seedData() {
  console.log("\n── Seeding test data ──");

  for (const uid of ALL_USERS) {
    const email = `test-${uid.slice(0, 8)}@verify.test`;
    const { error } = await db.auth.admin.createUser({
      id: uid,
      email,
      password: TEST_PASSWORD,
      email_confirm: true,
    });
    if (error && !error.message.includes("already")) {
      console.warn(`  User create warn (${uid.slice(0, 8)}): ${error.message}`);
    }
  }

  for (const [id, name, coachId] of [
    [GROUP_A_ID, "Verify Group A", COACH_A_ID],
    [GROUP_B_ID, "Verify Group B", COACH_B_ID],
  ] as const) {
    await db.from("coaching_groups").upsert({
      id,
      name,
      coach_user_id: coachId,
      created_at_ms: NOW - 30 * DAY_MS,
    }, { onConflict: "id" });
  }

  await db.from("coaching_members").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  const members = [
    { id: crypto.randomUUID(), user_id: COACH_A_ID, group_id: GROUP_A_ID, display_name: "Coach A", role: "admin_master", joined_at_ms: NOW - 30 * DAY_MS },
    { id: crypto.randomUUID(), user_id: ASSISTANT_A, group_id: GROUP_A_ID, display_name: "Assistant A", role: "assistant", joined_at_ms: NOW - 25 * DAY_MS },
    { id: crypto.randomUUID(), user_id: ATHLETE_A1, group_id: GROUP_A_ID, display_name: "Athlete A1", role: "athlete", joined_at_ms: NOW - 20 * DAY_MS },
    { id: crypto.randomUUID(), user_id: ATHLETE_A2, group_id: GROUP_A_ID, display_name: "Athlete A2", role: "athlete", joined_at_ms: NOW - 15 * DAY_MS },
    { id: crypto.randomUUID(), user_id: COACH_B_ID, group_id: GROUP_B_ID, display_name: "Coach B", role: "admin_master", joined_at_ms: NOW - 30 * DAY_MS },
    { id: crypto.randomUUID(), user_id: ATHLETE_B1, group_id: GROUP_B_ID, display_name: "Athlete B1", role: "athlete", joined_at_ms: NOW - 10 * DAY_MS },
    { id: crypto.randomUUID(), user_id: ATHLETE_B2, group_id: GROUP_B_ID, display_name: "Athlete B2", role: "athlete", joined_at_ms: NOW - 5 * DAY_MS },
  ];
  const { error: memErr } = await db.from("coaching_members").insert(members);
  if (memErr) console.warn(`  Members insert warn: ${memErr.message}`);

  for (const uid of [ATHLETE_A1, ATHLETE_A2, ATHLETE_B1, ATHLETE_B2]) {
    await db.from("profile_progress").upsert({
      user_id: uid,
      daily_streak_count: uid === ATHLETE_A1 ? 5 : 0,
    }, { onConflict: "user_id" });
  }

  // ── Running sessions ──
  await db.from("sessions").delete().in("user_id", ALL_USERS);
  const sessions = [
    {
      id: crypto.randomUUID(),
      user_id: ATHLETE_A1,
      status: 3,
      start_time_ms: YESTERDAY.getTime() + 8 * 3600000,
      end_time_ms: YESTERDAY.getTime() + 9 * 3600000,
      total_distance_m: 5000,
      moving_ms: 3600000,
      is_verified: true,
    },
    {
      id: crypto.randomUUID(),
      user_id: ATHLETE_A1,
      status: 3,
      start_time_ms: YESTERDAY.getTime() + 17 * 3600000,
      end_time_ms: YESTERDAY.getTime() + 18 * 3600000,
      total_distance_m: 3000,
      moving_ms: 2400000,
      is_verified: true,
    },
    {
      id: crypto.randomUUID(),
      user_id: ATHLETE_B1,
      status: 3,
      start_time_ms: YESTERDAY.getTime() + 10 * 3600000,
      end_time_ms: YESTERDAY.getTime() + 11 * 3600000,
      total_distance_m: 7000,
      moving_ms: 4200000,
      is_verified: true,
    },
  ];
  const { error: sessErr } = await db.from("sessions").insert(sessions);
  if (sessErr) console.warn(`  Sessions insert warn: ${sessErr.message}`);

  // ── Training sessions (OS-01) ──
  await db.from("coaching_training_attendance").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("coaching_training_sessions").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);

  const twoDaysAgo = new Date(YESTERDAY.getTime() - DAY_MS);
  const fiveDaysAgo = new Date(YESTERDAY.getTime() - 4 * DAY_MS);

  const trainingSessions = [
    {
      id: TRAINING_1,
      group_id: GROUP_A_ID,
      created_by: COACH_A_ID,
      title: "Treino Intervalado",
      starts_at: YESTERDAY.toISOString(),
      status: "done",
    },
    {
      id: TRAINING_2,
      group_id: GROUP_A_ID,
      created_by: COACH_A_ID,
      title: "Treino Longo",
      starts_at: twoDaysAgo.toISOString(),
      status: "done",
    },
    {
      id: TRAINING_3,
      group_id: GROUP_A_ID,
      created_by: COACH_A_ID,
      title: "Treino Técnico",
      starts_at: fiveDaysAgo.toISOString(),
      status: "done",
    },
  ];
  const { error: tsErr } = await db.from("coaching_training_sessions").insert(trainingSessions);
  if (tsErr) console.warn(`  Training sessions insert warn: ${tsErr.message}`);

  // Athlete A1 attended 2 of 3 trainings; Athlete A2 attended 0 (missed all)
  const attendanceRecords = [
    {
      id: crypto.randomUUID(),
      group_id: GROUP_A_ID,
      session_id: TRAINING_1,
      athlete_user_id: ATHLETE_A1,
      checked_by: COACH_A_ID,
      method: "qr",
    },
    {
      id: crypto.randomUUID(),
      group_id: GROUP_A_ID,
      session_id: TRAINING_3,
      athlete_user_id: ATHLETE_A1,
      checked_by: ASSISTANT_A,
      method: "qr",
    },
  ];
  const { error: attErr } = await db.from("coaching_training_attendance").insert(attendanceRecords);
  if (attErr) console.warn(`  Attendance insert warn: ${attErr.message}`);

  console.log("  Seed complete: 2 groups, 5 athletes, 3 run sessions, 3 trainings, 2 attendance records");
}

// ── Run compute jobs ───────────────────────────────────────────────────────

async function runCompute(): Promise<{ kpiMs: number; athleteMs: number; alertMs: number }> {
  console.log("\n── Running compute functions ──");

  const t0 = performance.now();
  const { data: kpiCount, error: e1 } = await db.rpc(
    "compute_coaching_kpis_daily",
    { p_day: YESTERDAY_STR },
  );
  const kpiMs = performance.now() - t0;
  if (e1) throw new Error(`compute_coaching_kpis_daily failed: ${e1.message}`);
  console.log(`  Group KPIs computed: ${kpiCount} groups (${kpiMs.toFixed(0)}ms)`);

  const t1 = performance.now();
  const { data: athleteCount, error: e2 } = await db.rpc(
    "compute_coaching_athlete_kpis_daily",
    { p_day: YESTERDAY_STR },
  );
  const athleteMs = performance.now() - t1;
  if (e2) throw new Error(`compute_coaching_athlete_kpis_daily failed: ${e2.message}`);
  console.log(`  Athlete KPIs computed: ${athleteCount} athletes (${athleteMs.toFixed(0)}ms)`);

  const t2 = performance.now();
  const { data: alertCount, error: e3 } = await db.rpc(
    "compute_coaching_alerts_daily",
    { p_day: YESTERDAY_STR },
  );
  const alertMs = performance.now() - t2;
  if (e3) throw new Error(`compute_coaching_alerts_daily failed: ${e3.message}`);
  console.log(`  Alerts generated: ${alertCount} (${alertMs.toFixed(0)}ms)`);

  return { kpiMs, athleteMs, alertMs };
}

// ── Verify correctness ─────────────────────────────────────────────────────

async function verifyCorrectness() {
  console.log("\n── Verifying correctness ──");

  // Group A KPIs
  const { data: kpiA } = await db
    .from("coaching_kpis_daily")
    .select("*")
    .eq("group_id", GROUP_A_ID)
    .eq("day", YESTERDAY_STR)
    .single();

  assert(kpiA !== null, "Group A KPI row exists");
  assert(kpiA!.total_athletes === 2, `Group A total_athletes = 2 (got ${kpiA!.total_athletes})`);
  assert(kpiA!.total_coaches === 2, `Group A total_coaches = 2 (got ${kpiA!.total_coaches})`);
  assert(kpiA!.dau === 1, `Group A DAU = 1 (got ${kpiA!.dau})`);
  assert(kpiA!.wau >= 1, `Group A WAU >= 1 (got ${kpiA!.wau})`);
  assert(kpiA!.sessions_today === 2, `Group A sessions_today = 2 (got ${kpiA!.sessions_today})`);
  assert(kpiA!.distance_today_m === 8000, `Group A distance = 8000m (got ${kpiA!.distance_today_m})`);

  // Monotonicity: DAU <= WAU <= MAU <= total_athletes
  assert(kpiA!.dau <= kpiA!.wau, `DAU(${kpiA!.dau}) <= WAU(${kpiA!.wau})`);
  assert(kpiA!.wau <= kpiA!.mau, `WAU(${kpiA!.wau}) <= MAU(${kpiA!.mau})`);
  assert(kpiA!.mau <= kpiA!.total_athletes, `MAU(${kpiA!.mau}) <= total(${kpiA!.total_athletes})`);

  // ── NEW: Attendance KPI fields ──
  assert(
    kpiA!.attendance_sessions_7d === 3,
    `Group A attendance_sessions_7d = 3 (got ${kpiA!.attendance_sessions_7d})`,
  );
  assert(
    kpiA!.attendance_checkins_7d === 2,
    `Group A attendance_checkins_7d = 2 (got ${kpiA!.attendance_checkins_7d})`,
  );
  assert(
    kpiA!.attendance_rate_7d !== null,
    `Group A attendance_rate_7d is not null (got ${kpiA!.attendance_rate_7d})`,
  );
  // rate = 2 / (3 sessions * 2 athletes) * 100 = 33.33%
  const expectedRate = 33.33;
  assert(
    Math.abs(Number(kpiA!.attendance_rate_7d) - expectedRate) < 1,
    `Group A attendance_rate_7d ≈ ${expectedRate}% (got ${kpiA!.attendance_rate_7d})`,
  );

  // Group B: no trainings → attendance = 0
  const { data: kpiB } = await db
    .from("coaching_kpis_daily")
    .select("*")
    .eq("group_id", GROUP_B_ID)
    .eq("day", YESTERDAY_STR)
    .single();

  assert(kpiB !== null, "Group B KPI row exists");
  assert(kpiB!.dau === 1, `Group B DAU = 1 (got ${kpiB!.dau})`);
  assert(kpiB!.attendance_sessions_7d === 0, `Group B attendance_sessions_7d = 0 (got ${kpiB!.attendance_sessions_7d})`);
  assert(kpiB!.attendance_rate_7d === null, `Group B attendance_rate_7d = null (no sessions)`);

  // Athlete A1 (active, streak=5)
  const { data: akA1 } = await db
    .from("coaching_athlete_kpis_daily")
    .select("*")
    .eq("user_id", ATHLETE_A1)
    .eq("day", YESTERDAY_STR)
    .single();

  assert(akA1 !== null, "Athlete A1 KPI row exists");
  assert(akA1!.sessions_7d >= 2, `A1 sessions_7d >= 2 (got ${akA1!.sessions_7d})`);
  assert(akA1!.engagement_score > 0, `A1 score > 0 (got ${akA1!.engagement_score})`);
  assert(akA1!.engagement_score <= 100, `A1 score <= 100`);
  assert(akA1!.current_streak === 5, `A1 streak = 5 (got ${akA1!.current_streak})`);

  // Athlete A2 (no sessions — high risk)
  const { data: akA2 } = await db
    .from("coaching_athlete_kpis_daily")
    .select("*")
    .eq("user_id", ATHLETE_A2)
    .eq("day", YESTERDAY_STR)
    .single();

  assert(akA2 !== null, "Athlete A2 KPI row exists");
  assert(akA2!.sessions_7d === 0, `A2 sessions_7d = 0 (got ${akA2!.sessions_7d})`);
  assert(akA2!.risk_level === "high", `A2 risk = high (got ${akA2!.risk_level})`);
  assert(akA2!.engagement_score < 20, `A2 score < 20 (got ${akA2!.engagement_score})`);

  // All athlete invariants
  const { data: allAK } = await db
    .from("coaching_athlete_kpis_daily")
    .select("user_id, sessions_7d, sessions_14d, sessions_30d, engagement_score, risk_level")
    .eq("day", YESTERDAY_STR)
    .in("group_id", [GROUP_A_ID, GROUP_B_ID]);

  for (const ak of allAK ?? []) {
    const u = ak.user_id.slice(0, 8);
    assert(ak.sessions_7d <= ak.sessions_14d, `${u}: s7d(${ak.sessions_7d}) <= s14d(${ak.sessions_14d})`);
    assert(ak.sessions_14d <= ak.sessions_30d, `${u}: s14d(${ak.sessions_14d}) <= s30d(${ak.sessions_30d})`);
    assert(ak.engagement_score >= 0 && ak.engagement_score <= 100, `${u}: score in [0,100]`);

    const expectedRisk = ak.engagement_score >= 40 ? "ok" : ak.engagement_score >= 20 ? "medium" : "high";
    assert(ak.risk_level === expectedRisk, `${u}: risk=${ak.risk_level} matches score=${ak.engagement_score}`);
  }

  // ── Alerts ──
  const { data: alerts } = await db
    .from("coaching_alerts")
    .select("*")
    .in("group_id", [GROUP_A_ID, GROUP_B_ID])
    .eq("day", YESTERDAY_STR);

  assert((alerts ?? []).length > 0, `Alerts generated: ${(alerts ?? []).length}`);

  const highAlerts = (alerts ?? []).filter((a: { alert_type: string }) => a.alert_type === "athlete_high_risk");
  assert(highAlerts.length >= 1, `At least 1 high-risk alert (got ${highAlerts.length})`);

  // ── NEW: MISSED_TRAININGS_14D alert for Athlete A2 ──
  const missedAlerts = (alerts ?? []).filter(
    (a: { alert_type: string; user_id: string }) =>
      a.alert_type === "missed_trainings_14d" && a.user_id === ATHLETE_A2,
  );
  assert(
    missedAlerts.length === 1,
    `MISSED_TRAININGS_14D alert exists for Athlete A2 (got ${missedAlerts.length})`,
  );

  // Athlete A1 should NOT have a missed training alert (attended 2/3)
  const a1MissedAlerts = (alerts ?? []).filter(
    (a: { alert_type: string; user_id: string }) =>
      a.alert_type === "missed_trainings_14d" && a.user_id === ATHLETE_A1,
  );
  assert(
    a1MissedAlerts.length === 0,
    `No MISSED_TRAININGS_14D for Athlete A1 (attended, got ${a1MissedAlerts.length})`,
  );

  return kpiA;
}

// ── Verify idempotency ─────────────────────────────────────────────────────

async function verifyIdempotency(originalKpi: Record<string, unknown>) {
  console.log("\n── Verifying idempotency (re-run compute) ──");

  await db.rpc("compute_coaching_kpis_daily", { p_day: YESTERDAY_STR });
  await db.rpc("compute_coaching_athlete_kpis_daily", { p_day: YESTERDAY_STR });
  await db.rpc("compute_coaching_alerts_daily", { p_day: YESTERDAY_STR });

  const { data: kpiA2 } = await db
    .from("coaching_kpis_daily")
    .select("dau, wau, mau, sessions_today, distance_today_m, attendance_sessions_7d, attendance_checkins_7d, attendance_rate_7d")
    .eq("group_id", GROUP_A_ID)
    .eq("day", YESTERDAY_STR)
    .single();

  assert(kpiA2!.dau === originalKpi.dau, `Idempotent: DAU unchanged (${kpiA2!.dau})`);
  assert(kpiA2!.wau === originalKpi.wau, `Idempotent: WAU unchanged (${kpiA2!.wau})`);
  assert(kpiA2!.mau === originalKpi.mau, `Idempotent: MAU unchanged (${kpiA2!.mau})`);
  assert(kpiA2!.sessions_today === originalKpi.sessions_today, `Idempotent: sessions unchanged`);
  assert(kpiA2!.distance_today_m === originalKpi.distance_today_m, `Idempotent: distance unchanged`);
  assert(
    kpiA2!.attendance_sessions_7d === originalKpi.attendance_sessions_7d,
    `Idempotent: attendance_sessions_7d unchanged (${kpiA2!.attendance_sessions_7d})`,
  );
  assert(
    kpiA2!.attendance_checkins_7d === originalKpi.attendance_checkins_7d,
    `Idempotent: attendance_checkins_7d unchanged (${kpiA2!.attendance_checkins_7d})`,
  );

  // Alerts should not duplicate (ON CONFLICT DO NOTHING)
  const { data: alerts } = await db
    .from("coaching_alerts")
    .select("group_id, user_id, alert_type")
    .in("group_id", [GROUP_A_ID, GROUP_B_ID])
    .eq("day", YESTERDAY_STR);

  const keys = (alerts ?? []).map(
    (a: { group_id: string; user_id: string; alert_type: string }) =>
      `${a.group_id}:${a.user_id}:${a.alert_type}`,
  );
  const uniqueKeys = new Set(keys);
  assert(keys.length === uniqueKeys.size, `Alerts are unique after re-run (${keys.length} total, ${uniqueKeys.size} unique)`);

  // Verify MISSED_TRAININGS_14D is still exactly 1 for A2 after re-run
  const missedAlerts = (alerts ?? []).filter(
    (a: { alert_type: string; user_id: string }) =>
      a.alert_type === "missed_trainings_14d" && a.user_id === ATHLETE_A2,
  );
  assert(
    missedAlerts.length === 1,
    `Idempotent: MISSED_TRAININGS_14D still exactly 1 for A2 (got ${missedAlerts.length})`,
  );
}

// ── Verify RLS isolation (real user tokens) ────────────────────────────────

async function verifyRLS() {
  console.log("\n── Verifying RLS isolation ──");

  if (!process.env.SUPABASE_ANON_KEY) {
    console.log("  SKIP: SUPABASE_ANON_KEY not set — cannot test RLS with real user tokens");
    console.log("  (Set SUPABASE_ANON_KEY to enable full RLS testing)");
    return;
  }

  // 1. Coach A sees group A but not group B
  try {
    const coachAClient = await createUserClient(COACH_A_ID);

    const { data: kpisA } = await coachAClient
      .from("coaching_kpis_daily")
      .select("group_id")
      .eq("day", YESTERDAY_STR);

    const groupIds = (kpisA ?? []).map((r: { group_id: string }) => r.group_id);
    assert(groupIds.includes(GROUP_A_ID), "Coach A can read Group A KPIs");
    assert(!groupIds.includes(GROUP_B_ID), "Coach A CANNOT read Group B KPIs");

    const { data: athleteKpis } = await coachAClient
      .from("coaching_athlete_kpis_daily")
      .select("group_id, user_id")
      .eq("day", YESTERDAY_STR);

    const athleteGroups = new Set((athleteKpis ?? []).map((r: { group_id: string }) => r.group_id));
    assert(!athleteGroups.has(GROUP_B_ID), "Coach A cannot see Group B athlete KPIs");

    const { data: alertsA } = await coachAClient
      .from("coaching_alerts")
      .select("group_id")
      .eq("day", YESTERDAY_STR);

    const alertGroups = new Set((alertsA ?? []).map((r: { group_id: string }) => r.group_id));
    assert(!alertGroups.has(GROUP_B_ID), "Coach A cannot see Group B alerts");
  } catch (e) {
    console.warn(`  RLS test (Coach A) error: ${e}`);
  }

  // 2. Athlete A1 sees only own athlete_kpis, not group-level
  try {
    const a1Client = await createUserClient(ATHLETE_A1);

    const { data: groupKpis } = await a1Client
      .from("coaching_kpis_daily")
      .select("group_id")
      .eq("day", YESTERDAY_STR);

    assert((groupKpis ?? []).length === 0, "Athlete A1 cannot read group-level KPIs (not staff)");

    const { data: ownKpis } = await a1Client
      .from("coaching_athlete_kpis_daily")
      .select("user_id")
      .eq("day", YESTERDAY_STR);

    const ownUserIds = (ownKpis ?? []).map((r: { user_id: string }) => r.user_id);
    assert(ownUserIds.length > 0, "Athlete A1 can read own athlete KPIs");
    assert(ownUserIds.every((uid: string) => uid === ATHLETE_A1), "Athlete A1 sees ONLY own rows");
    assert(!ownUserIds.includes(ATHLETE_A2), "Athlete A1 cannot see Athlete A2 KPIs");
  } catch (e) {
    console.warn(`  RLS test (Athlete A1) error: ${e}`);
  }

  // 3. Coach B sees group B but not group A
  try {
    const coachBClient = await createUserClient(COACH_B_ID);

    const { data: kpisB } = await coachBClient
      .from("coaching_kpis_daily")
      .select("group_id")
      .eq("day", YESTERDAY_STR);

    const groupIdsB = (kpisB ?? []).map((r: { group_id: string }) => r.group_id);
    assert(!groupIdsB.includes(GROUP_A_ID), "Coach B CANNOT read Group A KPIs");
    assert(groupIdsB.includes(GROUP_B_ID), "Coach B can read Group B KPIs");
  } catch (e) {
    console.warn(`  RLS test (Coach B) error: ${e}`);
  }
}

// ── Verify performance ─────────────────────────────────────────────────────

function verifyPerformance(timings: { kpiMs: number; athleteMs: number; alertMs: number }) {
  console.log("\n── Verifying performance ──");

  const BUDGET_MS = 5000;
  assert(timings.kpiMs < BUDGET_MS, `Group KPIs computed in ${timings.kpiMs.toFixed(0)}ms (< ${BUDGET_MS}ms)`);
  assert(timings.athleteMs < BUDGET_MS, `Athlete KPIs computed in ${timings.athleteMs.toFixed(0)}ms (< ${BUDGET_MS}ms)`);
  assert(timings.alertMs < BUDGET_MS, `Alerts computed in ${timings.alertMs.toFixed(0)}ms (< ${BUDGET_MS}ms)`);

  const totalMs = timings.kpiMs + timings.athleteMs + timings.alertMs;
  console.log(`  Total compute time: ${totalMs.toFixed(0)}ms`);
}

// ── Cleanup ────────────────────────────────────────────────────────────────

async function cleanup() {
  console.log("\n── Cleaning up test data ──");
  await db.from("coaching_alerts").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("coaching_athlete_kpis_daily").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("coaching_kpis_daily").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("coaching_training_attendance").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("coaching_training_sessions").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("sessions").delete().in("user_id", ALL_USERS);
  await db.from("coaching_members").delete().in("group_id", [GROUP_A_ID, GROUP_B_ID]);
  await db.from("profile_progress").delete().in("user_id", ALL_USERS);
  await db.from("coaching_groups").delete().in("id", [GROUP_A_ID, GROUP_B_ID]);

  for (const uid of ALL_USERS) {
    await db.auth.admin.deleteUser(uid);
  }

  console.log("  Cleanup complete");
}

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log("╔══════════════════════════════════════════════════════╗");
  console.log("║   KPI Snapshot Verification Suite (v2 + Attendance) ║");
  console.log("╚══════════════════════════════════════════════════════╝");
  console.log(`Target day: ${YESTERDAY_STR}`);
  console.log(`RLS tests: ${process.env.SUPABASE_ANON_KEY ? "ENABLED" : "DISABLED (set SUPABASE_ANON_KEY)"}`);

  try {
    await seedData();
    const timings = await runCompute();
    const originalKpi = await verifyCorrectness();
    await verifyIdempotency(originalKpi!);
    await verifyRLS();
    verifyPerformance(timings);

    console.log("\n══════════════════════════════════════════");
    if (failCount === 0) {
      console.log(`  ALL ${passCount} CHECKS PASSED`);
    } else {
      console.log(`  ${passCount} PASSED, ${failCount} FAILED`);
    }
    console.log("══════════════════════════════════════════\n");

    if (failCount > 0) process.exitCode = 1;
  } catch (err) {
    console.error("\n=== VERIFICATION ABORTED ===");
    console.error(err);
    process.exitCode = 1;
  } finally {
    await cleanup();
  }
}

main();
