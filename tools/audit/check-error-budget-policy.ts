/**
 * check-error-budget-policy.ts — L20-13 policy contract guard.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const DOC = resolve(__dirname, "..", "..", "docs", "ERROR_BUDGET_POLICY.md");
if (!existsSync(DOC)) { console.error(`[FAIL] missing ${DOC}`); process.exit(1); }
const md = readFileSync(DOC, "utf8");

const checks: Array<[string, boolean]> = [
  ["title — error budget policy",        /Error Budget Policy/i.test(md)],
  ["definitions — SLO",                  /\*\*SLO\*\*/.test(md)],
  ["definitions — burn rate",            /\*\*Burn rate\*\*/i.test(md)],
  ["tier — Green/Yellow/Orange/Red",
    /Green[\s\S]{0,400}Yellow[\s\S]{0,400}Orange[\s\S]{0,400}Red/.test(md)],
  ["thresholds — 50%/80%/100%",          /50\s*%[\s\S]{0,200}80\s*%[\s\S]{0,200}100\s*%/.test(md)],
  ["enforcement — GitHub deploy gate",   /error-budget-gate\.yml/.test(md)],
  ["enforcement — manual override SRE",  /sre-leads/.test(md)],
  ["replenishment — calendar month",     /calendar month|calendário/i.test(md)],
  ["replenishment — no carry-over",      /Carry-over[\s\S]{0,200}\*\*not\*\*\s+allowed|não.*acumula/i.test(md)],
  ["incident — P1/P2/P3/P4 weights",     /P1\s*=\s*4×|P1.*4x/i.test(md)],
  ["reporting — monthly report",         /monthly report|mensal/i.test(md)],
  ["crossref — SLO doc",                 /docs\/observability\/SLO/.test(md)],
  ["history — revision table",           /Histórico/.test(md)],
];

let failed = 0;
for (const [n, ok] of checks) { if (ok) console.log(`[OK]   ${n}`); else { failed++; console.error(`[FAIL] ${n}`); } }
console.log(`\n${checks.length - failed}/${checks.length} error-budget-policy checks passed.`);
if (failed) process.exit(1);
