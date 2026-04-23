/**
 * tools/test_l09_09_legal_contracts.ts
 *
 * Integration tests for the L09-09 legal contracts path
 * (`supabase/migrations/20260421210000_l09_09_legal_contracts_consent.sql` +
 *  docs/legal/TERMO_ADESAO_ASSESSORIA.md + TERMO_ATLETA.md).
 *
 * Coverage
 * ────────
 *   schema & seed
 *     (1)  consent_policy_versions has 'club_adhesion' v1.0
 *     (2)  consent_policy_versions has 'athlete_contract' v1.0
 *     (3)  document_hash for club_adhesion matches MD content
 *     (4)  document_hash for athlete_contract matches MD content
 *     (5)  document_url points to /legal/TERMO_*.md
 *     (6)  is_required=true and required_for_role canonical (admin_master/athlete)
 *
 *   constraints
 *     (7)  consent_policy_versions CHECK includes new types
 *     (8)  consent_events CHECK includes new types
 *
 *   fn_consent_grant
 *     (9)  authenticated user can grant club_adhesion v1.0
 *     (10) authenticated user can grant athlete_contract v1.0
 *     (11) v_user_consent_status reflects the grant w/ is_valid=true
 *     (12) old version is rejected (P0001 VERSION_TOO_OLD)
 *     (13) unknown consent_type is rejected (P0001 INVALID_CONSENT_TYPE)
 *
 *   fn_consent_revoke
 *     (14) athlete_contract IS revocable (returns event w/ action=revoked)
 *     (15) club_adhesion IS revocable
 *
 *   integrity
 *     (16) raw SHA-256 of MD on disk equals document_hash in DB
 *
 * Usage
 * ─────
 *   NODE_PATH=portal/node_modules npx tsx tools/test_l09_09_legal_contracts.ts
 *
 * Pre-requisitos: supabase local started, migration 20260421210000 aplicada,
 * MDs em docs/legal/ no commit corrente.
 */

import { createClient } from "@supabase/supabase-js";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve, join } from "node:path";
import { randomUUID } from "node:crypto";

const SUPABASE_URL = process.env.SUPABASE_URL ?? "http://127.0.0.1:54321";
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU";
const ANON_KEY =
  process.env.SUPABASE_ANON_KEY ??
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0";

const db = createClient(SUPABASE_URL, SERVICE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const ROOT = resolve(__dirname, "..");

const OK = "\x1b[32m\u2713\x1b[0m";
const FAIL = "\x1b[31m\u2717\x1b[0m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

let passed = 0;
let failed = 0;

function section(t: string) {
  console.log(`\n${BOLD}── ${t} ──${RESET}`);
}

function fmtErr(e: unknown): string {
  if (e instanceof Error) return e.message;
  if (e && typeof e === "object") {
    const o = e as { code?: string; message?: string; details?: string };
    return [o.code, o.message, o.details].filter(Boolean).join(" | ");
  }
  return String(e);
}

async function test(name: string, fn: () => Promise<void>) {
  try {
    await fn();
    console.log(`  ${OK} ${name}`);
    passed++;
  } catch (e) {
    console.log(`  ${FAIL} ${name}: ${fmtErr(e)}`);
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

function sha256OfFile(relPath: string): string {
  const buf = readFileSync(join(ROOT, relPath));
  return createHash("sha256").update(buf).digest("hex");
}

const TEST_PASSWORD = "L0909-test-password-not-secret";

function emailFor(userId: string) {
  return `l0909-${userId}@test.local`;
}

async function createUser(suffix: string): Promise<string> {
  const userId = randomUUID();
  const { error } = await db.auth.admin.createUser({
    id: userId,
    email: emailFor(userId),
    password: TEST_PASSWORD,
    email_confirm: true,
  });
  if (error) throw new Error(`auth.admin.createUser: ${error.message}`);
  await db.from("profiles").upsert(
    { id: userId, display_name: `L09-09 ${suffix}` },
    { onConflict: "id" },
  );
  return userId;
}

async function userClient(userId: string) {
  const cli = createClient(SUPABASE_URL, ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await cli.auth.signInWithPassword({
    email: emailFor(userId),
    password: TEST_PASSWORD,
  });
  if (error) throw new Error(`signIn ${userId}: ${error.message}`);
  return cli;
}

async function cleanupUserConsent(userId: string) {
  await db.from("consent_events").delete().eq("user_id", userId);
}

async function main() {
  console.log(`${BOLD}L09-09 — Legal Contracts Consent integration tests${RESET}`);

  // ──────────────────────────────────────────────────────────────────────
  section("schema & seed");

  await test("(1) consent_policy_versions has 'club_adhesion' v1.0", async () => {
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("consent_type, current_version, minimum_version, is_required, required_for_role, document_url, document_hash")
      .eq("consent_type", "club_adhesion")
      .single();
    if (error) throw error;
    assertEq(data.current_version, "1.0", "current_version");
    assertEq(data.minimum_version, "1.0", "minimum_version");
  });

  await test("(2) consent_policy_versions has 'athlete_contract' v1.0", async () => {
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("consent_type, current_version, minimum_version, is_required, required_for_role, document_url, document_hash")
      .eq("consent_type", "athlete_contract")
      .single();
    if (error) throw error;
    assertEq(data.current_version, "1.0", "current_version");
    assertEq(data.minimum_version, "1.0", "minimum_version");
  });

  await test("(3) document_hash club_adhesion = SHA-256(TERMO_ADESAO_ASSESSORIA.md)", async () => {
    const expected = sha256OfFile("docs/legal/TERMO_ADESAO_ASSESSORIA.md");
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("document_hash")
      .eq("consent_type", "club_adhesion")
      .single();
    if (error) throw error;
    assertEq(data.document_hash, expected, "document_hash mismatch");
  });

  await test("(4) document_hash athlete_contract = SHA-256(TERMO_ATLETA.md)", async () => {
    const expected = sha256OfFile("docs/legal/TERMO_ATLETA.md");
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("document_hash")
      .eq("consent_type", "athlete_contract")
      .single();
    if (error) throw error;
    assertEq(data.document_hash, expected, "document_hash mismatch");
  });

  await test("(5) document_url aponta para /legal/TERMO_*.md", async () => {
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("consent_type, document_url")
      .in("consent_type", ["club_adhesion", "athlete_contract"]);
    if (error) throw error;
    const club = data!.find((r: any) => r.consent_type === "club_adhesion");
    const athlete = data!.find((r: any) => r.consent_type === "athlete_contract");
    assertEq(club?.document_url, "/legal/TERMO_ADESAO_ASSESSORIA.md", "club URL");
    assertEq(athlete?.document_url, "/legal/TERMO_ATLETA.md", "athlete URL");
  });

  await test("(6) is_required=true e required_for_role canônicos", async () => {
    const { data, error } = await db
      .from("consent_policy_versions")
      .select("consent_type, is_required, required_for_role")
      .in("consent_type", ["club_adhesion", "athlete_contract"]);
    if (error) throw error;
    const club = data!.find((r: any) => r.consent_type === "club_adhesion");
    const athlete = data!.find((r: any) => r.consent_type === "athlete_contract");
    assertEq(club?.is_required, true, "club_adhesion is_required");
    assertEq(athlete?.is_required, true, "athlete_contract is_required");
    assertEq(club?.required_for_role, "admin_master", "club role");
    assertEq(athlete?.required_for_role, "athlete", "athlete role");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("constraints");

  await test("(7) consent_policy_versions CHECK rejeita tipo inválido", async () => {
    const probe = `not_a_real_type_${Date.now()}`;
    const { error: insErr } = await db
      .from("consent_policy_versions")
      .insert({
        consent_type: probe,
        current_version: "1.0",
        minimum_version: "1.0",
      });
    assertTrue(!!insErr, "esperado falhar com CHECK violation para tipo inválido");
    assertTrue(/check|violates|consent_type/i.test(insErr!.message),
      `mensagem inesperada: ${insErr!.message}`);
  });

  await test("(8) consent_events CHECK accepts new types via RPC path", async () => {
    // Testado indiretamente em (9)/(10) — se aqueles passam, o CHECK aceita.
    // Aqui validamos que o test run está vinculando à constraint nova: tenta
    // INSERT direto via service_role com o novo tipo.
    const userId = await createUser("ce-check");
    const { error } = await db
      .from("consent_events")
      .insert({
        user_id: userId,
        consent_type: "club_adhesion",
        action: "granted",
        version: "1.0",
        source: "migration",
      });
    if (error) {
      // Pode falhar por trigger append-only se for UPDATE; INSERT é
      // permitido a service_role. Mas há um trigger _consent_events_append_only
      // que NÃO bloqueia INSERT (só UPDATE/DELETE).
      throw new Error(`INSERT direto deveria funcionar para service_role: ${error.message}`);
    }
    // cleanup
    await db.from("consent_events").delete().eq("user_id", userId);
    await db.auth.admin.deleteUser(userId);
  });

  // ──────────────────────────────────────────────────────────────────────
  section("fn_consent_grant + fn_consent_revoke");

  await test("(9) authenticated user → fn_consent_grant('club_adhesion','1.0')", async () => {
    const userId = await createUser("grant-club");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    const { data, error } = await cli.rpc("fn_consent_grant", {
      p_consent_type: "club_adhesion",
      p_version: "1.0",
      p_source: "portal",
      p_request_id: `l0909-club-${Date.now()}`,
    });
    if (error) throw error;
    const row = data as any;
    assertEq(row?.action, "granted", "action");
    assertEq(row?.consent_type, "club_adhesion", "consent_type");
  });

  await test("(10) authenticated user → fn_consent_grant('athlete_contract','1.0')", async () => {
    const userId = await createUser("grant-athlete");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    const { data, error } = await cli.rpc("fn_consent_grant", {
      p_consent_type: "athlete_contract",
      p_version: "1.0",
      p_source: "portal",
      p_request_id: `l0909-athlete-${Date.now()}`,
    });
    if (error) throw error;
    const row = data as any;
    assertEq(row?.action, "granted", "action");
    assertEq(row?.consent_type, "athlete_contract", "consent_type");
  });

  await test("(11) v_user_consent_status reflete grant com is_valid=true", async () => {
    const userId = await createUser("status");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    await cli.rpc("fn_consent_grant", {
      p_consent_type: "athlete_contract",
      p_version: "1.0",
      p_source: "portal",
    });
    const { data, error } = await db
      .from("v_user_consent_status")
      .select("consent_type, action, accepted_version, is_valid")
      .eq("user_id", userId)
      .eq("consent_type", "athlete_contract")
      .single();
    if (error) throw error;
    assertEq(data.action, "granted", "action");
    assertEq(data.accepted_version, "1.0", "accepted_version");
    assertEq(data.is_valid, true, "is_valid");
  });

  await test("(12) version < minimum → P0001 VERSION_TOO_OLD", async () => {
    const userId = await createUser("oldver");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    const { error } = await cli.rpc("fn_consent_grant", {
      p_consent_type: "athlete_contract",
      p_version: "0.5",
      p_source: "portal",
    });
    assertTrue(!!error, "deveria ter falhado");
    assertTrue(/VERSION_TOO_OLD|too_old/i.test(error!.message),
      `mensagem inesperada: ${error!.message}`);
  });

  await test("(13) unknown consent_type → P0001 INVALID_CONSENT_TYPE", async () => {
    const userId = await createUser("unktype");
    const cli = await userClient(userId);
    const { error } = await cli.rpc("fn_consent_grant", {
      p_consent_type: "bogus_xyz",
      p_version: "1.0",
      p_source: "portal",
    });
    assertTrue(!!error, "deveria ter falhado");
    assertTrue(/INVALID_CONSENT_TYPE/i.test(error!.message),
      `mensagem inesperada: ${error!.message}`);
  });

  await test("(14) athlete_contract IS revocable via fn_consent_revoke", async () => {
    const userId = await createUser("revoke-ath");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    await cli.rpc("fn_consent_grant", {
      p_consent_type: "athlete_contract",
      p_version: "1.0",
      p_source: "portal",
    });
    const { data, error } = await cli.rpc("fn_consent_revoke", {
      p_consent_type: "athlete_contract",
      p_source: "portal",
      p_request_id: `l0909-rev-${Date.now()}`,
    });
    if (error) throw error;
    assertEq((data as any)?.action, "revoked", "action");
  });

  await test("(15) club_adhesion IS revocable via fn_consent_revoke", async () => {
    const userId = await createUser("revoke-club");
    await cleanupUserConsent(userId);
    const cli = await userClient(userId);
    await cli.rpc("fn_consent_grant", {
      p_consent_type: "club_adhesion",
      p_version: "1.0",
      p_source: "portal",
    });
    const { data, error } = await cli.rpc("fn_consent_revoke", {
      p_consent_type: "club_adhesion",
      p_source: "portal",
    });
    if (error) throw error;
    assertEq((data as any)?.action, "revoked", "action");
  });

  // ──────────────────────────────────────────────────────────────────────
  section("integrity (lockstep MD ↔ DB)");

  await test("(16) raw SHA-256 do MD on disk = document_hash em DB (lockstep)", async () => {
    const pairs: [string, string][] = [
      ["club_adhesion", "docs/legal/TERMO_ADESAO_ASSESSORIA.md"],
      ["athlete_contract", "docs/legal/TERMO_ATLETA.md"],
    ];
    for (const [t, p] of pairs) {
      const expected = sha256OfFile(p);
      const { data, error } = await db
        .from("consent_policy_versions")
        .select("document_hash")
        .eq("consent_type", t)
        .single();
      if (error) throw error;
      if (data.document_hash !== expected) {
        throw new Error(
          `lockstep failure for ${t}: ` +
            `MD on disk=${expected}, DB document_hash=${data.document_hash}. ` +
            `Run: npx tsx tools/legal/check-document-hashes.ts`,
        );
      }
    }
  });

  // ──────────────────────────────────────────────────────────────────────
  console.log(
    `\n${BOLD}Result:${RESET} ${OK} ${passed} passed, ${FAIL} ${failed} failed\n`,
  );
  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error("Fatal:", fmtErr(e));
  process.exit(2);
});
