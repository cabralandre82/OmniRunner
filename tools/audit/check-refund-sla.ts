/**
 * check-refund-sla.ts — L09-07 CI guard.
 *
 * Static checks over the migration + policy.
 */

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const ROOT = resolve(__dirname, "..", "..");
const MIG = resolve(
  ROOT,
  "supabase/migrations/20260421430000_l09_07_refund_sla.sql",
);
const POLICY = resolve(ROOT, "docs/compliance/REFUND_POLICY.md");
const FINDING = resolve(
  ROOT,
  "docs/audit/findings/L09-07-politica-de-reembolso-chargeback-sem-prazo-sla.md",
);

interface CheckResult { name: string; ok: boolean; detail?: string; }
const results: CheckResult[] = [];
const push = (n: string, ok: boolean, d?: string) =>
  results.push({ name: n, ok, detail: d });
const safe = (p: string, l: string) => {
  try { return readFileSync(p, "utf8"); }
  catch { push(l, false, `missing: ${p}`); return null; }
};

const mig = safe(MIG, "migration present");
if (mig) {
  push("migration present", true);
  push(
    "adds sla_target_at column",
    /ADD COLUMN IF NOT EXISTS sla_target_at\s+timestamptz/.test(mig),
  );
  push(
    "adds sla_breached_at column",
    /ADD COLUMN IF NOT EXISTS sla_breached_at\s+timestamptz/.test(mig),
  );
  push(
    "adds sla_breach_reason column",
    /ADD COLUMN IF NOT EXISTS sla_breach_reason\s+text/.test(mig),
  );
  push(
    "trigger fn_billing_refund_requests_set_sla_target defined",
    /FUNCTION public\.fn_billing_refund_requests_set_sla_target/.test(mig),
  );
  push(
    "trigger SECURITY DEFINER + pinned search_path",
    /fn_billing_refund_requests_set_sla_target[\s\S]+?SECURITY DEFINER[\s\S]+?SET search_path = public, pg_catalog, pg_temp/.test(
      mig,
    ),
  );
  push(
    "weekend branch (Fri/Sat/Sun → 72h)",
    /IN \(5, 6, 0\)/.test(mig) && /72 hours/.test(mig),
  );
  push(
    "weekday branch (→ 48h)",
    /48 hours/.test(mig) && /Mon–Thu|Mon-Thu|Mon--Thu/.test(mig),
  );
  push(
    "backfill UPDATE for historical rows",
    /UPDATE public\.billing_refund_requests[\s\S]+?WHERE r\.sla_target_at IS NULL/.test(
      mig,
    ),
  );
  push(
    "trigger BEFORE INSERT on billing_refund_requests",
    /CREATE TRIGGER trg_billing_refund_requests_sla[\s\S]+?BEFORE INSERT ON public\.billing_refund_requests/.test(
      mig,
    ),
  );
  push(
    "view v_billing_refund_requests_breached declared",
    /CREATE VIEW public\.v_billing_refund_requests_breached/.test(mig),
  );
  push(
    "view uses security_invoker",
    /security_invoker = true/.test(mig),
  );
  push(
    "view filters status IN (requested, approved)",
    /r\.status IN \('requested', 'approved'\)/.test(mig),
  );
  push(
    "helper fn_billing_refund_sla_mark_breached declared",
    /FUNCTION public\.fn_billing_refund_sla_mark_breached/.test(mig),
  );
  push(
    "helper idempotent (sla_breached_at IS NULL guard)",
    /sla_breached_at IS NULL/.test(mig),
  );
  push(
    "helper grants EXECUTE to service_role only",
    /REVOKE ALL ON FUNCTION public\.fn_billing_refund_sla_mark_breached[\s\S]+?FROM PUBLIC, anon, authenticated/.test(
      mig,
    ) &&
      /GRANT EXECUTE ON FUNCTION public\.fn_billing_refund_sla_mark_breached[\s\S]+?TO service_role/.test(
        mig,
      ),
  );
  push("self-test present", /\$L09_07_selftest\$/.test(mig));
  push(
    "self-test asserts trigger populated sla_target_at",
    /trigger did not set sla_target_at/.test(mig),
  );
  push(
    "self-test asserts view surfaces the breach",
    /breached view did not surface/.test(mig),
  );
  push(
    "self-test asserts mark_breached returns >0",
    /mark_breached returned 0/.test(mig),
  );
}

const policy = safe(POLICY, "REFUND_POLICY.md present");
if (policy) {
  push("REFUND_POLICY.md present", true);
  push("cites CDC Art. 49 (7 days)", /CDC Art\. 49[\s\S]+?7 days/i.test(policy));
  push("declares 48 business hours SLA", /48 business h|48 business hours/i.test(policy));
  push(
    "documents weekend heuristic (72h)",
    /72h/.test(policy) || /\+72h/.test(policy),
  );
  push(
    "chargeback handling section present",
    /## 3\. Chargeback handling/.test(policy),
  );
  push(
    "holiday calendar section present",
    /## 4\. Holiday calendar/.test(policy),
  );
  push(
    "decision log present",
    /## 6\. Decision log/.test(policy) && /- \*\*20\d\d-\d\d-\d\d\*\*/.test(policy),
  );
  push(
    "policy cross-links migration",
    /20260421430000_l09_07_refund_sla\.sql/.test(policy),
  );
  push(
    "policy cross-links process-refund Edge Function",
    /supabase\/functions\/process-refund/.test(policy),
  );
  push(
    "policy cross-links billing_refund_requests migration",
    /20260221000015_billing_refund_requests\.sql/.test(policy),
  );
  push("policy cross-links L09-08", /L09-08/.test(policy));
  push(
    "CI guard script referenced",
    /npm run audit:refund-sla/.test(policy),
  );
}

const finding = safe(FINDING, "L09-07 finding present");
if (finding) {
  push(
    "finding references policy",
    /docs\/compliance\/REFUND_POLICY\.md/.test(finding),
  );
  push(
    "finding references migration",
    /20260421430000_l09_07_refund_sla\.sql/.test(finding),
  );
}

let failed = 0;
for (const r of results) {
  if (r.ok) console.log(`[OK]   ${r.name}`);
  else { failed += 1; console.error(`[FAIL] ${r.name}${r.detail ? ` — ${r.detail}` : ""}`); }
}
console.log(`\n${results.length - failed}/${results.length} refund-sla checks passed.`);
if (failed > 0) {
  console.error("\nL09-07 invariants broken. See docs/compliance/REFUND_POLICY.md.");
  process.exit(1);
}
