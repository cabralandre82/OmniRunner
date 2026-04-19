/**
 * tools/test_l18_idempotency.ts
 *
 * Integration tests for the L18-02 unified idempotency layer
 * (`supabase/migrations/20260419120000_l18_idempotency_keys_unified.sql`).
 *
 * Coverage:
 *
 *   - Table shape + constraints (status enum, namespace regex, key length)
 *   - fn_idem_begin
 *       * first call → action=execute (claim row inserted)
 *       * replay (after finalize) → action=replay returns cached body+status
 *       * mismatch (different request_hash) → action=mismatch
 *       * stale claim (claimed_at older than lease) → reclaim with stale_recovered=true
 *       * released → reclaim
 *       * input validation (NULL, TTL out of range)
 *   - fn_idem_finalize
 *       * happy path returns true and stores response
 *       * second finalize on already-completed key returns false (no-op)
 *       * status code out of HTTP range rejected
 *       * NULL response rejected
 *   - fn_idem_release
 *       * claimed → released (true)
 *       * already-completed → false
 *   - fn_idem_gc
 *       * deletes expired rows, leaves fresh rows
 *   - cron schedule registered + cron_run_state seeded
 *
 * Usage:
 *
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l18_idempotency.ts
 */

import { createClient } from "@supabase/supabase-js";
import { createHash, randomUUID } from "node:crypto";

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

const NAMESPACE = "test.idem";
const ACTOR_A = "00000000-0000-4000-8000-000000000001";
const ACTOR_B = "00000000-0000-4000-8000-000000000002";

function hex(input: string): string {
  return `\\x${createHash("sha256").update(input).digest("hex")}`;
}

function uniqueKey(): string {
  // 16+ chars, opaque format
  return `t${Date.now().toString(36)}${randomUUID().replace(/-/g, "").slice(0, 16)}`;
}

async function callBegin(args: {
  key: string;
  actorId?: string;
  hashSource?: string;
  ttl?: number;
  lease?: number;
}): Promise<{
  action: string;
  replay_status: number | null;
  replay_body: unknown;
  stale_recovered: boolean;
}> {
  const { data, error } = await db.rpc("fn_idem_begin" as any, {
    p_namespace: NAMESPACE,
    p_actor_id: args.actorId ?? ACTOR_A,
    p_key: args.key,
    p_request_hash: hex(args.hashSource ?? "default-body"),
    p_ttl_seconds: args.ttl ?? 86400,
    p_claim_lease_secs: args.lease ?? 60,
  });
  if (error) throw new Error(`fn_idem_begin: ${error.message}`);
  const row = Array.isArray(data) ? data[0] : data;
  return row;
}

async function callFinalize(args: {
  key: string;
  actorId?: string;
  status: number;
  body: unknown;
}): Promise<boolean> {
  const { data, error } = await db.rpc("fn_idem_finalize" as any, {
    p_namespace: NAMESPACE,
    p_actor_id: args.actorId ?? ACTOR_A,
    p_key: args.key,
    p_status_code: args.status,
    p_response: args.body,
  });
  if (error) throw new Error(`fn_idem_finalize: ${error.message}`);
  return data === true;
}

async function callRelease(args: {
  key: string;
  actorId?: string;
}): Promise<boolean> {
  const { data, error } = await db.rpc("fn_idem_release" as any, {
    p_namespace: NAMESPACE,
    p_actor_id: args.actorId ?? ACTOR_A,
    p_key: args.key,
  });
  if (error) throw new Error(`fn_idem_release: ${error.message}`);
  return data === true;
}

async function selectRow(args: {
  key: string;
  actorId?: string;
}): Promise<any> {
  const { data, error } = await db
    .from("idempotency_keys")
    .select("*")
    .eq("namespace", NAMESPACE)
    .eq("actor_id", args.actorId ?? ACTOR_A)
    .eq("key", args.key)
    .maybeSingle();
  if (error) throw new Error(`select idem: ${error.message}`);
  return data;
}

async function deleteAllTestRows() {
  // Cleanup any test-namespace residue between runs.
  const { error } = await db
    .from("idempotency_keys")
    .delete()
    .eq("namespace", NAMESPACE);
  if (error && !/no rows/i.test(error.message)) {
    throw new Error(`delete test rows: ${error.message}`);
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
  const { error } = await db.from("idempotency_keys").select("namespace").limit(0);
  return !error;
}

// ── Tests ───────────────────────────────────────────────────────────────────

async function testSchema() {
  section("idempotency_keys schema + reachability");

  await test("table is reachable via service role", async () => {
    assertTrue(await tableReachable(), "idempotency_keys should be reachable");
  });

  await test("namespace regex rejects uppercase / leading digit", async () => {
    const key = uniqueKey();
    const { error } = await db
      .from("idempotency_keys")
      .insert({
        namespace: "BAD",
        actor_id: ACTOR_A,
        key,
        request_hash: hex("x"),
      });
    assertTrue(
      Boolean(error) && /idem_namespace_check/.test(error?.message ?? ""),
      `expected idem_namespace_check violation, got ${error?.message}`,
    );
  });

  await test("status enum rejects unknown values", async () => {
    const key = uniqueKey();
    const { error } = await db
      .from("idempotency_keys")
      .insert({
        namespace: NAMESPACE,
        actor_id: ACTOR_A,
        key,
        request_hash: hex("x"),
        status: "wat",
      });
    assertTrue(
      Boolean(error) && /idem_status_check/.test(error?.message ?? ""),
      `expected idem_status_check violation, got ${error?.message}`,
    );
  });

  await test("status_code out of HTTP range rejected by check constraint", async () => {
    const key = uniqueKey();
    const { error } = await db
      .from("idempotency_keys")
      .insert({
        namespace: NAMESPACE,
        actor_id: ACTOR_A,
        key,
        request_hash: hex("x"),
        status_code: 99,
      });
    assertTrue(
      Boolean(error) && /idem_status_code_range/.test(error?.message ?? ""),
      `expected idem_status_code_range violation, got ${error?.message}`,
    );
  });

  await test("completed-without-response rejected by check constraint", async () => {
    const key = uniqueKey();
    const { error } = await db
      .from("idempotency_keys")
      .insert({
        namespace: NAMESPACE,
        actor_id: ACTOR_A,
        key,
        request_hash: hex("x"),
        status: "completed",
      });
    assertTrue(
      Boolean(error) && /idem_completed_must_have_response/.test(error?.message ?? ""),
      `expected idem_completed_must_have_response violation, got ${error?.message}`,
    );
  });
}

async function testBegin() {
  section("fn_idem_begin");

  await test("first call → action=execute and inserts a 'claimed' row", async () => {
    const key = uniqueKey();
    const r = await callBegin({ key });
    assertEq(r.action, "execute", "action");
    assertEq(r.stale_recovered, false, "stale_recovered");
    const row = await selectRow({ key });
    assertEq(row?.status, "claimed", "row.status");
  });

  await test("replay after finalize returns cached status + body", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    await callFinalize({ key, status: 201, body: { id: "abc" } });
    const r = await callBegin({ key });
    assertEq(r.action, "replay", "action");
    assertEq(r.replay_status, 201, "replay_status");
    assertEq(JSON.stringify(r.replay_body), JSON.stringify({ id: "abc" }), "replay_body");
  });

  await test("mismatch when same key sent with a different request_hash", async () => {
    const key = uniqueKey();
    await callBegin({ key, hashSource: "body-v1" });
    const r = await callBegin({ key, hashSource: "body-v2" });
    assertEq(r.action, "mismatch", "action");
    assertEq(r.replay_status, null, "replay_status null");
    assertEq(r.replay_body, null, "replay_body null");
  });

  await test("stale claim (lease=1s) is reclaimable with stale_recovered=true", async () => {
    const key = uniqueKey();
    await callBegin({ key, lease: 1 });
    await new Promise((r) => setTimeout(r, 1500));
    const r = await callBegin({ key, lease: 1 });
    assertEq(r.action, "execute", "action");
    assertEq(r.stale_recovered, true, "stale_recovered");
  });

  await test("released row is re-claimable (action=execute)", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    await callRelease({ key });
    const r = await callBegin({ key });
    assertEq(r.action, "execute", "action");
    const row = await selectRow({ key });
    assertEq(row?.status, "claimed", "back to claimed");
  });

  await test("rejects ttl_seconds out of range", async () => {
    const key = uniqueKey();
    let threw = false;
    try {
      await callBegin({ key, ttl: 0 });
    } catch (e: any) {
      threw = /p_ttl_seconds out of range/.test(e.message);
    }
    assertTrue(threw, "expected ttl out-of-range error");
  });

  await test("different actors get isolated buckets for same key", async () => {
    const key = uniqueKey();
    const a = await callBegin({ key, actorId: ACTOR_A });
    const b = await callBegin({ key, actorId: ACTOR_B });
    assertEq(a.action, "execute", "actor A first");
    assertEq(b.action, "execute", "actor B isolated");
  });
}

async function testFinalize() {
  section("fn_idem_finalize");

  await test("happy path returns true and stores response", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    const ok = await callFinalize({ key, status: 200, body: { foo: "bar" } });
    assertEq(ok, true, "finalize returns true");
    const row = await selectRow({ key });
    assertEq(row?.status, "completed", "status=completed");
    assertEq(row?.status_code, 200, "status_code stored");
    assertEq(JSON.stringify(row?.response_body), JSON.stringify({ foo: "bar" }), "body stored");
    assertTrue(row?.finalized_at != null, "finalized_at set");
  });

  await test("second finalize on already-completed key returns false", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    await callFinalize({ key, status: 200, body: { v: 1 } });
    const ok = await callFinalize({ key, status: 500, body: { v: 2 } });
    assertEq(ok, false, "second finalize returns false");
    const row = await selectRow({ key });
    assertEq(row?.status_code, 200, "original status preserved");
  });

  await test("rejects status_code outside HTTP range", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    let threw = false;
    try {
      await callFinalize({ key, status: 999, body: {} });
    } catch (e: any) {
      threw = /out of HTTP range/.test(e.message);
    }
    assertTrue(threw, "expected status_code range error");
  });

  await test("rejects NULL response (must use fn_idem_release)", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    let threw = false;
    try {
      await callFinalize({ key, status: 200, body: null as any });
    } catch (e: any) {
      threw = /p_response is NULL/.test(e.message);
    }
    assertTrue(threw, "expected NULL response rejection");
  });

  await test("finalize on missing key is a no-op (returns false)", async () => {
    const key = uniqueKey();
    const ok = await callFinalize({ key, status: 200, body: { x: 1 } });
    assertEq(ok, false, "finalize on missing returns false");
  });
}

async function testRelease() {
  section("fn_idem_release");

  await test("claimed → released returns true", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    const ok = await callRelease({ key });
    assertEq(ok, true, "release returns true");
    const row = await selectRow({ key });
    assertEq(row?.status, "released", "status=released");
  });

  await test("release on completed row returns false (no-op)", async () => {
    const key = uniqueKey();
    await callBegin({ key });
    await callFinalize({ key, status: 200, body: { x: 1 } });
    const ok = await callRelease({ key });
    assertEq(ok, false, "release on completed returns false");
  });
}

async function testGc() {
  section("fn_idem_gc");

  await test("expired rows deleted, fresh rows preserved", async () => {
    const expiredKey = uniqueKey();
    const freshKey = uniqueKey();

    const { error: e1 } = await db
      .from("idempotency_keys")
      .insert({
        namespace: NAMESPACE,
        actor_id: ACTOR_A,
        key: expiredKey,
        request_hash: hex("expired"),
        expires_at: new Date(Date.now() - 60_000).toISOString(),
      });
    if (e1) throw new Error(`seed expired: ${e1.message}`);

    const { error: e2 } = await db
      .from("idempotency_keys")
      .insert({
        namespace: NAMESPACE,
        actor_id: ACTOR_A,
        key: freshKey,
        request_hash: hex("fresh"),
        expires_at: new Date(Date.now() + 60_000).toISOString(),
      });
    if (e2) throw new Error(`seed fresh: ${e2.message}`);

    const { data: deleted, error } = await db.rpc("fn_idem_gc" as any);
    if (error) throw new Error(`fn_idem_gc: ${error.message}`);
    assertTrue((deleted as number) >= 1, `gc should delete ≥1, got ${deleted}`);

    const expiredRow = await selectRow({ key: expiredKey });
    assertEq(expiredRow, null, "expired row gone");
    const freshRow = await selectRow({ key: freshKey });
    assertTrue(freshRow != null, "fresh row preserved");
  });
}

async function testCronRegistration() {
  section("cron schedule registration");

  await test("cron_run_state seeded for idempotency-keys-gc", async () => {
    const { data, error } = await db
      .from("cron_run_state")
      .select("name, last_status")
      .eq("name", "idempotency-keys-gc")
      .maybeSingle();
    if (error) throw new Error(`select cron_run_state: ${error.message}`);
    assertTrue(data != null, "cron_run_state row exists");
  });

  await test("fn_idem_gc_safe is callable end-to-end (full lifecycle)", async () => {
    const { error } = await db.rpc("fn_idem_gc_safe" as any);
    if (error) throw new Error(`fn_idem_gc_safe: ${error.message}`);
    const { data } = await db
      .from("cron_run_state")
      .select("last_status, last_meta")
      .eq("name", "idempotency-keys-gc")
      .maybeSingle();
    assertTrue(
      data?.last_status === "completed" || data?.last_status === "skipped",
      `last_status should be completed/skipped, got ${data?.last_status}`,
    );
  });
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`${BOLD}L18-02 idempotency layer integration tests${RESET}`);
  console.log(`Target: ${SUPABASE_URL}`);

  if (!(await preflight())) {
    console.log(`\n${SKIP} Local Supabase unreachable at ${SUPABASE_URL} — start with 'supabase start' to run.`);
    process.exit(0);
  }
  if (!(await tableReachable())) {
    console.log(`\n${FAIL} idempotency_keys not reachable. Run 'supabase migration up --include-all'.`);
    process.exit(1);
  }

  await deleteAllTestRows();

  try {
    await testSchema();
    await testBegin();
    await testFinalize();
    await testRelease();
    await testGc();
    await testCronRegistration();
  } finally {
    await deleteAllTestRows().catch(() => {});
  }

  console.log(
    `\n${BOLD}Results:${RESET} ${OK} ${passed} passed, ${FAIL} ${failed} failed, ${SKIP} ${skipped} skipped`,
  );
  process.exit(failed > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(2);
});
