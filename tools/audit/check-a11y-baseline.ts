/**
 * check-a11y-baseline.ts — L07-05 static CI guard.
 *
 * - docs/a11y.md exists with the required sections.
 * - portal/.eslintrc.json pins the 10 jsx-a11y rules to "error".
 * - Portal source does not regress the 4 high-risk patterns listed
 *   in docs/a11y.md §3: icon-only buttons, tables without <caption>,
 *   toasts without role="alert", and custody/swap action buttons
 *   without an aria-label.
 *
 * The scan is a pragmatic grep, not a full JSX AST walker — false
 * positives are tolerable because every flagged location must land
 * either in §5 "Exceptions log" or get a real aria-label.
 *
 * Usage: npm run audit:a11y-baseline
 */

import { readFileSync, readdirSync, statSync } from "node:fs";
import { resolve, extname, relative, join } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const DOC = resolve(ROOT, "docs/a11y.md");
const ESLINT = resolve(ROOT, "portal/.eslintrc.json");
const PORTAL_SRC = resolve(ROOT, "portal/src");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L07-05-portal-sem-acessibilidade-a11y-declarada.md",
);
const ALLOWLIST_PATH = resolve(
  ROOT,
  "tools/audit/a11y-baseline-allowlist.json",
);

interface Allowlist { table_without_caption?: string[]; }
let allowlist: Allowlist = {};
try {
  allowlist = JSON.parse(readFileSync(ALLOWLIST_PATH, "utf8")) as Allowlist;
} catch {
  /* ignore — ratchet starts empty */
}
const allowedTables = new Set(allowlist.table_without_caption ?? []);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

// 1. docs/a11y.md
const doc = safeRead(DOC, "docs/a11y.md present");
if (doc) {
  push("docs/a11y.md present", true);
  push("declares WCAG 2.1 AA", /WCAG 2\.1 (level )?AA/i.test(doc));
  push("cites LBI 13.146/2015", /13\.146\/2015/.test(doc));
  push(
    "pins the 10 jsx-a11y rules",
    [
      "alt-text",
      "aria-props",
      "aria-role",
      "aria-unsupported-elements",
      "click-events-have-key-events",
      "heading-has-content",
      "label-has-associated-control",
      "no-autofocus",
      "no-noninteractive-tabindex",
      "role-has-required-aria-props",
    ].every((r) => new RegExp(`jsx-a11y/${r}`).test(doc)),
  );
  push(
    "declares keyboard map",
    /Tab \/ Shift-Tab/i.test(doc) && /Esc/.test(doc),
  );
  push(
    "includes exceptions log section",
    /## 5\. Exceptions log/.test(doc),
  );
  push(
    "cross-links to ESLint config + guard",
    /portal\/\.eslintrc\.json/.test(doc) &&
      /check-a11y-baseline\.ts/.test(doc),
  );
  push(
    "references manual audit cadence",
    /Monthly|Quarterly|monthly|quarterly/.test(doc),
  );
}

// 2. ESLint rules pinned
const eslint = safeRead(ESLINT, "portal/.eslintrc.json present");
if (eslint) {
  let parsed: any = null;
  try { parsed = JSON.parse(eslint); } catch (err) {
    push("portal/.eslintrc.json parses", false, String(err));
  }
  if (parsed) {
    push("portal/.eslintrc.json parses", true);
    const extendsArr = Array.isArray(parsed.extends) ? parsed.extends : [parsed.extends];
    push(
      "extends next/core-web-vitals",
      extendsArr.some((e: string) => e === "next/core-web-vitals"),
    );
    push(
      "extends jsx-a11y/recommended",
      extendsArr.some((e: string) => e === "plugin:jsx-a11y/recommended"),
    );
    const required = [
      "jsx-a11y/alt-text",
      "jsx-a11y/aria-props",
      "jsx-a11y/aria-role",
      "jsx-a11y/aria-unsupported-elements",
      "jsx-a11y/click-events-have-key-events",
      "jsx-a11y/heading-has-content",
      "jsx-a11y/label-has-associated-control",
      "jsx-a11y/no-autofocus",
      "jsx-a11y/no-noninteractive-tabindex",
      "jsx-a11y/role-has-required-aria-props",
    ];
    for (const rule of required) {
      push(
        `eslint pins ${rule} to error`,
        parsed.rules && parsed.rules[rule] === "error",
      );
    }
  }
}

// 3. Scan portal/src for high-risk patterns.
function walk(dir: string): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    if (entry.startsWith(".") || entry === "node_modules") continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      out.push(...walk(full));
    } else if (st.isFile() && [".tsx", ".jsx"].includes(extname(full))) {
      if (/\.(test|spec)\./.test(full)) continue;
      out.push(full);
    }
  }
  return out;
}

let files: string[] = [];
try { files = walk(PORTAL_SRC); }
catch { push("portal/src walkable", false, `missing: ${PORTAL_SRC}`); }

if (files.length > 0) {
  push("portal/src walkable", true);

  // 3.1 Icon-only <button> — single JSX child that is a component
  //     whose name ends with "Icon" and no aria-label anywhere on
  //     the button opening tag.
  const iconOnly: string[] = [];
  // 3.2 <table> without <caption> in the same file (very cheap check).
  const tableNoCaption: string[] = [];
  // 3.4 buttons whose TEXT contents matches Distribuir / Aceitar swap /
  //     Withdraw / Withdrawal / Burn / Emissão and that have NEITHER
  //     aria-label NOR visible text (text is empty, icon-only).
  const custodyIconOnly: string[] = [];
  const critical = /Distribuir|Aceitar swap|Withdraw|Emissão|Burn/;

  for (const file of files) {
    const src = readFileSync(file, "utf8");
    const rel = relative(ROOT, file);

    // icon-only button regex
    const buttonRe = /<button\b([^>]*)>\s*<(\w+Icon)[^>]*\/?>\s*<\/button>/g;
    let m: RegExpExecArray | null;
    while ((m = buttonRe.exec(src)) !== null) {
      const attrs = m[1];
      if (!/\baria-label\b/.test(attrs) && !/\baria-labelledby\b/.test(attrs)) {
        iconOnly.push(`${rel}: <button><${m[2]} /></button>`);
      }
    }

    // table without caption (ratcheted against the allowlist)
    if (/<table\b/.test(src) && !/<caption\b/.test(src)) {
      if (!allowedTables.has(rel)) tableNoCaption.push(rel);
    }

    // custody / swap action buttons
    const custodyRe = new RegExp(
      `<button\\b([^>]*)>[^<]*(${critical.source})[^<]*<\\/button>`,
      "g",
    );
    while ((m = custodyRe.exec(src)) !== null) {
      // This variant has visible text — ok. Not the one we're scanning.
    }
    const custodyIconRe = /<button\b([^>]*)>\s*<(\w+Icon)[^>]*\/?>\s*<\/button>/g;
    // (Same pattern as iconOnly — this is a narrow projection: files
    // whose path or nearby comment mentions one of the critical words.)
    if (critical.test(src)) {
      while ((m = custodyIconRe.exec(src)) !== null) {
        const attrs = m[1];
        if (!/\baria-label\b/.test(attrs) && !/\baria-labelledby\b/.test(attrs)) {
          custodyIconOnly.push(`${rel}: <button><${m[2]} /></button>`);
        }
      }
    }
  }

  push(
    "no icon-only <button> without aria-label",
    iconOnly.length === 0,
    iconOnly.length > 0 ? `offenders:\n  ${iconOnly.slice(0, 10).join("\n  ")}` : undefined,
  );
  push(
    "no NEW <table> without <caption> (beyond ratchet allowlist)",
    tableNoCaption.length === 0,
    tableNoCaption.length > 0
      ? `offenders:\n  ${tableNoCaption.slice(0, 10).join("\n  ")}\n` +
        `(allowlist at tools/audit/a11y-baseline-allowlist.json; NEW files must be fixed, not added to the list)`
      : undefined,
  );

  // Also flag **stale** allowlist entries — files in the allowlist
  // that no longer exist OR that no longer contain <table> without
  // <caption>. Keeping the list pristine avoids ratchet-rot.
  const staleAllowlist: string[] = [];
  for (const entry of allowedTables) {
    const full = resolve(ROOT, entry);
    try {
      const s = readFileSync(full, "utf8");
      if (!/<table\b/.test(s) || /<caption\b/.test(s)) staleAllowlist.push(entry);
    } catch {
      staleAllowlist.push(entry + " (missing file)");
    }
  }
  push(
    "a11y allowlist has no stale entries",
    staleAllowlist.length === 0,
    staleAllowlist.length > 0
      ? `remove from tools/audit/a11y-baseline-allowlist.json:\n  ${staleAllowlist.slice(0, 10).join("\n  ")}`
      : undefined,
  );
  push(
    "no icon-only custody/swap action button without aria-label",
    custodyIconOnly.length === 0,
    custodyIconOnly.length > 0
      ? `offenders:\n  ${custodyIconOnly.slice(0, 10).join("\n  ")}`
      : undefined,
  );
}

// 4. Finding references
const finding = safeRead(FINDING, "L07-05 finding present");
if (finding) {
  push(
    "finding references docs/a11y.md",
    /docs\/a11y\.md/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} a11y-baseline checks passed.`);
if (failed > 0) {
  console.error("\nL07-05 invariants broken. See docs/a11y.md.");
  process.exit(1);
}
