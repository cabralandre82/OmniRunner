/**
 * check-athlete-subscriptions.ts
 *
 * L23-09 — CI guard for per-athlete subscription billing flow.
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
  "supabase/migrations/20260421670000_l23_09_athlete_subscriptions.sql",
);
const mig = safeRead(migPath, "L23-09 migration present");

if (mig) {
  // Subscriptions table.
  push(
    "creates athlete_subscriptions table",
    /CREATE TABLE IF NOT EXISTS public\.athlete_subscriptions/.test(mig),
  );
  push(
    "price_cents positive CHECK",
    /athlete_subscriptions_price_positive[\s\S]{0,100}price_cents > 0/.test(mig),
  );
  push(
    "currency length CHECK",
    /athlete_subscriptions_currency_len[\s\S]{0,100}length\(currency\) = 3/.test(mig),
  );
  push(
    "billing_day_of_month CHECK [1, 28]",
    /athlete_subscriptions_day_range[\s\S]{0,100}billing_day_of_month BETWEEN 1 AND 28/.test(mig),
  );
  push(
    "gateway CHECK enum",
    /athlete_subscriptions_gateway_check[\s\S]{0,200}'asaas', 'stripe', 'mercadopago'/.test(mig),
  );
  push(
    "subscription status CHECK enum",
    /athlete_subscriptions_status_check[\s\S]{0,200}'active', 'paused', 'cancelled'/.test(mig),
  );
  push(
    "subscription state/timestamp biconditional CHECK",
    /athlete_subscriptions_state_timestamps[\s\S]{0,600}status = 'active'[\s\S]{0,200}cancelled_at IS NULL[\s\S]{0,300}status = 'paused'[\s\S]{0,200}paused_at IS NOT NULL[\s\S]{0,300}status = 'cancelled'[\s\S]{0,200}cancelled_at IS NOT NULL/.test(mig),
  );
  push(
    "active partial unique index blocks duplicate",
    /athlete_subscriptions_active_uniq[\s\S]{0,200}\(group_id, athlete_user_id\)[\s\S]{0,200}WHERE status IN \('active', 'paused'\)/.test(mig),
  );
  push(
    "subscriptions RLS enabled",
    /ALTER TABLE public\.athlete_subscriptions ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "subscriptions athlete-self read policy",
    /athlete_subscriptions_athlete_read[\s\S]{0,200}athlete_user_id = auth\.uid\(\)/.test(mig),
  );
  push(
    "subscriptions staff read policy",
    /athlete_subscriptions_staff_read[\s\S]{0,400}'admin_master', 'coach'/.test(mig),
  );

  // Invoices table.
  push(
    "creates athlete_subscription_invoices table",
    /CREATE TABLE IF NOT EXISTS public\.athlete_subscription_invoices/.test(mig),
  );
  push(
    "invoices amount_cents positive CHECK",
    /athlete_sub_invoices_amount_positive[\s\S]{0,100}amount_cents > 0/.test(mig),
  );
  push(
    "invoices status CHECK enum",
    /athlete_sub_invoices_status_check[\s\S]{0,200}'pending', 'paid', 'overdue', 'cancelled'/.test(mig),
  );
  push(
    "invoices paid_timestamp biconditional CHECK",
    /athlete_sub_invoices_paid_timestamp[\s\S]{0,200}\(status = 'paid'\) = \(paid_at IS NOT NULL\)/.test(mig),
  );
  push(
    "invoices cancelled_timestamp biconditional CHECK",
    /athlete_sub_invoices_cancelled_timestamp[\s\S]{0,200}\(status = 'cancelled'\) = \(cancelled_at IS NOT NULL\)/.test(mig),
  );
  push(
    "invoices period_first_of_month CHECK",
    /athlete_sub_invoices_period_first_of_month[\s\S]{0,200}date_trunc\('month', period_month\)::date = period_month/.test(mig),
  );
  push(
    "invoices unique (subscription_id, period_month) — idempotency",
    /athlete_sub_invoices_period_uniq[\s\S]{0,200}\(subscription_id, period_month\)/.test(mig),
  );
  push(
    "invoices status+due partial index",
    /athlete_sub_invoices_status_due_idx[\s\S]{0,200}WHERE status IN \('pending', 'overdue'\)/.test(mig),
  );
  push(
    "invoices RLS enabled",
    /ALTER TABLE public\.athlete_subscription_invoices ENABLE ROW LEVEL SECURITY/.test(mig),
  );
  push(
    "invoices athlete-self read policy",
    /athlete_sub_invoices_athlete_read[\s\S]{0,200}athlete_user_id = auth\.uid\(\)/.test(mig),
  );
  push(
    "invoices staff read policy",
    /athlete_sub_invoices_staff_read[\s\S]{0,400}'admin_master', 'coach'/.test(mig),
  );

  // fn_subscription_start.
  push(
    "fn_subscription_start SECURITY DEFINER",
    /fn_subscription_start[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "start: only admin_master/coach",
    /only admin_master or coach can start subscription/.test(mig),
  );
  push(
    "start: athlete must be group member",
    /athlete is not a member of this group/.test(mig),
  );
  push(
    "start: price floor R$ 5,00",
    /p_price_cents < 500[\s\S]{0,200}'price must be at least R\$ 5,00/.test(mig),
  );
  push(
    "start: billing_day [1, 28]",
    /p_billing_day < 1 OR p_billing_day > 28[\s\S]{0,200}billing_day must be in \[1, 28\]/.test(mig),
  );
  push(
    "start granted to authenticated",
    /GRANT EXECUTE ON FUNCTION public\.fn_subscription_start[\s\S]{0,200}TO authenticated/.test(mig),
  );

  // fn_subscription_pause.
  push(
    "fn_subscription_pause SECURITY DEFINER FOR UPDATE",
    /fn_subscription_pause[\s\S]{0,400}SECURITY DEFINER[\s\S]{0,800}FOR UPDATE/.test(mig),
  );
  push(
    "pause: only admin_master/coach",
    /only admin_master or coach can pause subscription/.test(mig),
  );
  push(
    "pause: rejects non-active",
    /subscription not active \(current %\)/.test(mig),
  );

  // fn_subscription_cancel.
  push(
    "fn_subscription_cancel SECURITY DEFINER",
    /fn_subscription_cancel[\s\S]{0,400}SECURITY DEFINER/.test(mig),
  );
  push(
    "cancel: athlete-self OR group staff",
    /only athlete self or group staff can cancel/.test(mig),
  );
  push(
    "cancel: idempotent on already cancelled",
    /fn_subscription_cancel[\s\S]{0,1600}status = 'cancelled' THEN[\s\S]{0,100}RETURN FALSE/.test(mig),
  );
  push(
    "cancel: cascades pending invoices to cancelled",
    /UPDATE public\.athlete_subscription_invoices[\s\S]{0,400}SET status = 'cancelled'[\s\S]{0,400}status = 'pending'/.test(mig),
  );

  // fn_subscription_generate_cycle.
  push(
    "generate_cycle service-role only",
    /fn_subscription_generate_cycle is service-role only/.test(mig),
  );
  push(
    "generate_cycle defaults to current month",
    /date_trunc\('month', now\(\)\)::date/.test(mig),
  );
  push(
    "generate_cycle validates period_month is 1st of month",
    /p_period_month must be the first day of a month/.test(mig),
  );
  push(
    "generate_cycle idempotent via ON CONFLICT",
    /ON CONFLICT \(subscription_id, period_month\) DO NOTHING/.test(mig),
  );
  push(
    "generate_cycle only picks active subscriptions",
    /sub\.status = 'active'/.test(mig),
  );
  push(
    "generate_cycle computes due_date from billing_day",
    /\(c\.billing_day_of_month - 1\) \* INTERVAL '1 day'/.test(mig),
  );
  push(
    "generate_cycle granted to service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_subscription_generate_cycle\(DATE\) TO service_role/.test(mig)
      && !/fn_subscription_generate_cycle[\s\S]{0,400}TO authenticated/.test(mig),
  );

  // fn_subscription_mark_invoice_paid.
  push(
    "mark_invoice_paid service-role only",
    /fn_subscription_mark_invoice_paid is service-role only/.test(mig),
  );
  push(
    "mark_invoice_paid idempotent on paid status",
    /fn_subscription_mark_invoice_paid[\s\S]{0,1200}status = 'paid' THEN[\s\S]{0,100}RETURN FALSE/.test(mig),
  );
  push(
    "mark_invoice_paid refuses cancelled",
    /cannot pay cancelled invoice/.test(mig),
  );
  push(
    "mark_invoice_paid emits outbox event fail-open",
    /subscription\.invoice\.paid[\s\S]{0,800}EXCEPTION WHEN OTHERS THEN[\s\S]{0,200}RAISE WARNING 'outbox emit failed/.test(mig),
  );
  push(
    "mark_invoice_paid guarded by to_regproc on outbox emitter",
    /to_regproc\('public\.fn_outbox_emit/.test(mig),
  );
  push(
    "mark_invoice_paid granted service_role only",
    /GRANT EXECUTE ON FUNCTION public\.fn_subscription_mark_invoice_paid[\s\S]{0,200}TO service_role/.test(mig)
      && !/fn_subscription_mark_invoice_paid[\s\S]{0,400}TO authenticated/.test(mig),
  );

  // Overdue sweep.
  push(
    "mark_overdue service-role only",
    /fn_subscription_mark_overdue is service-role only/.test(mig),
  );
  push(
    "mark_overdue flags pending past due_date",
    /status = 'pending'[\s\S]{0,200}due_date < CURRENT_DATE/.test(mig),
  );

  // Self-tests.
  push(
    "self-test asserts state_timestamps CHECK presence",
    /self-test: state_timestamps CHECK missing/.test(mig),
  );
  push(
    "self-test asserts period_first_of_month CHECK presence",
    /self-test: period_first_of_month CHECK missing/.test(mig),
  );
  push(
    "self-test asserts paid_timestamp CHECK presence",
    /self-test: paid_timestamp CHECK missing/.test(mig),
  );
  push(
    "self-test asserts active_uniq partial index presence",
    /self-test: active_uniq partial index missing/.test(mig),
  );
  push(
    "self-test asserts invoices period_uniq index presence",
    /self-test: invoices period_uniq index missing/.test(mig),
  );

  push(
    "migration runs in a single transaction",
    /^BEGIN;/m.test(mig) && /^COMMIT;/m.test(mig),
  );
}

const findingPath = resolve(
  ROOT,
  "docs/audit/findings/L23-09-billing-integrado-cobranca-de-mensalidade-aos-atletas.md",
);
const finding = safeRead(findingPath, "L23-09 finding present");
if (finding) {
  push(
    "finding references migration",
    /20260421670000_l23_09_athlete_subscriptions\.sql/.test(finding),
  );
  push(
    "finding references subscription primitives",
    /athlete_subscriptions/.test(finding)
      && /fn_subscription_mark_invoice_paid/.test(finding),
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
  `\n${results.length - failed}/${results.length} athlete-subscriptions checks passed.`,
);
if (failed > 0) {
  console.error("\nL23-09 invariants broken.");
  process.exit(1);
}
