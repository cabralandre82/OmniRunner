import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";

/**
 * auto-topup-check — Supabase Edge Function
 *
 * Invoked after a token debit to determine whether automatic credit
 * replenishment should trigger.  Runs with service-role auth only
 * (no user JWT) because it is called server-to-server.
 *
 * POST /auto-topup-check
 * Headers: Authorization: Bearer <service_role_key>
 * Body: { group_id }
 *
 * Decision tree (DECISAO 050 §3.6 — hybrid mode):
 *   1. Is auto_topup enabled for this group?
 *   2. Is available_tokens < threshold_tokens?
 *   3. Monthly cap not exceeded?
 *   4. 24h cooldown respected?
 *   5. Stripe customer + payment method configured?
 *      YES → Create billing_purchase (source=auto_topup) + PaymentIntent (off-session)
 *      NO  → Send push notification via notify-rules (low_credits_alert)
 *
 * Idempotency: cooldown + monthly cap prevent duplicate charges even
 * if this function is called multiple times in rapid succession.
 */

const FN = "auto-topup-check";
const COOLDOWN_HOURS = 24;

// deno-lint-ignore no-explicit-any
type DB = any;

interface TopupSettings {
  group_id: string;
  enabled: boolean;
  threshold_tokens: number;
  product_id: string;
  max_per_month: number;
  last_triggered_at: string | null;
}

interface SkipResult {
  triggered: false;
  reason: string;
  notified?: boolean;
}

interface TriggerResult {
  triggered: true;
  purchase_id: string;
  payment_intent_id: string;
}

type CheckResult = SkipResult | TriggerResult;

function monthKey(): string {
  const now = new Date();
  return `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, "0")}`;
}

function isWithinCooldown(lastTriggeredAt: string | null): boolean {
  if (!lastTriggeredAt) return false;
  const last = new Date(lastTriggeredAt).getTime();
  const cutoff = Date.now() - COOLDOWN_HOURS * 60 * 60 * 1000;
  return last > cutoff;
}

async function countMonthlyTopups(
  db: DB,
  groupId: string,
): Promise<number> {
  const now = new Date();
  const startOfMonth = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1),
  ).toISOString();

  const { count, error } = await db
    .from("billing_purchases")
    .select("id", { count: "exact", head: true })
    .eq("group_id", groupId)
    .eq("source", "auto_topup")
    .gte("created_at", startOfMonth);

  if (error) throw error;
  return count ?? 0;
}

async function sendLowCreditsNotification(
  supabaseUrl: string,
  serviceKey: string,
  groupId: string,
  balance: number,
  threshold: number,
): Promise<boolean> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 15_000);
  try {
    const res = await fetch(`${supabaseUrl}/functions/v1/notify-rules`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        rule: "low_credits_alert",
        context: { group_id: groupId, balance, threshold },
      }),
      signal: ctrl.signal,
    });
    return res.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}

async function runCheck(
  db: DB,
  stripe: Stripe | null,
  supabaseUrl: string,
  serviceKey: string,
  groupId: string,
  requestId: string,
): Promise<CheckResult> {
  // 1. Load auto-topup settings (service role bypasses RLS)
  const { data: settings, error: settingsErr } = await db
    .from("billing_auto_topup_settings")
    .select("group_id, enabled, threshold_tokens, product_id, max_per_month, last_triggered_at")
    .eq("group_id", groupId)
    .maybeSingle();

  if (settingsErr) throw settingsErr;
  if (!settings) return { triggered: false, reason: "no_settings" };

  const cfg = settings as TopupSettings;
  if (!cfg.enabled) return { triggered: false, reason: "disabled" };

  // 2. Check current balance
  const { data: inventory } = await db
    .from("coaching_token_inventory")
    .select("available_tokens")
    .eq("group_id", groupId)
    .maybeSingle();

  const balance = inventory?.available_tokens ?? 0;
  if (balance >= cfg.threshold_tokens) {
    return { triggered: false, reason: "above_threshold" };
  }

  // 3. Monthly cap
  const monthlyCount = await countMonthlyTopups(db, groupId);
  if (monthlyCount >= cfg.max_per_month) {
    return { triggered: false, reason: "monthly_cap_reached" };
  }

  // 4. 24h cooldown
  if (isWithinCooldown(cfg.last_triggered_at)) {
    return { triggered: false, reason: "cooldown" };
  }

  // 5. Stripe payment method — if not available, fallback to push notification
  const { data: customer } = await db
    .from("billing_customers")
    .select("stripe_customer_id, stripe_default_pm")
    .eq("group_id", groupId)
    .maybeSingle();

  const hasStripe =
    stripe &&
    customer?.stripe_customer_id &&
    customer?.stripe_default_pm;

  if (!hasStripe) {
    const notified = await sendLowCreditsNotification(
      supabaseUrl,
      serviceKey,
      groupId,
      balance,
      cfg.threshold_tokens,
    );

    await db
      .from("billing_auto_topup_settings")
      .update({
        last_triggered_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("group_id", groupId);

    return { triggered: false, reason: "no_payment_method_notified", notified };
  }

  // 6. Load product
  const { data: product, error: prodErr } = await db
    .from("billing_products")
    .select("id, name, credits_amount, price_cents, currency, is_active")
    .eq("id", cfg.product_id)
    .maybeSingle();

  if (prodErr) throw prodErr;
  if (!product || !product.is_active) {
    return { triggered: false, reason: "product_unavailable" };
  }

  // 7. Create billing_purchase (source=auto_topup)
  const { data: purchase, error: purchaseErr } = await db
    .from("billing_purchases")
    .insert({
      group_id: groupId,
      product_id: product.id,
      credits_amount: product.credits_amount,
      price_cents: product.price_cents,
      currency: product.currency,
      status: "pending",
      payment_method: "card",
      source: "auto_topup",
      requested_by: null,
    })
    .select("id")
    .single();

  if (purchaseErr) throw purchaseErr;

  // 8. Billing event
  await db.from("billing_events").insert({
    purchase_id: purchase.id,
    event_type: "created",
    metadata: {
      source: "auto_topup",
      threshold: cfg.threshold_tokens,
      balance_at_trigger: balance,
      request_id: requestId,
    },
  });

  // 9. Stripe PaymentIntent (off-session, confirm=true, card only)
  let paymentIntent: Stripe.PaymentIntent;
  try {
    paymentIntent = await stripe.paymentIntents.create({
      amount: product.price_cents,
      currency: product.currency.toLowerCase(),
      customer: customer.stripe_customer_id,
      payment_method: customer.stripe_default_pm,
      off_session: true,
      confirm: true,
      metadata: {
        purchase_id: purchase.id,
        group_id: groupId,
        product_id: product.id,
        source: "auto_topup",
        request_id: requestId,
      },
    });
  } catch (stripeErr: unknown) {
    // 3DS required or card declined — cancel purchase, log, and bail
    const msg =
      stripeErr instanceof Error ? stripeErr.message : String(stripeErr);

    await db
      .from("billing_purchases")
      .update({
        status: "cancelled",
        updated_at: new Date().toISOString(),
      })
      .eq("id", purchase.id)
      .eq("status", "pending");

    await db.from("billing_events").insert({
      purchase_id: purchase.id,
      event_type: "cancelled",
      metadata: {
        source: "auto_topup",
        reason: "stripe_error",
        detail: msg,
        request_id: requestId,
      },
    });

    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `STRIPE_CHARGE_FAILED: ${msg}`,
      duration_ms: 0,
    });

    // Notify staff about failed auto-topup (3DS required, card declined, etc)
    const svcUrl = Deno.env.get("SUPABASE_URL");
    const svcKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SERVICE_ROLE_KEY");
    if (svcUrl && svcKey) {
      fetch(`${svcUrl}/functions/v1/notify-rules`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${svcKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          rule: "auto_topup_failed",
          context: { group_id: groupId, reason: msg, purchase_id: purchase.id },
        }),
        signal: AbortSignal.timeout(10_000),
      }).catch(() => {});
    }

    return { triggered: false, reason: "stripe_charge_failed" };
  }

  // 10. Link payment reference and update last_triggered_at
  await db
    .from("billing_purchases")
    .update({
      payment_reference: paymentIntent.id,
      updated_at: new Date().toISOString(),
    })
    .eq("id", purchase.id);

  await db
    .from("billing_auto_topup_settings")
    .update({
      last_triggered_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("group_id", groupId);

  // 11. If the PaymentIntent succeeded immediately, fulfill inline.
  //     Otherwise the webhook will handle it asynchronously.
  if (paymentIntent.status === "succeeded") {
    await db
      .from("billing_purchases")
      .update({
        status: "paid",
        updated_at: new Date().toISOString(),
      })
      .eq("id", purchase.id)
      .eq("status", "pending");

    const { error: fulfillErr } = await db.rpc("fn_fulfill_purchase", {
      p_purchase_id: purchase.id,
    });

    if (fulfillErr) {
      const msg = fulfillErr.message ?? "";
      if (!msg.includes("must be in paid status")) {
        logError({
          request_id: requestId,
          fn: FN,
          user_id: null,
          error_code: `FULFILL_FAILED: ${msg}`,
          duration_ms: 0,
        });
      }
    }
  }

  // 12. Analytics (fire-and-forget)
  await db
    .from("product_events")
    .insert({
      user_id: null,
      event_name: "billing_auto_topup_triggered",
      properties: {
        group_id: groupId,
        purchase_id: purchase.id,
        product_id: product.id,
        credits_amount: product.credits_amount,
        balance_before: balance,
        threshold: cfg.threshold_tokens,
        payment_intent_id: paymentIntent.id,
        payment_intent_status: paymentIntent.status,
      },
    })
    .then(
      () => {},
      () => {},
    );

  return {
    triggered: true,
    purchase_id: purchase.id,
    payment_intent_id: paymentIntent.id,
  };
}

// ─── Main Handler ────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '2.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // Auth: service-role only (no user JWT — server-to-server call)
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role key required", requestId);
    }

    // Parse body
    let body: Record<string, unknown>;
    try {
      const text = await req.text();
      body = text.trim() ? JSON.parse(text) : {};
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const groupId = body.group_id;
    if (!groupId || typeof groupId !== "string") {
      status = 400;
      return jsonErr(400, "MISSING_FIELDS", "group_id is required", requestId);
    }

    // DB client (service role)
    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    // Stripe client (optional — if not configured, falls back to push notification)
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    let stripe: Stripe | null = null;
    if (stripeKey) {
      stripe = new Stripe(stripeKey, {
        apiVersion: "2023-10-16",
        httpClient: Stripe.createFetchHttpClient(),
      });
    }

    const result = await runCheck(db, stripe, supabaseUrl, serviceKey, groupId, requestId);

    return jsonOk(result, requestId);
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    logError({
      request_id: requestId,
      fn: FN,
      user_id: null,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId,
        fn: FN,
        user_id: null,
        error_code: errorCode,
        duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId,
        fn: FN,
        user_id: null,
        status,
        duration_ms: elapsed(),
      });
    }
  }
});
