/**
 * check-api-error-i18n.ts
 *
 * L07-01 — CI guard for the API error i18n registry and for the
 * no-new-pt-BR-literal invariant in portal/src/app/api/**.
 */

import { readdirSync, readFileSync, statSync, writeFileSync, existsSync } from "node:fs";
import { resolve, relative } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const registryPath = resolve(ROOT, "portal/src/lib/api/error-messages.ts");
const registry = safeRead(registryPath, "error-messages registry present");

const errorsPath = resolve(ROOT, "portal/src/lib/api/errors.ts");
const errors = safeRead(errorsPath, "errors.ts present");

// ────────────────────────────────────────────────────────────────────────────
// 1. Static shape checks on the registry
// ────────────────────────────────────────────────────────────────────────────

if (registry) {
  push(
    "registry exports ERROR_MESSAGES record",
    /export const ERROR_MESSAGES\s*:\s*Record<string,\s*LocalisedMessage>/.test(registry),
  );
  push(
    "registry exports ERROR_LOCALES with en, ptBR, es",
    /export const ERROR_LOCALES[\s\S]{0,200}"en"[\s\S]{0,40}"ptBR"[\s\S]{0,40}"es"/.test(registry),
  );
  push(
    "registry exports resolveErrorMessage",
    /export function resolveErrorMessage\(/.test(registry),
  );
  push(
    "registry exports resolveClientLocale",
    /export function resolveClientLocale\(/.test(registry),
  );
  push(
    "registry exports REGISTERED_ERROR_CODES",
    /export const REGISTERED_ERROR_CODES/.test(registry),
  );
  push(
    "resolveErrorMessage defaults to English when locale unknown",
    /\?\? entry\.en/.test(registry) || /return entry\.en/.test(registry),
  );
  push(
    "resolveClientLocale recognises pt/ptBR",
    /raw\.startsWith\("pt"\)/.test(registry)
      && /return "ptBR"/.test(registry),
  );
  push(
    "resolveClientLocale recognises es",
    /raw\.startsWith\("es"\)/.test(registry)
      && /return "es"/.test(registry),
  );
  push(
    "resolveClientLocale falls back to en",
    /return "en"/.test(registry),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// 2. Every COMMON_ERROR_CODES entry has a registry translation
// ────────────────────────────────────────────────────────────────────────────

const commonCodes: string[] = [];
if (errors) {
  const match = errors.match(/export const COMMON_ERROR_CODES\s*=\s*\[([\s\S]*?)\]/);
  if (match) {
    for (const m of match[1].matchAll(/"([A-Z_]+)"/g)) {
      commonCodes.push(m[1]);
    }
  }
}
push(
  "COMMON_ERROR_CODES parsed from errors.ts",
  commonCodes.length > 0,
  `parsed ${commonCodes.length}`,
);

const registryCodes = new Set<string>();
if (registry) {
  const keyRe = /^\s{2}([A-Z][A-Z0-9_]+):\s*\{$/gm;
  for (const m of registry.matchAll(keyRe)) {
    registryCodes.add(m[1]);
  }
}
push(
  "registry parsed at least 25 codes",
  registryCodes.size >= 25,
  `parsed ${registryCodes.size}`,
);

for (const code of commonCodes) {
  push(
    `registry covers COMMON code ${code}`,
    registryCodes.has(code),
  );
}

// Per-code shape: every entry has en + ptBR + es keys
if (registry) {
  for (const code of registryCodes) {
    const blockRe = new RegExp(
      `\\b${code}:\\s*\\{([\\s\\S]*?)\\},`,
      "m",
    );
    const m = registry.match(blockRe);
    if (!m) {
      push(`registry entry ${code} has en/ptBR/es triple`, false, "block not parseable");
      continue;
    }
    const body = m[1];
    const hasEn = /\ben:\s*"[^"]+"/.test(body);
    const hasPtBR = /\bptBR:\s*"[^"]+"/.test(body);
    const hasEs = /\bes:\s*"[^"]+"/.test(body);
    push(
      `registry entry ${code} has en/ptBR/es triple`,
      hasEn && hasPtBR && hasEs,
      !hasEn ? "missing en" : !hasPtBR ? "missing ptBR" : !hasEs ? "missing es" : undefined,
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 3. Scan portal/src/app/api/** for pt-BR diacriticals inside
//    string literals of *.ts/*.tsx files (excluding tests + SQL comments).
//
//    The guard is route-focused: it flags new pt-BR user-facing
//    literals introduced in route handlers. Code-comments and
//    Portuguese in variable names are allowed.
// ────────────────────────────────────────────────────────────────────────────

const DIACRITICS = /[áéíóúãõâêôÁÉÍÓÚÃÕÂÊÔ]/;
// Narrow whitelist of short Portuguese prepositions/particles that commonly
// appear in identifiers and quoted role names ("atleta", "assessoria").
// These are allowed because they're identifier-like, not user copy.
const LEXICAL_WHITELIST = new Set<string>([
  "atleta", "atletas",
  "assessoria", "assessorias",
  "treinador", "treinadores",
  "administração", "usuário", "usuários",
]);

function walk(dir: string, acc: string[]): string[] {
  const entries = readdirSync(dir);
  for (const name of entries) {
    const full = `${dir}/${name}`;
    const s = statSync(full);
    if (s.isDirectory()) {
      walk(full, acc);
    } else if (
      s.isFile()
      && (full.endsWith(".ts") || full.endsWith(".tsx"))
      && !full.endsWith(".test.ts")
      && !full.endsWith(".test.tsx")
    ) {
      acc.push(full);
    }
  }
  return acc;
}

const apiFiles = walk(resolve(ROOT, "portal/src/app/api"), []);
push(
  "scanned portal/src/app/api files",
  apiFiles.length > 20,
  `found ${apiFiles.length} non-test .ts/.tsx files`,
);

const STRING_RE = /"([^"\\]|\\.){4,}"/g;

type Offender = { file: string; line: number; literal: string };
const offenders: Offender[] = [];

for (const file of apiFiles) {
  const src = readFileSync(file, "utf8");
  const lines = src.split("\n");
  lines.forEach((line, idx) => {
    const trimmed = line.trim();
    if (trimmed.startsWith("//")) return;
    if (trimmed.startsWith("*")) return;
    if (trimmed.startsWith("/*")) return;
    for (const m of line.matchAll(STRING_RE)) {
      const lit = m[0];
      if (!DIACRITICS.test(lit)) continue;
      const inner = lit.slice(1, -1).toLowerCase().trim();
      if (LEXICAL_WHITELIST.has(inner)) continue;
      offenders.push({ file: relative(ROOT, file), line: idx + 1, literal: lit });
    }
  });
}

// ────────────────────────────────────────────────────────────────────────────
// 3a. Baseline ratchet — legacy pt-BR literals are recorded in
//     tools/audit/baselines/api-error-i18n-baseline.txt as
//     "file:line:literal" entries. The guard fails only when a
//     NEW offender appears that's not in the baseline, or when an
//     entry in the baseline is no longer present (time to shrink
//     the baseline — run with UPDATE_BASELINE=1 to refresh).
// ────────────────────────────────────────────────────────────────────────────

function offenderKey(o: Offender): string {
  return `${o.file}::${o.literal}`;
}

const baselinePath = resolve(
  ROOT,
  "tools/audit/baselines/api-error-i18n-baseline.txt",
);

const shouldUpdateBaseline = process.env.UPDATE_BASELINE === "1";

if (shouldUpdateBaseline) {
  const lines = offenders
    .map((o) => `${o.file}::${o.literal}`)
    .sort()
    .reduce<string[]>((acc, line) => {
      if (acc[acc.length - 1] !== line) acc.push(line);
      return acc;
    }, []);
  writeFileSync(baselinePath, lines.join("\n") + "\n", "utf8");
  push(
    `baseline refreshed with ${lines.length} entries`,
    true,
    baselinePath,
  );
} else {
  const baseline = existsSync(baselinePath)
    ? new Set(
        readFileSync(baselinePath, "utf8")
          .split("\n")
          .map((s) => s.trim())
          .filter((s) => s && !s.startsWith("#")),
      )
    : new Set<string>();

  const currentKeys = new Set(offenders.map(offenderKey));

  const newOffenders = offenders.filter((o) => !baseline.has(offenderKey(o)));
  const staleBaselineEntries = [...baseline].filter((b) => !currentKeys.has(b));

  push(
    `baseline present (legacy debt = ${baseline.size} entries)`,
    baseline.size > 0,
    baseline.size === 0
      ? "baseline missing — run `UPDATE_BASELINE=1 npm run audit:api-error-i18n` once to seed"
      : undefined,
  );

  push(
    "no NEW pt-BR diacritical literals (compared to baseline)",
    newOffenders.length === 0,
    newOffenders.length > 0
      ? `${newOffenders.length} new offenders (first: ${newOffenders[0].file}:${newOffenders[0].line} ${newOffenders[0].literal})`
      : undefined,
  );

  push(
    "baseline ratchet clean (no stale entries — fixed files leave the baseline)",
    staleBaselineEntries.length === 0,
    staleBaselineEntries.length > 0
      ? `${staleBaselineEntries.length} baseline entries are now clean — run UPDATE_BASELINE=1 to shrink`
      : undefined,
  );
}

// ────────────────────────────────────────────────────────────────────────────
// 4. Finding self-reference
// ────────────────────────────────────────────────────────────────────────────

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L07-01-mensagens-de-erro-em-portugues-hardcoded-no-backend.md",
);
const finding = safeRead(findingPath, "L07-01 finding present");
if (finding) {
  push(
    "finding references error-messages registry",
    /portal\/src\/lib\/api\/error-messages\.ts/.test(finding),
  );
  push(
    "finding references CI guard",
    /audit:api-error-i18n|check-api-error-i18n/.test(finding),
  );
  push(
    "finding documents en/ptBR/es locale coverage",
    /ptBR/.test(finding) && /\ben\b/.test(finding) && /\bes\b/.test(finding),
  );
}

// ────────────────────────────────────────────────────────────────────────────
// 5. Summary
// ────────────────────────────────────────────────────────────────────────────

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} api-error-i18n checks passed.`,
);
if (failed > 0) {
  console.error("\nL07-01 invariants broken.");
  if (offenders.length > 0) {
    console.error("\nOffending literals (first 20):");
    for (const o of offenders.slice(0, 20)) {
      console.error(`  ${o.file}:${o.line}  ${o.literal}`);
    }
  }
  process.exit(1);
}
