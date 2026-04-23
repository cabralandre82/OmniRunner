/**
 * check-withdrawal-timeline.ts
 *
 * L05-08 — CI guard for the withdrawal-progress timeline primitives.
 *
 * Invariants:
 *   1. Migration creates `custody_withdrawal_events` with the
 *      (withdrawal_id, status) UNIQUE constraint and RLS enabled.
 *   2. Trigger `trg_custody_withdrawals_events` fires on
 *      INSERT OR UPDATE OF status on custody_withdrawals.
 *   3. `fn_withdrawal_timeline(uuid)` exists, SECURITY DEFINER,
 *      STABLE, pins search_path.
 *   4. Timeline response shape covers status, events, ETA,
 *      sla_breached and refund_eta_days.
 *   5. Historical rows are backfilled as part of the migration
 *      (ON CONFLICT DO NOTHING).
 *   6. Migration runs in a single BEGIN/COMMIT with a self-test.
 *   7. Portal exposes GET /api/custody/withdraw/[id]/timeline that
 *      calls `fn_withdrawal_timeline` and gates on admin_master
 *      membership of the host group.
 *
 * Usage: npm run audit:withdrawal-timeline
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (name: string, ok: boolean, detail?: string) =>
  results.push({ name, ok, detail });

function safeRead(path: string, label: string): string | null {
  try { return readFileSync(path, "utf8"); }
  catch { push(label, false, `missing: ${path}`); return null; }
}

const migPath = resolve(
  ROOT,
  "supabase/migrations/20260421490000_l05_08_withdrawal_timeline.sql",
);
const mig = safeRead(migPath, "L05-08 migration present");
if (mig) {
  push(
    "creates custody_withdrawal_events table",
    /CREATE TABLE IF NOT EXISTS public\.custody_withdrawal_events/.test(mig),
  );
  push(
    "has UNIQUE(withdrawal_id, status)",
    /UNIQUE \(withdrawal_id, status\)/.test(mig),
  );
  push(
    "enables RLS",
    /ALTER TABLE public\.custody_withdrawal_events ENABLE ROW LEVEL SECURITY/.test(
      mig,
    ),
  );
  push(
    "policy restricts to admin_master of host group",
    /cm\.role = 'admin_master'/.test(mig),
  );
  push(
    "grants SELECT to authenticated",
    /GRANT SELECT ON TABLE public\.custody_withdrawal_events TO authenticated/.test(
      mig,
    ),
  );
  push(
    "defines record_withdrawal_event trigger function",
    /CREATE OR REPLACE FUNCTION public\.fn_record_withdrawal_event\(\)/.test(mig),
  );
  push(
    "trigger fires on INSERT OR UPDATE OF status",
    /AFTER INSERT OR UPDATE OF status[\s\S]{0,60}custody_withdrawals/.test(mig),
  );
  push(
    "trigger idempotent via ON CONFLICT DO NOTHING",
    /ON CONFLICT \(withdrawal_id, status\) DO NOTHING/.test(mig),
  );
  push(
    "defines fn_withdrawal_timeline(uuid)",
    /CREATE OR REPLACE FUNCTION public\.fn_withdrawal_timeline\(\s*p_withdrawal_id uuid\s*\)/.test(
      mig,
    ),
  );
  push(
    "returns jsonb",
    /fn_withdrawal_timeline[\s\S]{0,120}RETURNS jsonb/.test(mig),
  );
  push(
    "is STABLE + SECURITY DEFINER",
    /fn_withdrawal_timeline[\s\S]{0,400}STABLE[\s\S]{0,80}SECURITY DEFINER/.test(
      mig,
    ),
  );
  push(
    "pins search_path",
    /fn_withdrawal_timeline[\s\S]{0,600}SET search_path = public, pg_temp/.test(
      mig,
    ),
  );
  push(
    "timeline returns status, events, expected_completion_at, sla_breached, refund_eta_days",
    [
      "'status', v_w.status",
      "'events', v_events",
      "'expected_completion_at', v_eta",
      "'sla_breached', v_sla_breached",
      "'refund_eta_days'",
    ].every((s) => mig.includes(s)),
  );
  push(
    "grants EXECUTE to authenticated + service_role",
    /GRANT EXECUTE ON FUNCTION public\.fn_withdrawal_timeline\(uuid\) TO authenticated/.test(
      mig,
    ) &&
      /GRANT EXECUTE ON FUNCTION public\.fn_withdrawal_timeline\(uuid\) TO service_role/.test(
        mig,
      ),
  );
  push(
    "backfills historical rows",
    /INSERT INTO public\.custody_withdrawal_events[\s\S]{0,400}'backfill', true/.test(
      mig,
    ),
  );
  push(
    "self-test: trigger missing",
    /self-test: trigger missing/.test(mig),
  );
  push(
    "self-test: fn_withdrawal_timeline SECURITY DEFINER",
    /self-test: fn_withdrawal_timeline not SECURITY DEFINER/.test(mig),
  );
  push(
    "self-test: unknown id returns NULL",
    /self-test: timeline for unknown id should be NULL/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const routePath = resolve(
  ROOT,
  "portal/src/app/api/custody/withdraw/[id]/timeline/route.ts",
);
const route = safeRead(routePath, "timeline route present");
if (route) {
  push(
    "route calls fn_withdrawal_timeline RPC",
    /rpc\(\s*"fn_withdrawal_timeline"/.test(route),
  );
  push(
    "route gates admin_master",
    /role !== "admin_master"/.test(route),
  );
  push(
    "route validates UUID param",
    /\/\^\[0-9a-f-\]\{36\}\$\/i\.test\(id\)/.test(route),
  );
  push(
    "route returns 404 for foreign-group withdrawal",
    /NOT_FOUND/.test(route) && /w\.group_id !== groupId/.test(route),
  );
  push(
    "route wrapped in withErrorHandler",
    /withErrorHandler\(\s*_get/.test(route),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L05-08-withdraw-nenhuma-tela-de-progresso-para-pending-processing.md",
);
const finding = safeRead(findingPath, "L05-08 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421490000_l05_08_withdrawal_timeline\.sql/.test(finding),
  );
  push(
    "finding references timeline route",
    /portal\/src\/app\/api\/custody\/withdraw\/\[id\]\/timeline\/route\.ts/.test(
      finding,
    ),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}
console.log(
  `\n${results.length - failed}/${results.length} withdrawal-timeline checks passed.`,
);
if (failed > 0) {
  console.error("\nL05-08 invariants broken.");
  process.exit(1);
}
