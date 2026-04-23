/**
 * check-coach-daily-digest.ts
 *
 * L23-02 — CI guard enforcing the invariants of
 * `supabase/migrations/20260421740000_l23_02_coach_daily_digest.sql`.
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const SQL = resolve(
  ROOT,
  "supabase",
  "migrations",
  "20260421740000_l23_02_coach_daily_digest.sql",
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

// ─────────── shell ─────────────────────────────────────────────────
push("migration — BEGIN/COMMIT wrapping", /BEGIN;[\s\S]*COMMIT;/.test(sql));
push("migration — references finding L23-02", /L23-02/.test(sql));
push("migration — OmniCoin opt-out marker", /L04-07-OK/.test(sql));

// ─────────── function declaration ──────────────────────────────────
push(
  "fn — fn_coach_daily_digest declared",
  /CREATE OR REPLACE FUNCTION public\.fn_coach_daily_digest/.test(sql),
);
push(
  "fn — signature accepts (uuid, date, int)",
  /fn_coach_daily_digest\(\s*p_group_id\s+uuid[\s\S]{0,200}p_as_of\s+date[\s\S]{0,200}p_max_per_bucket\s+int/.test(sql),
);
push("fn — RETURNS jsonb", /fn_coach_daily_digest[\s\S]{0,400}RETURNS jsonb/.test(sql));
push("fn — SECURITY DEFINER", /fn_coach_daily_digest[\s\S]{0,400}SECURITY DEFINER/.test(sql));
push("fn — STABLE volatility", /fn_coach_daily_digest[\s\S]{0,400}\bSTABLE\b/.test(sql));
push(
  "fn — search_path pinned to public,pg_temp",
  /fn_coach_daily_digest[\s\S]{0,400}SET search_path\s*=\s*public,\s*pg_temp/.test(sql),
);
push(
  "fn — REVOKE FROM PUBLIC",
  /REVOKE ALL ON FUNCTION public\.fn_coach_daily_digest\(uuid, date, int\)\s+FROM PUBLIC/.test(sql),
);
push(
  "fn — GRANT EXECUTE to authenticated",
  /GRANT EXECUTE ON FUNCTION public\.fn_coach_daily_digest\(uuid, date, int\)\s+TO authenticated/.test(sql),
);

// ─────────── input guards ──────────────────────────────────────────
push(
  "guard — UNAUTHORIZED when caller NULL",
  /v_caller IS NULL[\s\S]{0,200}P0010[\s\S]{0,200}UNAUTHORIZED/.test(sql),
);
push(
  "guard — INVALID_INPUT when group_id NULL",
  /p_group_id IS NULL[\s\S]{0,200}P0001[\s\S]{0,200}INVALID_INPUT/.test(sql),
);
push(
  "guard — INVALID_INPUT when max_per_bucket out of [1,200]",
  /p_max_per_bucket[\s\S]{0,200}<\s*1[\s\S]{0,200}>\s*200[\s\S]{0,200}P0001/.test(sql),
);
push(
  "guard — INVALID_INPUT when as_of NULL",
  /p_as_of IS NULL[\s\S]{0,200}P0001/.test(sql),
);
push(
  "guard — GROUP_NOT_FOUND raises P0002",
  /GROUP_NOT_FOUND[\s\S]{0,200}P0002|P0002[\s\S]{0,200}GROUP_NOT_FOUND/.test(sql),
);
push(
  "guard — role gate accepts admin_master/coach/assistant",
  /v_role NOT IN \('admin_master',\s*'coach',\s*'assistant'\)/.test(sql),
);

// ─────────── time windows ──────────────────────────────────────────
push("window — 7d current", /v_window_now_lo\s*:=\s*v_window_now_hi - interval '7 days'/.test(sql));
push("window — 7d previous", /v_window_prev_lo\s*:=\s*v_window_prev_hi - interval '7 days'/.test(sql));
push("window — inactive_cut 3d", /v_inactive_cut\s*:=\s*v_window_now_hi - interval '3 days'/.test(sql));
push(
  "window — pace history baseline 90d",
  /interval '90 days'/.test(sql),
);

// ─────────── signal definitions ────────────────────────────────────
push("signal — sig_inactive_3d", /sig_inactive_3d/.test(sql));
push("signal — sig_plan_not_followed", /sig_plan_not_followed/.test(sql));
push("signal — sig_integrity_flag", /sig_integrity_flag/.test(sql));
push("signal — sig_declining_volume threshold 0.5x", /dist_m_7d\s*<\s*\(r\.dist_m_prev_7d \* 0\.5\)/.test(sql));
push("signal — sig_overtraining_spike threshold 2.0x", /dist_m_7d\s*>\s*\(r\.dist_m_prev_7d \* 2\.0\)/.test(sql));
push("signal — sig_new_pr beats baseline", /best_recent_pace\s*<\s*r\.baseline_best_pace/.test(sql));

// ─────────── bucket priority ───────────────────────────────────────
push(
  "bucket — needs_attention from 3 critical signals",
  /sig_inactive_3d[\s\S]{0,200}sig_plan_not_followed[\s\S]{0,200}sig_integrity_flag[\s\S]{0,100}'needs_attention'/.test(sql),
);
push(
  "bucket — at_risk from volume signals",
  /sig_declining_volume[\s\S]{0,200}sig_overtraining_spike[\s\S]{0,100}'at_risk'/.test(sql),
);
push(
  "bucket — new_prs from sig_new_pr",
  /sig_new_pr[\s\S]{0,100}'new_prs'/.test(sql),
);
push(
  "bucket — performing_well requires adherence ≥80",
  /adherence_14d_pct[\s\S]{0,40},\s*0\)\s*>=\s*80[\s\S]{0,100}'performing_well'/.test(sql),
);

// ─────────── score weights ─────────────────────────────────────────
push("score — integrity_flag = 100",      /sig_integrity_flag[\s\S]{0,40}100/.test(sql));
push("score — plan_not_followed = 60",    /sig_plan_not_followed[\s\S]{0,40}60/.test(sql));
push("score — inactive_3d = 40",          /sig_inactive_3d\s+THEN\s+40/.test(sql));
push("score — overtraining_spike = 30",   /sig_overtraining_spike\s+THEN\s+30/.test(sql));
push("score — declining_volume = 20",     /sig_declining_volume\s+THEN\s+20/.test(sql));
push("score — new_pr = 10",               /sig_new_pr\s+THEN\s+10/.test(sql));

// ─────────── per-row capping ───────────────────────────────────────
push(
  "capped — row_number partition by bucket",
  /row_number\(\) OVER \(\s*PARTITION BY b\.bucket/.test(sql),
);
push("capped — uses p_max_per_bucket", /rk <= p_max_per_bucket/.test(sql));

// ─────────── output envelope ───────────────────────────────────────
push("envelope — group_id field",   /'group_id'/.test(sql));
push("envelope — as_of field",      /'as_of'/.test(sql));
push("envelope — generated_at",     /'generated_at'/.test(sql));
push("envelope — window object",    /'window'[\s\S]{0,200}'now_lo'[\s\S]{0,200}'prev_lo'/.test(sql));
push(
  "envelope — counts has 6 keys",
  /'counts'[\s\S]{0,400}'total_athletes'[\s\S]{0,200}'needs_attention'[\s\S]{0,200}'at_risk'[\s\S]{0,200}'new_prs'[\s\S]{0,200}'performing_well'[\s\S]{0,200}'neutral'/.test(sql),
);
push(
  "envelope — 4 buckets returned as arrays",
  /'needs_attention'[\s\S]{0,400}'at_risk'[\s\S]{0,400}'new_prs'[\s\S]{0,400}'performing_well'/.test(sql),
);
push(
  "envelope — empty bucket coalesces to []",
  /coalesce\([\s\S]{0,400}'\[\]'::jsonb\)/.test(sql),
);

// ─────────── per-row shape ─────────────────────────────────────────
push("row — athlete_user_id",      /'athlete_user_id'/.test(sql));
push("row — display_name",         /'display_name'/.test(sql));
push("row — bucket",               /'bucket'/.test(sql));
push("row — score",                /'score'/.test(sql));
push("row — last_session_at",      /'last_session_at'/.test(sql));
push("row — verified_sessions_7d", /'verified_sessions_7d'/.test(sql));
push("row — adherence_14d_pct",    /'adherence_14d_pct'/.test(sql));
push("row — best_recent_pace",     /'best_recent_pace'/.test(sql));
push("row — baseline_best_pace",   /'baseline_best_pace'/.test(sql));
push(
  "row — signals array enumerates 6 codes",
  /array_remove\(ARRAY\[[\s\S]{0,800}'inactive_3d'[\s\S]{0,200}'plan_not_followed'[\s\S]{0,200}'integrity_flag'[\s\S]{0,200}'declining_volume'[\s\S]{0,200}'overtraining_spike'[\s\S]{0,200}'new_pr'/.test(sql),
);

// ─────────── OmniCoin safety ───────────────────────────────────────
push(
  "omnicoin — no INSERT into coin_ledger",
  !/INSERT\s+INTO\s+public\.coin_ledger/i.test(sql),
);
push(
  "omnicoin — no UPDATE of wallets",
  !/UPDATE\s+public\.wallets/i.test(sql),
);
push(
  "omnicoin — comment confirms read-only",
  /never touches[\s\S]{0,80}coin_ledger/i.test(sql),
);

// ─────────── self-test ─────────────────────────────────────────────
push(
  "self-test — asserts SECURITY DEFINER",
  /must be SECURITY DEFINER/.test(sql),
);
push(
  "self-test — asserts STABLE",
  /must be STABLE/.test(sql),
);
push(
  "self-test — asserts search_path pinned",
  /must pin search_path/.test(sql),
);
push(
  "self-test — asserts PUBLIC revoked",
  /must REVOKE FROM PUBLIC/.test(sql),
);
push("self-test — emits PASSED notice", /L23-02 self-test PASSED/.test(sql));

// ─────────── finding cross-ref ─────────────────────────────────────
const findingPath = resolve(
  ROOT,
  "docs",
  "audit",
  "findings",
  "L23-02-dashboard-de-overview-diario-para-coach-tem-100.md",
);
if (existsSync(findingPath)) {
  const f = readFileSync(findingPath, "utf8");
  push("finding — references migration",
    /20260421740000_l23_02_coach_daily_digest/.test(f));
  push("finding — references CI guard",
    /audit:coach-daily-digest|check-coach-daily-digest/.test(f));
  push("finding — status marked fixed", /status:\s*fixed/.test(f));
}

// ─────────── summary ───────────────────────────────────────────────
let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} coach-daily-digest checks passed.`);
if (failed > 0) {
  console.error("\nL23-02 invariants broken.");
  process.exit(1);
}
