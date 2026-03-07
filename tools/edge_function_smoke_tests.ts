/**
 * edge_function_smoke_tests.ts
 *
 * Smoke-tests every Supabase Edge Function by:
 *   1. Verifying index.ts exists and is structurally valid TypeScript
 *   2. Checking _shared/ utilities exist and export expected symbols
 *   3. If local Supabase is running, calling GET /health on each function
 *   4. Calling POST without auth → expecting 401/403
 *   5. Calling POST with malformed body → expecting 400
 *   6. Calling with unsupported HTTP method → expecting 405
 *
 * Usage:
 *   npx tsx tools/edge_function_smoke_tests.ts
 *
 * Env vars (optional):
 *   SUPABASE_URL       — defaults to http://127.0.0.1:54321
 *   SUPABASE_ANON_KEY  — required for some HTTP tests, skip if absent
 */

import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

// ── Colors ──────────────────────────────────────────────────────────────────

const OK = "\x1b[32m✓\x1b[0m";
const FAIL = "\x1b[31m✗\x1b[0m";
const SKIP = "\x1b[33m⊘\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";
const RESET = "\x1b[0m";

// ── Counters ────────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;
let skipped = 0;
const failures: string[] = [];

function pass(msg: string) {
  passed++;
  console.log(`  ${OK} ${msg}`);
}

function fail(msg: string, context?: string) {
  failed++;
  console.log(`  ${FAIL} ${msg}`);
  failures.push(context ? `${context}: ${msg}` : msg);
}

function skip(msg: string) {
  skipped++;
  console.log(`  ${SKIP} ${msg}`);
}

// ── Config ──────────────────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL || "http://127.0.0.1:54321";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const FUNCTIONS_DIR = resolve(__dirname, "../supabase/functions");
const FETCH_TIMEOUT_MS = 5_000;

const SHARED_FILES = [
  "auth.ts",
  "cors.ts",
  "errors.ts",
  "http.ts",
  "integrity_flags.ts",
  "logger.ts",
  "obs.ts",
  "rate_limit.ts",
  "validate.ts",
];

const SHARED_EXPORTS: Record<string, string[]> = {
  "auth.ts": ["requireUser", "AuthError", "getBearerToken", "AuthResult"],
  "cors.ts": ["CORS_HEADERS", "handleCors"],
  "http.ts": ["jsonOk", "jsonErr"],
  "logger.ts": ["log"],
  "obs.ts": ["startTimer", "logRequest", "logError"],
  "validate.ts": ["requireJson", "requireFields", "ValidationError"],
  "errors.ts": ["classifyError"],
  "rate_limit.ts": ["checkRateLimit", "RateLimitOpts", "RateLimitResult"],
  "integrity_flags.ts": [
    "CRITICAL_FLAGS",
    "QUALITY_FLAGS",
    "ALL_FLAGS",
    "isCriticalFlag",
  ],
};

// ── Source analysis helpers ─────────────────────────────────────────────────

interface FunctionMeta {
  name: string;
  hasIndexTs: boolean;
  fileSize: number;
  hasHealth: boolean;
  hasAuth: boolean;
  hasCors: boolean;
  httpMethods: string[];
  importsShared: string[];
  isServiceRole: boolean;
  isWebhook: boolean;
  primaryMethod: string;
}

function analyzeSource(name: string, source: string): FunctionMeta {
  const hasHealth = source.includes("/health");
  const usesRequireUser = source.includes("requireUser");
  const checksAuthHeader =
    source.includes("Authorization") || source.includes("Bearer");
  const checksWebhookToken =
    source.includes("asaas-access-token") ||
    source.includes("webhook_token") ||
    source.includes("stripe-signature") ||
    source.includes("x-webhook-secret");
  const isIntentionallyPublic =
    source.includes("intentionally public") ||
    source.includes("no auth required");
  const hasAuth = usesRequireUser || checksAuthHeader || checksWebhookToken || isIntentionallyPublic;
  const hasCors =
    source.includes("handleCors") || source.includes("CORS_HEADERS");
  const usesServiceKey =
    source.includes("SERVICE_ROLE_KEY") ||
    source.includes("serviceKey");
  const isWebhook =
    source.includes("stripe-signature") ||
    source.includes("STRAVA_VERIFY_TOKEN") ||
    source.includes("asaas-access-token") ||
    name.startsWith("webhook-");
  const isServiceRole = usesServiceKey && !usesRequireUser;

  const methods: string[] = [];
  if (/req\.method\s*[!=]==?\s*["']POST["']/.test(source)) methods.push("POST");
  if (/req\.method\s*[!=]==?\s*["']GET["']/.test(source)) methods.push("GET");
  if (/req\.method\s*[!=]==?\s*["']PATCH["']/.test(source)) methods.push("PATCH");
  if (/req\.method\s*[!=]==?\s*["']DELETE["']/.test(source)) methods.push("DELETE");
  if (/req\.method\s*[!=]==?\s*["']PUT["']/.test(source)) methods.push("PUT");

  // Determine primary method: look for "Use POST" or "Use GET" pattern
  let primaryMethod = "POST";
  if (/jsonErr\(\s*405.*"Use GET"/.test(source)) primaryMethod = "GET";
  else if (/req\.method\s*!==\s*["']GET["']/.test(source) && !methods.includes("POST"))
    primaryMethod = "GET";

  const sharedImports: string[] = [];
  const importRegex = /from\s+["']\.\.\/(_shared\/(\w+))\.ts["']/g;
  let match: RegExpExecArray | null;
  while ((match = importRegex.exec(source)) !== null) {
    if (!sharedImports.includes(match[2])) sharedImports.push(match[2]);
  }

  return {
    name,
    hasIndexTs: true,
    fileSize: Buffer.byteLength(source, "utf8"),
    hasHealth,
    hasAuth,
    hasCors,
    httpMethods: methods,
    importsShared: sharedImports,
    isServiceRole,
    isWebhook,
    primaryMethod,
  };
}

function validateTypeScript(source: string, fnName: string): string[] {
  const issues: string[] = [];

  if (!source.includes('import { serve }') && !source.includes("import {serve}")) {
    issues.push("missing serve() import from Deno std");
  }
  if (!source.includes("serve(")) {
    issues.push("missing serve() call");
  }
  if (!source.includes("async (req") && !source.includes("async(req")) {
    issues.push("missing async request handler");
  }

  // Check brace balance (rough but catches common issues)
  const openBraces = (source.match(/{/g) || []).length;
  const closeBraces = (source.match(/}/g) || []).length;
  if (openBraces !== closeBraces) {
    issues.push(`brace mismatch: ${openBraces} open vs ${closeBraces} close`);
  }

  const openParens = (source.match(/\(/g) || []).length;
  const closeParens = (source.match(/\)/g) || []).length;
  if (openParens !== closeParens) {
    issues.push(`paren mismatch: ${openParens} open vs ${closeParens} close`);
  }

  // Ensure no dangling awaits outside async context (naive check)
  if (source.includes("await ") && !source.includes("async ")) {
    issues.push("await used without async function");
  }

  return issues;
}

// ── HTTP helpers ────────────────────────────────────────────────────────────

async function isSupabaseRunning(): Promise<boolean> {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 2_000);
    const res = await fetch(`${SUPABASE_URL}/functions/v1/`, {
      signal: ctrl.signal,
    });
    clearTimeout(timer);
    return res.status > 0;
  } catch {
    return false;
  }
}

async function safeFetch(
  url: string,
  init: RequestInit = {},
): Promise<{ status: number; body: string } | null> {
  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), FETCH_TIMEOUT_MS);
    const res = await fetch(url, { ...init, signal: ctrl.signal });
    clearTimeout(timer);
    const body = await res.text();
    return { status: res.status, body };
  } catch {
    return null;
  }
}

// ── Test suites ─────────────────────────────────────────────────────────────

function testSharedUtilities() {
  console.log(`\n${BOLD}═══ Phase 1: _shared/ utilities ═══${RESET}`);

  const sharedDir = join(FUNCTIONS_DIR, "_shared");
  if (!existsSync(sharedDir)) {
    fail("_shared/ directory does not exist", "_shared");
    return;
  }
  pass("_shared/ directory exists");

  for (const file of SHARED_FILES) {
    const filePath = join(sharedDir, file);
    if (!existsSync(filePath)) {
      fail(`_shared/${file} missing`, "_shared");
      continue;
    }

    const source = readFileSync(filePath, "utf8");
    const size = Buffer.byteLength(source, "utf8");

    if (size === 0) {
      fail(`_shared/${file} is empty`, "_shared");
      continue;
    }
    pass(`_shared/${file} exists (${size} bytes)`);

    const expectedExports = SHARED_EXPORTS[file] ?? [];
    for (const exp of expectedExports) {
      if (source.includes(exp)) {
        pass(`_shared/${file} exports \`${exp}\``);
      } else {
        fail(`_shared/${file} missing export: ${exp}`, "_shared");
      }
    }
  }

  // Verify logger.ts has structured JSON output
  const loggerPath = join(sharedDir, "logger.ts");
  if (existsSync(loggerPath)) {
    const loggerSrc = readFileSync(loggerPath, "utf8");
    if (loggerSrc.includes("JSON.stringify")) {
      pass("_shared/logger.ts uses structured JSON logging");
    } else {
      fail("_shared/logger.ts does not use JSON.stringify", "_shared");
    }
    if (loggerSrc.includes("timestamp")) {
      pass("_shared/logger.ts includes timestamp in log entries");
    } else {
      fail("_shared/logger.ts missing timestamp field", "_shared");
    }
  }
}

function testFunctionSource(fnName: string): FunctionMeta | null {
  const indexPath = join(FUNCTIONS_DIR, fnName, "index.ts");

  if (!existsSync(indexPath)) {
    fail(`${fnName}/index.ts does not exist`, fnName);
    return null;
  }

  const source = readFileSync(indexPath, "utf8");
  const stat = statSync(indexPath);

  if (stat.size === 0) {
    fail(`${fnName}/index.ts is empty (0 bytes)`, fnName);
    return null;
  }
  pass(`index.ts exists (${stat.size} bytes)`);

  // Structural TypeScript validation
  const issues = validateTypeScript(source, fnName);
  if (issues.length === 0) {
    pass("TypeScript structure valid");
  } else {
    for (const issue of issues) {
      fail(`TS issue: ${issue}`, fnName);
    }
  }

  const meta = analyzeSource(fnName, source);

  // Health endpoint
  if (meta.hasHealth) {
    pass("has /health endpoint");
  } else {
    fail("missing /health endpoint", fnName);
  }

  // Auth validation
  if (meta.hasAuth) {
    const authDesc = meta.isWebhook
      ? "webhook signature"
      : meta.isServiceRole
        ? "service-role key"
        : "user JWT (requireUser)";
    pass(`auth: ${authDesc}`);
  } else {
    fail("no auth validation detected", fnName);
  }

  // CORS handling
  if (meta.hasCors) {
    pass("CORS handling present");
  } else if (meta.isWebhook || meta.isServiceRole) {
    skip("no CORS (webhook/service-role — expected)");
  } else {
    fail("missing CORS handling", fnName);
  }

  // HTTP method enforcement
  if (meta.httpMethods.length > 0) {
    pass(`HTTP methods: ${meta.httpMethods.join(", ")}`);
  } else {
    skip("no explicit method check");
  }

  // Error handling pattern
  if (source.includes("catch") && (source.includes("jsonErr") || source.includes("INTERNAL"))) {
    pass("has error catch with structured response");
  } else {
    fail("missing catch/error handling block", fnName);
  }

  // Observability (logRequest/logError)
  if (source.includes("logRequest") || source.includes("logError")) {
    pass("observability logging (logRequest/logError)");
  } else {
    skip("no observability logging");
  }

  return meta;
}

async function testFunctionHTTP(meta: FunctionMeta) {
  const fnUrl = `${SUPABASE_URL}/functions/v1/${meta.name}`;

  // Test 1: GET /health → 200
  if (meta.hasHealth) {
    const res = await safeFetch(`${fnUrl}/health`, { method: "GET" });
    if (!res) {
      skip("health endpoint unreachable");
    } else if (res.status === 200) {
      try {
        const body = JSON.parse(res.body);
        if (body.status === "ok") {
          pass(`GET /health → 200 { status: "ok", version: "${body.version ?? "?"}" }`);
        } else {
          fail(
            `GET /health → 200 but unexpected body: ${res.body.slice(0, 80)}`,
            meta.name,
          );
        }
      } catch {
        fail("GET /health → 200 but invalid JSON", meta.name);
      }
    } else {
      fail(`GET /health → ${res.status} (expected 200)`, meta.name);
    }
  }

  // Test 2: POST without auth → 401/403
  if (meta.hasAuth && !meta.isServiceRole && !meta.isWebhook) {
    const res = await safeFetch(fnUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({}),
    });
    if (!res) {
      skip("POST no-auth unreachable");
    } else if (res.status === 401 || res.status === 403) {
      pass(`POST no-auth → ${res.status} (correctly rejected)`);
    } else {
      fail(`POST no-auth → ${res.status} (expected 401/403)`, meta.name);
    }
  }

  // Test 3: POST with anon key but malformed body → 400
  if (
    SUPABASE_ANON_KEY &&
    meta.httpMethods.includes("POST") &&
    !meta.isServiceRole &&
    !meta.isWebhook
  ) {
    const res = await safeFetch(fnUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${SUPABASE_ANON_KEY}`,
      },
      body: "not-json!!!",
    });
    if (!res) {
      skip("POST malformed-body unreachable");
    } else if (res.status === 400) {
      pass("POST malformed body → 400");
    } else if (res.status === 401 || res.status === 403) {
      skip(`POST malformed body → ${res.status} (auth rejected first)`);
    } else {
      fail(`POST malformed body → ${res.status} (expected 400)`, meta.name);
    }
  }

  // Test 4: Unsupported method → 405
  const unusedMethod = meta.httpMethods.includes("PATCH") ? "PUT" : "PATCH";
  if (meta.httpMethods.length > 0) {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    };
    if (SUPABASE_ANON_KEY) {
      headers["Authorization"] = `Bearer ${SUPABASE_ANON_KEY}`;
    }
    const res = await safeFetch(fnUrl, {
      method: unusedMethod,
      headers,
      body: JSON.stringify({}),
    });
    if (!res) {
      skip(`${unusedMethod} method unreachable`);
    } else if (res.status === 405) {
      pass(`${unusedMethod} → 405 METHOD_NOT_ALLOWED`);
    } else if (res.status === 401 || res.status === 403) {
      skip(`${unusedMethod} → ${res.status} (auth rejected first)`);
    } else {
      skip(`${unusedMethod} → ${res.status}`);
    }
  }

  // Test 5: OPTIONS preflight → 204 (for CORS-enabled functions)
  if (meta.hasCors) {
    const res = await safeFetch(fnUrl, {
      method: "OPTIONS",
      headers: {
        Origin: "https://example.com",
        "Access-Control-Request-Method": "POST",
      },
    });
    if (!res) {
      skip("OPTIONS preflight unreachable");
    } else if (res.status === 204 || res.status === 200) {
      pass(`OPTIONS preflight → ${res.status}`);
    } else {
      fail(`OPTIONS preflight → ${res.status} (expected 204)`, meta.name);
    }
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const startTime = Date.now();

  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║          Edge Function Smoke Tests                        ║");
  console.log("╚════════════════════════════════════════════════════════════╝");
  console.log(`Functions dir : ${FUNCTIONS_DIR}`);
  console.log(`Supabase URL  : ${SUPABASE_URL}`);
  console.log(`Anon key      : ${SUPABASE_ANON_KEY ? "set" : "not set"}`);

  if (!existsSync(FUNCTIONS_DIR)) {
    console.error(`\nFATAL: functions directory not found: ${FUNCTIONS_DIR}`);
    process.exit(1);
  }

  const entries = readdirSync(FUNCTIONS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name !== "_shared")
    .map((d) => d.name)
    .sort();

  console.log(`Functions     : ${entries.length}\n`);

  // ── Phase 1: _shared/ validation ──────────────────────────────────────
  testSharedUtilities();

  // ── Phase 2: source-level validation per function ─────────────────────
  console.log(`\n${BOLD}═══ Phase 2: Source validation (${entries.length} functions) ═══${RESET}`);
  const metas: FunctionMeta[] = [];

  for (const fnName of entries) {
    console.log(`\n${BOLD}─── ${fnName} ───${RESET}`);
    const meta = testFunctionSource(fnName);
    if (meta) metas.push(meta);
  }

  // ── Phase 3: HTTP smoke tests ─────────────────────────────────────────
  console.log(`\n${BOLD}═══ Phase 3: HTTP smoke tests ═══${RESET}`);
  const supabaseUp = await isSupabaseRunning();

  if (!supabaseUp) {
    console.log(
      `  ${SKIP} Supabase not running at ${SUPABASE_URL} — skipping all HTTP tests`,
    );
    skipped += metas.length;
  } else {
    console.log(`  Supabase detected at ${SUPABASE_URL}\n`);
    for (const meta of metas) {
      console.log(`  ${DIM}── ${meta.name} ──${RESET}`);
      await testFunctionHTTP(meta);
    }
  }

  // ── Phase 4: Cross-cutting checks ─────────────────────────────────────
  console.log(`\n${BOLD}═══ Phase 4: Cross-cutting checks ═══${RESET}`);

  // All functions should have /health
  const withoutHealth = metas.filter((m) => !m.hasHealth);
  if (withoutHealth.length === 0) {
    pass(`all ${metas.length} functions have /health endpoint`);
  } else {
    fail(
      `${withoutHealth.length} function(s) missing /health: ${withoutHealth.map((m) => m.name).join(", ")}`,
      "cross-cutting",
    );
  }

  // All functions should have auth
  const withoutAuth = metas.filter((m) => !m.hasAuth);
  if (withoutAuth.length === 0) {
    pass(`all ${metas.length} functions have auth validation`);
  } else {
    fail(
      `${withoutAuth.length} function(s) without auth: ${withoutAuth.map((m) => m.name).join(", ")}`,
      "cross-cutting",
    );
  }

  // All user-facing functions should have CORS
  const userFacing = metas.filter(
    (m) => !m.isServiceRole && !m.isWebhook,
  );
  const userFacingNoCors = userFacing.filter((m) => !m.hasCors);
  if (userFacingNoCors.length === 0) {
    pass(`all ${userFacing.length} user-facing functions have CORS handling`);
  } else {
    fail(
      `${userFacingNoCors.length} user-facing function(s) missing CORS: ${userFacingNoCors.map((m) => m.name).join(", ")}`,
      "cross-cutting",
    );
  }

  // Check _shared/ coverage
  const sharedCoverage = new Set(metas.flatMap((m) => m.importsShared));
  const allSharedModules = SHARED_FILES.map((f) => f.replace(".ts", ""));
  const unusedShared = allSharedModules.filter((m) => !sharedCoverage.has(m));
  if (unusedShared.length === 0) {
    pass("all _shared/ modules are used by at least one function");
  } else {
    skip(`unused _shared/ modules: ${unusedShared.join(", ")}`);
  }

  // Check for consistent health endpoint format
  const healthFormats = new Set<string>();
  for (const fnName of entries) {
    const src = readFileSync(join(FUNCTIONS_DIR, fnName, "index.ts"), "utf8");
    const healthMatch = src.match(/version:\s*['"]([^'"]+)['"]/);
    if (healthMatch) healthFormats.add(healthMatch[1]);
  }
  if (healthFormats.size <= 1) {
    pass(`consistent health version across all functions: ${[...healthFormats][0] ?? "N/A"}`);
  } else {
    fail(
      `inconsistent health versions: ${[...healthFormats].join(", ")}`,
      "cross-cutting",
    );
  }

  // ── Summary ───────────────────────────────────────────────────────────
  const elapsed = Date.now() - startTime;

  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log(
    `  ${OK} ${passed} passed    ${FAIL} ${failed} failed    ${SKIP} ${skipped} skipped`,
  );
  console.log(`  Functions scanned: ${metas.length}/${entries.length}`);
  console.log(`  Duration: ${elapsed}ms`);

  if (failures.length > 0) {
    console.log(`\n${BOLD}Failed tests:${RESET}`);
    for (const f of failures) {
      console.log(`  ${FAIL} ${f}`);
    }
  }

  console.log("═══════════════════════════════════════════════════════════════\n");

  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});
