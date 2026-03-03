/**
 * edge_function_inventory.ts
 *
 * Generates a formatted inventory table of all Supabase Edge Functions.
 * For each function, reports:
 *   - index.ts existence and file size
 *   - Imports from _shared/
 *   - /health endpoint presence
 *   - HTTP methods handled (GET/POST/PATCH/DELETE)
 *   - CORS handling
 *   - Auth validation approach (user JWT, service-role, webhook, none)
 *   - Rate limiting and input validation
 *
 * Usage:
 *   npx tsx tools/edge_function_inventory.ts
 */

import { readdirSync, readFileSync, statSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";

// ── Config ──────────────────────────────────────────────────────────────────

const FUNCTIONS_DIR = resolve(__dirname, "../supabase/functions");

interface FunctionEntry {
  name: string;
  exists: boolean;
  size: number;
  sharedImports: string[];
  hasHealth: boolean;
  httpMethods: string[];
  hasCors: boolean;
  authType: "user" | "service-role" | "webhook" | "none";
  hasRateLimit: boolean;
  hasValidation: boolean;
  hasErrorClassifier: boolean;
  hasObservability: boolean;
  description: string;
}

// ── Source analysis ─────────────────────────────────────────────────────────

function extractDescription(source: string): string {
  const jsdocMatch = source.match(
    /\/\*\*\s*\n\s*\*\s*(\S.*?)(?:\s*—|\s*\n)/,
  );
  if (jsdocMatch) return jsdocMatch[1].trim();

  const fnMatch = source.match(/const FN\s*=\s*["']([^"']+)["']/);
  if (fnMatch) return fnMatch[1];

  return "";
}

function analyzeFunction(name: string): FunctionEntry {
  const indexPath = join(FUNCTIONS_DIR, name, "index.ts");

  if (!existsSync(indexPath)) {
    return {
      name,
      exists: false,
      size: 0,
      sharedImports: [],
      hasHealth: false,
      httpMethods: [],
      hasCors: false,
      authType: "none",
      hasRateLimit: false,
      hasValidation: false,
      hasErrorClassifier: false,
      hasObservability: false,
      description: "",
    };
  }

  const source = readFileSync(indexPath, "utf8");
  const stat = statSync(indexPath);

  // Shared imports
  const sharedImports: string[] = [];
  const importRegex = /from\s+["']\.\.\/(_shared\/(\w+))\.ts["']/g;
  let match: RegExpExecArray | null;
  while ((match = importRegex.exec(source)) !== null) {
    if (!sharedImports.includes(match[2])) sharedImports.push(match[2]);
  }

  const hasHealth = source.includes("/health");

  // HTTP methods
  const methods: string[] = [];
  if (/req\.method\s*[!=]==?\s*["']POST["']/.test(source)) methods.push("POST");
  if (/req\.method\s*[!=]==?\s*["']GET["']/.test(source)) methods.push("GET");
  if (/req\.method\s*[!=]==?\s*["']PATCH["']/.test(source)) methods.push("PATCH");
  if (/req\.method\s*[!=]==?\s*["']DELETE["']/.test(source)) methods.push("DELETE");
  if (/req\.method\s*[!=]==?\s*["']PUT["']/.test(source)) methods.push("PUT");

  const hasCors =
    source.includes("handleCors") || source.includes("CORS_HEADERS");

  // Auth type detection
  let authType: FunctionEntry["authType"] = "none";
  const usesRequireUser = source.includes("requireUser");
  const checksServiceKey =
    source.includes("SERVICE_ROLE_KEY") || source.includes("serviceKey");

  if (usesRequireUser) {
    authType = "user";
  } else if (checksServiceKey) {
    const isWebhook =
      source.includes("stripe-signature") ||
      source.includes("STRAVA_VERIFY_TOKEN") ||
      name.startsWith("webhook-");
    authType = isWebhook ? "webhook" : "service-role";
  } else if (source.includes("Authorization") || source.includes("Bearer")) {
    authType = "user";
  }

  const hasRateLimit = source.includes("checkRateLimit");
  const hasValidation =
    source.includes("requireJson") || source.includes("requireFields");
  const hasErrorClassifier = source.includes("classifyError");
  const hasObservability =
    source.includes("logRequest") || source.includes("logError");

  const description = extractDescription(source);

  return {
    name,
    exists: true,
    size: stat.size,
    sharedImports,
    hasHealth,
    httpMethods: methods,
    hasCors,
    authType,
    hasRateLimit,
    hasValidation,
    hasErrorClassifier,
    hasObservability,
    description,
  };
}

// ── Table formatting ────────────────────────────────────────────────────────

function padRight(s: string, len: number): string {
  return s.length >= len ? s.slice(0, len) : s + " ".repeat(len - s.length);
}

function padLeft(s: string, len: number): string {
  return s.length >= len ? s : " ".repeat(len - s.length) + s;
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "-";
  if (bytes < 1024) return `${bytes}B`;
  return `${(bytes / 1024).toFixed(1)}K`;
}

function yn(val: boolean): string {
  return val ? "\x1b[32m✓\x1b[0m" : "\x1b[31m✗\x1b[0m";
}

function authLabel(type: FunctionEntry["authType"]): string {
  switch (type) {
    case "user":
      return "\x1b[36muser\x1b[0m";
    case "service-role":
      return "\x1b[33m svc\x1b[0m";
    case "webhook":
      return "\x1b[35mhook\x1b[0m";
    default:
      return "\x1b[31mnone\x1b[0m";
  }
}

// ── Categorization ──────────────────────────────────────────────────────────

function categorize(name: string): string {
  if (name.startsWith("challenge-")) return "Challenge";
  if (name.startsWith("champ-")) return "Championship";
  if (name.startsWith("clearing-")) return "Clearing";
  if (name.startsWith("strava-")) return "Strava";
  if (name.startsWith("webhook-")) return "Webhooks";
  if (
    name.startsWith("token-") ||
    name.includes("checkout") ||
    name.includes("purchase") ||
    name === "list-purchases" ||
    name === "process-refund" ||
    name.includes("portal-session") ||
    name.includes("auto-topup")
  )
    return "Billing";
  if (
    name.includes("leaderboard") ||
    name.includes("league") ||
    name.includes("badge") ||
    name.includes("matchmake") ||
    name.includes("wrapped") ||
    name.includes("progression")
  )
    return "Gamification";
  if (name.endsWith("-cron")) return "Cron";
  if (
    name.includes("account") ||
    name.includes("profile") ||
    name.includes("social") ||
    name.includes("role") ||
    name.includes("verification") ||
    name.includes("verify-session") ||
    name.includes("validate-social")
  )
    return "User/Profile";
  if (name.includes("push") || name.includes("notify")) return "Notifications";
  if (name.includes("analytics") || name.includes("running-dna"))
    return "Analytics";
  return "Other";
}

// ── Main ────────────────────────────────────────────────────────────────────

function main() {
  console.log("╔════════════════════════════════════════════════════════════╗");
  console.log("║          Edge Function Inventory                          ║");
  console.log("╚════════════════════════════════════════════════════════════╝\n");

  if (!existsSync(FUNCTIONS_DIR)) {
    console.error(`FATAL: functions directory not found: ${FUNCTIONS_DIR}`);
    process.exit(1);
  }

  const dirs = readdirSync(FUNCTIONS_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory() && d.name !== "_shared")
    .map((d) => d.name)
    .sort();

  const entries = dirs.map(analyzeFunction);

  // ── _shared/ inventory ────────────────────────────────────────────────
  const sharedDir = join(FUNCTIONS_DIR, "_shared");
  if (existsSync(sharedDir)) {
    const sharedFiles = readdirSync(sharedDir)
      .filter((f) => f.endsWith(".ts"))
      .sort();
    console.log(`\x1b[1m_shared/ modules (${sharedFiles.length}):\x1b[0m`);
    for (const f of sharedFiles) {
      const fp = join(sharedDir, f);
      const sz = statSync(fp).size;
      const moduleName = f.replace(".ts", "");
      const usedBy = entries.filter((e) =>
        e.sharedImports.includes(moduleName),
      ).length;
      console.log(
        `  ${padRight(f, 24)} ${padLeft(formatSize(sz), 6)}  used by ${padLeft(String(usedBy), 2)}/${entries.length} functions`,
      );
    }
    console.log();
  }

  // ── Main table ────────────────────────────────────────────────────────
  const NAME_W = 34;
  const SIZE_W = 7;

  const header = `${padRight("Function", NAME_W)} ${padLeft("Size", SIZE_W)}  Hlth  Auth   CORS  Rate  Vldt  Obs   Methods`;
  const separator = "─".repeat(header.length + 10);

  console.log(`\x1b[1m${header}\x1b[0m`);
  console.log(separator);

  for (const e of entries) {
    if (!e.exists) {
      console.log(
        `${padRight(e.name, NAME_W)} \x1b[31m  MISSING index.ts\x1b[0m`,
      );
      continue;
    }

    const line = [
      padRight(e.name, NAME_W),
      padLeft(formatSize(e.size), SIZE_W),
      ` ${yn(e.hasHealth)}   `,
      `${authLabel(e.authType)}  `,
      `${yn(e.hasCors)}    `,
      `${yn(e.hasRateLimit)}    `,
      `${yn(e.hasValidation)}    `,
      `${yn(e.hasObservability)}    `,
      e.httpMethods.join(",") || "-",
    ].join(" ");

    console.log(line);
  }

  console.log(separator);

  // ── Summary stats ─────────────────────────────────────────────────────
  const total = entries.length;
  const existing = entries.filter((e) => e.exists).length;
  const withHealth = entries.filter((e) => e.hasHealth).length;
  const withCors = entries.filter((e) => e.hasCors).length;
  const withRateLimit = entries.filter((e) => e.hasRateLimit).length;
  const withValidation = entries.filter((e) => e.hasValidation).length;
  const withObservability = entries.filter((e) => e.hasObservability).length;
  const withErrorClassifier = entries.filter((e) => e.hasErrorClassifier).length;
  const authCounts = {
    user: entries.filter((e) => e.authType === "user").length,
    "service-role": entries.filter((e) => e.authType === "service-role").length,
    webhook: entries.filter((e) => e.authType === "webhook").length,
    none: entries.filter((e) => e.authType === "none").length,
  };

  const totalSize = entries.reduce((sum, e) => sum + e.size, 0);

  console.log(`\n\x1b[1mSummary:\x1b[0m`);
  console.log(`  Total functions     : ${total}`);
  console.log(`  With index.ts       : ${existing}/${total}`);
  console.log(`  Total code size     : ${formatSize(totalSize)}`);
  console.log(`  With /health        : ${withHealth}/${total}`);
  console.log(`  With CORS           : ${withCors}/${total}`);
  console.log(`  With rate limit     : ${withRateLimit}/${total}`);
  console.log(`  With validation     : ${withValidation}/${total}`);
  console.log(`  With observability  : ${withObservability}/${total}`);
  console.log(`  With error classify : ${withErrorClassifier}/${total}`);
  console.log(
    `  Auth breakdown      : user=${authCounts.user}  svc=${authCounts["service-role"]}  webhook=${authCounts.webhook}  none=${authCounts.none}`,
  );

  // ── Missing capabilities ──────────────────────────────────────────────
  const gaps: string[] = [];
  const noHealth = entries.filter((e) => e.exists && !e.hasHealth);
  const noAuth = entries.filter((e) => e.exists && e.authType === "none");
  const noObs = entries.filter((e) => e.exists && !e.hasObservability);

  if (noHealth.length > 0)
    gaps.push(
      `Missing /health (${noHealth.length}): ${noHealth.map((e) => e.name).join(", ")}`,
    );
  if (noAuth.length > 0)
    gaps.push(
      `No auth (${noAuth.length}): ${noAuth.map((e) => e.name).join(", ")}`,
    );
  if (noObs.length > 0)
    gaps.push(
      `No observability (${noObs.length}): ${noObs.map((e) => e.name).join(", ")}`,
    );

  if (gaps.length > 0) {
    console.log(`\n\x1b[1m\x1b[33mGaps:\x1b[0m`);
    for (const g of gaps) {
      console.log(`  ⚠ ${g}`);
    }
  }

  // ── By category ───────────────────────────────────────────────────────
  const categoryMap = new Map<string, FunctionEntry[]>();
  for (const e of entries) {
    const cat = categorize(e.name);
    if (!categoryMap.has(cat)) categoryMap.set(cat, []);
    categoryMap.get(cat)!.push(e);
  }

  const sortedCategories = [...categoryMap.entries()].sort(
    (a, b) => b[1].length - a[1].length,
  );

  console.log(`\n\x1b[1mBy category:\x1b[0m`);
  for (const [cat, fns] of sortedCategories) {
    const catSize = fns.reduce((s, f) => s + f.size, 0);
    console.log(
      `  ${padRight(cat, 16)} (${padLeft(String(fns.length), 2)}) ${padLeft(formatSize(catSize), 7)}  ${fns.map((f) => f.name).join(", ")}`,
    );
  }

  // ── Shared import frequency ───────────────────────────────────────────
  const importFreq = new Map<string, number>();
  for (const e of entries) {
    for (const imp of e.sharedImports) {
      importFreq.set(imp, (importFreq.get(imp) ?? 0) + 1);
    }
  }

  const sortedImports = [...importFreq.entries()].sort(
    (a, b) => b[1] - a[1],
  );

  console.log(`\n\x1b[1m_shared/ import frequency:\x1b[0m`);
  for (const [mod, count] of sortedImports) {
    const bar = "█".repeat(Math.round((count / total) * 40));
    console.log(
      `  ${padRight(mod, 20)} ${padLeft(String(count), 3)}/${total}  ${bar}`,
    );
  }

  console.log();

  if (existing < total) process.exitCode = 1;
}

main();
