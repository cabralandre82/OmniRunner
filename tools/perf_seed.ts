/**
 * perf_seed.ts
 *
 * Seeds the database with realistic volume for performance testing.
 * 100 groups × 22 users each ≈ 100k+ rows across all coaching tables.
 *
 * Usage:
 *   NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts
 *   NODE_PATH=portal/node_modules npx tsx tools/perf_seed.ts --cleanup
 */

import { createClient } from "@supabase/supabase-js";

// ── Config ──────────────────────────────────────────────────────────────────

const SUPABASE_URL =
  process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// ── Volume targets ──────────────────────────────────────────────────────────

const NUM_GROUPS = 100;
const ATHLETES_PER_GROUP = 20;
const SESSIONS_PER_GROUP = 50;
const AVG_ATTENDANCE_PER_SESSION = 15;
const KPI_DAYS = 30;
const ALERTS_PER_GROUP = 5;
const TEMPLATES_PER_GROUP = 3;
const BLOCKS_PER_TEMPLATE = 5;
const ASSIGNMENTS_PER_GROUP = 100;
const ANNOUNCEMENTS_PER_GROUP = 10;
const ANNOUNCEMENT_READ_RATE = 0.5;
const TAGS_PER_GROUP = 5;
const TAGS_PER_ATHLETE = 3;
const NOTES_PER_ATHLETE = 2;
const PLANS_PER_GROUP = 1;
const SUBSCRIPTIONS_PER_GROUP = 20;
const LEDGER_ENTRIES_PER_GROUP = 100;

const MARKER_NAME = "__PERF_SEED_MARKER__";
const BATCH_SIZE = 500;
const AUTH_CONCURRENCY = 40;
const TEST_PASSWORD = "PerfSeed-2026!";

// ── Types ───────────────────────────────────────────────────────────────────

interface GroupPlan {
  groupId: string;
  coachUserId: string;
  assistantUserId: string;
  athleteUserIds: string[];
  sessionIds: string[];
  templateIds: string[];
  announcementIds: string[];
  tagIds: string[];
  planId: string;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

function progress(label: string, current: number, total: number) {
  process.stdout.write(`\r  ${label}... ${current}/${total}  `);
  if (current >= total) process.stdout.write("\n");
}

async function batchInsert(table: string, rows: any[], label: string) {
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    const { error } = await db.from(table).insert(batch);
    if (error) {
      console.error(
        `\n  ERROR [${table}] batch ${Math.floor(i / BATCH_SIZE) + 1}: ${error.message}`
      );
      throw error;
    }
    progress(label, Math.min(i + BATCH_SIZE, rows.length), rows.length);
  }
}

async function batchUpsert(
  table: string,
  rows: any[],
  onConflict: string,
  label: string
) {
  for (let i = 0; i < rows.length; i += BATCH_SIZE) {
    const batch = rows.slice(i, i + BATCH_SIZE);
    const { error } = await db.from(table).upsert(batch, { onConflict });
    if (error) {
      console.error(
        `\n  ERROR [${table}] batch ${Math.floor(i / BATCH_SIZE) + 1}: ${error.message}`
      );
      throw error;
    }
    progress(label, Math.min(i + BATCH_SIZE, rows.length), rows.length);
  }
}

async function createAuthUsers(userIds: string[]) {
  let done = 0;
  for (let i = 0; i < userIds.length; i += AUTH_CONCURRENCY) {
    const batch = userIds.slice(i, i + AUTH_CONCURRENCY);
    await Promise.all(
      batch.map(async (uid) => {
        const email = `perf-${uid.slice(0, 8)}@perf.local`;
        const { error } = await db.auth.admin.createUser({
          id: uid,
          email,
          password: TEST_PASSWORD,
          email_confirm: true,
        });
        if (error && !error.message.includes("already")) {
          console.warn(`\n  WARN createUser ${uid.slice(0, 8)}: ${error.message}`);
        }
      })
    );
    done += batch.length;
    progress("Auth users", Math.min(done, userIds.length), userIds.length);
  }
}

function dayString(daysAgo: number): string {
  return new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);
}

function isoAgo(daysAgo: number): string {
  return new Date(Date.now() - daysAgo * 86_400_000).toISOString();
}

// ── Seed ────────────────────────────────────────────────────────────────────

async function seed() {
  console.log("=== Performance Seed ===");
  console.log(`URL:    ${SUPABASE_URL}`);
  console.log(`Target: ${NUM_GROUPS} groups, ${NUM_GROUPS * (2 + ATHLETES_PER_GROUP)} users\n`);
  const start = Date.now();

  // ── 0. Check marker ──
  const { data: marker } = await db
    .from("coaching_groups")
    .select("id")
    .eq("name", MARKER_NAME)
    .limit(1);

  if (marker && marker.length > 0) {
    console.log("Seed data already exists (marker found). Run --cleanup first.");
    return;
  }

  // ── 1. Pre-generate all IDs ──
  const groups: GroupPlan[] = [];
  const allUserIds: string[] = [];

  for (let g = 0; g < NUM_GROUPS; g++) {
    const coachUserId = crypto.randomUUID();
    const assistantUserId = crypto.randomUUID();
    const athleteUserIds = Array.from({ length: ATHLETES_PER_GROUP }, () =>
      crypto.randomUUID()
    );
    const sessionIds = Array.from({ length: SESSIONS_PER_GROUP }, () =>
      crypto.randomUUID()
    );
    const templateIds = Array.from({ length: TEMPLATES_PER_GROUP }, () =>
      crypto.randomUUID()
    );
    const announcementIds = Array.from({ length: ANNOUNCEMENTS_PER_GROUP }, () =>
      crypto.randomUUID()
    );
    const tagIds = Array.from({ length: TAGS_PER_GROUP }, () =>
      crypto.randomUUID()
    );

    groups.push({
      groupId: crypto.randomUUID(),
      coachUserId,
      assistantUserId,
      athleteUserIds,
      sessionIds,
      templateIds,
      announcementIds,
      tagIds,
      planId: crypto.randomUUID(),
    });

    allUserIds.push(coachUserId, assistantUserId, ...athleteUserIds);
  }

  // ── 2. Auth users (triggers profile creation) ──
  console.log(`  [1/18] Auth users (${allUserIds.length})`);
  await createAuthUsers(allUserIds);

  // ── 3. Upsert profiles with display names ──
  console.log(`  [2/18] Profiles`);
  const profiles: any[] = [];
  for (let g = 0; g < groups.length; g++) {
    const gp = groups[g];
    const gn = String(g + 1).padStart(3, "0");
    profiles.push({
      id: gp.coachUserId,
      display_name: `Coach ${gn}`,
      email: `perf-${gp.coachUserId.slice(0, 8)}@perf.local`,
    });
    profiles.push({
      id: gp.assistantUserId,
      display_name: `Asst ${gn}`,
      email: `perf-${gp.assistantUserId.slice(0, 8)}@perf.local`,
    });
    for (let a = 0; a < gp.athleteUserIds.length; a++) {
      profiles.push({
        id: gp.athleteUserIds[a],
        display_name: `Athlete ${gn}-${String(a + 1).padStart(2, "0")}`,
        email: `perf-${gp.athleteUserIds[a].slice(0, 8)}@perf.local`,
      });
    }
  }
  await batchUpsert("profiles", profiles, "id", "Profiles");

  // ── 4. Groups (includes marker) ──
  console.log(`  [3/18] Groups`);
  const groupRows = [
    {
      id: crypto.randomUUID(),
      name: MARKER_NAME,
      coach_user_id: groups[0].coachUserId,
      created_at_ms: Date.now(),
    },
    ...groups.map((gp, i) => ({
      id: gp.groupId,
      name: `Perf Group ${String(i + 1).padStart(3, "0")}`,
      coach_user_id: gp.coachUserId,
      created_at_ms: Date.now() - (NUM_GROUPS - i) * 86_400_000,
    })),
  ];
  await batchInsert("coaching_groups", groupRows, "Groups");

  // ── 5. Members ──
  console.log(`  [4/18] Members`);
  const memberRows: any[] = [];
  for (const gp of groups) {
    memberRows.push({
      user_id: gp.coachUserId,
      group_id: gp.groupId,
      display_name: "Coach",
      role: "admin_master",
      joined_at_ms: Date.now(),
    });
    memberRows.push({
      user_id: gp.assistantUserId,
      group_id: gp.groupId,
      display_name: "Assistant",
      role: "assistant",
      joined_at_ms: Date.now(),
    });
    for (let a = 0; a < gp.athleteUserIds.length; a++) {
      memberRows.push({
        user_id: gp.athleteUserIds[a],
        group_id: gp.groupId,
        display_name: `Athlete ${a + 1}`,
        role: "athlete",
        joined_at_ms: Date.now(),
      });
    }
  }
  await batchInsert("coaching_members", memberRows, "Members");

  // ── 6. Training sessions ──
  const totalSessions = NUM_GROUPS * SESSIONS_PER_GROUP;
  console.log(`  [5/18] Training sessions (${totalSessions})`);
  const sessionRows: any[] = [];
  const sessionStatuses = ["scheduled", "done", "cancelled"];
  for (const gp of groups) {
    for (let s = 0; s < SESSIONS_PER_GROUP; s++) {
      const daysAgo = Math.floor((s * 60) / SESSIONS_PER_GROUP);
      sessionRows.push({
        id: gp.sessionIds[s],
        group_id: gp.groupId,
        created_by: gp.coachUserId,
        title: `Session ${s + 1}`,
        starts_at: isoAgo(daysAgo),
        status: s < SESSIONS_PER_GROUP - 5 ? "done" : sessionStatuses[s % 3],
      });
    }
  }
  await batchInsert("coaching_training_sessions", sessionRows, "Sessions");

  // ── 7. Attendance ──
  const estAttendance = NUM_GROUPS * SESSIONS_PER_GROUP * AVG_ATTENDANCE_PER_SESSION;
  console.log(`  [6/18] Attendance (~${estAttendance})`);
  const attendanceRows: any[] = [];
  for (const gp of groups) {
    for (let s = 0; s < SESSIONS_PER_GROUP; s++) {
      const daysAgo = Math.floor((s * 60) / SESSIONS_PER_GROUP);
      const shuffled = [...gp.athleteUserIds].sort(() => Math.random() - 0.5);
      const attendees = shuffled.slice(0, AVG_ATTENDANCE_PER_SESSION);
      for (const athleteId of attendees) {
        attendanceRows.push({
          id: crypto.randomUUID(),
          group_id: gp.groupId,
          session_id: gp.sessionIds[s],
          athlete_user_id: athleteId,
          checked_by: gp.coachUserId,
          checked_at: isoAgo(daysAgo),
          status: "present",
          method: Math.random() > 0.5 ? "qr" : "manual",
        });
      }
    }
  }
  await batchInsert("coaching_training_attendance", attendanceRows, "Attendance");

  // ── 8. KPIs daily ──
  const totalKpis = NUM_GROUPS * KPI_DAYS;
  console.log(`  [7/18] KPIs daily (${totalKpis})`);
  const kpiRows: any[] = [];
  for (const gp of groups) {
    for (let d = 0; d < KPI_DAYS; d++) {
      kpiRows.push({
        id: crypto.randomUUID(),
        group_id: gp.groupId,
        day: dayString(d),
        active_users_1d: Math.floor(Math.random() * ATHLETES_PER_GROUP),
        score: +(Math.random() * 100).toFixed(1),
      });
    }
  }
  await batchInsert("coaching_kpis_daily", kpiRows, "KPIs");

  // ── 9. Athlete KPIs daily ──
  const totalAthleteKpis = NUM_GROUPS * ATHLETES_PER_GROUP * KPI_DAYS;
  console.log(`  [8/18] Athlete KPIs daily (${totalAthleteKpis})`);
  const athleteKpiRows: any[] = [];
  for (const gp of groups) {
    for (const athleteId of gp.athleteUserIds) {
      for (let d = 0; d < KPI_DAYS; d++) {
        athleteKpiRows.push({
          id: crypto.randomUUID(),
          group_id: gp.groupId,
          user_id: athleteId,
          day: dayString(d),
          score: Math.round(Math.random() * 100),
          sessions_7d: Math.floor(Math.random() * 7),
        });
      }
    }
  }
  await batchInsert("coaching_athlete_kpis_daily", athleteKpiRows, "Athlete KPIs");

  // ── 10. Alerts ──
  const totalAlerts = NUM_GROUPS * ALERTS_PER_GROUP;
  console.log(`  [9/18] Alerts (${totalAlerts})`);
  const alertTypes = ["churn_risk", "low_attendance", "no_workout", "payment_overdue", "milestone"];
  const severities = ["info", "warning", "critical"];
  const alertRows: any[] = [];
  for (const gp of groups) {
    for (let a = 0; a < ALERTS_PER_GROUP; a++) {
      alertRows.push({
        id: crypto.randomUUID(),
        group_id: gp.groupId,
        user_id: gp.athleteUserIds[a % ATHLETES_PER_GROUP],
        day: dayString(a),
        alert_type: alertTypes[a % alertTypes.length],
        severity: severities[a % severities.length],
        resolved: a > 2,
      });
    }
  }
  await batchInsert("coaching_alerts", alertRows, "Alerts");

  // ── 11. Workout templates ──
  const totalTemplates = NUM_GROUPS * TEMPLATES_PER_GROUP;
  console.log(`  [10/18] Workout templates (${totalTemplates})`);
  const templateRows: any[] = [];
  for (const gp of groups) {
    for (let t = 0; t < TEMPLATES_PER_GROUP; t++) {
      templateRows.push({
        id: gp.templateIds[t],
        group_id: gp.groupId,
        name: `Template ${t + 1}`,
        created_by: gp.coachUserId,
      });
    }
  }
  await batchInsert("coaching_workout_templates", templateRows, "Templates");

  // ── 12. Workout blocks ──
  const totalBlocks = totalTemplates * BLOCKS_PER_TEMPLATE;
  console.log(`  [11/18] Workout blocks (${totalBlocks})`);
  const blockTypes = ["warmup", "main", "cooldown", "interval", "recovery"];
  const blockRows: any[] = [];
  for (const gp of groups) {
    for (let t = 0; t < TEMPLATES_PER_GROUP; t++) {
      for (let b = 0; b < BLOCKS_PER_TEMPLATE; b++) {
        blockRows.push({
          id: crypto.randomUUID(),
          template_id: gp.templateIds[t],
          order_index: b,
          block_type: blockTypes[b % blockTypes.length],
          duration_seconds: 300 + b * 120,
        });
      }
    }
  }
  await batchInsert("coaching_workout_blocks", blockRows, "Blocks");

  // ── 13. Workout assignments ──
  // Unique constraint: (athlete_user_id, scheduled_date)
  const totalAssignments = NUM_GROUPS * ASSIGNMENTS_PER_GROUP;
  console.log(`  [12/18] Workout assignments (${totalAssignments})`);
  const assignmentRows: any[] = [];
  for (const gp of groups) {
    for (let a = 0; a < ASSIGNMENTS_PER_GROUP; a++) {
      const athleteIdx = a % ATHLETES_PER_GROUP;
      const dateOffset = Math.floor(a / ATHLETES_PER_GROUP);
      assignmentRows.push({
        id: crypto.randomUUID(),
        group_id: gp.groupId,
        athlete_user_id: gp.athleteUserIds[athleteIdx],
        template_id: gp.templateIds[a % TEMPLATES_PER_GROUP],
        scheduled_date: dayString(dateOffset),
        status: a < 70 ? "completed" : "pending",
        created_by: gp.coachUserId,
      });
    }
  }
  await batchInsert("coaching_workout_assignments", assignmentRows, "Assignments");

  // ── 14. Workout executions ──
  const completedAssignments = assignmentRows.filter((a) => a.status === "completed");
  console.log(`  [13/18] Workout executions (${completedAssignments.length})`);
  const executionRows: any[] = [];
  for (const assignment of completedAssignments) {
    executionRows.push({
      id: crypto.randomUUID(),
      assignment_id: assignment.id,
      athlete_user_id: assignment.athlete_user_id,
      actual_duration: 1800 + Math.floor(Math.random() * 3600),
      actual_distance: 3000 + Math.floor(Math.random() * 12000),
      avg_pace: 240 + Math.floor(Math.random() * 120),
      avg_hr: 130 + Math.floor(Math.random() * 40),
      source: Math.random() > 0.5 ? "manual" : "garmin",
      completed_at: new Date().toISOString(),
    });
  }
  await batchInsert("coaching_workout_executions", executionRows, "Executions");

  // ── 15. Announcements ──
  const totalAnn = NUM_GROUPS * ANNOUNCEMENTS_PER_GROUP;
  console.log(`  [14/18] Announcements (${totalAnn})`);
  const announcementRows: any[] = [];
  for (const gp of groups) {
    for (let a = 0; a < ANNOUNCEMENTS_PER_GROUP; a++) {
      announcementRows.push({
        id: gp.announcementIds[a],
        group_id: gp.groupId,
        created_by: gp.coachUserId,
        title: `Announcement ${a + 1}`,
        body: `Performance test announcement body #${a + 1}.`,
        pinned: a === 0,
      });
    }
  }
  await batchInsert("coaching_announcements", announcementRows, "Announcements");

  // ── 16. Announcement reads (~50% rate) ──
  console.log(`  [15/18] Announcement reads`);
  const readRows: any[] = [];
  for (const gp of groups) {
    for (const annId of gp.announcementIds) {
      for (const athleteId of gp.athleteUserIds) {
        if (Math.random() < ANNOUNCEMENT_READ_RATE) {
          readRows.push({
            announcement_id: annId,
            user_id: athleteId,
          });
        }
      }
    }
  }
  await batchInsert("coaching_announcement_reads", readRows, "Announcement reads");

  // ── 17. Tags + athlete tags ──
  const totalTags = NUM_GROUPS * TAGS_PER_GROUP;
  console.log(`  [16/18] Tags (${totalTags}) + athlete tags`);
  const tagNames = ["Beginner", "Intermediate", "Advanced", "Injured", "VIP"];
  const tagColors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#FFA07A", "#98D8C8"];
  const tagRows: any[] = [];
  for (const gp of groups) {
    for (let t = 0; t < TAGS_PER_GROUP; t++) {
      tagRows.push({
        id: gp.tagIds[t],
        group_id: gp.groupId,
        name: tagNames[t],
        color: tagColors[t],
      });
    }
  }
  await batchInsert("coaching_tags", tagRows, "Tags");

  const athleteTagRows: any[] = [];
  for (const gp of groups) {
    for (const athleteId of gp.athleteUserIds) {
      const picked = [...gp.tagIds]
        .sort(() => Math.random() - 0.5)
        .slice(0, TAGS_PER_ATHLETE);
      for (const tagId of picked) {
        athleteTagRows.push({
          id: crypto.randomUUID(),
          group_id: gp.groupId,
          athlete_user_id: athleteId,
          tag_id: tagId,
        });
      }
    }
  }
  await batchInsert("coaching_athlete_tags", athleteTagRows, "Athlete tags");

  // ── 18. Athlete notes ──
  const totalNotes = NUM_GROUPS * ATHLETES_PER_GROUP * NOTES_PER_ATHLETE;
  console.log(`  [17/18] Athlete notes (${totalNotes}) + member status`);
  const noteRows: any[] = [];
  for (const gp of groups) {
    for (const athleteId of gp.athleteUserIds) {
      for (let n = 0; n < NOTES_PER_ATHLETE; n++) {
        noteRows.push({
          id: crypto.randomUUID(),
          group_id: gp.groupId,
          athlete_user_id: athleteId,
          created_by: gp.coachUserId,
          note: `Performance note ${n + 1} for athlete.`,
        });
      }
    }
  }
  await batchInsert("coaching_athlete_notes", noteRows, "Notes");

  // Member status
  const statusValues = ["active", "paused", "inactive"];
  const memberStatusRows: any[] = [];
  for (const gp of groups) {
    for (let a = 0; a < gp.athleteUserIds.length; a++) {
      memberStatusRows.push({
        group_id: gp.groupId,
        user_id: gp.athleteUserIds[a],
        status: statusValues[a % statusValues.length],
      });
    }
  }
  await batchUpsert(
    "coaching_member_status",
    memberStatusRows,
    "group_id,user_id",
    "Member status"
  );

  // ── 19. Plans, subscriptions, ledger ──
  console.log(`  [18/18] Plans, subscriptions, ledger`);
  const planRows: any[] = [];
  for (const gp of groups) {
    planRows.push({
      id: gp.planId,
      group_id: gp.groupId,
      name: "Standard Plan",
      monthly_price: 99.9,
      billing_cycle: "monthly",
      created_by: gp.coachUserId,
    });
  }
  await batchInsert("coaching_plans", planRows, "Plans");

  const subRows: any[] = [];
  for (const gp of groups) {
    for (let a = 0; a < SUBSCRIPTIONS_PER_GROUP; a++) {
      subRows.push({
        id: crypto.randomUUID(),
        group_id: gp.groupId,
        athlete_user_id: gp.athleteUserIds[a],
        plan_id: gp.planId,
        status: a < 15 ? "active" : "paused",
      });
    }
  }
  await batchInsert("coaching_subscriptions", subRows, "Subscriptions");

  const ledgerTypes = ["revenue", "expense"];
  const ledgerCategories = ["mensalidade", "evento", "material", "other"];
  const ledgerRows: any[] = [];
  for (const gp of groups) {
    for (let l = 0; l < LEDGER_ENTRIES_PER_GROUP; l++) {
      ledgerRows.push({
        id: crypto.randomUUID(),
        group_id: gp.groupId,
        type: ledgerTypes[l % 2],
        category: ledgerCategories[l % ledgerCategories.length],
        amount: +(50 + Math.random() * 200).toFixed(2),
        description: `Ledger entry ${l + 1}`,
        date: dayString(l % 30),
        created_by: gp.coachUserId,
      });
    }
  }
  await batchInsert("coaching_financial_ledger", ledgerRows, "Ledger");

  // ── Summary ──
  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`\n=== Done in ${elapsed}s ===\n`);
  console.log("Seeded volumes:");
  console.log(`  Groups:            ${NUM_GROUPS}`);
  console.log(`  Auth users:        ${allUserIds.length}`);
  console.log(`  Members:           ${memberRows.length}`);
  console.log(`  Sessions:          ${sessionRows.length}`);
  console.log(`  Attendance:        ${attendanceRows.length}`);
  console.log(`  KPIs daily:        ${kpiRows.length}`);
  console.log(`  Athlete KPIs:      ${athleteKpiRows.length}`);
  console.log(`  Alerts:            ${alertRows.length}`);
  console.log(`  Templates:         ${templateRows.length}`);
  console.log(`  Blocks:            ${blockRows.length}`);
  console.log(`  Assignments:       ${assignmentRows.length}`);
  console.log(`  Executions:        ${executionRows.length}`);
  console.log(`  Announcements:     ${announcementRows.length}`);
  console.log(`  Announcement reads:${readRows.length}`);
  console.log(`  Tags:              ${tagRows.length}`);
  console.log(`  Athlete tags:      ${athleteTagRows.length}`);
  console.log(`  Notes:             ${noteRows.length}`);
  console.log(`  Member statuses:   ${memberStatusRows.length}`);
  console.log(`  Plans:             ${planRows.length}`);
  console.log(`  Subscriptions:     ${subRows.length}`);
  console.log(`  Ledger entries:    ${ledgerRows.length}`);
}

// ── Cleanup ─────────────────────────────────────────────────────────────────

async function cleanup() {
  console.log("=== Performance Seed Cleanup ===");
  console.log(`URL: ${SUPABASE_URL}\n`);
  const start = Date.now();

  // Find all perf-seed groups (marker + Perf Group NNN)
  const { data: perfGroups } = await db
    .from("coaching_groups")
    .select("id")
    .or(`name.eq.${MARKER_NAME},name.like.Perf Group %`);

  if (!perfGroups || perfGroups.length === 0) {
    console.log("  No seed data found.");
    return;
  }

  const groupIds = perfGroups.map((g: any) => g.id);
  console.log(`  Found ${groupIds.length} groups to clean up`);

  // Gather member user IDs for auth cleanup
  const allUserIds: string[] = [];
  for (let i = 0; i < groupIds.length; i += BATCH_SIZE) {
    const batch = groupIds.slice(i, i + BATCH_SIZE);
    const { data } = await db
      .from("coaching_members")
      .select("user_id")
      .in("group_id", batch);
    if (data) allUserIds.push(...data.map((m: any) => m.user_id));
  }
  const uniqueUserIds = [...new Set(allUserIds)];
  console.log(`  Found ${uniqueUserIds.length} auth users to clean up`);

  // Gather template IDs for block cleanup (FK to template_id, not group_id)
  const templateIds: string[] = [];
  for (let i = 0; i < groupIds.length; i += BATCH_SIZE) {
    const batch = groupIds.slice(i, i + BATCH_SIZE);
    const { data } = await db
      .from("coaching_workout_templates")
      .select("id")
      .in("group_id", batch);
    if (data) templateIds.push(...data.map((t: any) => t.id));
  }

  // Gather announcement IDs for reads cleanup (FK to announcement_id)
  const annIds: string[] = [];
  for (let i = 0; i < groupIds.length; i += BATCH_SIZE) {
    const batch = groupIds.slice(i, i + BATCH_SIZE);
    const { data } = await db
      .from("coaching_announcements")
      .select("id")
      .in("group_id", batch);
    if (data) annIds.push(...data.map((a: any) => a.id));
  }

  // Delete workout blocks by template_id
  for (let i = 0; i < templateIds.length; i += BATCH_SIZE) {
    await db
      .from("coaching_workout_blocks")
      .delete()
      .in("template_id", templateIds.slice(i, i + BATCH_SIZE));
  }
  console.log("  Cleaned coaching_workout_blocks");

  // Delete announcement reads by announcement_id
  for (let i = 0; i < annIds.length; i += BATCH_SIZE) {
    await db
      .from("coaching_announcement_reads")
      .delete()
      .in("announcement_id", annIds.slice(i, i + BATCH_SIZE));
  }
  console.log("  Cleaned coaching_announcement_reads");

  // Delete remaining tables by group_id (dependency order: children first)
  const groupIdTables = [
    "coaching_workout_executions",
    "coaching_workout_assignments",
    "coaching_workout_templates",
    "coaching_subscriptions",
    "coaching_financial_ledger",
    "coaching_plans",
    "coaching_announcements",
    "coaching_athlete_notes",
    "coaching_athlete_tags",
    "coaching_tags",
    "coaching_member_status",
    "coaching_training_attendance",
    "coaching_training_sessions",
    "coaching_kpis_daily",
    "coaching_athlete_kpis_daily",
    "coaching_alerts",
    "coaching_device_links",
    "coaching_members",
  ];

  for (const table of groupIdTables) {
    for (let i = 0; i < groupIds.length; i += BATCH_SIZE) {
      const batch = groupIds.slice(i, i + BATCH_SIZE);
      await db.from(table).delete().in("group_id", batch);
    }
    console.log(`  Cleaned ${table}`);
  }

  // Delete groups by id
  for (let i = 0; i < groupIds.length; i += BATCH_SIZE) {
    await db
      .from("coaching_groups")
      .delete()
      .in("id", groupIds.slice(i, i + BATCH_SIZE));
  }
  console.log("  Cleaned coaching_groups");

  // Delete auth users
  console.log(`  Deleting ${uniqueUserIds.length} auth users...`);
  let deleted = 0;
  for (let i = 0; i < uniqueUserIds.length; i += AUTH_CONCURRENCY) {
    const batch = uniqueUserIds.slice(i, i + AUTH_CONCURRENCY);
    await Promise.all(
      batch.map((uid) => db.auth.admin.deleteUser(uid).catch(() => {}))
    );
    deleted += batch.length;
    progress(
      "Auth users",
      Math.min(deleted, uniqueUserIds.length),
      uniqueUserIds.length
    );
  }

  const elapsed = ((Date.now() - start) / 1000).toFixed(1);
  console.log(`\n=== Cleanup done in ${elapsed}s ===`);
}

// ── Preflight ───────────────────────────────────────────────────────────────

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

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const alive = await preflight();
  if (!alive) {
    console.error(`ERROR: Cannot reach Supabase at ${SUPABASE_URL}`);
    console.error("Start local Supabase first:  supabase start");
    process.exit(2);
  }

  const arg = process.argv[2];
  if (arg === "--cleanup") {
    await cleanup();
  } else {
    await seed();
  }
}

main().catch((err) => {
  console.error("\nFATAL:", err);
  process.exit(1);
});
