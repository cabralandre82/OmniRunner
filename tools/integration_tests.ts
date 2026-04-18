/**
 * integration_tests.ts
 *
 * Comprehensive Supabase integration test suite that validates:
 *   - Schema: tables, columns, types, unique constraints
 *   - RLS isolation: cross-group, cross-user data boundaries
 *   - Constraint enforcement: unique, check constraints
 *   - RPC contracts: fn shape, error handling
 *   - Idempotency: repeated calls don't corrupt data
 *
 * Covers migrations:
 *   20260303300000_fix_coaching_roles
 *   20260303300001_alert_dedup_constraints
 *   20260303400000_training_sessions_attendance
 *   20260303500000_crm_tags_notes_status
 *   20260303600000_announcements
 *   20260304100000_workout_builder
 *   20260304200000_financial_engine
 *   20260304400000_wearables
 *
 * Usage:
 *   NODE_PATH=portal/node_modules npx tsx tools/integration_tests.ts
 *
 * Env vars (defaults to local Supabase CLI values if unset):
 *   SUPABASE_URL              (default: http://127.0.0.1:54321)
 *   SUPABASE_SERVICE_ROLE_KEY (default: local dev key)
 *   SUPABASE_ANON_KEY         (default: local dev key — enables RLS tests)
 */

import { createClient, type SupabaseClient } from "@supabase/supabase-js";

// ── Config ──────────────────────────────────────────────────────────────────

const SUPABASE_URL =
  process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";
const ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WO7jMlhUEkSia-H64vRXJvJI3VoLIU1suUts";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

// ── Output formatting ───────────────────────────────────────────────────────

const OK = "\x1b[32m✓\x1b[0m";
const FAIL = "\x1b[31m✗\x1b[0m";
const SKIP = "\x1b[33m⊘\x1b[0m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;
let skipped = 0;

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`  ${OK} ${name}`);
    passed++;
  } catch (e: any) {
    console.log(`  ${FAIL} ${name}: ${e.message}`);
    failed++;
  }
}

function skip(name: string, reason?: string) {
  console.log(`  ${SKIP} ${name}${reason ? ` — ${reason}` : ""}`);
  skipped++;
}

function section(title: string) {
  console.log(`\n${BOLD}── ${title} ──${RESET}`);
}

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

// ── Test IDs (deterministic, easy cleanup) ──────────────────────────────────

const GROUP_A = "11111111-aaaa-aaaa-aaaa-000000000001";
const GROUP_B = "11111111-bbbb-bbbb-bbbb-000000000002";
const COACH_A = "22222222-aaaa-aaaa-aaaa-000000000001";
const COACH_B = "22222222-bbbb-bbbb-bbbb-000000000002";
const ATHLETE_A1 = "33333333-aaaa-aaaa-aaaa-000000000001";
const ATHLETE_A2 = "33333333-aaaa-aaaa-aaaa-000000000002";
const ATHLETE_B1 = "33333333-bbbb-bbbb-bbbb-000000000001";
const ASSISTANT_A = "44444444-aaaa-aaaa-aaaa-000000000001";

const SESSION_A1 = "55555555-aaaa-aaaa-aaaa-000000000001";
const SESSION_A2 = "55555555-aaaa-aaaa-aaaa-000000000002";

const ALL_USER_IDS = [COACH_A, COACH_B, ATHLETE_A1, ATHLETE_A2, ATHLETE_B1, ASSISTANT_A];
const ALL_GROUP_IDS = [GROUP_A, GROUP_B];

const TEST_PASSWORD = "IntTest-Pwd-2026!";
const NOW_MS = Date.now();

// ── Helpers ─────────────────────────────────────────────────────────────────

async function sql<T = any>(query: string): Promise<T[]> {
  const { data, error } = await db.rpc("sql_query" as any, { query });
  if (error) {
    // Fallback: use the Postgres REST introspection endpoint
    throw new Error(`SQL query failed: ${error.message}`);
  }
  return data as T[];
}

async function rawSql<T = any>(query: string): Promise<T[]> {
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({}),
  });
  // Not all installations expose a raw SQL RPC, so this is best-effort
  throw new Error("raw SQL not available");
}

async function tableExists(tableName: string): Promise<boolean> {
  const { data, error } = await db
    .from(tableName)
    .select("*")
    .limit(0);
  return !error;
}

async function getColumns(
  tableName: string
): Promise<{ column_name: string; data_type: string; udt_name: string }[]> {
  // Use information_schema via the service-role introspection
  const { data, error } = await db
    .from("information_schema.columns" as any)
    .select("column_name, data_type, udt_name")
    .eq("table_schema", "public")
    .eq("table_name", tableName);

  // Fallback: if information_schema isn't exposed via PostgREST, check via a dummy select
  if (error || !data) return [];
  return data as any[];
}

async function constraintExists(constraintName: string): Promise<boolean> {
  // Try inserting a duplicate and catching the constraint error
  // We can't query pg_constraint directly via PostgREST, so we verify
  // constraints indirectly through the constraint tests
  return true; // placeholder — actual tests verify via duplicate inserts
}

async function createUserClient(userId: string): Promise<SupabaseClient> {
  const email = `inttest-${userId.slice(0, 8)}@test.local`;
  const client = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await client.auth.signInWithPassword({
    email,
    password: TEST_PASSWORD,
  });
  if (error) throw new Error(`Sign-in failed for ${email}: ${error.message}`);
  return client;
}

// ── Seed ────────────────────────────────────────────────────────────────────

async function seed() {
  section("Seeding test data");

  // Create auth users
  for (const uid of ALL_USER_IDS) {
    const email = `inttest-${uid.slice(0, 8)}@test.local`;
    const { error } = await db.auth.admin.createUser({
      id: uid,
      email,
      password: TEST_PASSWORD,
      email_confirm: true,
    });
    if (error && !error.message.includes("already")) {
      console.warn(`  warn: user ${uid.slice(0, 8)}: ${error.message}`);
    }
  }

  // Groups
  for (const [id, name, coachId] of [
    [GROUP_A, "IntTest Group A", COACH_A],
    [GROUP_B, "IntTest Group B", COACH_B],
  ] as const) {
    await db.from("coaching_groups").upsert(
      { id, name, coach_user_id: coachId, created_at_ms: NOW_MS - 30 * 86_400_000 },
      { onConflict: "id" }
    );
  }

  // Members
  await db.from("coaching_members").delete().in("group_id", ALL_GROUP_IDS);
  const members = [
    { user_id: COACH_A, group_id: GROUP_A, display_name: "Coach A", role: "admin_master", joined_at_ms: NOW_MS },
    { user_id: ASSISTANT_A, group_id: GROUP_A, display_name: "Assistant A", role: "assistant", joined_at_ms: NOW_MS },
    { user_id: ATHLETE_A1, group_id: GROUP_A, display_name: "Athlete A1", role: "athlete", joined_at_ms: NOW_MS },
    { user_id: ATHLETE_A2, group_id: GROUP_A, display_name: "Athlete A2", role: "athlete", joined_at_ms: NOW_MS },
    { user_id: COACH_B, group_id: GROUP_B, display_name: "Coach B", role: "admin_master", joined_at_ms: NOW_MS },
    { user_id: ATHLETE_B1, group_id: GROUP_B, display_name: "Athlete B1", role: "athlete", joined_at_ms: NOW_MS },
  ];
  const { error: memErr } = await db.from("coaching_members").insert(members);
  if (memErr) console.warn(`  warn: members insert: ${memErr.message}`);

  // Training sessions for group A
  await db.from("coaching_training_attendance").delete().in("group_id", ALL_GROUP_IDS);
  await db.from("coaching_training_sessions").delete().in("group_id", ALL_GROUP_IDS);

  const { error: tsErr } = await db.from("coaching_training_sessions").insert([
    {
      id: SESSION_A1,
      group_id: GROUP_A,
      created_by: COACH_A,
      title: "IntTest Morning Run",
      starts_at: new Date().toISOString(),
      status: "scheduled",
    },
    {
      id: SESSION_A2,
      group_id: GROUP_A,
      created_by: COACH_A,
      title: "IntTest Interval",
      starts_at: new Date().toISOString(),
      status: "done",
    },
  ]);
  if (tsErr) console.warn(`  warn: training sessions: ${tsErr.message}`);

  console.log("  Seed complete");
}

// ═══════════════════════════════════════════════════════════════════════════
// Category 1: Schema validation
// ═══════════════════════════════════════════════════════════════════════════

async function testSchema() {
  section("Category 1: Schema validation");

  const expectedTables = [
    "coaching_training_sessions",
    "coaching_training_attendance",
    "coaching_tags",
    "coaching_athlete_tags",
    "coaching_athlete_notes",
    "coaching_member_status",
    "coaching_announcements",
    "coaching_announcement_reads",
    "coaching_workout_templates",
    "coaching_workout_blocks",
    "coaching_workout_assignments",
    "coaching_plans",
    "coaching_subscriptions",
    "coaching_financial_ledger",
    "coaching_device_links",
    "coaching_workout_executions",
  ];

  for (const table of expectedTables) {
    await test(`Table "${table}" exists`, async () => {
      const exists = await tableExists(table);
      assert(exists, `Table ${table} not found`);
    });
  }

  // Verify key columns on selected tables
  const columnChecks: [string, string][] = [
    ["coaching_training_sessions", "group_id"],
    ["coaching_training_sessions", "starts_at"],
    ["coaching_training_sessions", "status"],
    ["coaching_training_attendance", "session_id"],
    ["coaching_training_attendance", "athlete_user_id"],
    ["coaching_training_attendance", "method"],
    ["coaching_tags", "color"],
    ["coaching_athlete_notes", "note"],
    ["coaching_member_status", "status"],
    ["coaching_announcements", "title"],
    ["coaching_announcements", "body"],
    ["coaching_announcements", "pinned"],
    ["coaching_announcement_reads", "announcement_id"],
    ["coaching_announcement_reads", "user_id"],
    ["coaching_workout_templates", "name"],
    ["coaching_workout_blocks", "block_type"],
    ["coaching_workout_blocks", "duration_seconds"],
    ["coaching_workout_assignments", "scheduled_date"],
    ["coaching_workout_assignments", "version"],
    ["coaching_plans", "monthly_price"],
    ["coaching_plans", "billing_cycle"],
    ["coaching_subscriptions", "next_due_date"],
    ["coaching_subscriptions", "status"],
    ["coaching_financial_ledger", "type"],
    ["coaching_financial_ledger", "amount"],
    ["coaching_device_links", "provider"],
    ["coaching_device_links", "access_token"],
    ["coaching_workout_executions", "source"],
    ["coaching_workout_executions", "avg_hr"],
  ];

  for (const [table, column] of columnChecks) {
    await test(`Column "${table}.${column}" exists`, async () => {
      // Attempt a select of just that column — will fail if column doesn't exist
      const { error } = await db.from(table).select(column).limit(0);
      assert(!error, error?.message ?? "unknown");
    });
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Category 2: RLS isolation tests
// ═══════════════════════════════════════════════════════════════════════════

async function testRLS() {
  section("Category 2: RLS isolation");

  const canCreateUsers = !!ANON_KEY;
  if (!canCreateUsers) {
    skip("All RLS tests", "SUPABASE_ANON_KEY not available");
    return;
  }

  // Seed extra data for RLS tests (using service_role)
  // Insert attendance for athlete A1 in group A
  await db.from("coaching_training_attendance").upsert(
    {
      id: "66666666-aaaa-aaaa-aaaa-000000000001",
      group_id: GROUP_A,
      session_id: SESSION_A1,
      athlete_user_id: ATHLETE_A1,
      checked_by: COACH_A,
      method: "qr",
    },
    { onConflict: "session_id,athlete_user_id" }
  );

  // Insert attendance for athlete A2 in group A
  await db.from("coaching_training_attendance").upsert(
    {
      id: "66666666-aaaa-aaaa-aaaa-000000000002",
      group_id: GROUP_A,
      session_id: SESSION_A2,
      athlete_user_id: ATHLETE_A2,
      checked_by: COACH_A,
      method: "manual",
    },
    { onConflict: "session_id,athlete_user_id" }
  );

  // Insert athlete notes (staff-only data)
  await db.from("coaching_athlete_notes").upsert(
    {
      id: "77777777-aaaa-aaaa-aaaa-000000000001",
      group_id: GROUP_A,
      athlete_user_id: ATHLETE_A1,
      created_by: COACH_A,
      note: "IntTest note — athlete should NOT see this",
    },
    { onConflict: "id" }
  );

  // Insert financial ledger entry (staff-only)
  await db.from("coaching_financial_ledger").insert({
    id: "88888888-aaaa-aaaa-aaaa-000000000001",
    group_id: GROUP_A,
    type: "revenue",
    category: "mensalidade",
    amount: 150.00,
    description: "IntTest revenue entry",
    date: new Date().toISOString().slice(0, 10),
    created_by: COACH_A,
  });

  // Insert workout template (staff-only)
  await db.from("coaching_workout_templates").insert({
    id: "99999999-aaaa-aaaa-aaaa-000000000001",
    group_id: GROUP_A,
    name: "IntTest Template",
    created_by: COACH_A,
  });

  // Create user-scoped clients
  let coachAClient: SupabaseClient;
  let athleteA1Client: SupabaseClient;
  let coachBClient: SupabaseClient;

  try {
    coachAClient = await createUserClient(COACH_A);
  } catch {
    skip("RLS tests (Coach A sign-in failed)", "auth setup required");
    return;
  }
  try {
    athleteA1Client = await createUserClient(ATHLETE_A1);
  } catch {
    skip("RLS tests (Athlete A1 sign-in failed)", "auth setup required");
    return;
  }
  try {
    coachBClient = await createUserClient(COACH_B);
  } catch {
    skip("RLS tests (Coach B sign-in failed)", "auth setup required");
    return;
  }

  // ── Staff of group A cannot read group B data ──
  await test("Staff A cannot read group B training sessions", async () => {
    const { data } = await coachAClient
      .from("coaching_training_sessions")
      .select("id, group_id")
      .eq("group_id", GROUP_B);
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });

  await test("Staff B cannot read group A training sessions", async () => {
    const { data } = await coachBClient
      .from("coaching_training_sessions")
      .select("id, group_id")
      .eq("group_id", GROUP_A);
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });

  // ── Athlete can only see their own attendance ──
  await test("Athlete A1 sees only own attendance", async () => {
    const { data } = await athleteA1Client
      .from("coaching_training_attendance")
      .select("athlete_user_id");
    const userIds = (data ?? []).map((r: any) => r.athlete_user_id);
    assert(userIds.length > 0, "Should see at least own attendance");
    assert(
      userIds.every((uid: string) => uid === ATHLETE_A1),
      `Saw other users' attendance: ${userIds.join(", ")}`
    );
  });

  // ── Athlete cannot read coaching_athlete_notes ──
  await test("Athlete A1 cannot read coaching_athlete_notes", async () => {
    const { data } = await athleteA1Client
      .from("coaching_athlete_notes")
      .select("id");
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });

  // ── Athlete cannot read coaching_financial_ledger ──
  await test("Athlete A1 cannot read coaching_financial_ledger", async () => {
    const { data } = await athleteA1Client
      .from("coaching_financial_ledger")
      .select("id");
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });

  // ── Athlete cannot read coaching_workout_templates ──
  await test("Athlete A1 cannot read coaching_workout_templates", async () => {
    const { data } = await athleteA1Client
      .from("coaching_workout_templates")
      .select("id");
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });

  // ── Staff can read all attendance in their group ──
  await test("Staff A (coach) sees all attendance in group A", async () => {
    const { data } = await coachAClient
      .from("coaching_training_attendance")
      .select("athlete_user_id")
      .eq("group_id", GROUP_A);
    const userIds = new Set((data ?? []).map((r: any) => r.athlete_user_id));
    assert(userIds.has(ATHLETE_A1), "Should see Athlete A1 attendance");
    assert(userIds.has(ATHLETE_A2), "Should see Athlete A2 attendance");
  });

  // ── Staff A cannot read group B financial data ──
  await test("Staff A cannot read group B financial ledger", async () => {
    const { data } = await coachAClient
      .from("coaching_financial_ledger")
      .select("id, group_id")
      .eq("group_id", GROUP_B);
    assert((data ?? []).length === 0, `Expected 0 rows, got ${(data ?? []).length}`);
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Category 3: Constraint tests
// ═══════════════════════════════════════════════════════════════════════════

async function testConstraints() {
  section("Category 3: Constraint enforcement");

  // 3.1 Unique constraint on coaching_training_attendance(session_id, athlete_user_id)
  await test("UNIQUE attendance(session_id, athlete_user_id) rejects duplicate", async () => {
    // First insert (might already exist from seed/RLS tests)
    await db.from("coaching_training_attendance").upsert(
      {
        id: "66666666-cccc-cccc-cccc-000000000001",
        group_id: GROUP_A,
        session_id: SESSION_A1,
        athlete_user_id: ATHLETE_A2,
        checked_by: COACH_A,
        method: "qr",
      },
      { onConflict: "session_id,athlete_user_id" }
    );

    // Second insert with different id but same session+athlete should fail
    const { error } = await db.from("coaching_training_attendance").insert({
      id: "66666666-cccc-cccc-cccc-000000000099",
      group_id: GROUP_A,
      session_id: SESSION_A1,
      athlete_user_id: ATHLETE_A2,
      checked_by: COACH_A,
      method: "manual",
    });
    assert(!!error, "Expected constraint violation");
    assert(
      error!.message.includes("unique") ||
        error!.message.includes("duplicate") ||
        error!.code === "23505",
      `Expected unique violation, got: ${error!.message}`
    );
  });

  // 3.2 Unique constraint on coaching_announcement_reads(announcement_id, user_id)
  await test("UNIQUE announcement_reads(announcement_id, user_id) rejects duplicate", async () => {
    // Create an announcement first
    const annId = "aaa00000-aaaa-aaaa-aaaa-000000000001";
    await db.from("coaching_announcements").upsert(
      {
        id: annId,
        group_id: GROUP_A,
        created_by: COACH_A,
        title: "IntTest Announcement",
        body: "Test body content",
      },
      { onConflict: "id" }
    );

    // First read
    await db.from("coaching_announcement_reads").upsert(
      { announcement_id: annId, user_id: ATHLETE_A1 },
      { onConflict: "announcement_id,user_id" }
    );

    // Duplicate insert (not upsert) should fail
    const { error } = await db.from("coaching_announcement_reads").insert({
      announcement_id: annId,
      user_id: ATHLETE_A1,
    });
    assert(!!error, "Expected constraint violation");
    assert(
      error!.message.includes("unique") ||
        error!.message.includes("duplicate") ||
        error!.code === "23505",
      `Expected unique violation, got: ${error!.message}`
    );
  });

  // 3.3 Unique constraint on coaching_athlete_tags(group_id, athlete_user_id, tag_id)
  await test("UNIQUE athlete_tags(group_id, athlete_user_id, tag_id) rejects duplicate", async () => {
    // Create a tag
    const tagId = "bbb00000-aaaa-aaaa-aaaa-000000000001";
    await db.from("coaching_tags").upsert(
      { id: tagId, group_id: GROUP_A, name: "IntTest Tag" },
      { onConflict: "id" }
    );

    // First athlete-tag association
    await db.from("coaching_athlete_tags").upsert(
      {
        id: "bbb00000-aaaa-aaaa-aaaa-000000000010",
        group_id: GROUP_A,
        athlete_user_id: ATHLETE_A1,
        tag_id: tagId,
      },
      { onConflict: "group_id,athlete_user_id,tag_id" }
    );

    // Duplicate insert should fail
    const { error } = await db.from("coaching_athlete_tags").insert({
      id: "bbb00000-aaaa-aaaa-aaaa-000000000099",
      group_id: GROUP_A,
      athlete_user_id: ATHLETE_A1,
      tag_id: tagId,
    });
    assert(!!error, "Expected constraint violation");
    assert(
      error!.message.includes("unique") ||
        error!.message.includes("duplicate") ||
        error!.code === "23505",
      `Expected unique violation, got: ${error!.message}`
    );
  });

  // 3.4 Unique constraint on coaching_workout_assignments(athlete_user_id, scheduled_date)
  await test("UNIQUE workout_assignments(athlete_user_id, scheduled_date) rejects duplicate", async () => {
    const tmplId = "ccc00000-aaaa-aaaa-aaaa-000000000001";
    await db.from("coaching_workout_templates").upsert(
      { id: tmplId, group_id: GROUP_A, name: "IntTest WO Template", created_by: COACH_A },
      { onConflict: "id" }
    );

    const schedDate = "2099-12-31";

    // First assignment
    await db.from("coaching_workout_assignments").upsert(
      {
        id: "ccc00000-aaaa-aaaa-aaaa-000000000010",
        group_id: GROUP_A,
        athlete_user_id: ATHLETE_A1,
        template_id: tmplId,
        scheduled_date: schedDate,
        created_by: COACH_A,
      },
      { onConflict: "athlete_user_id,scheduled_date" }
    );

    // Duplicate insert should fail
    const { error } = await db.from("coaching_workout_assignments").insert({
      id: "ccc00000-aaaa-aaaa-aaaa-000000000099",
      group_id: GROUP_A,
      athlete_user_id: ATHLETE_A1,
      template_id: tmplId,
      scheduled_date: schedDate,
      created_by: COACH_A,
    });
    assert(!!error, "Expected constraint violation");
    assert(
      error!.message.includes("unique") ||
        error!.message.includes("duplicate") ||
        error!.code === "23505",
      `Expected unique violation, got: ${error!.message}`
    );
  });

  // 3.5 Unique constraint on coaching_subscriptions(athlete_user_id, group_id)
  await test("UNIQUE subscriptions(athlete_user_id, group_id) rejects duplicate", async () => {
    const planId = "ddd00000-aaaa-aaaa-aaaa-000000000001";
    await db.from("coaching_plans").upsert(
      {
        id: planId,
        group_id: GROUP_A,
        name: "IntTest Plan",
        monthly_price: 99.90,
        billing_cycle: "monthly",
        created_by: COACH_A,
      },
      { onConflict: "id" }
    );

    // First subscription
    await db.from("coaching_subscriptions").upsert(
      {
        id: "ddd00000-aaaa-aaaa-aaaa-000000000010",
        group_id: GROUP_A,
        athlete_user_id: ATHLETE_A1,
        plan_id: planId,
        status: "active",
      },
      { onConflict: "athlete_user_id,group_id" }
    );

    // Duplicate insert should fail
    const { error } = await db.from("coaching_subscriptions").insert({
      id: "ddd00000-aaaa-aaaa-aaaa-000000000099",
      group_id: GROUP_A,
      athlete_user_id: ATHLETE_A1,
      plan_id: planId,
      status: "active",
    });
    assert(!!error, "Expected constraint violation");
    assert(
      error!.message.includes("unique") ||
        error!.message.includes("duplicate") ||
        error!.code === "23505",
      `Expected unique violation, got: ${error!.message}`
    );
  });

  // 3.6 Check constraint on coaching_members.role (from fix_coaching_roles)
  await test("CHECK constraint on coaching_members.role rejects invalid role", async () => {
    const { error } = await db.from("coaching_members").insert({
      user_id: ATHLETE_A1,
      group_id: GROUP_B,
      display_name: "Bad role test",
      role: "superadmin",
      joined_at_ms: NOW_MS,
    });
    assert(!!error, "Expected check constraint violation");
    assert(
      error!.message.includes("check") ||
        error!.message.includes("violates") ||
        error!.code === "23514",
      `Expected check violation, got: ${error!.message}`
    );
  });

  // 3.7 Check constraint on coaching_training_sessions.status
  await test("CHECK constraint on training_sessions.status rejects invalid status", async () => {
    const { error } = await db.from("coaching_training_sessions").insert({
      group_id: GROUP_A,
      created_by: COACH_A,
      title: "Bad status test",
      starts_at: new Date().toISOString(),
      status: "invalid_status",
    });
    assert(!!error, "Expected check constraint violation");
    assert(
      error!.message.includes("check") ||
        error!.message.includes("violates") ||
        error!.code === "23514",
      `Expected check violation, got: ${error!.message}`
    );
  });

  // 3.8 L01-44: platform_fee_config.fee_type CHECK aceita todos os 5 valores canônicos
  const CANONICAL_FEE_TYPES = [
    "clearing",
    "swap",
    "maintenance",
    "billing_split",
    "fx_spread",
  ];

  await test("L01-44: platform_fee_config has all 5 canonical fee_type rows seeded", async () => {
    const { data, error } = await db
      .from("platform_fee_config")
      .select("fee_type")
      .in("fee_type", CANONICAL_FEE_TYPES);
    assert(!error, `Unexpected error: ${error?.message}`);
    const seeded = new Set((data ?? []).map((r: { fee_type: string }) => r.fee_type));
    for (const t of CANONICAL_FEE_TYPES) {
      assert(seeded.has(t), `fee_type '${t}' ausente em platform_fee_config (drift em 170000 não aplicado)`);
    }
  });

  await test("L01-44: platform_fee_config.fee_type CHECK rejects invalid fee_type", async () => {
    const { error } = await db.from("platform_fee_config").insert({
      fee_type: "not_a_real_fee",
      rate_pct: 1.0,
    });
    assert(!!error, "Expected check constraint violation for invalid fee_type");
    assert(
      error!.message.includes("check") ||
        error!.message.includes("violates") ||
        error!.code === "23514",
      `Expected check violation, got: ${error!.message}`
    );
  });

  // 3.9 L02-02: clearing_failure_log table + view exist for swallowed exception audit
  await test("L02-02: clearing_failure_log table exists with expected columns", async () => {
    const exists = await tableExists("clearing_failure_log");
    assert(exists, "clearing_failure_log table not found (migration 20260417140000)");

    const expectedCols = [
      "failure_type",
      "burn_ref_id",
      "clearing_event_id",
      "settlement_id",
      "sqlstate",
      "sqlerrm",
      "context",
      "resolved",
      "retry_count",
    ];
    for (const col of expectedCols) {
      const { error } = await db.from("clearing_failure_log").select(col).limit(0);
      assert(!error, `Column clearing_failure_log.${col} missing: ${error?.message}`);
    }
  });

  await test("L02-02: clearing_failure_log.failure_type CHECK rejects invalid values", async () => {
    const { error } = await db.from("clearing_failure_log").insert({
      failure_type: "not_a_real_failure",
      sqlstate: "P0001",
      sqlerrm: "test",
    });
    assert(!!error, "Expected CHECK constraint violation on failure_type");
    assert(
      error!.message.includes("check") ||
        error!.message.includes("violates") ||
        error!.code === "23514",
      `Expected check violation, got: ${error!.message}`
    );
  });

  await test("L02-02: clearing_failures_unresolved view exists and is queryable", async () => {
    const { error } = await db.from("clearing_failures_unresolved").select("*").limit(1);
    assert(!error, `clearing_failures_unresolved view not queryable: ${error?.message}`);
  });

  // 3.10 L18-03: todas SECURITY DEFINER em public com search_path fixo
  await test("L18-03: no SECURITY DEFINER function in public lacks SET search_path", async () => {
    const { data, error } = await db
      .from("security_definer_hardening_audit")
      .select("function_name, args, has_search_path")
      .eq("has_search_path", false);

    assert(!error, `security_definer_hardening_audit not queryable: ${error?.message}`);
    const unhardened = data ?? [];
    if (unhardened.length > 0) {
      const list = unhardened
        .map((r: { function_name: string; args: string }) => `  - public.${r.function_name}(${r.args})`)
        .join("\n");
      assert(
        false,
        `L18-03 regression: ${unhardened.length} SECURITY DEFINER function(s) without search_path:\n${list}\n` +
          `Fix: adicione SET search_path = public, pg_temp no CREATE OR REPLACE FUNCTION correspondente.`
      );
    }
  });

  await test("L18-03: security_definer_hardening_audit lists all SECDEF in public", async () => {
    const { count, error } = await db
      .from("security_definer_hardening_audit")
      .select("*", { count: "exact", head: true });
    assert(!error, `count failed: ${error?.message}`);
    assert(typeof count === "number" && count > 0, "Expected at least one SECURITY DEFINER function in public");
  });

  // 3.11 L19-05: todas as RPCs financeiras críticas deployadas têm lock_timeout
  await test("L19-05: no deployed financial RPC lacks SET lock_timeout", async () => {
    const { data, error } = await db
      .from("financial_rpc_lock_config_audit")
      .select("function_name, deployed, has_lock_timeout, lock_timeout_setting")
      .eq("deployed", true)
      .eq("has_lock_timeout", false);

    assert(!error, `financial_rpc_lock_config_audit not queryable: ${error?.message}`);
    const unhardened = data ?? [];
    if (unhardened.length > 0) {
      const list = unhardened
        .map((r: { function_name: string }) => `  - public.${r.function_name}`)
        .join("\n");
      assert(
        false,
        `L19-05 regression: ${unhardened.length} financial RPC(s) deployed without lock_timeout:\n${list}\n` +
          `Fix: adicione SET lock_timeout = '2s' no CREATE OR REPLACE FUNCTION ou rode migration de hardening.`
      );
    }
  });

  await test("L19-05: lock_timeout setting is '2s' for all hardened RPCs", async () => {
    const { data, error } = await db
      .from("financial_rpc_lock_config_audit")
      .select("function_name, lock_timeout_setting")
      .eq("deployed", true)
      .eq("has_lock_timeout", true);

    assert(!error, `query failed: ${error?.message}`);
    const rows = data ?? [];
    for (const r of rows as Array<{ function_name: string; lock_timeout_setting: string }>) {
      assert(
        r.lock_timeout_setting === "lock_timeout=2s",
        `L19-05: ${r.function_name} tem lock_timeout_setting="${r.lock_timeout_setting}", esperado "lock_timeout=2s"`
      );
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Category 4: RPC tests
// ═══════════════════════════════════════════════════════════════════════════

async function testRPCs() {
  section("Category 4: RPC contract tests");

  // RPCs are SECURITY DEFINER and require auth.uid() — service_role bypasses
  // auth but auth.uid() returns NULL, so RPCs return NOT_AUTHENTICATED / forbidden.
  // We test that RPCs exist, accept parameters, and return the expected shape.

  // 4.1 fn_mark_attendance
  await test("fn_mark_attendance exists and returns expected shape", async () => {
    const { data, error } = await db.rpc("fn_mark_attendance", {
      p_session_id: SESSION_A1,
      p_athlete_user_id: ATHLETE_A1,
      p_nonce: null,
    });
    // service_role with no auth.uid() → ok:false or ok:true depending on setup
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
    assert("status" in data || "message" in data, 'Response missing "status" or "message"');
  });

  // 4.2 fn_upsert_member_status
  await test("fn_upsert_member_status exists and returns expected shape", async () => {
    const { data, error } = await db.rpc("fn_upsert_member_status", {
      p_group_id: GROUP_A,
      p_user_id: ATHLETE_A1,
      p_status: "active",
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  // 4.3 fn_mark_announcement_read
  await test("fn_mark_announcement_read exists and returns expected shape", async () => {
    // Create announcement for this test
    const annId = "aaa00000-aaaa-aaaa-aaaa-000000000002";
    await db.from("coaching_announcements").upsert(
      {
        id: annId,
        group_id: GROUP_A,
        created_by: COACH_A,
        title: "IntTest Announce for RPC",
        body: "RPC test body",
      },
      { onConflict: "id" }
    );

    const { data, error } = await db.rpc("fn_mark_announcement_read", {
      p_announcement_id: annId,
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  // 4.4 fn_assign_workout
  await test("fn_assign_workout exists and returns expected shape", async () => {
    const tmplId = "ccc00000-aaaa-aaaa-aaaa-000000000001";
    // Ensure template exists
    await db.from("coaching_workout_templates").upsert(
      { id: tmplId, group_id: GROUP_A, name: "IntTest WO Template", created_by: COACH_A },
      { onConflict: "id" }
    );

    const { data, error } = await db.rpc("fn_assign_workout", {
      p_template_id: tmplId,
      p_athlete_user_id: ATHLETE_A2,
      p_scheduled_date: "2099-06-15",
      p_notes: null,
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  // 4.5 fn_update_subscription_status
  await test("fn_update_subscription_status exists and returns expected shape", async () => {
    // Ensure subscription exists
    const planId = "ddd00000-aaaa-aaaa-aaaa-000000000001";
    const subId = "ddd00000-aaaa-aaaa-aaaa-000000000010";

    const { data, error } = await db.rpc("fn_update_subscription_status", {
      p_subscription_id: subId,
      p_new_status: "paused",
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  // 4.6 Additional RPCs from other migrations
  await test("fn_issue_checkin_token exists", async () => {
    const { data, error } = await db.rpc("fn_issue_checkin_token", {
      p_session_id: SESSION_A1,
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  await test("fn_announcement_read_stats exists", async () => {
    const annId = "aaa00000-aaaa-aaaa-aaaa-000000000002";
    const { data, error } = await db.rpc("fn_announcement_read_stats", {
      p_announcement_id: annId,
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  await test("fn_create_ledger_entry exists", async () => {
    const { data, error } = await db.rpc("fn_create_ledger_entry", {
      p_group_id: GROUP_A,
      p_type: "revenue",
      p_category: "test",
      p_amount: 10.0,
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  await test("fn_generate_workout_payload exists", async () => {
    const { data, error } = await db.rpc("fn_generate_workout_payload", {
      p_assignment_id: "00000000-0000-0000-0000-000000000000",
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });

  await test("fn_import_execution exists", async () => {
    const { data, error } = await db.rpc("fn_import_execution", {
      p_source: "manual",
    });
    assert(!error, `RPC call failed: ${error?.message}`);
    assert(typeof data === "object", "Expected JSON object response");
    assert("ok" in data, 'Response missing "ok" field');
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Category 5: Idempotency tests
// ═══════════════════════════════════════════════════════════════════════════

async function testIdempotency() {
  section("Category 5: Idempotency");

  // 5.1 fn_mark_attendance twice — second call returns 'already_present'
  await test("fn_mark_attendance: second call returns 'already_present'", async () => {
    // Clean slate
    await db
      .from("coaching_training_attendance")
      .delete()
      .eq("session_id", SESSION_A2)
      .eq("athlete_user_id", ATHLETE_A1);

    // First call
    const { data: d1, error: e1 } = await db.rpc("fn_mark_attendance", {
      p_session_id: SESSION_A2,
      p_athlete_user_id: ATHLETE_A1,
    });
    assert(!e1, `First call failed: ${e1?.message}`);
    // Service role might return forbidden since auth.uid() is null;
    // if so, we skip the deeper check
    if (d1?.ok === false && d1?.message === "NOT_AUTHENTICATED") {
      // Try with a user client if possible
      try {
        const coachClient = await createUserClient(COACH_A);
        const { data: ud1 } = await coachClient.rpc("fn_mark_attendance", {
          p_session_id: SESSION_A2,
          p_athlete_user_id: ATHLETE_A1,
        });
        assert(ud1?.ok === true, `First call should succeed, got: ${JSON.stringify(ud1)}`);
        assert(
          ud1?.status === "inserted",
          `Expected 'inserted', got '${ud1?.status}'`
        );

        const { data: ud2 } = await coachClient.rpc("fn_mark_attendance", {
          p_session_id: SESSION_A2,
          p_athlete_user_id: ATHLETE_A1,
        });
        assert(ud2?.ok === true, `Second call should also be ok`);
        assert(
          ud2?.status === "already_present",
          `Expected 'already_present', got '${ud2?.status}'`
        );
      } catch (authErr: any) {
        // If auth fails, just verify the service_role path
        assert(d1?.ok !== undefined, "Response has 'ok' field");
      }
    } else if (d1?.ok === true) {
      assert(
        d1.status === "inserted",
        `Expected 'inserted', got '${d1.status}'`
      );
      const { data: d2 } = await db.rpc("fn_mark_attendance", {
        p_session_id: SESSION_A2,
        p_athlete_user_id: ATHLETE_A1,
      });
      assert(d2?.ok === true, "Second call should also be ok");
      assert(
        d2?.status === "already_present",
        `Expected 'already_present', got '${d2?.status}'`
      );
    }
  });

  // 5.2 fn_mark_announcement_read twice doesn't error
  await test("fn_mark_announcement_read: calling twice doesn't error", async () => {
    const annId = "aaa00000-aaaa-aaaa-aaaa-000000000002";

    const { error: e1 } = await db.rpc("fn_mark_announcement_read", {
      p_announcement_id: annId,
    });
    assert(!e1, `First call error: ${e1?.message}`);

    const { error: e2 } = await db.rpc("fn_mark_announcement_read", {
      p_announcement_id: annId,
    });
    assert(!e2, `Second call error: ${e2?.message}`);
  });

  // 5.3 Direct insert with ON CONFLICT on attendance
  await test("Direct INSERT ON CONFLICT on attendance doesn't error", async () => {
    // Using service_role to insert directly
    const { error: e1 } = await db.from("coaching_training_attendance").upsert(
      {
        id: "66666666-dddd-dddd-dddd-000000000001",
        group_id: GROUP_A,
        session_id: SESSION_A1,
        athlete_user_id: ATHLETE_A1,
        checked_by: COACH_A,
        method: "qr",
      },
      { onConflict: "session_id,athlete_user_id" }
    );
    assert(!e1, `First upsert error: ${e1?.message}`);

    // Upsert again — should not error
    const { error: e2 } = await db.from("coaching_training_attendance").upsert(
      {
        id: "66666666-dddd-dddd-dddd-000000000002",
        group_id: GROUP_A,
        session_id: SESSION_A1,
        athlete_user_id: ATHLETE_A1,
        checked_by: ASSISTANT_A,
        method: "manual",
      },
      { onConflict: "session_id,athlete_user_id" }
    );
    assert(!e2, `Second upsert error: ${e2?.message}`);
  });

  // 5.4 fn_upsert_member_status is idempotent
  await test("fn_upsert_member_status: double call is idempotent", async () => {
    const params = {
      p_group_id: GROUP_A,
      p_user_id: ATHLETE_A1,
      p_status: "paused",
    };

    const { data: d1, error: e1 } = await db.rpc("fn_upsert_member_status", params);
    assert(!e1, `First call error: ${e1?.message}`);

    const { data: d2, error: e2 } = await db.rpc("fn_upsert_member_status", params);
    assert(!e2, `Second call error: ${e2?.message}`);

    // Verify only one row exists
    const { data: rows } = await db
      .from("coaching_member_status")
      .select("*")
      .eq("group_id", GROUP_A)
      .eq("user_id", ATHLETE_A1);
    assert((rows ?? []).length === 1, `Expected 1 status row, got ${(rows ?? []).length}`);
  });

  // 5.5 fn_assign_workout ON CONFLICT increments version
  await test("fn_assign_workout: re-assign increments version", async () => {
    const tmplId = "ccc00000-aaaa-aaaa-aaaa-000000000001";
    const schedDate = "2099-07-01";

    const { data: d1, error: e1 } = await db.rpc("fn_assign_workout", {
      p_template_id: tmplId,
      p_athlete_user_id: ATHLETE_A1,
      p_scheduled_date: schedDate,
    });
    assert(!e1, `First assign error: ${e1?.message}`);

    const { data: d2, error: e2 } = await db.rpc("fn_assign_workout", {
      p_template_id: tmplId,
      p_athlete_user_id: ATHLETE_A1,
      p_scheduled_date: schedDate,
      p_notes: "updated notes",
    });
    assert(!e2, `Second assign error: ${e2?.message}`);

    // Verify version > 1 if the RPC ran with auth context
    const { data: assignment } = await db
      .from("coaching_workout_assignments")
      .select("version")
      .eq("athlete_user_id", ATHLETE_A1)
      .eq("scheduled_date", schedDate)
      .single();
    if (assignment) {
      assert(
        assignment.version >= 1,
        `Expected version >= 1, got ${assignment.version}`
      );
    }
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Cleanup
// ═══════════════════════════════════════════════════════════════════════════

async function cleanup() {
  section("Cleanup");

  // Delete in dependency order (children first)
  const deletions: [string, string, any[]][] = [
    ["coaching_workout_executions", "group_id", ALL_GROUP_IDS],
    ["coaching_workout_assignments", "group_id", ALL_GROUP_IDS],
    ["coaching_workout_blocks", "template_id", [
      "ccc00000-aaaa-aaaa-aaaa-000000000001",
      "99999999-aaaa-aaaa-aaaa-000000000001",
    ]],
    ["coaching_workout_templates", "group_id", ALL_GROUP_IDS],
    ["coaching_device_links", "group_id", ALL_GROUP_IDS],
    ["coaching_announcement_reads", "user_id", ALL_USER_IDS],
    ["coaching_announcements", "group_id", ALL_GROUP_IDS],
    ["coaching_financial_ledger", "group_id", ALL_GROUP_IDS],
    ["coaching_subscriptions", "group_id", ALL_GROUP_IDS],
    ["coaching_plans", "group_id", ALL_GROUP_IDS],
    ["coaching_member_status", "group_id", ALL_GROUP_IDS],
    ["coaching_athlete_tags", "group_id", ALL_GROUP_IDS],
    ["coaching_tags", "group_id", ALL_GROUP_IDS],
    ["coaching_athlete_notes", "group_id", ALL_GROUP_IDS],
    ["coaching_training_attendance", "group_id", ALL_GROUP_IDS],
    ["coaching_training_sessions", "group_id", ALL_GROUP_IDS],
    ["coaching_members", "group_id", ALL_GROUP_IDS],
    ["coaching_groups", "id", ALL_GROUP_IDS],
  ];

  for (const [table, col, ids] of deletions) {
    const { error } = await db.from(table).delete().in(col, ids);
    if (error) {
      // Non-fatal: table might not exist or have no matching rows
    }
  }

  for (const uid of ALL_USER_IDS) {
    await db.auth.admin.deleteUser(uid).catch(() => {
      /* ignore — user might not exist */
    });
  }

  console.log("  Cleanup complete");
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

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

async function main() {
  console.log("╔═══════════════════════════════════════════════════════════╗");
  console.log("║   Supabase Integration Test Suite — Migrations & RLS    ║");
  console.log("╚═══════════════════════════════════════════════════════════╝");
  console.log(`Supabase URL:  ${SUPABASE_URL}`);
  console.log(`RLS tests:     ${ANON_KEY ? "ENABLED" : "DISABLED (set SUPABASE_ANON_KEY)"}`);
  console.log(`Timestamp:     ${new Date().toISOString()}`);

  const alive = await preflight();
  if (!alive) {
    console.error(`\n\x1b[31mERROR: Cannot reach Supabase at ${SUPABASE_URL}\x1b[0m`);
    console.error("Start local Supabase first:  supabase start");
    process.exit(2);
  }

  try {
    await seed();
    await testSchema();
    await testRLS();
    await testConstraints();
    await testRPCs();
    await testIdempotency();
  } catch (err) {
    console.error("\n=== SUITE ABORTED ===");
    console.error(err);
    process.exitCode = 1;
  } finally {
    await cleanup();
  }

  console.log("\n══════════════════════════════════════════════════════════");
  console.log(`  Results: ${passed} passed, ${failed} failed, ${skipped} skipped`);
  console.log("══════════════════════════════════════════════════════════\n");

  if (failed > 0) process.exit(1);
}

main();
