/**
 * check-bulk-assign-rollback.ts
 *
 * L23-04 — CI guard enforcing the invariants of the bulk-assign
 * rollback schema + RPCs introduced in
 * `supabase/migrations/20260421730000_l23_04_bulk_assign_rollback.sql`.
 */

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const SQL = resolve(
  ROOT,
  "supabase",
  "migrations",
  "20260421730000_l23_04_bulk_assign_rollback.sql",
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

// ──────────────────────────────────────────────────────────────────
// Migration shell
// ──────────────────────────────────────────────────────────────────
push("migration — BEGIN/COMMIT wrapping", /BEGIN;[\s\S]*COMMIT;/.test(sql));
push("migration — references finding L23-04", /L23-04/.test(sql));
push("migration — OmniCoin opt-out marker", /L04-07-OK/.test(sql));

// ──────────────────────────────────────────────────────────────────
// Table
// ──────────────────────────────────────────────────────────────────
push(
  "table — bulk_assign_batches created",
  /CREATE TABLE IF NOT EXISTS public\.bulk_assign_batches/.test(sql),
);
push(
  "table — undo_ttl_minutes bounded [1,1440]",
  /undo_ttl_minutes[\s\S]{0,200}BETWEEN 1 AND 1440/.test(sql),
);
push(
  "table — undone_at/undone_by consistency CHECK",
  /bulk_assign_batches_undone_consistency/.test(sql),
);
push(
  "table — group_id references coaching_groups",
  /group_id\s+uuid NOT NULL REFERENCES public\.coaching_groups\(id\)/.test(sql),
);
push(
  "table — actor_id references auth.users",
  /actor_id\s+uuid NOT NULL REFERENCES auth\.users\(id\)/.test(sql),
);
push(
  "indexes — group + actor recent created",
  /bulk_assign_batches_group_recent[\s\S]{0,200}bulk_assign_batches_actor_recent/.test(sql),
);

// Column additions
push(
  "alter — plan_workout_releases.bulk_batch_id added",
  /ALTER TABLE public\.plan_workout_releases[\s\S]{0,200}bulk_batch_id uuid[\s\S]{0,200}REFERENCES public\.bulk_assign_batches\(id\)/.test(sql),
);
push(
  "alter — training_plan_weeks.bulk_batch_id added",
  /ALTER TABLE public\.training_plan_weeks[\s\S]{0,200}bulk_batch_id uuid[\s\S]{0,200}REFERENCES public\.bulk_assign_batches\(id\)/.test(sql),
);
push(
  "index — plan_workout_releases.bulk_batch_id partial",
  /plan_workout_releases_bulk_batch[\s\S]{0,200}WHERE bulk_batch_id IS NOT NULL/.test(sql),
);
push(
  "index — training_plan_weeks.bulk_batch_id partial",
  /training_plan_weeks_bulk_batch[\s\S]{0,200}WHERE bulk_batch_id IS NOT NULL/.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// RLS
// ──────────────────────────────────────────────────────────────────
push(
  "rls — bulk_assign_batches RLS enabled",
  /ALTER TABLE public\.bulk_assign_batches ENABLE ROW LEVEL SECURITY/.test(sql),
);
push(
  "rls — staff read policy",
  /bulk_assign_batches_staff_read[\s\S]{0,400}admin_master.*coach.*assistant/.test(sql),
);
push(
  "rls — no direct DML policy",
  /bulk_assign_batches_no_direct_dml[\s\S]{0,200}FOR ALL[\s\S]{0,200}USING \(false\)/.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// Functions
// ──────────────────────────────────────────────────────────────────
const fns = [
  { name: "fn_bulk_assign_batch_open",    sig: /uuid,\s*uuid,\s*text,\s*int/ },
  { name: "fn_bulk_assign_batch_attach",  sig: /uuid,\s*uuid\[\],\s*uuid\[\]/ },
  { name: "fn_bulk_assign_batch_undo",    sig: /uuid,\s*uuid,\s*text/ },
  { name: "fn_bulk_assign_batch_summary", sig: /uuid/ },
];
for (const fn of fns) {
  push(
    `fn — ${fn.name} declared`,
    new RegExp(`CREATE OR REPLACE FUNCTION public\\.${fn.name}`).test(sql),
  );
  push(
    `fn — ${fn.name} SECURITY DEFINER`,
    new RegExp(`${fn.name}[\\s\\S]{0,800}SECURITY DEFINER`).test(sql),
  );
  push(
    `fn — ${fn.name} search_path pinned`,
    new RegExp(`${fn.name}[\\s\\S]{0,1200}SET search_path\\s*=\\s*public,\\s*pg_temp`).test(sql),
  );
  push(
    `fn — ${fn.name} REVOKE FROM PUBLIC`,
    new RegExp(`REVOKE ALL ON FUNCTION public\\.${fn.name}\\([^)]*\\)\\s+FROM PUBLIC`).test(sql),
  );
  push(
    `fn — ${fn.name} GRANT EXECUTE to authenticated`,
    new RegExp(`GRANT EXECUTE ON FUNCTION public\\.${fn.name}\\([^)]*\\)\\s+TO authenticated`).test(sql),
  );
}

// ──────────────────────────────────────────────────────────────────
// Undo gates
// ──────────────────────────────────────────────────────────────────
push(
  "undo — TTL gate raises P0005 UNDO_WINDOW_EXPIRED",
  /UNDO_WINDOW_EXPIRED[\s\S]{0,200}ERRCODE\s*=\s*'P0005'|ERRCODE\s*=\s*'P0005'[\s\S]{0,200}UNDO_WINDOW_EXPIRED/.test(sql),
);
push(
  "undo — already-undone gate raises P0003",
  /BATCH_ALREADY_UNDONE[\s\S]{0,200}ERRCODE\s*=\s*'P0003'|ERRCODE\s*=\s*'P0003'[\s\S]{0,200}BATCH_ALREADY_UNDONE/.test(sql),
);
push(
  "undo — author-only gate (or platform_admin fallback)",
  /only the original author or a platform_admin/.test(sql) ||
    /actor_id\s*<>\s*v_batch\.actor_id/.test(sql),
);
push(
  "undo — role gate coach/admin_master",
  /NOT IN \('admin_master',\s*'coach'\)/.test(sql),
);
push(
  "undo — BATCH_NOT_FOUND raises P0002",
  /BATCH_NOT_FOUND[\s\S]{0,200}ERRCODE\s*=\s*'P0002'|ERRCODE\s*=\s*'P0002'[\s\S]{0,200}BATCH_NOT_FOUND/.test(sql),
);
push(
  "undo — cancels releases via UPDATE release_status",
  /UPDATE public\.plan_workout_releases[\s\S]{0,400}release_status\s*=\s*'cancelled'[\s\S]{0,400}bulk_batch_id\s*=\s*p_batch_id/.test(sql),
);
push(
  "undo — cancels weeks via UPDATE status",
  /UPDATE public\.training_plan_weeks[\s\S]{0,400}status\s*=\s*'cancelled'[\s\S]{0,400}bulk_batch_id\s*=\s*p_batch_id/.test(sql),
);
push(
  "undo — marks batch undone_at/undone_by",
  /UPDATE public\.bulk_assign_batches[\s\S]{0,300}undone_at\s*=\s*v_now[\s\S]{0,200}undone_by\s*=\s*p_actor_id/.test(sql),
);
push(
  "undo — writes workout_change_log entries",
  /INSERT INTO public\.workout_change_log[\s\S]{0,400}bulk_assign_undone/.test(sql),
);
push(
  "undo — returns jsonb with counts",
  /jsonb_build_object\([\s\S]{0,400}'releases_undone'[\s\S]{0,200}'weeks_undone'/.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// Open gates
// ──────────────────────────────────────────────────────────────────
push(
  "open — rejects ttl outside [1,1440]",
  /ttl_minutes[\s\S]{0,200}outside \[1,1440\]|outside \[1,1440\]/.test(sql),
);
push(
  "open — role gate coach/admin_master only",
  /only admin_master or coach may open a bulk-assign batch/.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// Summary
// ──────────────────────────────────────────────────────────────────
push(
  "summary — returns can_undo / already_undone / undo_deadline",
  /'can_undo'/.test(sql) &&
    /'already_undone'/.test(sql) &&
    /'undo_deadline'/.test(sql),
);
push(
  "summary — only staff roles may call",
  /admin_master.*coach.*assistant[\s\S]{0,400}UNAUTHORIZED/.test(sql),
);
push("summary — STABLE volatility", /fn_bulk_assign_batch_summary[\s\S]{0,1200}STABLE/.test(sql));

// ──────────────────────────────────────────────────────────────────
// Attach gates
// ──────────────────────────────────────────────────────────────────
push(
  "attach — defends batch-group boundary",
  /p_release_ids[\s\S]{0,600}group_id\s*=\s*v_batch\.group_id/.test(sql),
);
push(
  "attach — rejects already-undone batch",
  /cannot attach to an already-undone batch/.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// OmniCoin safety
// ──────────────────────────────────────────────────────────────────
push(
  "omnicoin — no INSERT into coin_ledger",
  !/INSERT\s+INTO\s+public\.coin_ledger/i.test(sql),
);
push(
  "omnicoin — no UPDATE of wallets",
  !/UPDATE\s+public\.wallets/i.test(sql),
);
push(
  "omnicoin — undo comment confirms read-only of coin_ledger",
  /Never touches coin_ledger/i.test(sql),
);

// ──────────────────────────────────────────────────────────────────
// Self-test
// ──────────────────────────────────────────────────────────────────
push("self-test — asserts table exists", /bulk_assign_batches table missing/.test(sql));
push("self-test — asserts plan_workout_releases column", /plan_workout_releases\.bulk_batch_id missing/.test(sql));
push("self-test — asserts training_plan_weeks column", /training_plan_weeks\.bulk_batch_id missing/.test(sql));
push("self-test — asserts RLS enabled", /RLS disabled on bulk_assign_batches/.test(sql));
push(
  "self-test — asserts all 4 RPCs SECURITY DEFINER",
  /missing or not SECURITY DEFINER/.test(sql),
);
push("self-test — emits PASSED notice", /L23-04 self-test PASSED/.test(sql));

// ──────────────────────────────────────────────────────────────────
// Finding cross-ref
// ──────────────────────────────────────────────────────────────────
const findingPath = resolve(
  ROOT,
  "docs",
  "audit",
  "findings",
  "L23-04-bulk-assign-semanal-ver-20260416000000-bulk-assign-and.md",
);
if (existsSync(findingPath)) {
  const f = readFileSync(findingPath, "utf8");
  push(
    "finding — references migration",
    /20260421730000_l23_04_bulk_assign_rollback/.test(f),
  );
  push(
    "finding — references CI guard",
    /audit:bulk-assign-rollback|check-bulk-assign-rollback/.test(f),
  );
  push("finding — status marked fixed", /status:\s*fixed/.test(f));
}

// ──────────────────────────────────────────────────────────────────
// Summary
// ──────────────────────────────────────────────────────────────────
let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} bulk-assign-rollback checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-04 invariants broken.");
  process.exit(1);
}
