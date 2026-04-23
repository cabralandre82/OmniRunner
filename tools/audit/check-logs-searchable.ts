/**
 * check-logs-searchable.ts — L20-10 runbook contract guard.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const DOC = resolve(__dirname, "..", "..", "docs", "runbooks", "LOGS_SEARCHABLE.md");
if (!existsSync(DOC)) { console.error(`[FAIL] missing ${DOC}`); process.exit(1); }
const md = readFileSync(DOC, "utf8");

const checks: Array<[string, boolean]> = [
  ["title — logs searchable",            /Logs Searchable/i.test(md)],
  ["legal — Marco Civil 6 months",       /Marco Civil[\s\S]{0,200}6\s+(months|meses)/.test(md)],
  ["legal — LGPD Art. 38",               /LGPD[\s\S]{0,40}Art\.?\s*38/.test(md)],
  ["legal — BCB Resolução 4658",         /4658/.test(md)],
  ["arch — Axiom or Datadog hot tier",   /Axiom|Datadog Logs/i.test(md)],
  ["arch — S3 Glacier cold tier",        /S3 Glacier/i.test(md)],
  ["fields — request_id mandatory",      /request_id/.test(md)],
  ["fields — user_id_hash never raw",    /user_id_hash[\s\S]{0,200}raw/.test(md)],
  ["fields — category enum",             /security \| financial \| privacy \| business/.test(md)],
  ["failure — ingestion lag >60s",       /ingest-lag-high|ingestion lag/i.test(md)],
  ["failure — PII leak runbook",         /PII_LEAK_RUNBOOK|PII leak/i.test(md)],
  ["cost — guardrail",                   /Cost guardrails/i.test(md)],
  ["crossref — SLO doc",                 /docs\/observability\/SLO|L20-02/.test(md)],
  ["history — revision table",           /Histórico/.test(md)],
];

let failed = 0;
for (const [n, ok] of checks) { if (ok) console.log(`[OK]   ${n}`); else { failed++; console.error(`[FAIL] ${n}`); } }
console.log(`\n${checks.length - failed}/${checks.length} logs-searchable checks passed.`);
if (failed) process.exit(1);
