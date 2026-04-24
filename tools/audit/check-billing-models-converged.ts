/**
 * check-billing-models-converged.ts
 *
 * L09-18 / ADR-0010 F-CON-1 — CI guard for the legacy↔new subscription
 * model bridge.
 *
 * Verifies (statically, against the source tree — no DB connection
 * required, follows the pattern of check-athlete-subscriptions.ts and
 * check-cron-idempotency.ts):
 *
 *   1. Migration 20260424180000_l09_18_subscription_bridge.sql exists and
 *      ships the 3 canonical functions:
 *        - fn_subscription_bridge_mark_paid_from_legacy(uuid, date, text)
 *          → fail-soft EXCEPTION WHEN OTHERS handler
 *          → service_role only at runtime
 *          → SECURITY DEFINER + SET search_path = public
 *          → granted to service_role, revoked from PUBLIC/anon/authenticated
 *        - fn_find_subscription_models_divergence(int)
 *          → STABLE + SECURITY DEFINER
 *          → 3 kinds: invoice_missing / invoice_overdue / invoice_pending
 *        - fn_assert_subscription_models_converged(int)
 *          → raise P0010 with samples + ADR-0010 reference
 *          → service_role only
 *
 *   2. supabase/functions/asaas-webhook/index.ts wires the bridge:
 *        - Calls fn_subscription_bridge_mark_paid_from_legacy on
 *          PAYMENT_CONFIRMED / PAYMENT_RECEIVED.
 *        - Fail-open: errors push into errors[] but do NOT break the 200.
 *        - derivePeriodMonth helper present and exported.
 *
 *   3. Finding L09-18 references the migration and the ADR.
 *
 * The runtime convergence check (querying the actual DB for divergent
 * subscriptions) is performed by the cron-health-monitor scaffolding
 * (L06-04) calling fn_assert_subscription_models_converged daily.
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

// ── 1. Migration ─────────────────────────────────────────────────────────────
const migPath = resolve(
  ROOT,
  "supabase/migrations/20260424180000_l09_18_subscription_bridge.sql",
);
const mig = safeRead(migPath, "L09-18 migration present");

if (mig) {
  // Bridge function.
  push(
    "creates fn_subscription_bridge_mark_paid_from_legacy",
    /CREATE OR REPLACE FUNCTION public\.fn_subscription_bridge_mark_paid_from_legacy\(/.test(mig),
  );
  push(
    "bridge signature (uuid, date, text)",
    /fn_subscription_bridge_mark_paid_from_legacy\([\s\S]{0,300}p_legacy_subscription_id\s+UUID[\s\S]{0,200}p_period_month\s+DATE[\s\S]{0,200}p_external_charge_id\s+TEXT/.test(mig),
  );
  push(
    "bridge is service-role only at runtime",
    /fn_subscription_bridge_mark_paid_from_legacy is service-role only/.test(mig),
  );
  push(
    "bridge is SECURITY DEFINER + search_path locked",
    /fn_subscription_bridge_mark_paid_from_legacy[\s\S]{0,400}SECURITY DEFINER[\s\S]{0,200}SET search_path = public/.test(mig),
  );
  push(
    "bridge fail-soft WHEN OTHERS returns ok=false reason",
    /WHEN OTHERS THEN[\s\S]{0,600}'ok',\s*false[\s\S]{0,400}'reason',\s*'exception:'/.test(mig),
  );
  push(
    "bridge re-raises insufficient_privilege (fail-loud on wiring bug)",
    /WHEN insufficient_privilege THEN[\s\S]{0,400}RAISE;/.test(mig),
  );
  push(
    "bridge calls fn_subscription_mark_invoice_paid",
    /v_was_paid_now\s*:=\s*public\.fn_subscription_mark_invoice_paid\(/.test(mig),
  );
  push(
    "bridge revokes from PUBLIC/anon/authenticated",
    /REVOKE ALL ON FUNCTION public\.fn_subscription_bridge_mark_paid_from_legacy[\s\S]{0,200}FROM PUBLIC, anon, authenticated/.test(mig),
  );
  push(
    "bridge granted to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_subscription_bridge_mark_paid_from_legacy[\s\S]{0,200}TO service_role/.test(mig),
  );
  push(
    "bridge handles legacy_sub_not_found path",
    /'reason',\s*'legacy_sub_not_found'/.test(mig),
  );
  push(
    "bridge handles no_athlete_sub path",
    /'reason',\s*'no_athlete_sub'/.test(mig),
  );
  push(
    "bridge handles invoice_not_found path",
    /'reason',\s*'invoice_not_found'/.test(mig),
  );
  push(
    "bridge handles already_paid idempotency",
    /'reason',\s*'already_paid'/.test(mig),
  );
  push(
    "bridge handles cancelled_invoice path (does not reopen)",
    /'reason',\s*'cancelled_invoice'/.test(mig),
  );

  // Detector.
  push(
    "creates fn_find_subscription_models_divergence",
    /CREATE OR REPLACE FUNCTION public\.fn_find_subscription_models_divergence\(/.test(mig),
  );
  push(
    "detector is STABLE",
    /fn_find_subscription_models_divergence[\s\S]{0,500}STABLE/.test(mig),
  );
  push(
    "detector reports 3 divergence kinds",
    /'invoice_missing'/.test(mig)
      && /'invoice_overdue'/.test(mig)
      && /'invoice_pending'/.test(mig),
  );
  push(
    "detector joins ONLY where athlete_subscriptions exists",
    /JOIN public\.athlete_subscriptions\s+asub/.test(mig),
  );
  push(
    "detector restricted to current period_month",
    /v_period DATE := date_trunc\('month', CURRENT_DATE\)::date/.test(mig),
  );
  push(
    "detector granted to service_role + authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_find_subscription_models_divergence\(INT\)\s+TO service_role,\s*authenticated/.test(mig),
  );

  // Assert wrapper.
  push(
    "creates fn_assert_subscription_models_converged",
    /CREATE OR REPLACE FUNCTION public\.fn_assert_subscription_models_converged\(/.test(mig),
  );
  push(
    "assert is service-role only at runtime",
    /fn_assert_subscription_models_converged is service-role only/.test(mig),
  );
  push(
    "assert raises P0010 on divergence",
    /RAISE EXCEPTION[\s\S]{0,400}USING ERRCODE = 'P0010'/.test(mig),
  );
  push(
    "assert message references ADR-0010 F-CON-1",
    /\[ADR-0010 F-CON-1\]/.test(mig),
  );
  push(
    "assert no-op when divergence count = 0",
    /IF v_count = 0 THEN[\s\S]{0,100}RETURN;/.test(mig),
  );
  push(
    "assert revoked from PUBLIC/anon/authenticated",
    /REVOKE ALL ON FUNCTION public\.fn_assert_subscription_models_converged[\s\S]{0,200}FROM PUBLIC, anon, authenticated/.test(mig),
  );

  // Self-test.
  push(
    "self-test verifies bridge function registered",
    /L09-18 self-test FAILED: bridge function missing/.test(mig),
  );
  push(
    "self-test verifies detector function registered",
    /L09-18 self-test FAILED: detector function missing/.test(mig),
  );
  push(
    "self-test verifies assert function registered",
    /L09-18 self-test FAILED: assert function missing/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

// ── 2. Webhook integration ───────────────────────────────────────────────────
const webhookPath = resolve(ROOT, "supabase/functions/asaas-webhook/index.ts");
const webhook = safeRead(webhookPath, "asaas-webhook present");

if (webhook) {
  push(
    "webhook calls bridge RPC",
    /fn_subscription_bridge_mark_paid_from_legacy/.test(webhook),
  );
  push(
    "webhook bridge call gated on PAYMENT_CONFIRMED|PAYMENT_RECEIVED",
    /event === "PAYMENT_CONFIRMED" \|\| event === "PAYMENT_RECEIVED"[\s\S]{0,400}fn_subscription_bridge_mark_paid_from_legacy/.test(webhook),
  );
  push(
    "webhook bridge is fail-open (errors do not throw)",
    /try \{[\s\S]{0,2000}fn_subscription_bridge_mark_paid_from_legacy[\s\S]{0,2000}\} catch \(e\) \{[\s\S]{0,400}errors\.push\(`bridge_invoice/.test(webhook),
  );
  push(
    "webhook references ADR-0010 in bridge comment",
    /ADR-0010/.test(webhook),
  );
  push(
    "webhook references L09-18 finding",
    /L09-18/.test(webhook),
  );
  push(
    "webhook exports derivePeriodMonth helper",
    /export function derivePeriodMonth\(/.test(webhook),
  );
  push(
    "derivePeriodMonth returns first day of month",
    /return dueDate\.slice\(0, 8\) \+ "01"/.test(webhook),
  );
}

// ── 3. Finding doc ───────────────────────────────────────────────────────────
const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L09-18-divergencia-asaas-webhook-nao-escreve-em-athlete-subscription-invoices.md",
);
const finding = safeRead(findingPath, "L09-18 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260424180000_l09_18_subscription_bridge\.sql/.test(finding),
  );
  push(
    "finding references ADR-0010",
    /ADR-0010/.test(finding),
  );
  push(
    "finding references fn_subscription_mark_invoice_paid",
    /fn_subscription_mark_invoice_paid/.test(finding),
  );
}

// ── 4. ADR exists ────────────────────────────────────────────────────────────
const adrPath = resolve(ROOT, "docs/adr/ADR-0010-billing-subscriptions-consolidation.md");
const adr = safeRead(adrPath, "ADR-0010 present");
if (adr) {
  push(
    "ADR-0010 status Accepted",
    /\*\*Status:\*\*\s*Accepted/.test(adr),
  );
  push(
    "ADR-0010 references L09-18",
    /L09-18/.test(adr),
  );
  push(
    "ADR-0010 lists F-CON-1 / F-CON-2 / F-CON-3 phases",
    /F-CON-1/.test(adr) && /F-CON-2/.test(adr) && /F-CON-3/.test(adr),
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
  `\n${results.length - failed}/${results.length} billing-models-converged checks passed.`,
);
if (failed > 0) {
  console.error(
    "\nL09-18 / ADR-0010 F-CON-1 invariants broken — see docs/adr/ADR-0010-billing-subscriptions-consolidation.md",
  );
  process.exit(1);
}
