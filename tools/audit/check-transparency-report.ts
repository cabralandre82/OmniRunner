/**
 * check-transparency-report.ts
 *
 * L09-10 — guards the canonical Marco Civil Art. 11 transparency
 * report template lives at `docs/legal/TRANSPARENCY_REPORT.md`
 * with all required sections and references.
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const DOC = resolve(ROOT, "docs", "legal", "TRANSPARENCY_REPORT.md");

if (!existsSync(DOC)) {
  console.error(`[FAIL] missing ${DOC}`);
  process.exit(1);
}
const md = readFileSync(DOC, "utf8");

const checks: Array<[string, boolean]> = [
  ["title — Relatório de Transparência", /Relatório de Transparência/.test(md)],
  ["legal — Marco Civil Art. 11", /Marco Civil[\s\S]{0,80}Art\.?\s*11/.test(md)],
  ["legal — LGPD Art. 4", /LGPD[\s\S]{0,40}Art\.?\s*4/.test(md)],
  ["section — período coberto", /Período coberto/i.test(md)],
  ["section — solicitações governamentais", /Solicitações governamentais/i.test(md)],
  ["section — direitos LGPD", /direitos\s+LGPD|titulares.*LGPD|LGPD.*Art\.\s*18/i.test(md)],
  ["section — incidentes de segurança", /Incidentes de segurança/i.test(md)],
  ["section — remoções de conteúdo", /Remoções de conteúdo/i.test(md)],
  ["sla — 15 dias mention", /15\s*d(ias)?\b/.test(md)],
  ["cadence — semestral", /semestral/i.test(md)],
  ["contact — DPO email", /dpo@omnirunner\.com\.br/.test(md)],
  ["history — revision table",  /Histórico de revisão/.test(md)],
  ["crossref — DPO doc",        /DPO_AND_DATA_SUBJECT_CHANNEL/.test(md)],
];

let failed = 0;
for (const [name, ok] of checks) {
  if (ok) console.log(`[OK]   ${name}`);
  else { failed += 1; console.error(`[FAIL] ${name}`); }
}
console.log(`\n${checks.length - failed}/${checks.length} transparency-report checks passed.`);
if (failed > 0) process.exit(1);
