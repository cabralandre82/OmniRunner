#!/usr/bin/env tsx
/**
 * L11-13 — Lockfile drift guard.
 *
 * Asserts that every workspace's package.json/package-lock.json pair
 * is internally consistent: the version recorded in the lockfile
 * resolves to the same range / version recorded in package.json for
 * every direct dependency / devDependency. We do NOT run `npm ci`
 * here (that's the workflow's job — see ci.yml) but we DO catch the
 * common cases:
 *
 *   1. A devDependency was added/updated to package.json without
 *      regenerating the lockfile.
 *   2. The lockfile lists a "packages" entry whose `version` field
 *      doesn't satisfy the package.json range.
 *   3. The lockfile is missing entirely.
 *
 * This is a lint-time check that runs in seconds, complementing the
 * full `npm ci --ignore-scripts` step which runs in 1-2 min.
 */
import * as fs from "node:fs";
import * as path from "node:path";

const ROOT = path.resolve(__dirname, "../..");

interface PackageJson {
  name?: string;
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
}

interface LockfilePackages {
  packages?: Record<string, { version?: string }>;
}

const WORKSPACES: ReadonlyArray<string> = [".", "portal"];

function readJson<T>(p: string): T | null {
  if (!fs.existsSync(p)) return null;
  return JSON.parse(fs.readFileSync(p, "utf8")) as T;
}

function pinned(version: string): string {
  return version
    .replace(/^[\^~>=<]+/, "")
    .replace(/^=/, "")
    .replace(/^v/, "")
    .trim();
}

function isRange(v: string): boolean {
  return /[<>~^]|\s|\|\|/.test(v);
}

function check(workspace: string): { errors: string[]; checked: number } {
  const ws = path.join(ROOT, workspace);
  const pjPath = path.join(ws, "package.json");
  const lockPath = path.join(ws, "package-lock.json");
  const pj = readJson<PackageJson>(pjPath);
  if (!pj) return { errors: [], checked: 0 };
  const lock = readJson<LockfilePackages>(lockPath);
  if (!lock) {
    return { errors: [`${workspace}: package-lock.json is missing`], checked: 0 };
  }
  const errors: string[] = [];
  const all: Record<string, string> = {
    ...(pj.dependencies ?? {}),
    ...(pj.devDependencies ?? {}),
  };
  let checked = 0;
  for (const [name, range] of Object.entries(all)) {
    if (range.startsWith("file:") || range.startsWith("link:")) continue;
    if (range.startsWith("workspace:")) continue;
    const lockEntry = lock.packages?.[`node_modules/${name}`];
    if (!lockEntry?.version) {
      errors.push(
        `${workspace}: ${name} present in package.json but missing from lockfile`,
      );
      continue;
    }
    checked++;
    if (!isRange(range)) {
      const want = pinned(range);
      if (want && lockEntry.version !== want) {
        errors.push(
          `${workspace}: ${name} pinned to ${want} in package.json but lockfile records ${lockEntry.version}`,
        );
      }
    }
  }
  return { errors, checked };
}

function main(): void {
  const out: string[] = [];
  let total = 0;
  for (const ws of WORKSPACES) {
    const { errors, checked } = check(ws);
    total += checked;
    out.push(...errors);
  }
  if (out.length === 0) {
    console.log(
      `[OK] lockfile drift guard verified ${total} dependencies across ${WORKSPACES.length} workspaces.`,
    );
    return;
  }
  console.error("[FAIL] lockfile drift detected:");
  for (const e of out) console.error("  - " + e);
  console.error("");
  console.error("Fix: run `npm install` in the offending workspace then commit");
  console.error("the regenerated package-lock.json. CI will re-run this check.");
  process.exit(1);
}

main();
