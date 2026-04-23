/**
 * check-flutter-sdk-pinning.ts
 *
 * L11-08 — CI guard enforcing the single-minor SDK pinning posture
 * for the Flutter app. A widened `environment.sdk` / `environment.flutter`
 * in pubspec.yaml, a CI workflow that drifts from the pubspec pairing,
 * or a missing `.tool-versions` all let local dev silently resolve
 * against a different Dart language spec than CI — which has bitten
 * us before (null-safety transition, sound-mode migration, etc.).
 *
 * Checks (all must pass for exit 0):
 *
 *   (a) `omni_runner/pubspec.yaml` has BOTH `environment.sdk` AND
 *       `environment.flutter` ranges whose upper bound is strictly
 *       within the NEXT minor (i.e., the range spans exactly ONE
 *       minor version, not multiple).
 *       Example (OK):  sdk: '>=3.11.0 <3.12.0'   flutter: '>=3.41.0 <3.42.0'
 *       Example (FAIL): sdk: '>=3.8.0 <4.0.0'    flutter: '>=3.0.0 <4.0.0'
 *
 *   (b) A non-empty warning comment block precedes the `environment:`
 *       key, mentioning L11-08 (makes intent visible at edit time).
 *
 *   (c) `.tool-versions` at the repo root contains `flutter <major.minor>`
 *       matching the pubspec `environment.flutter` range, AND
 *       `dart <major.minor>` matching `environment.sdk`.
 *
 *   (d) Every workflow in `.github/workflows/` that uses
 *       `subosito/flutter-action@*` AND the Flutter app (i.e., any
 *       `flutter-version:` line that exists) MUST match the pubspec
 *       `environment.flutter` MINOR. No workflow may pin a different
 *       flutter-version minor — that's the drift L11-08 catches.
 *
 *   (e) `docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md` exists and
 *       non-empty + references `check-flutter-sdk-pinning`.
 *
 * Usage:
 *   npx tsx tools/audit/check-flutter-sdk-pinning.ts
 *
 * Exit 0 = clean. Exit 1 = at least one regression.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

const PUBSPEC = "omni_runner/pubspec.yaml";
const TOOL_VERSIONS = ".tool-versions";
const WORKFLOWS_DIR = ".github/workflows";
const RUNBOOK = "docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md";

interface Violation {
  kind:
    | "missing_pubspec"
    | "missing_sdk_pin"
    | "missing_flutter_pin"
    | "sdk_range_too_wide"
    | "flutter_range_too_wide"
    | "missing_warning_block"
    | "missing_tool_versions"
    | "tool_versions_drift"
    | "workflow_flutter_drift"
    | "missing_runbook";
  detail: string;
  path?: string;
  line?: number;
  snippet?: string;
  fix: string;
}

function readText(relPath: string): string | null {
  const full = join(ROOT, relPath);
  if (!existsSync(full)) return null;
  return readFileSync(full, "utf8");
}

interface MinorBound {
  lower: { major: number; minor: number; patch: number };
  upper: { major: number; minor: number; patch: number } | null;
}

/**
 * Parse a pub range string like `>=3.11.0 <3.12.0` into its lower
 * and upper bounds. Returns null if the string is not a two-sided
 * range — we REJECT one-sided ranges (no `any`, no `>=X.Y.Z` without
 * upper) because the whole point is narrowing.
 */
function parseRange(raw: string): MinorBound | null {
  const value = raw.replace(/['"]/g, "").trim();
  const lowerM = value.match(/>=\s*(\d+)\.(\d+)\.(\d+)/);
  const upperM = value.match(/<\s*(\d+)\.(\d+)\.(\d+)/);
  if (!lowerM || !upperM) return null;
  return {
    lower: {
      major: Number(lowerM[1]),
      minor: Number(lowerM[2]),
      patch: Number(lowerM[3]),
    },
    upper: {
      major: Number(upperM[1]),
      minor: Number(upperM[2]),
      patch: Number(upperM[3]),
    },
  };
}

/**
 * A range is "single-minor" iff `upper` is exactly one minor higher
 * than `lower` at the same major, with a `.0` patch, AND `lower` has
 * the same major as upper. Examples:
 *   >=3.11.0 <3.12.0 → OK (same major, +1 minor, .0 patch on upper)
 *   >=3.8.0  <3.13.0 → FAIL (5-minor window)
 *   >=3.8.0  <4.0.0  → FAIL (cross-major window)
 *   >=3.11.0 <3.11.5 → FAIL (sub-minor; too narrow, blocks patches)
 */
function isSingleMinor(bound: MinorBound): boolean {
  if (!bound.upper) return false;
  if (bound.upper.major !== bound.lower.major) return false;
  if (bound.upper.minor !== bound.lower.minor + 1) return false;
  if (bound.upper.patch !== 0) return false;
  return true;
}

function getMinorTag(bound: MinorBound): string {
  return `${bound.lower.major}.${bound.lower.minor}`;
}

/**
 * Extract `environment.sdk` and `environment.flutter` raw ranges
 * from pubspec.yaml. Returns `{sdk, flutter, envLine, warningLines}`.
 */
function parsePubspec(body: string): {
  sdk: string | null;
  flutter: string | null;
  envLineIdx: number;
  warningCommentLines: number;
  warningMentionsLens: boolean;
} {
  const lines = body.split(/\r?\n/);
  let envLineIdx = -1;
  let sdk: string | null = null;
  let flutter: string | null = null;

  for (let i = 0; i < lines.length; i += 1) {
    if (/^\s*environment\s*:\s*$/.test(lines[i])) {
      envLineIdx = i;
      for (let j = i + 1; j < lines.length; j += 1) {
        const ln = lines[j];
        // Stop at next top-level key (non-indented non-comment).
        if (/^\S/.test(ln)) break;
        const sdkM = ln.match(/^\s*sdk\s*:\s*(.+?)\s*(?:#.*)?$/);
        const fluM = ln.match(/^\s*flutter\s*:\s*(.+?)\s*(?:#.*)?$/);
        if (sdkM) sdk = sdkM[1];
        if (fluM) flutter = fluM[1];
      }
      break;
    }
  }

  let warningCommentLines = 0;
  let warningMentionsLens = false;
  if (envLineIdx > 0) {
    let idx = envLineIdx - 1;
    while (idx >= 0 && /^\s*#/.test(lines[idx])) {
      warningCommentLines += 1;
      if (/L11-08/.test(lines[idx])) warningMentionsLens = true;
      idx -= 1;
    }
  }

  return { sdk, flutter, envLineIdx, warningCommentLines, warningMentionsLens };
}

function checkPubspec(violations: Violation[]): {
  sdkMinor: string | null;
  flutterMinor: string | null;
} {
  const body = readText(PUBSPEC);
  if (body === null) {
    violations.push({
      kind: "missing_pubspec",
      detail: `pubspec not found at ${PUBSPEC}`,
      path: PUBSPEC,
      fix: "restore omni_runner/pubspec.yaml from git history",
    });
    return { sdkMinor: null, flutterMinor: null };
  }

  const {
    sdk,
    flutter,
    envLineIdx,
    warningCommentLines,
    warningMentionsLens,
  } = parsePubspec(body);

  if (!sdk) {
    violations.push({
      kind: "missing_sdk_pin",
      detail: "environment.sdk not declared in pubspec.yaml",
      path: PUBSPEC,
      fix:
        "add `sdk: '>=<MINOR>.0 <<NEXT_MINOR>.0'` under environment: in " +
        "omni_runner/pubspec.yaml matching the Dart shipped with the " +
        "CI Flutter version.",
    });
  }
  if (!flutter) {
    violations.push({
      kind: "missing_flutter_pin",
      detail: "environment.flutter not declared in pubspec.yaml",
      path: PUBSPEC,
      fix:
        "add `flutter: '>=<MINOR>.0 <<NEXT_MINOR>.0'` under environment: " +
        "in omni_runner/pubspec.yaml matching the CI flutter-version.",
    });
  }

  let sdkMinor: string | null = null;
  let flutterMinor: string | null = null;

  if (sdk) {
    const sdkRange = parseRange(sdk);
    if (!sdkRange || !isSingleMinor(sdkRange)) {
      violations.push({
        kind: "sdk_range_too_wide",
        detail:
          `environment.sdk is \`${sdk}\` but L11-08 requires a ` +
          "SINGLE-MINOR window like `>=3.11.0 <3.12.0` (one minor wide).",
        path: PUBSPEC,
        line: envLineIdx + 1,
        snippet: sdk,
        fix:
          "narrow environment.sdk to exactly one minor — `>=3.11.0 <3.12.0` " +
          "matches the Dart 3.11 shipped by Flutter 3.41.",
      });
    } else {
      sdkMinor = getMinorTag(sdkRange);
    }
  }

  if (flutter) {
    const flutterRange = parseRange(flutter);
    if (!flutterRange || !isSingleMinor(flutterRange)) {
      violations.push({
        kind: "flutter_range_too_wide",
        detail:
          `environment.flutter is \`${flutter}\` but L11-08 requires ` +
          "a SINGLE-MINOR window like `>=3.41.0 <3.42.0`.",
        path: PUBSPEC,
        line: envLineIdx + 1,
        snippet: flutter,
        fix:
          "narrow environment.flutter to exactly one minor — " +
          "`>=3.41.0 <3.42.0` matches the CI flutter-version 3.41.x.",
      });
    } else {
      flutterMinor = getMinorTag(flutterRange);
    }
  }

  if (envLineIdx >= 0 && (warningCommentLines < 4 || !warningMentionsLens)) {
    violations.push({
      kind: "missing_warning_block",
      detail:
        `environment: at ${PUBSPEC}:${envLineIdx + 1} lacks a warning ` +
        `comment block (found ${warningCommentLines} contiguous comment ` +
        `line(s), mentions-L11-08=${warningMentionsLens}).`,
      path: PUBSPEC,
      line: envLineIdx + 1,
      fix:
        "restore the 4+ line # comment block above `environment:` " +
        "explaining the SDK/Flutter pin, pointing at the runbook, " +
        "and mentioning L11-08.",
    });
  }

  return { sdkMinor, flutterMinor };
}

function checkToolVersions(
  violations: Violation[],
  expected: { sdkMinor: string | null; flutterMinor: string | null },
): void {
  const body = readText(TOOL_VERSIONS);
  if (body === null) {
    violations.push({
      kind: "missing_tool_versions",
      detail: `${TOOL_VERSIONS} not found at repo root`,
      path: TOOL_VERSIONS,
      fix:
        "create .tool-versions at repo root with `flutter <ver>` and " +
        "`dart <ver>` lines matching the pubspec pins (asdf/tool-manager " +
        "uses this for local dev parity with CI).",
    });
    return;
  }

  const flutterLine = body.match(/^\s*flutter\s+(\d+\.\d+)(?:\.(\d+))?\s*$/m);
  const dartLine = body.match(/^\s*dart\s+(\d+\.\d+)(?:\.(\d+))?\s*$/m);

  if (expected.flutterMinor && flutterLine) {
    const actual = flutterLine[1];
    if (actual !== expected.flutterMinor) {
      violations.push({
        kind: "tool_versions_drift",
        detail:
          `.tool-versions has \`flutter ${actual}.*\` but pubspec ` +
          `environment.flutter pins \`${expected.flutterMinor}.x\`.`,
        path: TOOL_VERSIONS,
        fix:
          `bump .tool-versions to \`flutter ${expected.flutterMinor}.<patch>\` ` +
          `so asdf/fvm local installs match the pubspec pin.`,
      });
    }
  } else if (expected.flutterMinor) {
    violations.push({
      kind: "tool_versions_drift",
      detail: `.tool-versions is missing the \`flutter <ver>\` line`,
      path: TOOL_VERSIONS,
      fix:
        `add \`flutter ${expected.flutterMinor}.<patch>\` to .tool-versions.`,
    });
  }

  if (expected.sdkMinor && dartLine) {
    const actual = dartLine[1];
    if (actual !== expected.sdkMinor) {
      violations.push({
        kind: "tool_versions_drift",
        detail:
          `.tool-versions has \`dart ${actual}.*\` but pubspec ` +
          `environment.sdk pins \`${expected.sdkMinor}.x\`.`,
        path: TOOL_VERSIONS,
        fix:
          `bump .tool-versions to \`dart ${expected.sdkMinor}.<patch>\` ` +
          `so the Dart SDK matches the pubspec pin.`,
      });
    }
  } else if (expected.sdkMinor) {
    violations.push({
      kind: "tool_versions_drift",
      detail: `.tool-versions is missing the \`dart <ver>\` line`,
      path: TOOL_VERSIONS,
      fix:
        `add \`dart ${expected.sdkMinor}.<patch>\` to .tool-versions.`,
    });
  }
}

function checkWorkflows(
  violations: Violation[],
  expected: { flutterMinor: string | null },
): void {
  if (!expected.flutterMinor) return;

  const dir = join(ROOT, WORKFLOWS_DIR);
  if (!existsSync(dir)) return; // no workflows folder — skip silently

  const files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f));
  for (const f of files) {
    const full = join(dir, f);
    const body = readFileSync(full, "utf8");
    const lines = body.split(/\r?\n/);
    for (let i = 0; i < lines.length; i += 1) {
      const m = lines[i].match(/flutter-version\s*:\s*['"]?(\d+\.\d+)\./);
      if (m) {
        const ver = m[1];
        if (ver !== expected.flutterMinor) {
          violations.push({
            kind: "workflow_flutter_drift",
            detail:
              `${WORKFLOWS_DIR}/${f}:${i + 1} uses flutter-version ` +
              `\`${ver}.x\` but pubspec environment.flutter pins ` +
              `\`${expected.flutterMinor}.x\`.`,
            path: `${WORKFLOWS_DIR}/${f}`,
            line: i + 1,
            snippet: lines[i].trim(),
            fix:
              `change flutter-version to \`${expected.flutterMinor}.x\` ` +
              "in this workflow (or, if you intentionally want a different " +
              "Flutter for this job, update the pubspec pin AND update " +
              "the runbook — single-minor rule applies across all jobs).",
          });
        }
      }
    }
  }
}

function checkRunbook(violations: Violation[]): void {
  const body = readText(RUNBOOK);
  if (body === null || body.trim().length === 0) {
    violations.push({
      kind: "missing_runbook",
      detail: `${RUNBOOK} is missing or empty`,
      path: RUNBOOK,
      fix:
        `restore docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md from git ` +
        "history (must cover upgrade flow, rollback, and cross-refs).",
    });
    return;
  }
  if (!/check-flutter-sdk-pinning/.test(body)) {
    violations.push({
      kind: "missing_runbook",
      detail: `${RUNBOOK} does not cross-link the CI guard file name`,
      path: RUNBOOK,
      fix:
        "add a reference to `check-flutter-sdk-pinning.ts` in the runbook " +
        "(mutual-linkage keeps the three files consistent).",
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
  const pubspecPins = checkPubspec(violations);
  checkToolVersions(violations, pubspecPins);
  checkWorkflows(violations, pubspecPins);
  checkRunbook(violations);

  if (violations.length === 0) {
    const sdk = pubspecPins.sdkMinor ?? "?";
    const flu = pubspecPins.flutterMinor ?? "?";
    // eslint-disable-next-line no-console
    console.log(
      `✅ L11-08 Flutter/Dart SDK pinning OK — pubspec Dart ${sdk}.x + ` +
        `Flutter ${flu}.x, .tool-versions aligned, all workflows aligned, ` +
        "runbook linked.",
    );
    process.exit(0);
  }

  // eslint-disable-next-line no-console
  console.error(
    `❌ L11-08 guard found ${violations.length} violation(s):\n`,
  );
  for (const v of violations) {
    // eslint-disable-next-line no-console
    console.error(describe(v));
    // eslint-disable-next-line no-console
    console.error("");
  }
  // eslint-disable-next-line no-console
  console.error(
    "See docs/runbooks/FLUTTER_SDK_PINNING_RUNBOOK.md for the upgrade " +
      "procedure and rollback.",
  );
  process.exit(1);
}

main();
