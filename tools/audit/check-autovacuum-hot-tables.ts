/**
 * check-autovacuum-hot-tables.ts — L19-10 migration contract guard.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const SQL = resolve(__dirname, "..", "..", "supabase", "migrations",
  "20260421750000_l19_10_autovacuum_hot_tables.sql");
if (!existsSync(SQL)) { console.error(`[FAIL] missing ${SQL}`); process.exit(1); }
const sql = readFileSync(SQL, "utf8");

const tables = ["coin_ledger", "sessions", "product_events", "audit_logs",
  "workout_delivery_items", "workout_delivery_events"];

const checks: Array<[string, boolean]> = [
  ["migration — BEGIN/COMMIT wrapping",  /BEGIN;[\s\S]*COMMIT;/.test(sql)],
  ["migration — references L19-10",      /L19-10/.test(sql)],
  ["migration — OmniCoin opt-out",       /L04-07-OK/.test(sql)],
  ...tables.map<[string, boolean]>((t) => [
    `tables — ${t} listed as hot table`, sql.includes(`'${t}'`),
  ]),
  ["params — vacuum_scale_factor 0.05",  /autovacuum_vacuum_scale_factor\s*=\s*0\.05/.test(sql)],
  ["params — analyze_scale_factor 0.02", /autovacuum_analyze_scale_factor\s*=\s*0\.02/.test(sql)],
  ["params — vacuum_cost_delay 10",      /autovacuum_vacuum_cost_delay\s*=\s*10/.test(sql)],
  ["params — vacuum_cost_limit 1000",    /autovacuum_vacuum_cost_limit\s*=\s*1000/.test(sql)],
  ["idempotency — applies only when table exists",
    /pg_class[\s\S]{0,200}relname\s*=\s*v_table/.test(sql)],
  ["self-test — emits PASSED notice",    /L19-10 self-test PASSED/.test(sql)],
  ["safety — no INSERT into coin_ledger", !/INSERT\s+INTO\s+public\.coin_ledger/i.test(sql)],
];

let failed = 0;
for (const [n, ok] of checks) { if (ok) console.log(`[OK]   ${n}`); else { failed++; console.error(`[FAIL] ${n}`); } }
console.log(`\n${checks.length - failed}/${checks.length} autovacuum-hot-tables checks passed.`);
if (failed) process.exit(1);
