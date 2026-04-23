/**
 * check-portal-bounded-contexts.ts
 *
 * L17-02 — CI guard enforcing the `portal/src/lib` bounded-context
 * manifest.  This guard does NOT require a physical refactor of
 * existing files; it pins the logical layering in a single source
 * of truth (`portal/src/lib/_boundaries/manifest.ts`) and fails the
 * build when:
 *
 *   1. A non-test file or subdirectory in `portal/src/lib` is NOT
 *      claimed by the manifest.
 *   2. The manifest claims a path that does not exist on disk.
 *   3. LAYERING_RULES is violated by an import whose source and
 *      target are both claimed by the manifest — e.g., a file in
 *      the pure-domain context reaches into `supabase/*`.
 *
 * Baseline ratchet: pre-existing violations that would be painful
 * to fix atomically are captured in
 * `tools/audit/baselines/portal-bounded-contexts-baseline.txt`.
 * New violations always fail; stale baseline entries (already
 * fixed) also fail, forcing the baseline to shrink monotonically.
 */

import { readFileSync, existsSync, statSync, readdirSync, writeFileSync } from "node:fs";
import { resolve, relative, basename, dirname } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const LIB_DIR = resolve(ROOT, "portal", "src", "lib");
const BASELINE_PATH = resolve(
  ROOT,
  "tools",
  "audit",
  "baselines",
  "portal-bounded-contexts-baseline.txt",
);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

// ────────────────────────────────────────────────────────────────────
// Step 1 — load the manifest (by regex-reading the TS source, so the
//          guard can run without compiling the project).
// ────────────────────────────────────────────────────────────────────

const manifestPath = resolve(LIB_DIR, "_boundaries", "manifest.ts");
if (!existsSync(manifestPath)) {
  console.error(`[FAIL] manifest missing at ${manifestPath}`);
  process.exit(1);
}
const manifestSrc = readFileSync(manifestPath, "utf8");

const CONTEXT_NAMES = [
  "financial",
  "security",
  "platform",
  "infra",
  "domain",
  "integration",
  "shared",
  "qa",
  "boundaries",
] as const;
type BoundedContext = (typeof CONTEXT_NAMES)[number];

interface ManifestEntry { path: string; context: BoundedContext; }

const entryRe = /\{\s*path:\s*"([^"]+)",\s*context:\s*"([^"]+)"[^}]*\}/g;
const entries: ManifestEntry[] = [];
let m: RegExpExecArray | null;
while ((m = entryRe.exec(manifestSrc)) !== null) {
  entries.push({
    path: m[1],
    context: m[2] as BoundedContext,
  });
}
push(`manifest — parsed ${entries.length} entries`, entries.length >= 40);

const manifestByPath = new Map<string, BoundedContext>();
for (const e of entries) manifestByPath.set(e.path, e.context);

const layerRe = /\[\s*"([a-z]+)",\s*"([a-z]+)"\s*\]/g;
const layerPairs = new Set<string>();
let lm: RegExpExecArray | null;
// Only parse pairs appearing in the LAYERING_RULES block.
const layeringBlockStart = manifestSrc.indexOf("LAYERING_RULES");
const layeringBlockEnd = manifestSrc.indexOf("Query helpers", layeringBlockStart);
const layeringBody = manifestSrc.slice(layeringBlockStart, layeringBlockEnd);
while ((lm = layerRe.exec(layeringBody)) !== null) {
  layerPairs.add(`${lm[1]}:${lm[2]}`);
}
push(`manifest — parsed ${layerPairs.size} layering rules`, layerPairs.size >= 15);

function allowsImport(source: BoundedContext, target: BoundedContext): boolean {
  if (source === target) return true;
  return layerPairs.has(`${source}:${target}`);
}

// ────────────────────────────────────────────────────────────────────
// Step 2 — enumerate disk entries and cross-check against manifest.
// ────────────────────────────────────────────────────────────────────

const diskEntries: string[] = readdirSync(LIB_DIR).filter((n) => {
  if (n.startsWith(".")) return false;
  // Ignore plain *.test.ts files at the top level because they are
  // typically adjacent tests for an already-classified sibling.
  if (/^[a-z][a-z0-9-]*\.test\.ts$/.test(n)) {
    // But keep middleware-routes.test.ts and partnerships.test.ts
    // because they test router/context-crossing concerns and we
    // want the manifest to claim them explicitly.
    if (n === "middleware-routes.test.ts" || n === "partnerships.test.ts") return true;
    return false;
  }
  return true;
});

// 2a — every disk entry must be claimed
const unclaimed = diskEntries.filter((d) => !manifestByPath.has(d));
push(
  `cross-check — every disk entry is claimed (0 unclaimed)`,
  unclaimed.length === 0,
  unclaimed.length > 0 ? `unclaimed: ${unclaimed.join(", ")}` : undefined,
);

// 2b — every manifest entry must exist on disk
const missing = entries.filter((e) => !existsSync(resolve(LIB_DIR, e.path)));
push(
  `cross-check — every manifest entry exists on disk`,
  missing.length === 0,
  missing.length > 0 ? `missing: ${missing.map((e) => e.path).join(", ")}` : undefined,
);

// 2c — manifest spans all expected core contexts
for (const c of ["financial", "security", "platform", "infra", "domain"] as const) {
  const n = entries.filter((e) => e.context === c).length;
  push(`manifest — context "${c}" has members`, n > 0, `count=${n}`);
}

// ────────────────────────────────────────────────────────────────────
// Step 3 — scan imports and flag cross-context violations.
// ────────────────────────────────────────────────────────────────────

interface Violation {
  sourceFile: string;
  sourceContext: BoundedContext;
  targetPath: string;
  targetContext: BoundedContext;
  line: number;
}

function listFilesRecursive(dir: string): string[] {
  const out: string[] = [];
  for (const n of readdirSync(dir)) {
    const abs = resolve(dir, n);
    const st = statSync(abs);
    if (st.isDirectory()) out.push(...listFilesRecursive(abs));
    else if (/\.(ts|tsx)$/.test(n) && !/\.(d|test|spec)\.(ts|tsx)$/.test(n))
      out.push(abs);
  }
  return out;
}

/** Given an absolute file path inside LIB_DIR, return the top-level claim. */
function claimFor(absFile: string): { name: string; context: BoundedContext } | null {
  const rel = relative(LIB_DIR, absFile);
  if (rel.startsWith("..")) return null;
  const top = rel.split("/")[0];
  const ctx = manifestByPath.get(top);
  if (!ctx) return null;
  return { name: top, context: ctx };
}

/** Resolve a relative import like "./foo" or "../bar/baz" to top-level entry. */
function resolveRelativeImport(
  sourceAbs: string,
  spec: string,
): { name: string; context: BoundedContext } | null {
  if (!spec.startsWith(".")) return null;
  const absTarget = resolve(dirname(sourceAbs), spec);
  return claimFor(absTarget);
}

/** Resolve "@/lib/foo/bar" import to top-level claim. */
function resolveAliasImport(spec: string): { name: string; context: BoundedContext } | null {
  const m = /^@\/lib\/([^/]+)(?:\/|$)/.exec(spec);
  if (!m) return null;
  const top = m[1].endsWith(".ts") ? m[1] : (manifestByPath.has(m[1]) ? m[1] : `${m[1]}.ts`);
  const ctx = manifestByPath.get(top) ?? manifestByPath.get(m[1]);
  if (!ctx) return null;
  return { name: top, context: ctx };
}

const IMPORT_RE = /import[^"']+["']([^"']+)["'];?/g;
const violations: Violation[] = [];

const allFiles = listFilesRecursive(LIB_DIR);
for (const file of allFiles) {
  const origin = claimFor(file);
  if (!origin) continue;
  // Skip the manifest file itself and boundary metadata.
  if (file === manifestPath) continue;
  if (origin.context === "boundaries") continue;
  const src = readFileSync(file, "utf8");
  const lines = src.split("\n");
  let match: RegExpExecArray | null;
  while ((match = IMPORT_RE.exec(src)) !== null) {
    const spec = match[1];
    let target: { name: string; context: BoundedContext } | null = null;
    if (spec.startsWith(".")) target = resolveRelativeImport(file, spec);
    else if (spec.startsWith("@/lib/")) target = resolveAliasImport(spec);
    if (!target) continue;
    if (target.name === origin.name) continue; // same top-level family is fine
    if (!allowsImport(origin.context, target.context)) {
      const upToMatch = src.slice(0, match.index);
      const line = upToMatch.split("\n").length;
      violations.push({
        sourceFile: relative(ROOT, file),
        sourceContext: origin.context,
        targetPath: target.name,
        targetContext: target.context,
        line,
      });
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// Step 4 — apply baseline ratchet.
// ────────────────────────────────────────────────────────────────────

function readBaseline(): Set<string> {
  if (!existsSync(BASELINE_PATH)) return new Set();
  return new Set(
    readFileSync(BASELINE_PATH, "utf8")
      .split("\n")
      .map((s) => s.trim())
      .filter((s) => s && !s.startsWith("#")),
  );
}

function violationKey(v: Violation): string {
  return `${v.sourceFile}|${v.sourceContext}->${v.targetContext}|${v.targetPath}`;
}

const baseline = readBaseline();
const currentKeys = new Set(violations.map(violationKey));

const UPDATE = process.env.UPDATE_BASELINE === "1";

if (UPDATE) {
  const sorted = [...currentKeys].sort();
  const header = [
    "# L17-02 bounded-context baseline — pre-existing cross-layer imports.",
    "# Regenerate with: UPDATE_BASELINE=1 npm run audit:portal-bounded-contexts",
    "# This file is a DEBT LEDGER — it must only shrink, never grow.",
    "",
  ].join("\n");
  writeFileSync(BASELINE_PATH, header + sorted.join("\n") + "\n");
  console.log(`wrote ${sorted.length} baseline entries to ${BASELINE_PATH}`);
  process.exit(0);
}

const newViolations = violations.filter((v) => !baseline.has(violationKey(v)));
const staleBaseline = [...baseline].filter((k) => !currentKeys.has(k));

push(
  `ratchet — no NEW cross-context imports (${newViolations.length} found)`,
  newViolations.length === 0,
  newViolations.length > 0
    ? newViolations
        .slice(0, 5)
        .map(
          (v) =>
            `  ${v.sourceFile}:${v.line} (${v.sourceContext} → ${v.targetContext} via ${v.targetPath})`,
        )
        .join("\n")
    : undefined,
);
push(
  `ratchet — no stale baseline entries (${staleBaseline.length} found)`,
  staleBaseline.length === 0,
  staleBaseline.length > 0
    ? staleBaseline.slice(0, 5).join("\n  ")
    : undefined,
);

// ────────────────────────────────────────────────────────────────────
// Step 5 — finding cross-ref
// ────────────────────────────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs",
  "audit",
  "findings",
  "L17-02-5378-linhas-em-portal-src-lib-ts-e.md",
);
if (existsSync(findingPath)) {
  const f = readFileSync(findingPath, "utf8");
  push("finding — references manifest path", /_boundaries\/manifest\.ts/.test(f));
  push("finding — references CI guard", /audit:portal-bounded-contexts|check-portal-bounded-contexts/.test(f));
  push("finding — status marked fixed", /status:\s*fixed/.test(f));
}

// ────────────────────────────────────────────────────────────────────
// Summary
// ────────────────────────────────────────────────────────────────────

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} portal-bounded-contexts checks passed.`,
);
if (failed > 0) {
  console.error(
    "\nL17-02 invariants broken. If a new cross-context import is intentional, " +
      "update the manifest and run with UPDATE_BASELINE=1 to refresh the ratchet.",
  );
  process.exit(1);
}
