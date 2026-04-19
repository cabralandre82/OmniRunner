/**
 * One-shot helper to (re)generate `coverage-baseline.json` from the
 * current state of the world (L14-01).
 *
 *   npx tsx tools/openapi/refresh-baseline.ts
 *
 * Use this:
 *
 *   - Once, at gate introduction, to capture the existing
 *     undocumented routes as the grandfathered baseline. Commit.
 *   - When ops decides to formally widen the baseline (e.g. a new
 *     bulk-imported set of routes for a beta surface that won't be
 *     publicly documented yet). Commit with rationale in the PR.
 *
 * NEVER run this to "fix" CI when adding a new route — that defeats
 * the entire purpose of the gate. Documenting the route in the
 * registry is the right fix.
 */

import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");
const ROUTES_DIR = path.join(ROOT, "src", "app", "api");
const V1_OUT = path.join(ROOT, "public", "openapi-v1.json");
const LEGACY_DOC = path.join(ROOT, "public", "openapi.json");
const OUT = path.join(__dirname, "coverage-baseline.json");

function listRouteFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) listRouteFiles(full, acc);
    else if (entry.isFile() && entry.name === "route.ts") acc.push(full);
  }
  return acc;
}

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

const allRoutes = new Set(listRouteFiles(ROUTES_DIR).map(fileToApiPath));
const docLegacy = fs.existsSync(LEGACY_DOC)
  ? Object.keys(readJson<{ paths?: Record<string, unknown> }>(LEGACY_DOC).paths ?? {})
  : [];
const docV1 = fs.existsSync(V1_OUT)
  ? Object.keys(readJson<{ paths?: Record<string, unknown> }>(V1_OUT).paths ?? {})
  : [];
const documented = new Set([...docLegacy, ...docV1]);

const undocumented = Array.from(allRoutes)
  .filter((p) => !documented.has(p))
  .sort();

const baseline = {
  description:
    "Snapshot of API routes that are NOT documented in any OpenAPI " +
    "spec (neither legacy `openapi.json` nor v1 generator output). " +
    "These are GRANDFATHERED — the coverage gate (L14-01) will not " +
    "fail if a path in this list stays undocumented, but it WILL fail " +
    "if a NEW route is added that isn't documented and isn't here. " +
    "Shrink this list over time; never grow it without rationale.",
  generated_at: new Date().toISOString(),
  undocumented_paths: undocumented,
};

fs.writeFileSync(OUT, JSON.stringify(baseline, null, 2) + "\n", "utf-8");
console.log(
  `[openapi:baseline] wrote ${OUT} with ${undocumented.length} ` +
    `grandfathered path(s).`,
);
