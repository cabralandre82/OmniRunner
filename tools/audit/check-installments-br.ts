/**
 * check-installments-br.ts
 *
 * L22-07 — CI guard for BR installment plans + gateway preference.
 *
 * Usage: npm run audit:installments-br
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
  "supabase/migrations/20260421640000_l22_07_installments.sql",
);
const mig = safeRead(migPath, "L22-07 migration present");

if (mig) {
  // Gateway preference table.
  push(
    "creates billing_gateway_preferences",
    /CREATE TABLE IF NOT EXISTS public\.billing_gateway_preferences/.test(mig),
  );
  push(
    "gateway preferences PK on group_id",
    /group_id\s+UUID PRIMARY KEY REFERENCES public\.coaching_groups/.test(mig),
  );
  push(
    "gateway preferences preferred_gateway CHECK",
    /preferred_gateway IN \('asaas', 'stripe', 'mercadopago'\)/.test(mig),
  );
  push(
    "gateway preferences at-least-one-gateway CHECK",
    /at_least_one_gateway[\s\S]{0,100}allow_stripe OR allow_asaas OR allow_mercadopago/.test(mig),
  );
  push(
    "gateway preferences RLS enabled",
    /ALTER TABLE public\.billing_gateway_preferences ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "gateway preferences admin_master write policy",
    /billing_gateway_preferences_admin_write[\s\S]{0,400}cm\.role = 'admin_master'[\s\S]{0,400}WITH CHECK[\s\S]{0,400}cm\.role = 'admin_master'/.test(mig),
  );

  // Validators.
  push(
    "fn_validate_installment_config IMMUTABLE PARALLEL SAFE",
    /fn_validate_installment_config[\s\S]{0,300}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(mig),
  );
  push(
    "validator rejects count > 12",
    /p_count IS NULL OR p_count < 1 OR p_count > 12/.test(mig),
  );
  push(
    "validator rejects total <= 0",
    /p_total_cents IS NULL OR p_total_cents <= 0/.test(mig),
  );
  push(
    "validator enforces per-installment minimum (500 cents)",
    /\(p_total_cents \/ p_count\) < 500/.test(mig),
  );
  push(
    "validator granted to PUBLIC",
    /GRANT EXECUTE ON FUNCTION public\.fn_validate_installment_config\(INT, INT\) TO PUBLIC/.test(mig),
  );

  push(
    "fn_recommend_gateway IMMUTABLE",
    /fn_recommend_gateway[\s\S]{0,300}IMMUTABLE[\s\S]{0,80}PARALLEL SAFE/.test(mig),
  );
  push(
    "recommender: BR -> asaas",
    /upper\(p_country_code\) = 'BR'[\s\S]{0,80}RETURN 'asaas'/.test(mig),
  );
  push(
    "recommender: non-BR -> stripe",
    /RETURN 'stripe'/.test(mig),
  );
  push(
    "recommender: NULL -> stripe",
    /p_country_code IS NULL THEN[\s\S]{0,80}RETURN 'stripe'/.test(mig),
  );

  // Installment plans table.
  push(
    "creates billing_installment_plans",
    /CREATE TABLE IF NOT EXISTS public\.billing_installment_plans/.test(mig),
  );
  push(
    "plan has unique purchase_id",
    /purchase_id\s+UUID NOT NULL UNIQUE/.test(mig),
  );
  push(
    "plan status CHECK state machine",
    /billing_installment_plans_status_check[\s\S]{0,200}'active', 'completed', 'cancelled'/.test(mig),
  );
  push(
    "plan gateway CHECK enum",
    /billing_installment_plans_gateway_check[\s\S]{0,200}'asaas', 'stripe', 'mercadopago'/.test(mig),
  );
  push(
    "plan payment method CHECK enum",
    /billing_installment_plans_method_check[\s\S]{0,200}'credit_card', 'boleto', 'pix', 'bank_slip'/.test(mig),
  );
  push(
    "plan invokes fn_validate_installment_config in CHECK",
    /billing_installment_plans_config_valid[\s\S]{0,200}public\.fn_validate_installment_config/.test(mig),
  );
  push(
    "plan terminal timestamp CHECK",
    /billing_installment_plans_terminal_timestamps[\s\S]{0,600}status = 'completed' AND completed_at IS NOT NULL AND cancelled_at IS NULL[\s\S]{0,300}status = 'cancelled' AND cancelled_at IS NOT NULL AND completed_at IS NULL[\s\S]{0,300}status = 'active' AND completed_at IS NULL AND cancelled_at IS NULL/.test(mig),
  );
  push(
    "plan RLS enabled",
    /ALTER TABLE public\.billing_installment_plans ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "plan admin-read policy",
    /billing_installment_plans_admin_read[\s\S]{0,400}'admin_master', 'coach'/.test(mig),
  );

  // Installments table.
  push(
    "creates billing_installments",
    /CREATE TABLE IF NOT EXISTS public\.billing_installments/.test(mig),
  );
  push(
    "installments status CHECK",
    /billing_installments_status_check[\s\S]{0,200}'pending', 'paid', 'overdue', 'cancelled'/.test(mig),
  );
  push(
    "installments paid_timestamp CHECK biconditional",
    /billing_installments_paid_timestamp[\s\S]{0,200}\(status = 'paid'\) = \(paid_at IS NOT NULL\)/.test(mig),
  );
  push(
    "installments amount positive CHECK",
    /billing_installments_amount_positive[\s\S]{0,100}amount_cents > 0/.test(mig),
  );
  push(
    "installments unique (plan_id, sequence_no)",
    /billing_installments_plan_seq_uniq[\s\S]{0,200}\(plan_id, sequence_no\)/.test(mig),
  );
  push(
    "installments due index partial on pending",
    /billing_installments_due_idx[\s\S]{0,200}WHERE status = 'pending'/.test(mig),
  );
  push(
    "installments RLS enabled",
    /ALTER TABLE public\.billing_installments ENABLE ROW LEVEL SECURITY/.test(mig),
  );

  // fn_create_installment_plan.
  push(
    "fn_create_installment_plan SECURITY DEFINER",
    /fn_create_installment_plan[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "create plan rejects non-admin",
    /only admin_master can create installment plans/.test(mig),
  );
  push(
    "create plan uses fn_validate_installment_config",
    /fn_create_installment_plan[\s\S]{0,1800}NOT public\.fn_validate_installment_config/.test(mig),
  );
  push(
    "create plan integer-exact schedule",
    /v_per_cents := v_purchase\.price_cents \/ p_installment_count[\s\S]{0,200}v_remainder := v_purchase\.price_cents - \(v_per_cents \* p_installment_count\)/.test(mig),
  );
  push(
    "create plan remainder applied to first installment",
    /v_per_cents \+ \(CASE WHEN v_seq = 1 THEN v_remainder ELSE 0 END\)/.test(mig),
  );
  push(
    "create plan grants authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_create_installment_plan[\s\S]{0,200}TO authenticated/.test(mig),
  );

  // fn_mark_installment_paid.
  push(
    "fn_mark_installment_paid service-role only",
    /fn_mark_installment_paid is service-role only/.test(mig),
  );
  push(
    "mark paid uses FOR UPDATE",
    /fn_mark_installment_paid[\s\S]{0,1200}FOR UPDATE/.test(mig),
  );
  push(
    "mark paid idempotent on paid status",
    /IF v_inst\.status = 'paid' THEN[\s\S]{0,80}RETURN FALSE/.test(mig),
  );
  push(
    "mark paid rejects cancelled",
    /cannot pay cancelled installment/.test(mig),
  );
  push(
    "mark paid promotes plan to completed when all settled",
    /SELECT COUNT\(\*\) INTO v_pending[\s\S]{0,200}status IN \('pending', 'overdue'\)[\s\S]{0,400}SET status = 'completed'/.test(mig),
  );
  push(
    "mark paid grants service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_mark_installment_paid[\s\S]{0,200}TO service_role/.test(mig)
      && !/fn_mark_installment_paid[\s\S]{0,400}TO authenticated/.test(mig),
  );

  // Sweep.
  push(
    "fn_mark_installments_overdue service-role only",
    /fn_mark_installments_overdue is service-role only/.test(mig),
  );
  push(
    "overdue sweep updates pending past due",
    /SET status = 'overdue'[\s\S]{0,200}status = 'pending'[\s\S]{0,100}due_date < CURRENT_DATE/.test(mig),
  );

  // Cancel.
  push(
    "fn_cancel_installment_plan admin-only",
    /only admin_master can cancel installment plans/.test(mig),
  );
  push(
    "cancel refuses non-active plan",
    /plan already %[\s\S]{0,200}USING ERRCODE = 'P0005'/.test(mig),
  );
  push(
    "cancel cascades to installments",
    /UPDATE public\.billing_installments[\s\S]{0,200}SET status = 'cancelled'[\s\S]{0,200}plan_id = p_plan_id[\s\S]{0,200}status IN \('pending', 'overdue'\)/.test(mig),
  );

  // Self-tests.
  push(
    "self-test: BR recommends asaas",
    /self-test: BR must recommend asaas/.test(mig),
  );
  push(
    "self-test: US recommends stripe",
    /self-test: US must recommend stripe/.test(mig),
  );
  push(
    "self-test: 10x R$12,50 validates",
    /self-test: 10x R\$ 12,50 must validate/.test(mig),
  );
  push(
    "self-test: count > 12 rejects",
    /self-test: 13 installments must reject/.test(mig),
  );
  push(
    "self-test: micro-charge rejects",
    /self-test: per-installment < R\$ 5,00 must reject/.test(mig),
  );
  push(
    "self-test asserts plan config CHECK presence",
    /self-test: billing_installment_plans_config_valid CHECK missing/.test(mig),
  );
  push(
    "self-test asserts installment paid-timestamp CHECK presence",
    /self-test: billing_installments_paid_timestamp CHECK missing/.test(mig),
  );
  push(
    "self-test asserts unique seq index presence",
    /self-test: billing_installments_plan_seq_uniq index missing/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L22-07-compra-parcelada-para-assessoria-brasileira.md",
);
const finding = safeRead(findingPath, "L22-07 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421640000_l22_07_installments\.sql/.test(finding),
  );
  push(
    "finding references installment primitives",
    /fn_create_installment_plan/.test(finding)
      && /billing_installment_plans/.test(finding),
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
  `\n${results.length - failed}/${results.length} installments-br checks passed.`,
);
if (failed > 0) {
  console.error("\nL22-07 invariants broken.");
  process.exit(1);
}
