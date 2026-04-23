/**
 * check-actions-pinned.ts
 *
 * L11-10 — CI guard enforcing that every `uses:` line in
 * `.github/workflows/*.yml` references a 40-char commit SHA, not a
 * mutable tag. Existing unpinned references are tracked by the
 * baseline file `tools/audit/baselines/actions-pinned-baseline.txt`
 * — new violations fail CI, repaying the legacy debt is gradual.
 *
 * The baseline format is one `<workflow>:<line>:<full uses line>` per
 * row. To regenerate after fixing a real violation, run with
 * `BASELINE_REGEN=1 npx tsx tools/audit/check-actions-pinned.ts`.
 */

import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const WF_DIR = resolve(ROOT, ".github", "workflows");
const BASELINE = resolve(ROOT, "tools", "audit", "baselines", "actions-pinned-baseline.txt");

interface Violation { file: string; line: number; raw: string; }

const SHA_TAIL = /@[a-f0-9]{40}(?:\s|$)/;
// Local actions or composite actions in the same repo
const LOCAL_USES = /uses:\s+\.\//;

function* walkWorkflows(): Generator<string> {
  for (const f of readdirSync(WF_DIR)) {
    if (f.endsWith(".yml") || f.endsWith(".yaml")) yield resolve(WF_DIR, f);
  }
}

function findViolations(): Violation[] {
  const violations: Violation[] = [];
  for (const file of walkWorkflows()) {
    const lines = readFileSync(file, "utf8").split("\n");
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!trimmed.startsWith("- uses:") && !trimmed.startsWith("uses:")) continue;
      if (LOCAL_USES.test(trimmed)) continue;
      if (SHA_TAIL.test(trimmed + " ")) continue;
      const rel = file.replace(ROOT + "/", "");
      violations.push({ file: rel, line: i + 1, raw: trimmed });
    }
  }
  return violations;
}

function loadBaseline(): Set<string> {
  if (!existsSync(BASELINE)) return new Set();
  return new Set(
    readFileSync(BASELINE, "utf8")
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l && !l.startsWith("#")),
  );
}

function key(v: Violation): string {
  return `${v.file}:${v.line}:${v.raw}`;
}

const violations = findViolations();

if (process.env.BASELINE_REGEN === "1") {
  const sorted = [...violations].sort((a, b) => key(a).localeCompare(key(b)));
  const body =
    "# L11-10 baseline — one '<workflow>:<uses line>' per row.\n" +
    "# Re-pin actions to commit SHAs and remove from this file to repay debt.\n" +
    sorted.map(key).join("\n") +
    "\n";
  writeFileSync(BASELINE, body);
  console.log(`[baseline] wrote ${sorted.length} entries to ${BASELINE}`);
  process.exit(0);
}

const baseline = loadBaseline();
const newViolations = violations.filter((v) => !baseline.has(key(v)));

console.log(
  `[L11-10] total unpinned actions: ${violations.length} | baseline: ${baseline.size} | new: ${newViolations.length}`,
);

if (newViolations.length > 0) {
  console.error("\n[FAIL] new unpinned actions detected:");
  for (const v of newViolations) {
    console.error(`  ${v.file}:${v.line}  ${v.raw}`);
  }
  console.error(
    "\nPin the action by replacing `@vX` with `@<40-char-SHA> # vX.Y.Z`.\n" +
      "Helper: `gh api repos/<owner>/<repo>/git/ref/tags/vX.Y.Z`.\n" +
      "If your change actually pinned an existing entry, regenerate the baseline:\n" +
      "  BASELINE_REGEN=1 npx tsx tools/audit/check-actions-pinned.ts\n",
  );
  process.exit(1);
}

const stale = [...baseline].filter(
  (k) => !violations.some((v) => key(v) === k),
);
if (stale.length > 0) {
  console.warn(
    `[WARN] ${stale.length} stale baseline entries (already fixed). Run BASELINE_REGEN=1 to clean up.`,
  );
}

console.log("\n[OK] no new unpinned actions.");
