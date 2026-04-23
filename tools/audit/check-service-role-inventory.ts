/**
 * check-service-role-inventory.ts
 *
 * L10-03 — CI guard that every consumer of
 * `SUPABASE_SERVICE_ROLE_KEY` (and its env variants) appears in
 * the canonical inventory at
 * `docs/security/SERVICE_ROLE_USAGE_INVENTORY.md`.
 *
 * Invariants:
 *   1. Every non-`node_modules` / non-`.git` file that mentions
 *      SUPABASE_SERVICE_ROLE_KEY is listed in the inventory.
 *   2. The inventory cross-links to the L10-03 finding and the
 *      rotation runbook.
 *   3. The rotation runbook exists, references the finding, and
 *      names the environment-specific secret variants.
 *
 * Usage: npm run audit:service-role-inventory
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, relative } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const SKIP_DIRS = new Set([
  "node_modules",
  ".git",
  ".next",
  "dist",
  "build",
  ".turbo",
  "coverage",
  ".vercel",
  "out",
]);
const INTERESTING_EXTS = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".cjs",
  ".yml",
  ".yaml",
  ".sh",
  ".toml",
]);

// Consumers that are *allowed* to reference the key without being
// in the main inventory: the inventory file itself, this guard,
// and the rotation runbook (since they all document the pattern).
const ALLOW_DOCUMENTS = new Set<string>([
  "docs/security/SERVICE_ROLE_USAGE_INVENTORY.md",
  "docs/runbooks/SERVICE_ROLE_ROTATION_RUNBOOK.md",
  "tools/audit/check-service-role-inventory.ts",
]);

function walk(dir: string, out: string[]): void {
  let entries: string[];
  try { entries = readdirSync(dir); } catch { return; }
  for (const entry of entries) {
    if (SKIP_DIRS.has(entry)) continue;
    if (entry.startsWith(".")) continue;
    const abs = resolve(dir, entry);
    let st;
    try { st = statSync(abs); } catch { continue; }
    if (st.isDirectory()) {
      walk(abs, out);
    } else if (st.isFile()) {
      const ext = abs.slice(abs.lastIndexOf("."));
      if (INTERESTING_EXTS.has(ext)) out.push(abs);
    }
  }
}

const files: string[] = [];
walk(ROOT, files);

const KEY_RE =
  /SUPABASE_SERVICE_ROLE_KEY(?:_STAGING|_PREVIEW|_CI)?/;

const hits: string[] = [];
for (const abs of files) {
  let content: string;
  try { content = readFileSync(abs, "utf8"); } catch { continue; }
  if (KEY_RE.test(content)) {
    const rel = relative(ROOT, abs).replace(/\\/g, "/");
    hits.push(rel);
  }
}

const inventoryPath = resolve(
  ROOT,
  "docs/security/SERVICE_ROLE_USAGE_INVENTORY.md",
);
const inventory = safeRead(inventoryPath, "service-role inventory present");

const runbookPath = resolve(
  ROOT,
  "docs/runbooks/SERVICE_ROLE_ROTATION_RUNBOOK.md",
);
const runbook = safeRead(runbookPath, "service-role rotation runbook present");

if (inventory) {
  push(
    "inventory references L10-03 finding",
    /findings\/L10-03-service-role-key-distribuida-amplamente\.md/.test(
      inventory,
    ),
  );
  push(
    "inventory references rotation runbook",
    /runbooks\/SERVICE_ROLE_ROTATION_RUNBOOK\.md/.test(inventory),
  );
  push(
    "inventory names all four env variants",
    [
      "SUPABASE_SERVICE_ROLE_KEY",
      "SUPABASE_SERVICE_ROLE_KEY_STAGING",
      "SUPABASE_SERVICE_ROLE_KEY_PREVIEW",
      "SUPABASE_SERVICE_ROLE_KEY_CI",
    ].every((k) => inventory.includes(k)),
  );

  const unlisted: string[] = [];
  for (const hit of hits) {
    if (ALLOW_DOCUMENTS.has(hit)) continue;
    if (!inventory.includes(hit)) unlisted.push(hit);
  }
  push(
    "every consumer is listed in the inventory",
    unlisted.length === 0,
    unlisted.length === 0
      ? undefined
      : `unlisted files (${unlisted.length}): ${unlisted.slice(0, 5).join(", ")}${unlisted.length > 5 ? ", ..." : ""}`,
  );
}

if (runbook) {
  push(
    "runbook references L10-03 finding",
    /findings\/L10-03-service-role-key-distribuida-amplamente\.md/.test(
      runbook,
    ),
  );
  push(
    "runbook names all four env variants",
    [
      "SUPABASE_SERVICE_ROLE_KEY",
      "SUPABASE_SERVICE_ROLE_KEY_STAGING",
      "SUPABASE_SERVICE_ROLE_KEY_PREVIEW",
      "SUPABASE_SERVICE_ROLE_KEY_CI",
    ].every((k) => runbook.includes(k)),
  );
  push(
    "runbook declares quarterly cadence",
    /quarterly/i.test(runbook),
  );
  push(
    "runbook documents ad-hoc rotation path",
    /ad.hoc|suspected leak/i.test(runbook),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L10-03-service-role-key-distribuida-amplamente.md",
);
const finding = safeRead(findingPath, "L10-03 finding present");
if (finding) {
  push(
    "finding references rotation runbook",
    /SERVICE_ROLE_ROTATION_RUNBOOK\.md/.test(finding),
  );
  push(
    "finding references inventory",
    /SERVICE_ROLE_USAGE_INVENTORY\.md/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} service-role-inventory checks passed.`,
);
if (failed > 0) {
  console.error("\nL10-03 invariants broken.");
  process.exit(1);
}
