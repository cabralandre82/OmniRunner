/**
 * check-connection-pooling.ts — L19-09 runbook contract guard.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const DOC = resolve(__dirname, "..", "..", "docs", "runbooks", "CONNECTION_POOLING.md");
if (!existsSync(DOC)) { console.error(`[FAIL] missing ${DOC}`); process.exit(1); }
const md = readFileSync(DOC, "utf8");

const checks: Array<[string, boolean]> = [
  ["title — connection pooling",      /Connection Pooling/i.test(md)],
  ["topology — pgBouncer transaction mode", /pgBouncer[\s\S]{0,200}transaction mode/i.test(md)],
  ["pool sizes — Free/Pro/Team/Enterprise tiers", /Free[\s\S]{0,200}Pro[\s\S]{0,200}Team[\s\S]{0,200}Enterprise/i.test(md)],
  ["mode — explains transaction vs session", /transaction mode[\s\S]{0,800}session mode/i.test(md)],
  ["failure — remaining connection slots", /remaining connection slots/i.test(md)],
  ["failure — Edge Function ETIMEDOUT",   /ETIMEDOUT/i.test(md)],
  ["burst — references L23-02 digest",    /daily-digest|L23-02/i.test(md)],
  ["observability — pg_stat_activity",    /pg_stat_activity/i.test(md)],
  ["crossref — L02-11",                   /L02-11/.test(md)],
  ["crossref — L19-10 autovacuum",        /L19-10/.test(md)],
  ["history — revision table",            /Histórico/.test(md)],
];

let failed = 0;
for (const [n, ok] of checks) { if (ok) console.log(`[OK]   ${n}`); else { failed++; console.error(`[FAIL] ${n}`); } }
console.log(`\n${checks.length - failed}/${checks.length} connection-pooling checks passed.`);
if (failed) process.exit(1);
