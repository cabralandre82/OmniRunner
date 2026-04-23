/**
 * check-flutter-clean-arch.ts
 *
 * L18-04 — CI guard for Clean Architecture fences in `omni_runner/lib`.
 *
 * The Flutter app follows a layered layout:
 *   - `presentation/` (screens, widgets, blocs) — UI concerns only.
 *   - `features/`     (feature-specific UI + bloc, same rules as presentation).
 *   - `domain/`       (entities, value objects, usecases, repo interfaces) — pure.
 *   - `data/`         (repositories_impl, datasources, services) — IO adapters.
 *   - `core/`         (infra: router, di, logging, storage).
 *
 * Canonical fences enforced by this guard:
 *
 *   1. `presentation/*` and `features/*` MUST NOT import `data/*`.
 *   2. `presentation/*` and `features/*` MUST NOT import 3rd-party IO
 *      clients directly (`package:supabase_flutter`, `package:drift`,
 *      `package:dio`, `package:http`, `package:sqflite`).
 *      Use a repository interface declared in `domain/repositories/`.
 *   3. `domain/*` MUST NOT import `data/*`, `presentation/*`,
 *      `features/*`, `core/*`, or any of the 3rd-party IO clients.
 *      `domain/` is the pure core.
 *   4. `data/*` MAY import `domain/*` (implements contracts), but
 *      MUST NOT import `presentation/*` or `features/*`.
 *   5. `core/*` MAY import `domain/*` but MUST NOT import `data/*`
 *      or `presentation/*`.
 *
 * Existing violations are frozen in
 * `tools/audit/baselines/flutter-clean-arch-baseline.txt`.
 * New violations fail; stale baseline entries also fail (ratchet
 * monotonically decreases).
 */

import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { resolve, relative, sep } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const LIB_ROOT = resolve(ROOT, "omni_runner", "lib");
const BASELINE_PATH = resolve(
  ROOT,
  "tools",
  "audit",
  "baselines",
  "flutter-clean-arch-baseline.txt",
);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

// ────────────────────────────────────────────────────────────────────
// Layer detection
// ────────────────────────────────────────────────────────────────────

type Layer =
  | "presentation"
  | "features"
  | "domain"
  | "data"
  | "core"
  | "other";

function layerOf(relPath: string): Layer {
  const [top] = relPath.split(sep);
  switch (top) {
    case "presentation":
    case "features":
    case "domain":
    case "data":
    case "core":
      return top;
    default:
      return "other";
  }
}

// ────────────────────────────────────────────────────────────────────
// Forbidden-edge catalogue
// ────────────────────────────────────────────────────────────────────

interface ForbiddenEdge {
  readonly source: Layer;
  readonly targetPattern: RegExp;
  readonly label: string;
}

const FORBIDDEN_EDGES: ForbiddenEdge[] = [
  // Rule 1: UI → data
  {
    source: "presentation",
    targetPattern: /^package:omni_runner\/data\//,
    label: "presentation → data (must go through repository interface)",
  },
  {
    source: "features",
    targetPattern: /^package:omni_runner\/data\//,
    label: "features → data (must go through repository interface)",
  },

  // Rule 2: UI → 3rd-party IO clients
  {
    source: "presentation",
    targetPattern:
      /^package:(supabase_flutter|drift|dio|http|sqflite|firebase_firestore|cloud_firestore)\//,
    label: "presentation → 3rd-party IO client (must go through repository)",
  },
  {
    source: "features",
    targetPattern:
      /^package:(supabase_flutter|drift|dio|http|sqflite|firebase_firestore|cloud_firestore)\//,
    label: "features → 3rd-party IO client (must go through repository)",
  },

  // Rule 3: domain must be pure
  {
    source: "domain",
    targetPattern: /^package:omni_runner\/data\//,
    label: "domain → data (domain must be pure / outbound-only contracts)",
  },
  {
    source: "domain",
    targetPattern: /^package:omni_runner\/presentation\//,
    label: "domain → presentation (domain cannot depend on UI)",
  },
  {
    source: "domain",
    targetPattern: /^package:omni_runner\/features\//,
    label: "domain → features (domain cannot depend on feature modules)",
  },
  {
    source: "domain",
    targetPattern: /^package:omni_runner\/core\//,
    label: "domain → core (domain cannot depend on infra)",
  },
  {
    source: "domain",
    targetPattern:
      /^package:(supabase_flutter|drift|dio|http|sqflite|firebase_firestore|cloud_firestore|get_it|flutter\/)/,
    label: "domain → 3rd-party IO / DI / framework (domain must be pure)",
  },

  // Rule 4: data → presentation/features
  {
    source: "data",
    targetPattern: /^package:omni_runner\/(presentation|features)\//,
    label: "data → UI layer (inverted dependency)",
  },

  // Rule 5: core → data/presentation
  {
    source: "core",
    targetPattern: /^package:omni_runner\/data\//,
    label: "core → data (core sits below data)",
  },
  {
    source: "core",
    targetPattern: /^package:omni_runner\/presentation\//,
    label: "core → presentation (core sits below UI)",
  },
];

// ────────────────────────────────────────────────────────────────────
// File enumeration
// ────────────────────────────────────────────────────────────────────

function walk(dir: string): string[] {
  const out: string[] = [];
  if (!existsSync(dir)) return out;
  for (const name of readdirSync(dir)) {
    const abs = resolve(dir, name);
    const st = statSync(abs);
    if (st.isDirectory()) {
      out.push(...walk(abs));
    } else if (name.endsWith(".dart") && !name.endsWith(".g.dart")) {
      out.push(abs);
    }
  }
  return out;
}

const dartFiles = walk(LIB_ROOT);
push(`discovered ${dartFiles.length} .dart files under omni_runner/lib`, dartFiles.length >= 50);

// ────────────────────────────────────────────────────────────────────
// Import parsing
// ────────────────────────────────────────────────────────────────────

const IMPORT_RE = /^\s*import\s+["']([^"']+)["'];?\s*$/gm;

interface Violation {
  sourceFile: string;
  sourceLayer: Layer;
  spec: string;
  line: number;
  label: string;
}

const violations: Violation[] = [];

/**
 * Exemption: the DI composition root (`core/di/*`) is BY DESIGN the
 * single place allowed to wire concrete implementations across all
 * layers.  A "Clean Arch violation" here is the whole point of the
 * composition root.  We only exempt that specific directory.
 */
function isExempt(relPath: string): boolean {
  const posix = relPath.split(sep).join("/");
  return (
    // DI is the single composition root authorised to wire concretes.
    posix.startsWith("core/di/") ||
    // Router is a UI composition root (binds routes to screens/blocs).
    posix.startsWith("core/router/") ||
    // Push navigation handler dispatches to screens for deep-link clicks.
    posix.startsWith("core/push/") ||
    // App entry point wires the tree.
    posix === "main.dart"
  );
}

for (const file of dartFiles) {
  const rel = relative(LIB_ROOT, file);
  const layer = layerOf(rel);
  if (layer === "other") continue;
  if (isExempt(rel)) continue;
  const src = readFileSync(file, "utf8");
  let m: RegExpExecArray | null;
  while ((m = IMPORT_RE.exec(src)) !== null) {
    const spec = m[1];
    const lineNo = src.slice(0, m.index).split("\n").length;
    for (const rule of FORBIDDEN_EDGES) {
      if (rule.source !== layer) continue;
      if (rule.targetPattern.test(spec)) {
        violations.push({
          sourceFile: "omni_runner/lib/" + rel.split(sep).join("/"),
          sourceLayer: layer,
          spec,
          line: lineNo,
          label: rule.label,
        });
      }
    }
  }
}

// ────────────────────────────────────────────────────────────────────
// Layer-coverage assertions
// ────────────────────────────────────────────────────────────────────

function countLayer(l: Layer): number {
  return dartFiles.filter(
    (f) => layerOf(relative(LIB_ROOT, f)) === l,
  ).length;
}

push(`layer "presentation" has files`, countLayer("presentation") > 0);
push(`layer "domain" has files`, countLayer("domain") > 0);
push(`layer "data" has files`, countLayer("data") > 0);
push(`layer "core" has files`, countLayer("core") > 0);

// ────────────────────────────────────────────────────────────────────
// Baseline ratchet
// ────────────────────────────────────────────────────────────────────

function violationKey(v: Violation): string {
  return `${v.sourceFile}|${v.sourceLayer}|${v.spec}`;
}

function readBaseline(): Set<string> {
  if (!existsSync(BASELINE_PATH)) return new Set();
  return new Set(
    readFileSync(BASELINE_PATH, "utf8")
      .split("\n")
      .map((s) => s.trim())
      .filter((s) => s && !s.startsWith("#")),
  );
}

const baseline = readBaseline();
const currentKeys = new Set(violations.map(violationKey));

if (process.env.UPDATE_BASELINE === "1") {
  const sorted = [...currentKeys].sort();
  const header = [
    "# L18-04 Flutter Clean Architecture baseline.",
    "# This file is a DEBT LEDGER — it must only shrink.",
    "# Regenerate with: UPDATE_BASELINE=1 npm run audit:flutter-clean-arch",
    "",
  ].join("\n");
  writeFileSync(BASELINE_PATH, header + sorted.join("\n") + "\n");
  console.log(`wrote ${sorted.length} baseline entries to ${BASELINE_PATH}`);
  process.exit(0);
}

const newViolations = violations.filter((v) => !baseline.has(violationKey(v)));
const staleBaseline = [...baseline].filter((k) => !currentKeys.has(k));

push(
  `ratchet — no NEW Clean Arch violations (${newViolations.length} found)`,
  newViolations.length === 0,
  newViolations.length > 0
    ? newViolations
        .slice(0, 8)
        .map(
          (v) =>
            `\n  ${v.sourceFile}:${v.line}\n    ${v.spec}\n    ${v.label}`,
        )
        .join("")
    : undefined,
);
push(
  `ratchet — no stale baseline entries (${staleBaseline.length} found)`,
  staleBaseline.length === 0,
  staleBaseline.length > 0
    ? "\n  " + staleBaseline.slice(0, 8).join("\n  ")
    : undefined,
);

// ────────────────────────────────────────────────────────────────────
// Finding cross-reference
// ────────────────────────────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs",
  "audit",
  "findings",
  "L18-04-architecture-flutter-viola-clean-arch-em-varios-pontos.md",
);
if (existsSync(findingPath)) {
  const f = readFileSync(findingPath, "utf8");
  push("finding — references CI guard", /audit:flutter-clean-arch|check-flutter-clean-arch/.test(f));
  push("finding — status marked fixed", /status:\s*fixed/.test(f));
  push(
    "finding — references baseline file",
    /flutter-clean-arch-baseline\.txt|baseline ratchet/.test(f),
  );
  push(
    "finding — enumerates canonical layering rules",
    /presentation.*must not.*data|domain.*pure|Clean Arch/i.test(f),
  );
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
  `\n${results.length - failed}/${results.length} flutter-clean-arch checks passed.`,
);
if (failed > 0) {
  console.error(
    "\nL18-04 invariants broken. If a new cross-layer import is intentional, " +
      "refactor via a repository interface; only regenerate the baseline " +
      "(UPDATE_BASELINE=1) when genuinely paying down debt.",
  );
  process.exit(1);
}
