/**
 * check-champ-cancel-atomic.ts
 *
 * L05-06 — CI guard for atomic championship cancellation.
 *
 * Invariants:
 *   1. Migration defines `fn_champ_cancel_atomic(uuid, uuid)` as
 *      SECURITY DEFINER with pinned search_path and lock_timeout.
 *   2. Function returns jsonb, REVOKEs from PUBLIC/anon/authenticated
 *      and GRANTs EXECUTE to service_role only.
 *   3. Migration wraps work in a single BEGIN/COMMIT and self-tests.
 *   4. Edge function `champ-cancel` calls the RPC and no longer
 *      contains the silent `console.warn(...Badge refund failed...)`
 *      catch block.
 *   5. Edge function no longer issues raw writes to
 *      `championships` / `championship_participants` /
 *      `championship_invites` / `fn_credit_badge_inventory`
 *      (all of that now lives inside the RPC).
 *   6. Edge function surfaces FORBIDDEN / NOT_FOUND / INVALID_STATUS
 *      error branches from the RPC.
 *   7. Finding cross-links to the migration and the edge function.
 *
 * Usage: npm run audit:champ-cancel-atomic
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
  "supabase/migrations/20260421480000_l05_06_champ_cancel_atomic.sql",
);
const mig = safeRead(migPath, "L05-06 migration present");
if (mig) {
  push(
    "defines fn_champ_cancel_atomic(uuid, uuid)",
    /CREATE OR REPLACE FUNCTION public\.fn_champ_cancel_atomic\(\s*p_championship_id uuid,\s*p_caller_user_id\s+uuid\s*\)/.test(
      mig,
    ),
  );
  push(
    "returns jsonb",
    /fn_champ_cancel_atomic[\s\S]{0,200}RETURNS jsonb/.test(mig),
  );
  push(
    "is SECURITY DEFINER",
    /fn_champ_cancel_atomic[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "pins search_path",
    /fn_champ_cancel_atomic[\s\S]{0,600}SET search_path = public, pg_temp/.test(
      mig,
    ),
  );
  push(
    "declares lock_timeout",
    /fn_champ_cancel_atomic[\s\S]{0,600}SET lock_timeout/.test(mig),
  );
  push(
    "locks championship row FOR UPDATE",
    /FROM public\.championships[\s\S]{0,120}FOR UPDATE/.test(mig),
  );
  push(
    "re-checks coaching_members role invariant",
    /FROM public\.coaching_members[\s\S]{0,200}role NOT IN \('admin_master','coach'\)/.test(
      mig,
    ),
  );
  push(
    "withdraws enrolled/active participants",
    /UPDATE public\.championship_participants[\s\S]{0,200}status IN \('enrolled','active'\)/.test(
      mig,
    ),
  );
  push(
    "revokes pending invites",
    /UPDATE public\.championship_invites[\s\S]{0,200}status = 'pending'/.test(
      mig,
    ),
  );
  push(
    "calls fn_credit_badge_inventory guarded by badge count > 0",
    /IF v_badges_refunded > 0 THEN[\s\S]{0,300}fn_credit_badge_inventory\(/.test(
      mig,
    ),
  );
  push(
    "flips championships.status to cancelled",
    /UPDATE public\.championships[\s\S]{0,120}status = 'cancelled'/.test(mig),
  );
  push(
    "idempotent noop branch on already-cancelled",
    /v_champ\.status = 'cancelled'[\s\S]{0,400}'noop', true/.test(mig),
  );
  push(
    "raises FORBIDDEN on wrong role",
    /RAISE EXCEPTION[\s\S]{0,60}'FORBIDDEN:/.test(mig),
  );
  push(
    "raises NOT_FOUND on unknown championship",
    /RAISE EXCEPTION[\s\S]{0,60}'NOT_FOUND:/.test(mig),
  );
  push(
    "raises INVALID_STATUS outside draft/open/active",
    /RAISE EXCEPTION[\s\S]{0,60}'INVALID_STATUS:/.test(mig),
  );
  push(
    "raises INVALID_ARGS on NULL inputs",
    /RAISE EXCEPTION[\s\S]{0,60}'INVALID_ARGS:/.test(mig),
  );
  push(
    "grants EXECUTE to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_champ_cancel_atomic\(uuid, uuid\) TO service_role/.test(
      mig,
    ) &&
      /REVOKE ALL ON FUNCTION public\.fn_champ_cancel_atomic\(uuid, uuid\) FROM anon/.test(
        mig,
      ) &&
      /REVOKE ALL ON FUNCTION public\.fn_champ_cancel_atomic\(uuid, uuid\) FROM authenticated/.test(
        mig,
      ) &&
      /REVOKE ALL ON FUNCTION public\.fn_champ_cancel_atomic\(uuid, uuid\) FROM PUBLIC/.test(
        mig,
      ),
  );
  push(
    "self-test: SECURITY DEFINER",
    /self-test: helper not SECURITY DEFINER/.test(mig),
  );
  push(
    "self-test: NULL championship_id raises",
    /self-test: NULL championship_id did not raise/.test(mig),
  );
  push(
    "self-test: unknown championship raises",
    /self-test: unknown championship did not raise/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
  push(
    "COMMENT ON FUNCTION present",
    /COMMENT ON FUNCTION public\.fn_champ_cancel_atomic\(uuid, uuid\)/.test(mig),
  );
}

const fnPath = resolve(
  ROOT,
  "supabase/functions/champ-cancel/index.ts",
);
const fn = safeRead(fnPath, "champ-cancel edge function present");
if (fn) {
  push(
    "edge function calls fn_champ_cancel_atomic RPC",
    /db\.rpc\(\s*"fn_champ_cancel_atomic"/.test(fn),
  );
  push(
    "RPC call passes p_caller_user_id",
    /p_caller_user_id:\s*user\.id/.test(fn),
  );
  push(
    "no silent badge-refund catch left",
    !/Badge refund failed/.test(fn),
  );
  push(
    "no direct fn_credit_badge_inventory call from edge function",
    !/fn_credit_badge_inventory/.test(fn),
  );
  push(
    "no direct championships UPDATE from edge function",
    !/\.from\(\s*"championships"\s*\)[\s\S]{0,80}\.update/.test(fn),
  );
  push(
    "no direct championship_participants UPDATE from edge function",
    !/\.from\(\s*"championship_participants"\s*\)[\s\S]{0,80}\.update/.test(fn),
  );
  push(
    "no direct championship_invites UPDATE from edge function",
    !/\.from\(\s*"championship_invites"\s*\)[\s\S]{0,80}\.update/.test(fn),
  );
  push(
    "maps FORBIDDEN to HTTP 403",
    /includes\("FORBIDDEN"\)[\s\S]{0,200}status = 403/.test(fn),
  );
  push(
    "maps NOT_FOUND to HTTP 404",
    /includes\("NOT_FOUND"\)[\s\S]{0,200}status = 404/.test(fn),
  );
  push(
    "maps INVALID_STATUS to HTTP 409",
    /includes\("INVALID_STATUS"\)[\s\S]{0,200}status = 409/.test(fn),
  );
  push(
    "response surfaces badges_refunded",
    /badges_refunded:\s*rpcData\?\.badges_refunded/.test(fn),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L05-06-championship-champ-cancel-refund-de-badges-parcial-e.md",
);
const finding = safeRead(findingPath, "L05-06 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421480000_l05_06_champ_cancel_atomic\.sql/.test(finding),
  );
  push(
    "finding references champ-cancel",
    /supabase\/functions\/champ-cancel\/index\.ts/.test(finding),
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
  `\n${results.length - failed}/${results.length} champ-cancel-atomic checks passed.`,
);
if (failed > 0) {
  console.error("\nL05-06 invariants broken.");
  process.exit(1);
}
