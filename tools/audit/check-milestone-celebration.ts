/**
 * check-milestone-celebration.ts
 *
 * L22-09 — CI guard for the milestone-celebration subsystem.
 *
 * Fails closed if:
 *
 *   1. `MilestoneKind` enum file is missing or one of the 9
 *      shipped kinds disappears.
 *   2. A kind's `dedupKey` is empty, duplicated, or touches a
 *      persisted string (see "changing a value in-place is a
 *      migration" note on the enum).
 *   3. `MilestoneCopyBuilder` stops handling one of the 9 kinds
 *      in any of the 3 supported locales.
 *   4. `CELEBRATION_RUNBOOK.md` is missing or no longer cross-
 *      links this guard.
 *
 * Usage:
 *   npm run audit:milestone-celebration
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const KIND_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/value_objects/milestone_kind.dart",
);
const COPY_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/milestone_copy_builder.dart",
);
const DETECTOR_PATH = resolve(
  REPO_ROOT,
  "omni_runner/lib/domain/services/milestone_detector.dart",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/CELEBRATION_RUNBOOK.md",
);

const REQUIRED_KINDS = [
  "firstRun",
  "firstFiveK",
  "firstTenK",
  "firstHalfMarathon",
  "firstMarathon",
  "firstWeek",
  "streakSeven",
  "streakThirty",
  "longestRunEver",
] as const;

const REQUIRED_LOCALES = ["ptBR", "en", "es"] as const;

type CheckResult = { ok: boolean; label: string; detail?: string };
const results: CheckResult[] = [];

function push(label: string, ok: boolean, detail?: string) {
  results.push({ ok, label, detail });
}

function safeRead(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
}

// 1. MilestoneKind enum
{
  const src = safeRead(KIND_PATH);
  if (src === null) {
    push("milestone_kind.dart present", false, `missing: ${KIND_PATH}`);
  } else {
    push("milestone_kind.dart present", true);
    for (const k of REQUIRED_KINDS) {
      // Enum variants in Dart are written as `kind(` followed by
      // the named-params block. Regex pins the exact start-of-line
      // declaration.
      const re = new RegExp(`^\\s*${k}\\(`, "m");
      push(`enum declares ${k}`, re.test(src));
    }

    // Collect dedup keys via regex.
    const keyRe = /dedupKey:\s*'([^']+)'/g;
    const keys: string[] = [];
    let m: RegExpExecArray | null;
    while ((m = keyRe.exec(src)) !== null) {
      keys.push(m[1]);
    }
    push(
      "enum carries 9 dedupKey literals",
      keys.length === 9,
      `found ${keys.length}`,
    );
    const uniqueKeys = new Set(keys);
    push(
      "every dedupKey is unique",
      uniqueKeys.size === keys.length,
      `unique=${uniqueKeys.size} total=${keys.length}`,
    );
    for (const k of keys) {
      push(`dedupKey "${k}" is non-empty`, k.length > 0);
    }
  }
}

// 2. Copy builder covers every kind × every locale
{
  const src = safeRead(COPY_PATH);
  if (src === null) {
    push("milestone_copy_builder.dart present", false, `missing: ${COPY_PATH}`);
  } else {
    push("milestone_copy_builder.dart present", true);
    for (const locale of REQUIRED_LOCALES) {
      const methodName = `_${locale}(`;
      push(`builder has _${locale} method`, src.includes(methodName));
    }
    for (const kind of REQUIRED_KINDS) {
      // Each branch is `case MilestoneKind.kindName:` — we accept
      // it appearing any number of times (once per locale
      // switch). CI fails if ZERO occurrences.
      const re = new RegExp(`case\\s+MilestoneKind\\.${kind}\\s*:`, "g");
      const matches = src.match(re) ?? [];
      push(
        `builder branches on MilestoneKind.${kind} (≥3 times, once per locale)`,
        matches.length >= 3,
        `found ${matches.length}`,
      );
    }
    push(
      "builder exports requiredKinds list",
      /static\s+const\s+List<MilestoneKind>\s+requiredKinds\s*=/.test(src),
    );
  }
}

// 3. Detector file present + cardinality assertion
{
  const src = safeRead(DETECTOR_PATH);
  if (src === null) {
    push("milestone_detector.dart present", false, `missing: ${DETECTOR_PATH}`);
  } else {
    push("milestone_detector.dart present", true);
    push(
      "detector references firstWeekSessionThreshold constant",
      /firstWeekSessionThreshold/.test(src),
    );
  }
}

// 4. Runbook mutual-linkage
{
  const src = safeRead(RUNBOOK_PATH);
  if (src === null) {
    push("CELEBRATION_RUNBOOK.md present", false, `missing: ${RUNBOOK_PATH}`);
  } else {
    push("CELEBRATION_RUNBOOK.md present", true);
    push(
      "runbook cross-links CI guard script name",
      src.includes("check-milestone-celebration"),
    );
    push("runbook cross-links finding L22-09", src.includes("L22-09"));
  }
}

// Render
let failed = 0;
for (const r of results) {
  const mark = r.ok ? "PASS" : "FAIL";
  const line = r.detail ? `${mark} ${r.label} — ${r.detail}` : `${mark} ${r.label}`;
  // eslint-disable-next-line no-console
  console.log(line);
  if (!r.ok) failed += 1;
}
// eslint-disable-next-line no-console
console.log(`\n${results.length - failed}/${results.length} checks passed.`);

if (failed > 0) process.exit(1);
