/**
 * check-portal-test-file-size.ts
 *
 * L17-04 — CI guard enforcing that no portal Vitest test file grows
 * back into the 800-line mega-suite shape we split in this
 * finding. The original `portal/src/lib/qa-e2e.test.ts` was 842 lines
 * across 4 describe blocks with a large shared mock DB at the top —
 * painful to read, prone to "comment out the broken describe" rot, and
 * slow to re-run on unrelated diffs.
 *
 * The split moved all shared fixtures into
 * `src/lib/__qa__/qa-e2e-fixtures.ts` and produced 4 focused test
 * files each under 200 lines:
 *   - qa-e2e-smoke.test.ts         (section 1: 8 tests)
 *   - qa-e2e-idempotency.test.ts   (section 2: 4 tests)
 *   - qa-e2e-antifraud.test.ts     (section 3: 8 tests)
 *   - qa-e2e-concurrency.test.ts   (section 4: 4 tests)
 *
 * Invariants enforced by this check:
 *   1. No portal/src/**\/*.test.ts file exceeds HARD_LIMIT lines
 *      (default 800). Hard cap — a failure here is a fail.
 *   2. portal/src/**\/*.test.ts files SHOULD stay under SOFT_LIMIT
 *      lines (default 400). Soft cap — a failure here is a warn but
 *      does NOT fail the build. Files legitimately over the soft cap
 *      today are grandfathered via ALLOWLIST.
 *   3. The 4 qa-e2e-* files all exist and the monolithic
 *      qa-e2e.test.ts is gone (so we do not accidentally restore the
 *      old shape via merge).
 *
 * Usage:
 *   npm run audit:portal-test-file-size
 */

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = "portal/src";
const HARD_LIMIT = 800;
const SOFT_LIMIT = 400;

/**
 * Files that legitimately exceed the soft cap today but are not
 * mega-suites in the L17-04 sense (e.g. `custody/webhook/route.test.ts`
 * exercises 30+ gateway payload shapes and splitting costs more than
 * it saves). Keep this list tiny — a new entry needs code review.
 */
const ALLOWLIST = new Set<string>([
  "src/app/api/custody/webhook/route.test.ts",
  "src/lib/partnerships.test.ts",
  "src/lib/money.test.ts",
  "src/lib/schemas.test.ts",
  "src/app/api/swap/route.test.ts",
  "src/lib/clearing.test.ts",
  "src/lib/swap.test.ts",
  "src/app/api/coins/reverse/route.test.ts",
  "src/lib/api/csrf.test.ts",
]);

const QA_SPLIT_REQUIRED = [
  "portal/src/lib/qa-e2e-smoke.test.ts",
  "portal/src/lib/qa-e2e-idempotency.test.ts",
  "portal/src/lib/qa-e2e-antifraud.test.ts",
  "portal/src/lib/qa-e2e-concurrency.test.ts",
  "portal/src/lib/__qa__/qa-e2e-fixtures.ts",
];

const QA_MONOLITH_FORBIDDEN = "portal/src/lib/qa-e2e.test.ts";

type Finding = {
  file: string;
  lines: number;
  severity: "hard" | "soft";
};

function walkTests(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === "node_modules" || entry.name === ".next") continue;
      out.push(...walkTests(full));
    } else if (entry.isFile() && /\.test\.tsx?$/.test(entry.name)) {
      out.push(full);
    }
  }
  return out;
}

function countLines(abs: string): number {
  const content = readFileSync(abs, "utf8");
  if (content.length === 0) return 0;
  return content.split(/\r?\n/).length;
}

function exists(relPath: string): boolean {
  try {
    statSync(relPath);
    return true;
  } catch {
    return false;
  }
}

function main(): number {
  console.log(
    `L17-04 portal test-file size guard (HARD=${HARD_LIMIT}, SOFT=${SOFT_LIMIT})`,
  );

  let exitCode = 0;

  for (const requiredFile of QA_SPLIT_REQUIRED) {
    if (!exists(requiredFile)) {
      console.error(
        `  [FAIL] missing expected split file: ${requiredFile}`,
      );
      exitCode = 1;
    } else {
      console.log(`  [OK] exists: ${requiredFile}`);
    }
  }

  if (exists(QA_MONOLITH_FORBIDDEN)) {
    console.error(
      `  [FAIL] the monolithic ${QA_MONOLITH_FORBIDDEN} is back — splits regressed`,
    );
    exitCode = 1;
  } else {
    console.log(`  [OK] monolith absent: ${QA_MONOLITH_FORBIDDEN}`);
  }

  const testFiles = walkTests(ROOT);
  const hard: Finding[] = [];
  const soft: Finding[] = [];

  for (const abs of testFiles) {
    const rel = relative("portal", abs);
    const lines = countLines(abs);
    if (lines > HARD_LIMIT) {
      hard.push({ file: rel, lines, severity: "hard" });
    } else if (lines > SOFT_LIMIT && !ALLOWLIST.has(rel)) {
      soft.push({ file: rel, lines, severity: "soft" });
    }
  }

  if (hard.length > 0) {
    console.error(
      `\n  HARD CAP (> ${HARD_LIMIT} lines) — these files MUST be split:`,
    );
    for (const f of hard) {
      console.error(`    [FAIL] ${f.file} (${f.lines} lines)`);
    }
    exitCode = 1;
  } else {
    console.log(`  [OK] no file exceeds the hard cap of ${HARD_LIMIT} lines`);
  }

  if (soft.length > 0) {
    console.warn(
      `\n  SOFT CAP (> ${SOFT_LIMIT} lines, non-allowlisted) — consider splitting:`,
    );
    for (const f of soft) {
      console.warn(`    [WARN] ${f.file} (${f.lines} lines)`);
    }
    console.warn(
      `  (Soft-cap hits do not fail the build. Add to ALLOWLIST only after review.)`,
    );
  } else {
    console.log(
      `  [OK] no non-allowlisted file exceeds the soft cap of ${SOFT_LIMIT} lines`,
    );
  }

  if (exitCode !== 0) {
    console.error(
      `\nFAIL — see docs/runbooks/PORTAL_TEST_FILE_SIZE_RUNBOOK.md.`,
    );
    return exitCode;
  }

  console.log(`\nOK — portal test-file size invariants hold (L17-04).`);
  return 0;
}

process.exit(main());
