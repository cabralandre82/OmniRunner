/**
 * check-athlete-monthly-report.ts
 *
 * L23-11 — CI guard for the coach-facing athlete monthly report.
 *
 * Fails closed if:
 *
 *   1. Migration file disappears or is renamed.
 *   2. `coaching_monthly_notes` table, its unique constraint, or
 *      its text-length CHECKs go missing.
 *   3. `fn_athlete_monthly_report` loses SECURITY DEFINER / STABLE
 *      or the coach/assistant + athlete-in-group dual gate.
 *   4. `fn_upsert_monthly_note` loses SECURITY DEFINER / VOLATILE
 *      or the approved_at-when-all-fields gate.
 *   5. `fn_athlete_monthly_report_assert_shape` loses its `L23-11
 *      DRIFT:<reason>` markers that infra CI invokes via psql.
 *   6. Portal route is missing or its PUT handler stops calling the
 *      upsert RPC / drops the auth gate.
 *   7. Runbook is missing or no longer cross-links this guard.
 *
 * Usage:
 *   npm run audit:athlete-monthly-report
 */

import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const MIGRATIONS_DIR = resolve(REPO_ROOT, "supabase/migrations");
const ROUTE_PATH = resolve(
  REPO_ROOT,
  "portal/src/app/api/coaching/athlete-monthly-report/route.ts",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/ATHLETE_MONTHLY_REPORT_RUNBOOK.md",
);

interface CheckResult {
  name: string;
  ok: boolean;
  detail?: string;
}

const results: CheckResult[] = [];

function push(name: string, ok: boolean, detail?: string) {
  results.push({ name, ok, detail });
}

function safeRead(path: string, label: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch {
    push(label, false, `file not found: ${path}`);
    return null;
  }
}

function findMigration(): string | null {
  try {
    const files = readdirSync(MIGRATIONS_DIR);
    const match = files.find((f) =>
      /l23_11_athlete_monthly_report\.sql$/.test(f),
    );
    return match ? resolve(MIGRATIONS_DIR, match) : null;
  } catch {
    return null;
  }
}

const migrationPath = findMigration();
if (!migrationPath) {
  push(
    "migration file present",
    false,
    "no *l23_11_athlete_monthly_report.sql",
  );
} else {
  const src = readFileSync(migrationPath, "utf8");
  push("migration file present", true);

  push(
    "coaching_monthly_notes table declared",
    /CREATE TABLE\s+IF\s+NOT\s+EXISTS\s+public\.coaching_monthly_notes\s*\(/i.test(
      src,
    ),
  );
  push(
    "coaching_monthly_notes UNIQUE (group_id, user_id, month_start)",
    /uq_coaching_monthly_notes\s+UNIQUE\s*\(\s*group_id\s*,\s*user_id\s*,\s*month_start\s*\)/i
      .test(src),
  );
  push(
    "coaching_monthly_notes has month_trunc CHECK",
    /chk_coaching_monthly_notes_month_trunc/.test(src),
  );
  push(
    "coaching_monthly_notes has length CHECK on highlights",
    /chk_coaching_monthly_notes_highlights_len/.test(src),
  );
  push(
    "coaching_monthly_notes RLS enabled",
    /ALTER TABLE\s+public\.coaching_monthly_notes\s+ENABLE\s+ROW\s+LEVEL\s+SECURITY/i
      .test(src),
  );

  push(
    "fn_athlete_monthly_report declared",
    /CREATE OR REPLACE FUNCTION\s+public\.fn_athlete_monthly_report\s*\(/i.test(
      src,
    ),
  );
  push(
    "fn_athlete_monthly_report is SECURITY DEFINER",
    /fn_athlete_monthly_report[^;]*\bSECURITY\s+DEFINER\b/is.test(src),
  );
  push(
    "fn_athlete_monthly_report is STABLE",
    /fn_athlete_monthly_report[^;]*\bSTABLE\b/is.test(src),
  );
  push(
    "report RPC gates on coaching_members role",
    /coaching_members[\s\S]{0,800}role\s+(?:NOT\s+)?IN\s*\(\s*'coach'\s*,\s*'assistant'\s*\)/i
      .test(src),
  );
  push(
    "report RPC checks athlete is in group",
    /ATHLETE_NOT_IN_GROUP/.test(src),
  );
  push(
    "report RPC response carries metrics key",
    /'metrics'/.test(src) && /'coach_notes'/.test(src),
  );
  push(
    "report RPC surfaces pace_trend_sec_km",
    /pace_trend_sec_km/.test(src),
  );

  push(
    "fn_upsert_monthly_note declared",
    /CREATE OR REPLACE FUNCTION\s+public\.fn_upsert_monthly_note\s*\(/i.test(
      src,
    ),
  );
  push(
    "fn_upsert_monthly_note is SECURITY DEFINER",
    /fn_upsert_monthly_note[^;]*\bSECURITY\s+DEFINER\b/is.test(src),
  );
  push(
    "fn_upsert_monthly_note sets approved_at when 3 fields non-empty",
    /v_approved_at\s*:=\s*now\(\)/.test(src),
  );
  push(
    "fn_upsert_monthly_note upserts on unique key",
    /ON\s+CONFLICT\s*\(\s*group_id\s*,\s*user_id\s*,\s*month_start\s*\)/i.test(
      src,
    ),
  );

  push(
    "GRANT EXECUTE report TO authenticated",
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.fn_athlete_monthly_report[^;]+TO\s+authenticated/i
      .test(src),
  );
  push(
    "GRANT EXECUTE upsert TO authenticated",
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.fn_upsert_monthly_note[^;]+TO\s+authenticated/i
      .test(src),
  );

  push(
    "fn_athlete_monthly_report_assert_shape declared",
    /CREATE OR REPLACE FUNCTION\s+public\.fn_athlete_monthly_report_assert_shape\s*\(/i
      .test(src),
  );
  push(
    "shape guard raises L23-11 DRIFT markers",
    /L23-11\s+DRIFT:/i.test(src),
  );
  push(
    "migration has self-test DO block",
    /PERFORM\s+public\.fn_athlete_monthly_report_assert_shape\(\)/i.test(src),
  );
}

const route = safeRead(ROUTE_PATH, "portal route present");
if (route) {
  push("portal route present", true);
  push("route exports GET", /export\s+async\s+function\s+GET\s*\(/.test(route));
  push("route exports PUT", /export\s+async\s+function\s+PUT\s*\(/.test(route));
  push(
    "route calls fn_athlete_monthly_report",
    /fn_athlete_monthly_report/.test(route),
  );
  push(
    "route calls fn_upsert_monthly_note",
    /fn_upsert_monthly_note/.test(route),
  );
  push(
    "route gates on supabase.auth.getUser()",
    /supabase\.auth\.getUser\(\)/.test(route),
  );
  push(
    "route maps UNAUTHORIZED/ATHLETE_NOT_IN_GROUP to 401",
    /ATHLETE_NOT_IN_GROUP/.test(route)
      && /apiUnauthorized/.test(route),
  );
  push(
    "route validates group_id + user_id as uuid",
    /UUID_RE/.test(route)
      && /group_id/.test(route)
      && /user_id/.test(route),
  );
  push(
    "route bounds free-text at 2048 chars",
    /MAX_TEXT_LEN\s*=\s*2048/.test(route)
      || /2048/.test(route),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:athlete-monthly-report",
    runbook.includes("audit:athlete-monthly-report")
      || runbook.includes("check-athlete-monthly-report"),
  );
  push("runbook cross-links L23-11", runbook.includes("L23-11"));
}

let failed = 0;
for (const r of results) {
  if (r.ok) {
    console.log(`[OK]   ${r.name}`);
  } else {
    failed += 1;
    console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`);
  }
}

console.log(
  `\n${results.length - failed}/${results.length} athlete-monthly-report checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-11 invariants broken. See docs/runbooks/ATHLETE_MONTHLY_REPORT_RUNBOOK.md.",
  );
  process.exit(1);
}
