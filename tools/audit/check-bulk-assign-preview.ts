/**
 * check-bulk-assign-preview.ts
 *
 * L23-01 — CI guard for the bulk-assign preview RPC.  Enforces
 * schema shape, security properties and risk-classification
 * invariants of
 * `supabase/migrations/20260421720000_l23_01_bulk_assign_preview.sql`.
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const SQL = resolve(
  ROOT,
  "supabase",
  "migrations",
  "20260421720000_l23_01_bulk_assign_preview.sql",
);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

if (!existsSync(SQL)) {
  console.error(`[FAIL] migration missing at ${SQL}`);
  process.exit(1);
}
const sql = readFileSync(SQL, "utf8");

// ──────────────────────────────────────────────────────────────────────
// Migration shell
// ──────────────────────────────────────────────────────────────────────
push("migration — BEGIN/COMMIT wrapping", /BEGIN;[\s\S]*COMMIT;/.test(sql));
push("migration — references finding L23-01", /L23-01/.test(sql));
push(
  "migration — OmniCoin opt-out marker present",
  /L04-07-OK/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Function signature
// ──────────────────────────────────────────────────────────────────────
push(
  "function — CREATE OR REPLACE fn_bulk_assign_preview",
  /CREATE OR REPLACE FUNCTION public\.fn_bulk_assign_preview/.test(sql),
);
push(
  "function — takes (uuid, uuid[], date, numeric)",
  /p_group_id\s+uuid[\s\S]{0,200}p_athlete_ids\s+uuid\[\][\s\S]{0,200}p_target_date\s+date[\s\S]{0,200}p_planned_tss\s+numeric/.test(sql),
);
push("function — RETURNS jsonb", /RETURNS jsonb/.test(sql));
push("function — SECURITY DEFINER", /SECURITY DEFINER/.test(sql));
push("function — STABLE volatility", /\nSTABLE\b/.test(sql));
push(
  "function — search_path pinned",
  /SET search_path\s*=\s*public,\s*pg_temp/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Input guards
// ──────────────────────────────────────────────────────────────────────
push(
  "guard — null p_group_id raises P0001",
  /p_group_id IS NULL[\s\S]{0,200}ERRCODE\s*=\s*'P0001'/.test(sql),
);
push(
  "guard — empty p_athlete_ids raises P0001",
  /non-empty array[\s\S]{0,80}ERRCODE\s*=\s*'P0001'|ERRCODE\s*=\s*'P0001'[\s\S]{0,200}non-empty/.test(sql),
);
push(
  "guard — oversized p_athlete_ids (>500) raises P0001",
  /500[\s\S]{0,200}ERRCODE\s*=\s*'P0001'/.test(sql),
);
push(
  "guard — missing group raises P0002 GROUP_NOT_FOUND",
  /GROUP_NOT_FOUND[\s\S]{0,200}ERRCODE\s*=\s*'P0002'|ERRCODE\s*=\s*'P0002'[\s\S]{0,200}GROUP_NOT_FOUND/.test(sql),
);
push(
  "guard — null auth.uid() raises P0010",
  /v_caller IS NULL[\s\S]{0,200}ERRCODE\s*=\s*'P0010'/.test(sql),
);
push(
  "guard — non-coach/assistant raises P0010",
  /NOT IN \('coach',\s*'assistant'\)[\s\S]{0,200}ERRCODE\s*=\s*'P0010'/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Risk classification invariants
// ──────────────────────────────────────────────────────────────────────
push(
  "classify — uses confirmed_7d window",
  /confirmed_7d[\s\S]{0,400}INTERVAL '7 days'/.test(sql),
);
push(
  "classify — uses confirmed_14d window for baseline",
  /confirmed_14d[\s\S]{0,400}INTERVAL '14 days'/.test(sql),
);
push(
  "classify — uses upcoming week window",
  /upcoming[\s\S]{0,400}date_trunc\('week', now\(\)\)/.test(sql),
);
push(
  "classify — 'red' on >= 7 confirmed in 7d or >= 5 upcoming",
  />=\s*7\s+OR[\s\S]{0,80}>=\s*5\s+THEN\s+'red'/.test(sql),
);
push(
  "classify — 'yellow' on >= 5 confirmed in 7d or >= 3 upcoming",
  />=\s*5\s+OR[\s\S]{0,80}>=\s*3\s+THEN\s+'yellow'/.test(sql),
);
push(
  "classify — 'gray' when 14d has 0 confirmed workouts",
  /c14\.n,\s*0\)\s*=\s*0\s+THEN\s+'gray'/.test(sql),
);
push(
  "classify — non-athlete roles collapse to 'gray'",
  /member_role\s*<>\s*'athlete'\s+THEN\s+'gray'/.test(sql),
);
push(
  "classify — default branch is 'green'",
  /ELSE\s+'green'/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Output envelope
// ──────────────────────────────────────────────────────────────────────
const keys = [
  "generated_at",
  "group_id",
  "target_date",
  "planned_tss",
  "input_count",
  "counts",
  "athletes",
];
for (const k of keys) {
  push(
    `output — envelope includes "${k}"`,
    new RegExp(`'${k}'`).test(sql),
  );
}
const countKeys = ["green", "yellow", "red", "gray"];
for (const k of countKeys) {
  push(
    `counts — aggregate emits "${k}"`,
    new RegExp(`'${k}'[\\s\\S]{0,60}COALESCE\\(v_${k}`).test(sql),
  );
}

// per-athlete row shape
const athleteKeys = [
  "athlete_id",
  "display_name",
  "is_member",
  "member_role",
  "risk_level",
  "reasons",
  "workouts_confirmed_7d",
  "workouts_confirmed_14d",
  "upcoming_week_count",
  "last_confirmed_at",
];
for (const k of athleteKeys) {
  push(
    `athlete row — includes "${k}"`,
    new RegExp(`'${k}'`).test(sql),
  );
}

// sorting invariant (red first)
push(
  "ordering — red first, then yellow, gray, green",
  /WHEN\s+'red'\s+THEN\s+0[\s\S]{0,40}WHEN\s+'yellow'\s+THEN\s+1[\s\S]{0,40}WHEN\s+'gray'\s+THEN\s+2/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Grants
// ──────────────────────────────────────────────────────────────────────
push(
  "grants — REVOKE from PUBLIC",
  /REVOKE ALL ON FUNCTION public\.fn_bulk_assign_preview\(uuid,\s*uuid\[\],\s*date,\s*numeric\)\s+FROM PUBLIC/.test(sql),
);
push(
  "grants — GRANT EXECUTE to authenticated",
  /GRANT EXECUTE ON FUNCTION public\.fn_bulk_assign_preview\(uuid,\s*uuid\[\],\s*date,\s*numeric\)\s+TO authenticated/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Self-test
// ──────────────────────────────────────────────────────────────────────
push(
  "self-test — verifies SECURITY DEFINER",
  /must be SECURITY DEFINER/.test(sql),
);
push(
  "self-test — verifies STABLE",
  /must be STABLE/.test(sql),
);
push(
  "self-test — verifies EXECUTE grant",
  /role_routine_grants[\s\S]{0,400}authenticated/.test(sql),
);
push(
  "self-test — emits PASSED notice",
  /L23-01 self-test PASSED/.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// OmniCoin safety
// ──────────────────────────────────────────────────────────────────────
push(
  "omnicoin — no INSERT into coin_ledger",
  !/INSERT\s+INTO\s+public\.coin_ledger/i.test(sql),
);
push(
  "omnicoin — no UPDATE of wallets",
  !/UPDATE\s+public\.wallets/i.test(sql),
);
push(
  "omnicoin — function comment confirms read-only",
  /Never[\s\S]{0,40}touches coin_ledger/i.test(sql),
);

// ──────────────────────────────────────────────────────────────────────
// Finding cross-ref
// ──────────────────────────────────────────────────────────────────────
const findingPath = resolve(
  ROOT,
  "docs",
  "audit",
  "findings",
  "L23-01-workout-delivery-em-massa-sem-preview-por-atleta.md",
);
if (existsSync(findingPath)) {
  const f = readFileSync(findingPath, "utf8");
  push(
    "finding — references migration",
    /20260421720000_l23_01_bulk_assign_preview/.test(f),
  );
  push(
    "finding — references CI guard",
    /audit:bulk-assign-preview|check-bulk-assign-preview/.test(f),
  );
  push("finding — status marked fixed", /status:\s*fixed/.test(f));
}

// ──────────────────────────────────────────────────────────────────────
// Summary
// ──────────────────────────────────────────────────────────────────────
let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} bulk-assign-preview checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-01 invariants broken.");
  process.exit(1);
}
