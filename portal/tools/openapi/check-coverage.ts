/**
 * OpenAPI coverage + drift gate (L14-01).
 *
 *   npx tsx tools/openapi/check-coverage.ts
 *
 * Wired into `npm run openapi:check`. Run in CI BEFORE merging.
 *
 * Two checks:
 *
 *   (1) DRIFT — regenerates the v1 OpenAPI document in memory and
 *       compares it byte-for-byte (after canonical JSON
 *       serialization) with the committed `public/openapi-v1.json`.
 *       If they differ, the registered Zod schemas have changed and
 *       the file was not regenerated — fails CI with a clear "run
 *       npm run openapi:build" hint.
 *
 *   (2) COVERAGE — walks `src/app/api/**\/route.ts` and compares
 *       the path inventory against the union of:
 *
 *         - documented paths in the legacy hand-maintained
 *           `public/openapi.json` (kept for the v0 surface),
 *         - documented paths in the new `public/openapi-v1.json`
 *           (the v1 generator output),
 *         - the BASELINE list of grandfathered undocumented routes
 *           (frozen snapshot of the gap at the moment the gate was
 *           introduced; intentional decrement target).
 *
 *       Any route handler that is NOT in any of those three sets is
 *       a NEW undocumented route — fails CI. The baseline is what
 *       lets us turn the gate on today without forcing the whole
 *       team to write 30 schemas in one PR; the gap can shrink, but
 *       not grow.
 *
 * Exit codes:
 *
 *   0 — all checks passed
 *   1 — drift OR new undocumented route detected
 *   2 — invalid baseline / configuration error
 */

import * as fs from "node:fs";
import * as path from "node:path";

import { buildOpenApiDocument } from "../../src/lib/openapi/build";

const ROOT = path.resolve(__dirname, "../..");
const ROUTES_DIR = path.join(ROOT, "src", "app", "api");
const V1_OUT = path.join(ROOT, "public", "openapi-v1.json");
const LEGACY_DOC = path.join(ROOT, "public", "openapi.json");
const BASELINE = path.join(__dirname, "coverage-baseline.json");

interface Baseline {
  description: string;
  generated_at: string;
  undocumented_paths: string[];
}

// ---------- helpers ---------------------------------------------------------

function listRouteFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listRouteFiles(full, acc);
    else if (entry.isFile() && entry.name === "route.ts") acc.push(full);
  }
  return acc;
}

/**
 * Map a route.ts file path to its public API path:
 *
 *   src/app/api/swap/route.ts                   → /api/swap
 *   src/app/api/training-plan/[planId]/route.ts → /api/training-plan/{planId}
 */
function fileToApiPath(file: string): string {
  const rel = path.relative(path.join(ROOT, "src", "app"), file);
  const noRoute = rel.replace(/\/route\.ts$/, "");
  const segments = noRoute.split(path.sep);
  const transformed = segments.map((s) =>
    s.replace(/^\[(.+)\]$/, (_, name) => `{${name}}`),
  );
  return "/" + transformed.join("/");
}

function readJson<T>(file: string): T {
  return JSON.parse(fs.readFileSync(file, "utf-8")) as T;
}

function loadBaseline(): Baseline {
  if (!fs.existsSync(BASELINE)) {
    console.error(
      `[openapi:check] missing baseline at ${BASELINE} — generate with ` +
        `\`npx tsx tools/openapi/refresh-baseline.ts\` ` +
        `or commit the initial snapshot.`,
    );
    process.exit(2);
  }
  const b = readJson<Baseline>(BASELINE);
  if (!Array.isArray(b.undocumented_paths)) {
    console.error("[openapi:check] baseline malformed: expected " +
      "undocumented_paths: string[]");
    process.exit(2);
  }
  return b;
}

function documentedPaths(file: string): Set<string> {
  if (!fs.existsSync(file)) return new Set();
  const doc = readJson<{ paths?: Record<string, unknown> }>(file);
  return new Set(Object.keys(doc.paths ?? {}));
}

// ---------- (1) drift check -------------------------------------------------

function checkDrift(): boolean {
  if (!fs.existsSync(V1_OUT)) {
    console.error(
      `[openapi:check] FAIL — committed ${path.relative(ROOT, V1_OUT)} ` +
        `does not exist. Run \`npm run openapi:build\` and commit.`,
    );
    return false;
  }
  const committed = fs.readFileSync(V1_OUT, "utf-8");
  const fresh = JSON.stringify(buildOpenApiDocument(), null, 2) + "\n";
  if (committed === fresh) {
    console.log(
      `[openapi:check] OK — ${path.relative(ROOT, V1_OUT)} matches the ` +
        `current Zod registry.`,
    );
    return true;
  }
  console.error(
    `[openapi:check] FAIL — ${path.relative(ROOT, V1_OUT)} is stale.\n` +
      `        The committed file does not match what the registry ` +
      `would generate today.\n` +
      `        Fix: \`npm run openapi:build\` then commit the diff.`,
  );
  return false;
}

// ---------- (2) coverage check ----------------------------------------------

function checkCoverage(): boolean {
  const baseline = loadBaseline();
  const baselineSet = new Set(baseline.undocumented_paths);

  const allRoutes = new Set(
    listRouteFiles(ROUTES_DIR).map(fileToApiPath),
  );
  const docLegacy = documentedPaths(LEGACY_DOC);
  const docV1 = documentedPaths(V1_OUT);

  // Strip the v1/ prefix from generated paths so we don't double-count
  // them when checking coverage of the legacy file system layout.
  // Conversely, /api/v1/* route files are themselves route handlers
  // we want to be present in docV1 — they are.
  // We use Array.from(...) to flatten the Sets because the project's
  // tsconfig has no `target` set and rejects Set iteration in spread.
  const documentedSet = new Set<string>([
    ...Array.from(docLegacy),
    ...Array.from(docV1),
  ]);

  const undocumented: string[] = [];
  for (const route of Array.from(allRoutes).sort()) {
    if (documentedSet.has(route)) continue;
    if (baselineSet.has(route)) continue;
    undocumented.push(route);
  }

  // Report routes in the baseline that are now documented (so we know
  // when to shrink the baseline).
  const documentedFromBaseline: string[] = [];
  for (const route of baseline.undocumented_paths) {
    if (documentedSet.has(route)) documentedFromBaseline.push(route);
  }

  // Report routes in the baseline that no longer exist (route deleted).
  const goneFromBaseline: string[] = [];
  for (const route of baseline.undocumented_paths) {
    if (!allRoutes.has(route)) goneFromBaseline.push(route);
  }

  if (documentedFromBaseline.length > 0 || goneFromBaseline.length > 0) {
    console.log(
      `[openapi:check] INFO — baseline can be shrunk. The following ` +
        `paths can be removed from coverage-baseline.json:`,
    );
    for (const p of documentedFromBaseline)
      console.log(`        - ${p}  (now documented)`);
    for (const p of goneFromBaseline)
      console.log(`        - ${p}  (route deleted)`);
  }

  if (undocumented.length === 0) {
    console.log(
      `[openapi:check] OK — coverage. ${allRoutes.size} route handler(s); ` +
        `${docV1.size} v1 + ${docLegacy.size} legacy = ` +
        `${documentedSet.size} documented; ` +
        `${baseline.undocumented_paths.length} grandfathered.`,
    );
    return true;
  }

  console.error(
    `[openapi:check] FAIL — coverage. ${undocumented.length} route(s) ` +
      `added without OpenAPI documentation:`,
  );
  for (const p of undocumented) console.error(`        - ${p}`);
  console.error(
    `        Fix: register the route in src/lib/openapi/routes/, ` +
      `regenerate via \`npm run openapi:build\`, and commit.`,
  );
  console.error(
    `        Escape hatch (discouraged): add the path to ` +
      `tools/openapi/coverage-baseline.json and explain why in the PR.`,
  );
  return false;
}

// ---------- main ------------------------------------------------------------

const driftOk = checkDrift();
const coverageOk = checkCoverage();

if (!driftOk || !coverageOk) process.exit(1);
console.log("[openapi:check] all checks passed.");
