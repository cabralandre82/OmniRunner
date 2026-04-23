/**
 * check-admin-approvals-sod.ts
 *
 * L10-06 — CI guard for the Segregation-of-Duty (two-person
 * rule) scaffolding on platform_admin.
 *
 * Invariants:
 *   1. `admin_approvals` table exists with action_type CHECK,
 *      status CHECK, self-approval CHECK, and a status-transition
 *      CHECK that prevents "executed without approval".
 *   2. RLS enabled; only platform_admin can SELECT.
 *   3. BEFORE UPDATE trigger re-asserts no-self-approval,
 *      no-self-rejection, execute-requires-approval, and
 *      terminal-status-lock invariants.
 *   4. `fn_admin_approval_required(action, payload)` returns true
 *      for platform_fee_config / admin-grant / billing_provider
 *      regardless of amount, and for withdrawal/refund only above
 *      US$ 10k.
 *   5. `fn_admin_approvals_expire_overdue()` is service_role-only
 *      SECURITY DEFINER with pinned search_path.
 *   6. Self-test covers policy cases + INSERT-time self-approval
 *      block.
 *
 * Usage: npm run audit:admin-approvals-sod
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
  "supabase/migrations/20260421510000_l10_06_admin_approvals_sod.sql",
);
const mig = safeRead(migPath, "L10-06 migration present");
if (mig) {
  push(
    "creates admin_approvals table",
    /CREATE TABLE IF NOT EXISTS public\.admin_approvals/.test(mig),
  );
  push(
    "action_type CHECK lists the known classes",
    [
      "'platform_fee_config.update'",
      "'custody_withdrawal.execute'",
      "'refund.issue'",
      "'billing_provider.key_set'",
      "'platform_admin.grant'",
    ].every((s) => mig.includes(s)),
  );
  push(
    "status CHECK lists pending/approved/rejected/executed/expired",
    /status IN \('pending','approved','rejected','executed','expired'\)/.test(
      mig,
    ),
  );
  push(
    "chk_no_self_approval CHECK present",
    /CONSTRAINT chk_no_self_approval/.test(mig),
  );
  push(
    "chk_no_self_rejection CHECK present",
    /CONSTRAINT chk_no_self_rejection/.test(mig),
  );
  push(
    "chk_status_transition CHECK present",
    /CONSTRAINT chk_status_transition/.test(mig),
  );
  push(
    "expires_at default 24h",
    /DEFAULT \(now\(\) \+ interval '24 hours'\)/.test(mig),
  );
  push(
    "RLS enabled",
    /ALTER TABLE public\.admin_approvals ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "RLS gates platform_role = 'admin'",
    /platform_role = 'admin'/.test(mig),
  );
  push(
    "defines BEFORE UPDATE trigger fn_admin_approvals_guard",
    /CREATE OR REPLACE FUNCTION public\.fn_admin_approvals_guard/.test(mig) &&
      /BEFORE UPDATE ON public\.admin_approvals/.test(mig),
  );
  push(
    "trigger raises SELF_APPROVAL_FORBIDDEN",
    /SELF_APPROVAL_FORBIDDEN/.test(mig),
  );
  push(
    "trigger raises EXECUTE_REQUIRES_APPROVAL",
    /EXECUTE_REQUIRES_APPROVAL/.test(mig),
  );
  push(
    "trigger raises TERMINAL_STATUS_LOCKED",
    /TERMINAL_STATUS_LOCKED/.test(mig),
  );
  push(
    "defines fn_admin_approval_required policy helper",
    /CREATE OR REPLACE FUNCTION public\.fn_admin_approval_required\(/.test(mig),
  );
  push(
    "policy: fee-config and admin-grant always required",
    /p_action_type = 'platform_fee_config\.update'[\s\S]{0,60}p_action_type = 'platform_admin\.grant'/.test(
      mig,
    ),
  );
  push(
    "policy: threshold US$ 10k on money movers",
    /v_amount >= 10000/.test(mig),
  );
  push(
    "policy: billing_provider.key_set always required",
    /p_action_type = 'billing_provider\.key_set'[\s\S]{0,80}RETURN true/.test(
      mig,
    ),
  );
  push(
    "defines expire-overdue helper",
    /CREATE OR REPLACE FUNCTION public\.fn_admin_approvals_expire_overdue\(\)/.test(
      mig,
    ),
  );
  push(
    "expire-overdue is SECURITY DEFINER + pinned search_path",
    /fn_admin_approvals_expire_overdue[\s\S]{0,400}SECURITY DEFINER[\s\S]{0,200}SET search_path = public, pg_temp/.test(
      mig,
    ),
  );
  push(
    "expire-overdue: EXECUTE service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_admin_approvals_expire_overdue\(\) TO service_role/.test(
      mig,
    ) &&
      /REVOKE ALL ON FUNCTION public\.fn_admin_approvals_expire_overdue\(\) FROM authenticated/.test(
        mig,
      ),
  );
  push(
    "self-test: fee-config must require approval",
    /fee-config mutation must require approval/.test(mig),
  );
  push(
    "self-test: small withdrawal should NOT require",
    /small withdrawal should not require approval/.test(mig),
  );
  push(
    "self-test: 10k+ withdrawal requires",
    /10k\+ withdrawal should require approval/.test(mig),
  );
  push(
    "self-test: billing_provider.key_set always requires",
    /billing_provider\.key_set should always require approval/.test(mig),
  );
  push(
    "self-test: INSERT-time self-approval blocked",
    /self-approval at INSERT must be blocked/.test(mig),
  );
  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L10-06-segregacao-de-funcao-sod-ausente-em-platform-admin.md",
);
const finding = safeRead(findingPath, "L10-06 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421510000_l10_06_admin_approvals_sod\.sql/.test(finding),
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
  `\n${results.length - failed}/${results.length} admin-approvals-sod checks passed.`,
);
if (failed > 0) {
  console.error("\nL10-06 invariants broken.");
  process.exit(1);
}
