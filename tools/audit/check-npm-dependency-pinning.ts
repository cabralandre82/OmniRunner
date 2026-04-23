/**
 * check-npm-dependency-pinning.ts
 *
 * L11-06 — CI guard that refuses any package.json that lets the
 * following slip through:
 *
 *   (a) a CRITICAL_PACKAGES entry with anything other than an exact
 *       version (no `^`, `~`, `>=`, `*`, `latest`, git/file/tag ranges,
 *       workspace aliases). Critical here means: touching it without
 *       intentional review will break the product contract — the
 *       auth / rendering / observability / audit-runtime boundary.
 *
 *   (b) ANY dep declared as `*` or `latest` or an unpinned tag — these
 *       explode nondeterministically across `npm install` runs.
 *
 *   (c) a missing or mis-configured `.npmrc` in the workspaces we ship
 *       (`.npmrc` and `portal/.npmrc` must BOTH exist with
 *       `save-exact=true` and `save-prefix=` to prevent a future
 *       `npm install foo` from sneaking `^` back into package.json).
 *
 * This is defence in depth over layer-1 (`.npmrc`) — a human can still
 * hand-edit package.json and slip `^` past the `save-exact` default. The
 * guard catches it at PR time.
 *
 * Usage:
 *   npx tsx tools/audit/check-npm-dependency-pinning.ts
 *
 * Exit 0 = clean. Exit 1 = at least one regression.
 */

import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

/**
 * Packages that MUST be pinned to an exact version. These are boundaries
 * the auditors drew: changing them must always be intentional (code
 * review + regression run), not transitive.
 *
 *   • next               — rendering / routing / middleware contract.
 *   • @supabase/ssr      — auth cookie contract; minor bumps have
 *                          silently changed cookie names in the past.
 *   • @supabase/supabase-js — DB / RPC client; changes RLS error shape.
 *   • zod                — schema contract; zod 3→4 changed typing rules.
 *   • @sentry/nextjs     — observability boundary; bumped transport
 *                          semantics silently in past releases.
 *
 *   Root workspace:
 *   • tsx                — entrypoint for every `npm run audit:*`; a
 *                          breaking minor kills the whole CI fleet.
 *   • lefthook           — pre-commit runner; same explosion radius.
 *   • js-yaml            — audit registry parser; a silent breaking
 *                          change shifts audit-registry semantics.
 *
 * If you need to add an entry, bump the matching CANONICAL_WORKSPACES
 * entry AND update the runbook (Section 2 — "Policy matrix").
 */
const CRITICAL_PACKAGES: Record<string, string[]> = {
  "portal/package.json": [
    "next",
    "@supabase/ssr",
    "@supabase/supabase-js",
    "zod",
    "@sentry/nextjs",
  ],
  "package.json": [
    "tsx",
    "lefthook",
    "js-yaml",
  ],
};

/**
 * `.npmrc` files that MUST exist AND contain the `save-exact=true`
 * + `save-prefix=` lines. If a workspace has deps but no `.npmrc`,
 * the next contributor to run `npm install foo` silently reintroduces
 * caret ranges.
 */
const REQUIRED_NPMRC: Array<{ path: string; workspace: string }> = [
  { path: ".npmrc", workspace: "root" },
  { path: "portal/.npmrc", workspace: "portal" },
];

const REQUIRED_NPMRC_LINES = [
  /^\s*save-exact\s*=\s*true\s*$/m,
  /^\s*save-prefix\s*=\s*$/m,
];

/**
 * Range specifiers that are BANNED for every dep, not just criticals.
 * `*` and `latest` mean "whatever npm feels like today" — silently
 * nondeterministic across install runs.
 */
const BANNED_SPECIFIERS: Array<{ re: RegExp; label: string }> = [
  { re: /^\s*\*\s*$/, label: "wildcard '*'" },
  { re: /^\s*latest\s*$/i, label: "'latest' tag" },
  { re: /^\s*x\s*$/i, label: "wildcard 'x'" },
];

interface Violation {
  kind: "unpinned_critical" | "banned_specifier" | "missing_npmrc" | "malformed_npmrc";
  pkgJson?: string;
  dep?: string;
  range?: string;
  detail?: string;
}

function isExactVersion(range: string): boolean {
  if (!range) return false;
  // Reject well-known non-exact forms.
  if (/^[\^~]/.test(range)) return false;
  if (/[<>]=?/.test(range)) return false;
  if (/\s-\s/.test(range)) return false; // "1.0.0 - 2.0.0"
  if (/\|\|/.test(range)) return false;
  if (/[*x]/i.test(range)) return false;
  if (/^(?:file:|link:|git|https?:|github:|workspace:)/i.test(range)) return false;
  if (/^npm:/i.test(range)) return false;
  // Plain semver 1.2.3 or 1.2.3-beta.0 or 1.2.3+build.42 is fine.
  return /^\d+\.\d+\.\d+(?:[-+].+)?$/.test(range.trim());
}

function loadPkg(relPath: string): Record<string, unknown> {
  const full = join(ROOT, relPath);
  if (!existsSync(full)) {
    throw new Error(`missing package.json at ${relPath}`);
  }
  return JSON.parse(readFileSync(full, "utf8"));
}

function checkCriticalPins(violations: Violation[]): void {
  for (const [relPath, criticals] of Object.entries(CRITICAL_PACKAGES)) {
    const pkg = loadPkg(relPath);
    const all: Record<string, string> = {
      ...(pkg.dependencies as Record<string, string> | undefined ?? {}),
      ...(pkg.devDependencies as Record<string, string> | undefined ?? {}),
      ...(pkg.peerDependencies as Record<string, string> | undefined ?? {}),
      ...(pkg.optionalDependencies as Record<string, string> | undefined ?? {}),
    };
    for (const dep of criticals) {
      const range = all[dep];
      if (range === undefined) {
        violations.push({
          kind: "unpinned_critical",
          pkgJson: relPath,
          dep,
          range: "<missing>",
          detail: "declared in CRITICAL_PACKAGES but not present in package.json",
        });
        continue;
      }
      if (!isExactVersion(range)) {
        violations.push({
          kind: "unpinned_critical",
          pkgJson: relPath,
          dep,
          range,
          detail: "must be an exact semver (no ^, ~, ranges, or aliases)",
        });
      }
    }
  }
}

function checkBannedSpecifiers(violations: Violation[]): void {
  for (const relPath of Object.keys(CRITICAL_PACKAGES)) {
    const pkg = loadPkg(relPath);
    for (const section of ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"]) {
      const bucket = pkg[section] as Record<string, string> | undefined;
      if (!bucket) continue;
      for (const [dep, range] of Object.entries(bucket)) {
        for (const banned of BANNED_SPECIFIERS) {
          if (banned.re.test(range)) {
            violations.push({
              kind: "banned_specifier",
              pkgJson: relPath,
              dep,
              range,
              detail: `uses banned specifier ${banned.label}`,
            });
            break;
          }
        }
      }
    }
  }
}

function checkNpmrc(violations: Violation[]): void {
  for (const { path: relPath, workspace } of REQUIRED_NPMRC) {
    const full = join(ROOT, relPath);
    if (!existsSync(full)) {
      violations.push({
        kind: "missing_npmrc",
        pkgJson: relPath,
        detail: `missing .npmrc for ${workspace} workspace`,
      });
      continue;
    }
    const body = readFileSync(full, "utf8");
    const missing: string[] = [];
    for (const re of REQUIRED_NPMRC_LINES) {
      if (!re.test(body)) {
        missing.push(re.source);
      }
    }
    if (missing.length > 0) {
      violations.push({
        kind: "malformed_npmrc",
        pkgJson: relPath,
        detail: `missing required line(s): ${missing.join(", ")}`,
      });
    }
  }
}

function describe(v: Violation): string {
  switch (v.kind) {
    case "unpinned_critical":
      return `[${v.pkgJson}] ${v.dep} = "${v.range}" — ${v.detail}`;
    case "banned_specifier":
      return `[${v.pkgJson}] ${v.dep} = "${v.range}" — ${v.detail}`;
    case "missing_npmrc":
      return `[${v.pkgJson}] ${v.detail}`;
    case "malformed_npmrc":
      return `[${v.pkgJson}] ${v.detail}`;
  }
}

function main(): void {
  console.log("L11-06 npm dependency pinning guard");

  const violations: Violation[] = [];

  checkNpmrc(violations);
  checkCriticalPins(violations);
  checkBannedSpecifiers(violations);

  const byKind: Record<string, number> = {};
  for (const v of violations) {
    byKind[v.kind] = (byKind[v.kind] ?? 0) + 1;
  }

  // Summary status lines mirror the other audit guards.
  const npmrcStatus = violations.filter((v) => v.kind === "missing_npmrc" || v.kind === "malformed_npmrc");
  if (npmrcStatus.length === 0) {
    console.log(`  [OK] npmrc: ${REQUIRED_NPMRC.map((n) => n.path).join(" + ")} present with save-exact=true + save-prefix=`);
  } else {
    console.log(`  [FAIL] npmrc: ${npmrcStatus.length} issue(s)`);
  }

  const criticalStatus = violations.filter((v) => v.kind === "unpinned_critical");
  const criticalCount = Object.values(CRITICAL_PACKAGES).reduce((a, b) => a + b.length, 0);
  if (criticalStatus.length === 0) {
    console.log(`  [OK] criticals: ${criticalCount} package(s) pinned to exact semver across ${Object.keys(CRITICAL_PACKAGES).length} manifest(s)`);
  } else {
    console.log(`  [FAIL] criticals: ${criticalStatus.length} unpinned critical(s)`);
  }

  const bannedStatus = violations.filter((v) => v.kind === "banned_specifier");
  if (bannedStatus.length === 0) {
    console.log(`  [OK] specifiers: no '*', 'latest', or 'x' ranges in any tracked manifest`);
  } else {
    console.log(`  [FAIL] specifiers: ${bannedStatus.length} banned range(s)`);
  }

  if (violations.length === 0) {
    console.log("\nOK — L11-06 npm-dependency-pinning invariants hold.");
    process.exit(0);
  }

  console.log(`\n  ${violations.length} regression(s):`);
  for (const v of violations) {
    console.log(`    • ${describe(v)}`);
  }
  console.log(
    "\n  → Fix options:" +
      "\n    (a) Pin the critical package to the EXACT installed version" +
      "\n        (see `npm ls <pkg>`). Update both package.json and" +
      "\n        package-lock.json via `npm install <pkg>@<exact>`." +
      "\n    (b) If the package should NOT be critical, remove it from" +
      "\n        tools/audit/check-npm-dependency-pinning.ts::CRITICAL_PACKAGES" +
      "\n        — but that requires reviewer sign-off per the runbook." +
      "\n    (c) Re-create .npmrc with `save-exact=true` + `save-prefix=`."
  );
  console.log(`\nFAIL — ${violations.length} regression(s).`);
  process.exit(1);
}

main();
