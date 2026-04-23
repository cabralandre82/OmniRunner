/**
 * check-clearing-not-cession.ts
 *
 * L09-11 — guards the canonical document arguing why
 * `clearing_settlements` does NOT constitute cessão de crédito
 * (CC Art. 286), differentiating it from `swap_orders` (ADR-008).
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const DOC = resolve(ROOT, "docs", "legal", "CLEARING_NOT_CESSAO_DE_CREDITO.md");

if (!existsSync(DOC)) {
  console.error(`[FAIL] missing ${DOC}`);
  process.exit(1);
}
const md = readFileSync(DOC, "utf8");

const checks: Array<[string, boolean]> = [
  ["title — clearing not cessão de crédito",   /Clearing settlements\s*[≠!]=?\s*Cessão de crédito/.test(md)],
  ["legal — references CC Art. 286",            /Art\.?\s*286/.test(md)],
  ["legal — references CC Art. 290",            /Art\.?\s*290/.test(md)],
  ["legal — references CC Art. 368 compensação", /Art\.?\s*368/.test(md)],
  ["pillar — perimeter limited to one assessoria", /perímetro|mesma assessoria/i.test(md)],
  ["pillar — recibo eletrônico hash",           /SHA-256|hash/.test(md)],
  ["pillar — termo de adesão clause 4.2",       /Termo de Adesão.*4\.2|cláusula 4\.2/.test(md)],
  ["safeguard — limit per assessoria",          /R\$\s*100\.000|cap.*30 dias/i.test(md)],
  ["safeguard — reconciliação diária",          /Reconciliação\s+diária/i.test(md)],
  ["trigger — review when volume > 1M",         /R\$\s*1\.000\.000/.test(md)],
  ["trigger — cross-assessoria forbidden",      /cross-assessoria/i.test(md)],
  ["table — diff vs swap_orders",               /clearing_settlements[\s\S]{0,800}swap_orders/.test(md)],
  ["crossref — ADR-008",                        /ADR-008|008-swap-as-off-platform-credit-cession/.test(md)],
  ["crossref — ADR-007 custody model",          /007-custody-clearing-model/.test(md)],
  ["crossref — BCB classification",             /BCB_CLASSIFICATION/.test(md)],
  ["history — revision table",                  /Histórico de revisão/.test(md)],
];

let failed = 0;
for (const [name, ok] of checks) {
  if (ok) console.log(`[OK]   ${name}`);
  else { failed += 1; console.error(`[FAIL] ${name}`); }
}
console.log(`\n${checks.length - failed}/${checks.length} clearing-not-cession checks passed.`);
if (failed > 0) process.exit(1);
