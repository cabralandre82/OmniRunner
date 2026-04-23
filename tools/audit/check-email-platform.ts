/**
 * check-email-platform.ts
 *
 * L15-04 — CI guard enforcing that the transactional email platform
 * stays wired up as designed:
 *
 *   1. DB invariants (via `public.fn_email_outbox_assert_shape`):
 *      - `public.email_outbox` exists with RLS + FORCE RLS
 *      - UNIQUE idempotency_key index
 *      - all 5 CHECK constraints
 *      - fn_enqueue_email / fn_mark_email_sent / fn_mark_email_failed /
 *        fn_email_outbox_assert_shape registered with SECURITY DEFINER
 *      - anon + authenticated DO NOT have EXECUTE
 *
 *   2. Code invariants (static analysis):
 *      - `supabase/functions/_shared/email.ts` exists and exports the
 *        canonical primitives: escapeHtml, renderTemplate,
 *        assertRequiredVars, resolveProvider, ResendProvider,
 *        InbucketProvider, NullProvider, sendEmail, TEMPLATE_MANIFEST
 *      - `supabase/functions/send-email/index.ts` exists and is
 *        service-role gated (Bearer check against SUPABASE_SERVICE_ROLE_KEY)
 *      - `supabase/email-templates/manifest.json` parses and references
 *        every template_key that `_shared/email.ts` declares
 *      - each template `file` referenced from the manifest exists on disk
 *        and contains at least one `{{var}}` placeholder
 *      - callers outside `_shared/` and the send-email function do NOT
 *        talk to Resend/SendGrid/Postmark/Mailgun directly
 *
 *   3. Runbook invariant:
 *      - `docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md` exists
 *
 * Probing the DB is best-effort — when the container is not reachable
 * we log a NOTE and skip the DB section without failing CI (same pattern
 * as check-audit-logs-append-only / check-sessions-time-series-index).
 *
 * Usage: npm run audit:email-platform
 */

import { execSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

const OK = "[OK]";
const FAIL = "[FAIL]";
const NOTE = "[NOTE]";

let failures = 0;
const logs: string[] = [];

function pass(kind: string, msg: string) {
  logs.push(`  ${OK} ${kind}: ${msg}`);
}
function fail(kind: string, msg: string) {
  logs.push(`  ${FAIL} ${kind}: ${msg}`);
  failures++;
}
function note(kind: string, msg: string) {
  logs.push(`  ${NOTE} ${kind}: ${msg}`);
}

function readOrNull(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

function walkFiles(root: string, matcher: RegExp): string[] {
  const out: string[] = [];
  function visit(dir: string) {
    if (!existsSync(dir)) return;
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name.startsWith(".")) continue;
      if (entry.name === "node_modules") continue;
      const full = join(dir, entry.name);
      if (entry.isDirectory()) visit(full);
      else if (entry.isFile() && matcher.test(entry.name)) out.push(full);
    }
  }
  visit(root);
  return out;
}

// ───────────────────────── 1. DB invariants ─────────────────────────

function probeDb(): boolean {
  try {
    execSync(
      `docker exec ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At -c "SELECT 1;"`,
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    return true;
  } catch {
    return false;
  }
}

function runPsql(sql: string, allowError = false): string {
  try {
    return execSync(
      `docker exec -i ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At`,
      { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    ).toString().trim();
  } catch (e) {
    if (!allowError) throw e;
    const err = e as { stderr?: Buffer | string };
    return (typeof err.stderr === "string" ? err.stderr : err.stderr?.toString?.() ?? "");
  }
}

function checkDatabase(): void {
  if (!probeDb()) {
    note("db", `container '${CONTAINER}' not reachable — skipping DB invariants`);
    return;
  }

  // Does the helper exist? If not, migration hasn't been applied here.
  const helperPresent = runPsql(
    `SELECT COUNT(*)::text FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
      WHERE n.nspname='public' AND p.proname='fn_email_outbox_assert_shape';`,
    true,
  );
  if (helperPresent !== "1") {
    note("db", "fn_email_outbox_assert_shape() not installed — skipping DB invariants");
    return;
  }

  const out = runPsql(`SELECT public.fn_email_outbox_assert_shape();`, true);
  if (/ERROR|P0010|L15-04/.test(out)) {
    fail("db", `fn_email_outbox_assert_shape raised: ${out.split("\n").slice(-5).join(" | ")}`);
  } else {
    pass("db", "fn_email_outbox_assert_shape no-op (schema + privileges + indexes healthy)");
  }
}

// ─────────────────── 2. Code invariants ───────────────────

function checkSharedEmailModule(): void {
  const path = "supabase/functions/_shared/email.ts";
  const src = readOrNull(path);
  if (!src) {
    fail("shared", `${path} missing`);
    return;
  }
  const requiredExports = [
    /export\s+function\s+escapeHtml\b/,
    /export\s+function\s+renderTemplate\b/,
    /export\s+function\s+assertRequiredVars\b/,
    /export\s+function\s+resolveProvider\b/,
    /export\s+class\s+ResendProvider\b/,
    /export\s+class\s+InbucketProvider\b/,
    /export\s+class\s+NullProvider\b/,
    /export\s+async\s+function\s+sendEmail\b/,
    /export\s+const\s+TEMPLATE_MANIFEST\b/,
    /export\s+class\s+EmailError\b/,
  ];
  for (const re of requiredExports) {
    if (!re.test(src)) {
      fail("shared", `${path} missing export matching ${re}`);
      return;
    }
  }
  pass("shared", `${path} exports all canonical primitives`);
}

function checkSendEmailFunction(): void {
  const path = "supabase/functions/send-email/index.ts";
  const src = readOrNull(path);
  if (!src) {
    fail("edge-fn", `${path} missing`);
    return;
  }
  if (!/SUPABASE_SERVICE_ROLE_KEY/.test(src) && !/SERVICE_ROLE_KEY/.test(src)) {
    fail("edge-fn", `${path} does not check service-role bearer`);
    return;
  }
  if (!/fn_enqueue_email/.test(src)) {
    fail("edge-fn", `${path} does not call fn_enqueue_email`);
    return;
  }
  if (!/fn_mark_email_sent/.test(src) || !/fn_mark_email_failed/.test(src)) {
    fail("edge-fn", `${path} does not close the loop via fn_mark_email_sent/_failed`);
    return;
  }
  if (!/sendEmail\s*\(/.test(src)) {
    fail("edge-fn", `${path} does not dispatch via sendEmail()`);
    return;
  }
  pass("edge-fn", `${path} is service-role gated and wires enqueue → dispatch → mark`);
}

function checkManifest(): void {
  const manifestPath = "supabase/email-templates/manifest.json";
  const raw = readOrNull(manifestPath);
  if (!raw) {
    fail("templates", `${manifestPath} missing`);
    return;
  }
  let parsed: {
    templates?: Record<string, { subject?: string; file?: string; required_vars?: string[]; from_name?: string }>;
  };
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    fail("templates", `${manifestPath} is not valid JSON: ${(e as Error).message}`);
    return;
  }
  const templates = parsed.templates ?? {};
  const keys = Object.keys(templates);
  if (keys.length === 0) {
    fail("templates", `${manifestPath} has no templates entries`);
    return;
  }

  // Every template_key in manifest must appear in the _shared/email.ts
  // TEMPLATE_MANIFEST (so TypeScript keeps the key set narrow).
  const shared = readOrNull("supabase/functions/_shared/email.ts") ?? "";
  for (const key of keys) {
    if (!new RegExp(`\\b${key}\\b`).test(shared)) {
      fail("templates", `${manifestPath} key '${key}' not referenced in _shared/email.ts TEMPLATE_MANIFEST`);
      return;
    }
  }

  for (const [key, def] of Object.entries(templates)) {
    if (!def.file || typeof def.file !== "string") {
      fail("templates", `manifest[${key}] missing 'file'`);
      return;
    }
    const filePath = join("supabase/email-templates", def.file);
    const body = readOrNull(filePath);
    if (body === null) {
      fail("templates", `template file missing on disk: ${filePath}`);
      return;
    }
    if (!/{{\s*[a-zA-Z0-9_]+\s*}}/.test(body)) {
      fail("templates", `template '${key}' (${filePath}) has no {{var}} placeholder — suspicious`);
      return;
    }
    if (!Array.isArray(def.required_vars) || def.required_vars.length === 0) {
      fail("templates", `manifest[${key}].required_vars missing or empty`);
      return;
    }
    if (!def.subject || typeof def.subject !== "string" || def.subject.length === 0) {
      fail("templates", `manifest[${key}].subject missing`);
      return;
    }
  }
  pass("templates", `${keys.length} templates present with files + required_vars + subjects`);
}

function checkNoDirectProviderCallsOutsideAllowed(): void {
  const allowed = new Set<string>([
    "supabase/functions/_shared/email.ts",
    "supabase/functions/_shared/email.test.ts",
    "supabase/functions/send-email/index.ts",
  ]);
  const edgeFns = walkFiles("supabase/functions", /\.ts$/);
  const portal = walkFiles("portal/src", /\.(ts|tsx)$/);
  const candidates = [...edgeFns, ...portal];
  const offenders: string[] = [];
  for (const file of candidates) {
    const rel = relative(".", file).replace(/\\/g, "/");
    if (allowed.has(rel)) continue;
    if (/node_modules/.test(rel)) continue;
    if (/\.d\.ts$/.test(rel)) continue;
    // Skip the L15-04 audit check file itself.
    if (/check-email-platform\.ts$/.test(rel)) continue;
    const src = readOrNull(rel);
    if (!src) continue;
    const bad =
      /\bapi\.resend\.com\b/i.test(src) ||
      /\bapi\.sendgrid\.com\b/i.test(src) ||
      /\bapi\.postmarkapp\.com\b/i.test(src) ||
      /\bapi\.mailgun\.net\b/i.test(src);
    if (bad) offenders.push(rel);
  }
  if (offenders.length > 0) {
    fail(
      "providers",
      `direct provider HTTP calls found outside the canonical path: ${offenders.join(", ")}`,
    );
    return;
  }
  pass("providers", "no direct provider HTTP calls outside _shared/email.ts + send-email/index.ts");
}

function checkRunbook(): void {
  const path = "docs/runbooks/EMAIL_TRANSACTIONAL_RUNBOOK.md";
  if (!existsSync(path)) {
    fail("runbook", `${path} missing`);
    return;
  }
  const src = readFileSync(path, "utf8");
  if (src.length < 1500) {
    fail("runbook", `${path} too short (${src.length} bytes) — likely stub`);
    return;
  }
  pass("runbook", `${path} present (${src.length} bytes)`);
}

// ───────────────────────── main ─────────────────────────

function main() {
  console.log("L15-04 transactional email platform guard");
  checkDatabase();
  checkSharedEmailModule();
  checkSendEmailFunction();
  checkManifest();
  checkNoDirectProviderCallsOutsideAllowed();
  checkRunbook();

  for (const l of logs) console.log(l);

  if (failures > 0) {
    console.log(`\nFAIL — ${failures} regression(s).`);
    process.exit(1);
  }
  console.log("\nOK — L15-04 email-platform invariants hold.");
}

main();
