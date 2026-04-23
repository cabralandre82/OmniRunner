/**
 * check-sqlcipher-eol.ts
 *
 * L11-07 — CI guard enforcing the "pin and watch" posture for
 * `sqlcipher_flutter_libs` in the Flutter app. The upstream package
 * is end-of-life (`0.7.0+eol`) and will receive no further security
 * patches. Our posture (see `docs/adr/009-sqlcipher-eol-migration.md`)
 * is to:
 *
 *   1. Pin the plugin EXACTLY (no caret/tilde/range) so that a
 *      transitive name-squat fork cannot silently get picked up
 *      by `pub get`.
 *   2. Keep a documented migration plan (ADR + runbook) evergreen
 *      so an engineer triggered by a CVE / store rejection / etc.
 *      has a step-by-step response path, not a blank page.
 *   3. Keep Dependabot quiet for this package so no one ends up
 *      merging a bogus "bump" PR out of habit.
 *
 * This guard rejects any PR that slips through the above posture.
 *
 * Checks (all must pass for exit 0):
 *
 *   (a) `omni_runner/pubspec.yaml` contains a line that declares
 *       `sqlcipher_flutter_libs: 0.7.0+eol` (plain, no leading
 *       `^`/`~`, no range operators, no alternate version).
 *   (b) A non-empty warning comment block precedes that line
 *       (`# L11-07 ...`) so the intent is visible at edit time,
 *       not just at PR time.
 *   (c) `docs/adr/009-sqlcipher-eol-migration.md` exists and is
 *       non-empty.
 *   (d) `docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md` exists and is
 *       non-empty.
 *   (e) `.github/dependabot.yml` contains `sqlcipher_flutter_libs`
 *       somewhere in the `drift-and-storage` patterns block.
 *
 * Usage:
 *   npx tsx tools/audit/check-sqlcipher-eol.ts
 *
 * Exit 0 = clean. Exit 1 = at least one regression.
 */

import { existsSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

const PUBSPEC = "omni_runner/pubspec.yaml";
const ADR = "docs/adr/009-sqlcipher-eol-migration.md";
const RUNBOOK = "docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md";
const DEPENDABOT = ".github/dependabot.yml";

const EXPECTED_VERSION = "0.7.0+eol";
const PACKAGE_NAME = "sqlcipher_flutter_libs";

interface Violation {
  kind:
    | "missing_pubspec"
    | "pin_drift"
    | "missing_warning_block"
    | "missing_adr"
    | "missing_runbook"
    | "missing_dependabot_ignore";
  detail: string;
  path?: string;
  line?: number;
  snippet?: string;
  fix: string;
}

function readText(relPath: string): string | null {
  const full = join(ROOT, relPath);
  if (!existsSync(full)) return null;
  const stat = statSync(full);
  if (!stat.isFile()) return null;
  return readFileSync(full, "utf8");
}

/**
 * A declaration is "exact" here iff the value (after the `:`, before
 * any trailing comment) is literally `0.7.0+eol`. Anything with a
 * leading `^` / `~`, any comparator (`>=`/`<=`/`>`/`<`), any range
 * (`-`/`||`), any wildcard (`*`/`x`), or any alias (`git:`/`path:`/
 * `hosted:`/`sdk:`) fails.
 *
 * Note: `pub` uses slightly different range syntax than npm — this
 * function is tuned for pub, not npm.
 */
function isExactPubVersion(raw: string): boolean {
  const value = raw.trim();
  if (value !== EXPECTED_VERSION) {
    // Reject all other forms — this is the ONLY acceptable version
    // for this package in this posture. A future migration will
    // remove the package entirely, not bump it.
    return false;
  }
  return true;
}

function checkPubspec(violations: Violation[]): void {
  const body = readText(PUBSPEC);
  if (body === null) {
    violations.push({
      kind: "missing_pubspec",
      detail: `pubspec not found at ${PUBSPEC}`,
      path: PUBSPEC,
      fix: "restore omni_runner/pubspec.yaml from git history",
    });
    return;
  }

  const lines = body.split(/\r?\n/);
  let pinLineIdx = -1;
  let pinValueRaw = "";

  // Match a top-level pubspec dependency line:
  //   `  sqlcipher_flutter_libs: <value>  # optional trailing comment`
  // We accept any indentation since pubspec keys are indented under
  // `dependencies:`.
  const pinRe = new RegExp(
    `^\\s*${PACKAGE_NAME}\\s*:\\s*([^#\\n]*?)\\s*(?:#.*)?$`,
  );

  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(pinRe);
    if (m) {
      pinLineIdx = i;
      pinValueRaw = m[1];
      break;
    }
  }

  if (pinLineIdx < 0) {
    violations.push({
      kind: "pin_drift",
      detail: `pubspec does not declare ${PACKAGE_NAME} at all`,
      path: PUBSPEC,
      fix:
        `add \`${PACKAGE_NAME}: ${EXPECTED_VERSION}\` under dependencies: in ` +
        "omni_runner/pubspec.yaml, or if the package was removed " +
        "intentionally (migrated away), also remove this guard and " +
        "supersede ADR-009 with a new ADR.",
    });
    return;
  }

  if (!isExactPubVersion(pinValueRaw)) {
    violations.push({
      kind: "pin_drift",
      detail:
        `${PACKAGE_NAME} is declared as \`${pinValueRaw}\` but the ` +
        `L11-07 posture requires the exact pin \`${EXPECTED_VERSION}\`. ` +
        "Caret / tilde / ranges / aliases are all rejected because " +
        "this package is EOL and any upstream move is suspicious.",
      path: PUBSPEC,
      line: pinLineIdx + 1,
      snippet: lines[pinLineIdx],
      fix:
        `restore \`${PACKAGE_NAME}: ${EXPECTED_VERSION}\` (plain — no ^, ~, ` +
        "range, or alias). If you truly mean to migrate, open an " +
        "L11-07-ext PR that updates the ADR, runbook, and this guard.",
    });
    return;
  }

  // Require a warning block ABOVE the pin line — comment lines
  // starting with `#` contiguous with the pin line. The block must
  // mention L11-07 (so copy-pasted comments from elsewhere don't
  // satisfy this trivially) and be at least 4 comment lines long
  // (enough to carry the intent + the fix-path + the runbook pointer).
  let commentStart = pinLineIdx - 1;
  let commentLines = 0;
  let mentionsLens = false;
  while (commentStart >= 0) {
    const ln = lines[commentStart];
    if (/^\s*#/.test(ln)) {
      commentLines += 1;
      if (/L11-07/.test(ln)) mentionsLens = true;
      commentStart -= 1;
    } else {
      break;
    }
  }

  if (commentLines < 4 || !mentionsLens) {
    violations.push({
      kind: "missing_warning_block",
      detail:
        `${PACKAGE_NAME} pin at ${PUBSPEC}:${pinLineIdx + 1} lacks a ` +
        `warning comment block (found ${commentLines} contiguous ` +
        `comment line(s), mentions-L11-07=${mentionsLens}).`,
      path: PUBSPEC,
      line: pinLineIdx + 1,
      fix:
        "restore the 4+ line # comment block above the pin explaining " +
        "that the package is EOL, pointing at ADR-009 and the runbook, " +
        "and mentioning L11-07.",
    });
  }
}

function checkAdr(violations: Violation[]): void {
  const body = readText(ADR);
  if (body === null || body.trim().length === 0) {
    violations.push({
      kind: "missing_adr",
      detail: `${ADR} is missing or empty`,
      path: ADR,
      fix: `restore docs/adr/009-sqlcipher-eol-migration.md from git history`,
    });
    return;
  }
  // Sanity: the ADR MUST at least reference L11-07 and SQLCipher.
  if (!/L11-07/.test(body) || !/SQLCipher/i.test(body)) {
    violations.push({
      kind: "missing_adr",
      detail: `${ADR} exists but is not the expected L11-07 ADR`,
      path: ADR,
      fix:
        "restore the ADR body — it must reference L11-07 and SQLCipher; " +
        "the CI guard enforces that so a blank file does not silently pass.",
    });
  }
}

function checkRunbook(violations: Violation[]): void {
  const body = readText(RUNBOOK);
  if (body === null || body.trim().length === 0) {
    violations.push({
      kind: "missing_runbook",
      detail: `${RUNBOOK} is missing or empty`,
      path: RUNBOOK,
      fix: `restore docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md from git history`,
    });
    return;
  }
  // Sanity: runbook must reference the CI guard AND the ADR so the
  // three files are mutually-linked.
  if (
    !/check-sqlcipher-eol/.test(body) ||
    !/009-sqlcipher-eol-migration/.test(body)
  ) {
    violations.push({
      kind: "missing_runbook",
      detail: `${RUNBOOK} does not cross-link the CI guard and ADR-009`,
      path: RUNBOOK,
      fix:
        "restore the Section 2 table + cross-references in the runbook — " +
        "it must name `check-sqlcipher-eol.ts` and ADR-009 by file.",
    });
  }
}

function checkDependabot(violations: Violation[]): void {
  const body = readText(DEPENDABOT);
  if (body === null) {
    violations.push({
      kind: "missing_dependabot_ignore",
      detail: `${DEPENDABOT} is missing`,
      path: DEPENDABOT,
      fix:
        "restore .github/dependabot.yml — and ensure the " +
        "`drift-and-storage` group lists `sqlcipher_flutter_libs`.",
    });
    return;
  }

  // Locate the `drift-and-storage:` group and check that its pattern
  // list contains `sqlcipher_flutter_libs`. We don't want to parse
  // YAML for this — a simple contiguous-block search is enough since
  // dependabot files are short.
  const lines = body.split(/\r?\n/);
  let inGroup = false;
  let groupIndent = -1;
  let sawPattern = false;
  for (let i = 0; i < lines.length; i += 1) {
    const ln = lines[i];
    const groupMatch = ln.match(/^(\s*)drift-and-storage\s*:\s*$/);
    if (groupMatch) {
      inGroup = true;
      groupIndent = groupMatch[1].length;
      continue;
    }
    if (inGroup) {
      const leadMatch = ln.match(/^(\s*)\S/);
      if (!leadMatch) continue; // blank lines allowed inside group
      const indent = leadMatch[1].length;
      if (indent <= groupIndent) {
        // Left the group without finding the pattern.
        inGroup = false;
      } else if (new RegExp(`"?${PACKAGE_NAME}"?`).test(ln)) {
        sawPattern = true;
        break;
      }
    }
  }

  if (!sawPattern) {
    violations.push({
      kind: "missing_dependabot_ignore",
      detail:
        `${DEPENDABOT} is missing \`${PACKAGE_NAME}\` inside the ` +
        "`drift-and-storage` group patterns",
      path: DEPENDABOT,
      fix:
        "add `- \"sqlcipher_flutter_libs\"` under the " +
        "`drift-and-storage.patterns:` list so Dependabot stays silent " +
        "on this EOL package.",
    });
  }
}

function describe(v: Violation): string {
  const head = `[${v.kind}] ${v.detail}`;
  const locus =
    v.path && v.line
      ? `  at ${v.path}:${v.line}${v.snippet ? `  -> ${v.snippet.trim()}` : ""}`
      : v.path
      ? `  at ${v.path}`
      : "";
  return `${head}\n${locus}\n  fix: ${v.fix}`.trim();
}

function main(): void {
  const violations: Violation[] = [];
  checkPubspec(violations);
  checkAdr(violations);
  checkRunbook(violations);
  checkDependabot(violations);

  if (violations.length === 0) {
    // Success message doubles as a reminder the EOL posture is
    // intentional and under active watch — so a skim-reviewer
    // doesn't accidentally rubber-stamp a migration PR.
    // eslint-disable-next-line no-console
    console.log(
      `✅ L11-07 SQLCipher EOL posture OK — ${PACKAGE_NAME} pinned to ` +
        `${EXPECTED_VERSION}, ADR-009 + runbook + dependabot silence in place.`,
    );
    process.exit(0);
  }

  // eslint-disable-next-line no-console
  console.error(
    `❌ L11-07 guard found ${violations.length} violation(s):\n`,
  );
  for (const v of violations) {
    // eslint-disable-next-line no-console
    console.error(describe(v));
    // eslint-disable-next-line no-console
    console.error("");
  }
  // eslint-disable-next-line no-console
  console.error(
    "See docs/adr/009-sqlcipher-eol-migration.md and " +
      "docs/runbooks/SQLCIPHER_EOL_RUNBOOK.md for the full posture.",
  );
  process.exit(1);
}

main();
