/**
 * check-groups-nearby.ts
 *
 * L22-05 — CI guard for coaching_groups discovery shape.
 *
 * Invokes public.fn_coaching_groups_assert_discovery_shape() which
 * fails closed (P0010) when any of the pieces shipped by migration
 * 20260421370000 drifts:
 *
 *   - columns (base_lat, base_lng, allow_discovery, location_precision_m)
 *   - CHECK constraints (lat range, lng range, precision enum, flag-coord link)
 *   - partial btree index (idx_coaching_groups_discovery_lat)
 *   - helpers (fn_groups_snap_coord, fn_groups_nearby,
 *              fn_group_set_base_location)
 *   - privilege surface (anon denied, authenticated allowed on the
 *     two public RPCs).
 *
 * Usage:
 *   npm run audit:groups-nearby
 */

import { execSync } from "node:child_process";

const CONTAINER = process.env.SUPABASE_DB_CONTAINER ?? "supabase_db_project-running";
const DB_USER = process.env.SUPABASE_DB_USER ?? "postgres";
const DB_NAME = process.env.SUPABASE_DB_NAME ?? "postgres";

function psql(sql: string, opts: { allowError?: boolean } = {}): { out: string; ok: boolean } {
  try {
    const out = execSync(
      `docker exec -i ${CONTAINER} psql -U ${DB_USER} -d ${DB_NAME} -v ON_ERROR_STOP=1 -At`,
      { input: sql, encoding: "utf8", stdio: ["pipe", "pipe", "pipe"] },
    ).trim();
    return { out, ok: true };
  } catch (e) {
    if (opts.allowError) {
      const err = e as { stderr?: string | Buffer; message?: string };
      return {
        out:
          (typeof err.stderr === "string" ? err.stderr : err.stderr?.toString?.() ?? "") +
          (err.message ?? ""),
        ok: false,
      };
    }
    throw e;
  }
}

function main(): number {
  console.log("L22-05: checking coaching_groups discovery shape…");

  const probe = psql(
    "SELECT to_regprocedure('public.fn_coaching_groups_assert_discovery_shape()') IS NOT NULL;",
    { allowError: true },
  );
  if (!probe.ok || !/^t$/i.test(probe.out.trim())) {
    console.error(
      "\nERROR: public.fn_coaching_groups_assert_discovery_shape() not registered.\n" +
        "Apply migration 20260421370000_l22_05_coaching_groups_nearby.sql first.\n",
    );
    return 1;
  }

  const r = psql("SELECT public.fn_coaching_groups_assert_discovery_shape();", {
    allowError: true,
  });
  if (!r.ok) {
    console.error("\n  FAIL");
    const snippet = r.out
      .split("\n")
      .filter((line) =>
        /L22-05|coaching_groups|discovery|P0010|HINT|fn_groups_|allow_discovery|chk_coaching_groups_/i.test(
          line,
        ),
      )
      .slice(0, 50)
      .join("\n");
    console.error(snippet || r.out.slice(0, 2000));
    console.error(
      "\nSee docs/runbooks/GROUPS_NEARBY_RUNBOOK.md for the remediation playbook.",
    );
    return 1;
  }

  console.log("  coaching_groups: OK (discovery columns + CHECK + index + helpers aligned)");
  console.log("\nOK — L22-05 discovery shape invariants hold.");
  return 0;
}

process.exit(main());
