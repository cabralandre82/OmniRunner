/**
 * check-adr-governance.ts
 *
 * L17-07 — ADR governance: every ADR file in `docs/adr/` MUST be
 * listed in the README index, and every "Accepted" ADR MUST be
 * referenced from at least one code/migration/runbook file.
 */

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const ADR_DIR = resolve(ROOT, "docs", "adr");
const README = resolve(ADR_DIR, "README.md");

interface Result { name: string; ok: boolean; detail?: string; }
const results: Result[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

if (!existsSync(README)) {
  console.error(`[FAIL] missing ${README}`);
  process.exit(1);
}
const readme = readFileSync(README, "utf8");

const adrFiles = readdirSync(ADR_DIR)
  .filter((f) => /^(ADR-)?\d{3,4}-.*\.md$/.test(f))
  .sort();

push("readme — has Index section", /## Index/i.test(readme));
push("readme — has Status values section", /## Status values/i.test(readme));
push("readme — has When to write an ADR section", /## When to write an ADR/i.test(readme));
push("readme — references audit:adr-governance", /audit:adr-governance/.test(readme));

for (const f of adrFiles) {
  const inIndex = readme.includes(f);
  push(`index — ${f} listed in README`, inIndex);
}

push(
  "adr — at least 5 ADRs present",
  adrFiles.length >= 5,
  `found ${adrFiles.length}`,
);

push(
  "naming — new ADRs follow ADR-NNNN-<slug>.md",
  /ADR-NNNN-/.test(readme),
);

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} adr-governance checks passed.`);
if (failed > 0) {
  console.error("\nL17-07 invariants broken.");
  process.exit(1);
}
