/**
 * check-group-analytics.ts
 *
 * L23-07 — CI guard for the coach-facing group analytics RPC.
 *
 * Fails closed if:
 *
 *   1. The migration file disappears or is renamed.
 *   2. `fn_group_analytics_overview` no longer carries the
 *      required volatility + security + role-gate + window-clamp
 *      primitives.
 *   3. `fn_group_analytics_assert_shape()` no longer raises the
 *      `L23-07 DRIFT:<reason>` marker that infra CI relies on.
 *   4. `GROUP_ANALYTICS_RUNBOOK.md` is missing or no longer cross-
 *      links this guard.
 *
 * This is a static (grep-style) guard so it runs without a DB
 * running. The DB-level shape guard (`fn_group_analytics_assert_shape`)
 * is the runtime sibling — infra CI invokes it via psql.
 *
 * Usage:
 *   npm run audit:group-analytics
 */

import { readFileSync, readdirSync } from "node:fs";
import { resolve } from "node:path";

const REPO_ROOT = resolve(__dirname, "..", "..");

const MIGRATIONS_DIR = resolve(REPO_ROOT, "supabase/migrations");
const ROUTE_PATH = resolve(
  REPO_ROOT,
  "portal/src/app/api/platform/analytics/group-overview/route.ts",
);
const RUNBOOK_PATH = resolve(
  REPO_ROOT,
  "docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md",
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
      /l23_07_group_analytics_overview\.sql$/.test(f),
    );
    return match ? resolve(MIGRATIONS_DIR, match) : null;
  } catch {
    return null;
  }
}

const migrationPath = findMigration();
if (!migrationPath) {
  push("migration file present", false, "no *l23_07_group_analytics_overview.sql");
} else {
  const src = readFileSync(migrationPath, "utf8");
  push("migration file present", true);

  push(
    "fn_group_analytics_overview declared",
    /CREATE OR REPLACE FUNCTION\s+public\.fn_group_analytics_overview\s*\(/i.test(src),
  );
  push(
    "fn_group_analytics_overview is SECURITY DEFINER",
    /fn_group_analytics_overview[^;]*\bSECURITY\s+DEFINER\b/is.test(src),
  );
  push(
    "fn_group_analytics_overview is STABLE",
    /fn_group_analytics_overview[^;]*\bSTABLE\b/is.test(src),
  );
  push(
    "RPC gates on coaching_members role",
    /coaching_members[\s\S]{0,400}role\s+IN\s*\(\s*'coach'\s*,\s*'assistant'\s*\)/i.test(
      src,
    ),
  );
  push(
    "RPC raises UNAUTHORIZED on non-coach",
    /MESSAGE\s*=\s*'UNAUTHORIZED'/.test(src),
  );
  push(
    "window_days is clamped to [7, 180]",
    /v_window_days\s*<\s*7/.test(src) && /v_window_days\s*>\s*180/.test(src),
  );

  for (const section of [
    "volume_distribution",
    "overtraining",
    "attrition_risk",
    "collective_progress",
  ]) {
    push(
      `response jsonb carries "${section}"`,
      new RegExp(`'${section}'`).test(src),
    );
  }

  push(
    "GRANT EXECUTE TO authenticated present",
    /GRANT\s+EXECUTE\s+ON\s+FUNCTION\s+public\.fn_group_analytics_overview[^;]+TO\s+authenticated/i
      .test(src),
  );
  push(
    "REVOKE ALL FROM PUBLIC present",
    /REVOKE\s+ALL\s+ON\s+FUNCTION\s+public\.fn_group_analytics_overview[^;]+FROM\s+PUBLIC/i
      .test(src),
  );

  push(
    "fn_group_analytics_assert_shape declared",
    /CREATE OR REPLACE FUNCTION\s+public\.fn_group_analytics_assert_shape\s*\(/i.test(
      src,
    ),
  );
  push(
    "shape guard raises L23-07 DRIFT markers",
    /L23-07\s+DRIFT:/i.test(src),
  );
  push(
    "migration has self-test DO block",
    /PERFORM\s+public\.fn_group_analytics_assert_shape\(\)/i.test(src),
  );
}

const route = safeRead(ROUTE_PATH, "portal route present");
if (route) {
  push("portal route present", true);
  push(
    "route calls fn_group_analytics_overview",
    /fn_group_analytics_overview/.test(route),
  );
  push(
    "route gates on supabase.auth.getUser()",
    /supabase\.auth\.getUser\(\)/.test(route),
  );
  push(
    "route accepts group_id query param",
    /group_id/.test(route),
  );
}

const runbook = safeRead(RUNBOOK_PATH, "runbook present");
if (runbook) {
  push("runbook present", true);
  push(
    "runbook cross-links audit:group-analytics",
    runbook.includes("audit:group-analytics")
      || runbook.includes("check-group-analytics"),
  );
  push("runbook cross-links L23-07", runbook.includes("L23-07"));
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
  `\n${results.length - failed}/${results.length} group-analytics checks passed.`,
);

if (failed > 0) {
  console.error(
    "\nL23-07 invariants broken. See docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md.",
  );
  process.exit(1);
}
