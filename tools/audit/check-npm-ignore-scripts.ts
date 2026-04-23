/**
 * check-npm-ignore-scripts.ts
 *
 * L11-12 — CI guard requiring every `npm ci` invocation in
 * `.github/workflows/*.yml` to use the `--ignore-scripts` flag, so
 * that a malicious dependency cannot run arbitrary `postinstall`
 * scripts on our CI runners.
 *
 * If a job legitimately needs a postinstall (e.g. `husky install`),
 * it must run that script explicitly with `npm run <script>` after
 * `npm ci --ignore-scripts`.
 */

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const WF_DIR = resolve(ROOT, ".github", "workflows");

interface Violation { file: string; line: number; raw: string; }

function findViolations(): Violation[] {
  const out: Violation[] = [];
  if (!existsSync(WF_DIR)) return out;
  for (const f of readdirSync(WF_DIR)) {
    if (!f.endsWith(".yml") && !f.endsWith(".yaml")) continue;
    const path = resolve(WF_DIR, f);
    const lines = readFileSync(path, "utf8").split("\n");
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      const trimmed = line.trim();
      if (!/(?:^|\s)npm ci(\s|$)/.test(trimmed)) continue;
      if (/--ignore-scripts/.test(trimmed)) continue;
      out.push({
        file: path.replace(ROOT + "/", ""),
        line: i + 1,
        raw: trimmed,
      });
    }
  }
  return out;
}

const violations = findViolations();

if (violations.length === 0) {
  console.log("[OK] every `npm ci` uses --ignore-scripts.");
  process.exit(0);
}

console.error(
  `[FAIL] ${violations.length} \`npm ci\` invocations missing --ignore-scripts:`,
);
for (const v of violations) {
  console.error(`  ${v.file}:${v.line}  ${v.raw}`);
}
console.error(
  "\nReplace `npm ci` with `npm ci --ignore-scripts`. If a postinstall hook is\n" +
    "actually required (rare), run it explicitly afterwards via `npm run`.\n",
);
process.exit(1);
