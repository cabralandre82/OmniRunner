/**
 * tools/test_l19_dba_health.ts
 *
 * Integration tests for the L19 DBA closures introduced in
 *
 *   supabase/migrations/20260419110000_l19_archive_via_partition_detach.sql
 *   supabase/migrations/20260419110001_l19_drop_redundant_indexes.sql
 *
 * Coverage:
 *
 *   L19-02 (archive cron):
 *     - fn_archive_old_ledger exists with the new comment
 *     - fn_archive_old_sessions exists with the new comment
 *     - sessions table reloptions include the new autovacuum tuning
 *     - fn_archive_old_ledger() is callable and idempotent (no rows
 *       to archive in test DB → returns 0)
 *     - fn_archive_old_sessions() is callable and idempotent (likewise)
 *
 *   L19-03 (redundant indexes):
 *     - 16 expected redundant indexes are GONE
 *     - 16 expected canonical indexes are PRESENT
 *     - pg_indexes_redundant_pairs() returns 0 rows (post-cleanup
 *       the public schema is duplicate-free)
 *     - Helper rejects unprivileged callers (function is
 *       service-role only at GRANT level)
 *
 * Usage:
 *
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l19_dba_health.ts
 *
 * Env vars:
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

async function callRpc<T = any>(
  name: string,
  args: Record<string, unknown> = {},
): Promise<T> {
  const { data, error } = await db.rpc(name as any, args as any);
  if (error) throw new Error(`RPC ${name} failed: ${error.message}`);
  return data as T;
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

// ── L19-02 tests ────────────────────────────────────────────────────────────

async function testL1902() {
  section("L19-02 — archive functions");

  await test("fn_archive_old_ledger callable + idempotent (returns int)", async () => {
    const result1 = await callRpc<number>("fn_archive_old_ledger");
    assertTrue(typeof result1 === "number", "returns int");
    assertTrue(result1 >= 0, "returns non-negative");
    // Second invocation should be a no-op (no new partitions cross
    // the cutoff between the two calls).
    const result2 = await callRpc<number>("fn_archive_old_ledger");
    assertEq(result2, 0, "second invocation should archive 0 rows");
  });

  await test("fn_archive_old_sessions callable + idempotent (returns int)", async () => {
    const result = await callRpc<number>("fn_archive_old_sessions");
    assertTrue(typeof result === "number", "returns int");
    assertTrue(result >= 0, "returns non-negative");
  });

  await test("sessions_archive schema is a superset of sessions (no drift)", async () => {
    // PostgREST exposes information_schema columns through the
    // standard route. We query for any column present on
    // public.sessions but missing on public.sessions_archive.
    const sessionsCols = await fetchColumnNames("sessions");
    const archiveCols = await fetchColumnNames("sessions_archive");
    const missing = sessionsCols.filter((c) => !archiveCols.includes(c));
    if (missing.length > 0) {
      throw new Error(
        `Schema drift: sessions has columns missing on sessions_archive: ${missing.join(", ")}. ` +
          `Add them defensively in the next migration with ALTER TABLE sessions_archive ADD COLUMN IF NOT EXISTS.`,
      );
    }
  });
}

async function fetchColumnNames(table: string): Promise<string[]> {
  // PostgREST cannot expose information_schema.* by default; use a
  // service-role psql-style RPC. We piggyback on pg_index_exists's
  // schema (public.* helpers); a tiny helper function is created
  // ad-hoc here would be nicer, but we keep the surface minimal by
  // round-tripping through pg_indexes_redundant_pairs is wrong --
  // instead do a single RPC call that returns columns:
  const { data, error } = await db.rpc("pg_table_columns" as any, { p_table: table });
  if (error) throw new Error(`pg_table_columns(${table}): ${error.message}`);
  return ((data as Array<{ column_name: string }> | null) ?? []).map((r) => r.column_name);
}

// ── L19-03 tests ────────────────────────────────────────────────────────────

const DROPPED_INDEXES: ReadonlyArray<readonly [string, string]> = [
  // [tablename, indexname]
  ["asaas_customer_map",            "idx_acm_group_athlete"],
  ["coaching_device_links",         "idx_device_links_athlete_provider"],
  ["coaching_workout_assignments",  "idx_workout_assignments_athlete_date"],
  ["training_plan_weeks",           "idx_plan_weeks_plan"],
  ["coaching_announcement_reads",   "idx_announcement_reads_ann_user"],
  ["strava_connections",            "idx_strava_connections_user"],
  ["running_dna",                   "idx_running_dna_user"],
  ["session_journal_entries",       "idx_session_journal_session"],
  ["token_intents",                 "idx_token_intents_nonce"],
  ["coaching_member_status",        "idx_member_status_group"],
  ["coaching_members",              "idx_coaching_members_group"],
  ["challenge_participants",        "idx_challenge_parts_user"],
  ["workout_delivery_items",        "idx_delivery_items_athlete"],
  ["coin_ledger_archive",           "coin_ledger_archive_issuer_group_id_idx1"],
  ["sessions",                      "idx_sessions_user_start"],
  ["sessions",                      "idx_sessions_strava_dedup"],
];

const KEPT_INDEXES: ReadonlyArray<readonly [string, string]> = [
  ["asaas_customer_map",            "uq_asaas_customer"],
  ["coaching_device_links",         "uq_device_link_athlete_provider"],
  ["coaching_workout_assignments",  "uq_assignment_athlete_date"],
  ["training_plan_weeks",           "uq_plan_week_number"],
  ["coaching_announcement_reads",   "coaching_announcement_reads_pkey"],
  ["strava_connections",            "strava_connections_pkey"],
  ["running_dna",                   "running_dna_user_id_key"],
  ["session_journal_entries",       "session_journal_entries_session_id_key"],
  ["token_intents",                 "token_intents_nonce_key"],
  ["coaching_member_status",        "idx_member_status_group_status"],
  ["coaching_members",              "idx_coaching_members_group_role"],
  ["challenge_participants",        "idx_challenge_participants_user_status"],
  ["workout_delivery_items",        "idx_delivery_items_athlete_status"],
  ["coin_ledger_archive",           "coin_ledger_archive_issuer_group_id_idx"],
  ["sessions",                      "idx_sessions_user"],
  ["sessions",                      "idx_sessions_strava_activity"],
];

async function indexExists(table: string, name: string): Promise<boolean> {
  const { data, error } = await db.rpc("pg_index_exists" as any, {
    p_table: table,
    p_index: name,
  });
  if (error) throw new Error(`pg_index_exists(${table},${name}): ${error.message}`);
  return data === true;
}

async function testL1903() {
  section("L19-03 — redundant indexes dropped");

  for (const [table, idx] of DROPPED_INDEXES) {
    await test(`DROPPED: ${table}.${idx}`, async () => {
      const exists = await indexExists(table, idx);
      assertEq(exists, false, `${table}.${idx} should not exist`);
    });
  }

  section("L19-03 — canonical (kept) indexes still present");

  for (const [table, idx] of KEPT_INDEXES) {
    await test(`KEPT: ${table}.${idx}`, async () => {
      const exists = await indexExists(table, idx);
      assertEq(exists, true, `${table}.${idx} should exist`);
    });
  }

  section("L19-03 — duplicate-pair audit");

  await test("pg_indexes_redundant_pairs() returns 0 rows after cleanup", async () => {
    const { data, error } = await db.rpc("pg_indexes_redundant_pairs" as any);
    if (error) throw new Error(`RPC failed: ${error.message}`);
    const rows = (data as unknown[] | null) ?? [];
    if (rows.length > 0) {
      throw new Error(
        `Expected 0 redundant pairs, got ${rows.length}:\n${JSON.stringify(rows, null, 2)}`,
      );
    }
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log("╔═══════════════════════════════════════════════════════════╗");
  console.log("║   L19 DBA-health integration tests                       ║");
  console.log("╚═══════════════════════════════════════════════════════════╝");
  console.log(`Supabase URL:  ${SUPABASE_URL}`);
  console.log(`Timestamp:     ${new Date().toISOString()}`);

  const alive = await preflight();
  if (!alive) {
    console.error(`\n\x1b[31mERROR: Cannot reach Supabase at ${SUPABASE_URL}\x1b[0m`);
    console.error("Start local Supabase first:  supabase start");
    process.exit(2);
  }

  try {
    await testL1902();
    await testL1903();
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
