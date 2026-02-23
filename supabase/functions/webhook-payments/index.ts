import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";

/**
 * webhook-payments — Supabase Edge Function
 *
 * Receives Stripe webhook events and processes billing lifecycle:
 *   checkout.session.completed        → pending → paid → fulfilled
 *   checkout.session.async_payment_succeeded → (same, for boleto)
 *   checkout.session.async_payment_failed   → pending → cancelled
 *   checkout.session.expired                → pending → cancelled
 *   charge.refunded                         → billing_event(refunded)
 *   charge.dispute.created                  → billing_event(note_added)
 *
 * Idempotency layers:
 *   L1 — billing_events.stripe_event_id UNIQUE partial index
 *   L2 — conditional UPDATE (WHERE status = 'pending') prevents re-transition
 *   L3 — fn_fulfill_purchase checks status = 'paid' with FOR UPDATE lock
 *
 * See DECISAO 049.
 */

const FN = "webhook-payments";

// ─── Helpers ─────────────────────────────────────────────────────────────────

// deno-lint-ignore no-explicit-any
type DB = any;

async function insertEvent(
  db: DB,
  purchaseId: string,
  eventType: string,
  stripeEventId: string,
  metadata: Record<string, unknown>,
): Promise<boolean> {
  const { error } = await db.from("billing_events").insert({
    purchase_id: purchaseId,
    event_type: eventType,
    stripe_event_id: stripeEventId,
    metadata,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("unique constraint") || msg.includes("duplicate key")) {
      return false;
    }
    throw error;
  }
  return true;
}

async function trackBillingAnalytics(
  db: DB,
  purchaseId: string,
  eventName: string,
  extra: Record<string, unknown> = {},
): Promise<void> {
  try {
    const { data: purchase } = await db
      .from("billing_purchases")
      .select("requested_by, group_id, credits_amount, price_cents, product_id")
      .eq("id", purchaseId)
      .maybeSingle();

    if (!purchase?.requested_by) return;

    await db.from("product_events").insert({
      user_id: purchase.requested_by,
      event_name: eventName,
      properties: {
        purchase_id: purchaseId,
        group_id: purchase.group_id,
        credits_amount: purchase.credits_amount,
        product_id: purchase.product_id,
        ...extra,
      },
    });
  } catch {
    // Non-critical — analytics failure must not block payment flow
  }
}

async function resolvePaymentMethod(
  stripe: Stripe,
  paymentIntentId: string | null,
): Promise<string> {
  if (!paymentIntentId) return "stripe";
  try {
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId, {
      expand: ["latest_charge"],
    });
    // deno-lint-ignore no-explicit-any
    const charge = pi.latest_charge as any;
    return charge?.payment_method_details?.type ?? "stripe";
  } catch {
    return "stripe";
  }
}

function extractPurchaseId(
  // deno-lint-ignore no-explicit-any
  obj: any,
): string | null {
  return obj?.metadata?.purchase_id ?? null;
}

// ─── Event Handlers ──────────────────────────────────────────────────────────

async function handlePaymentConfirmed(
  db: DB,
  stripe: Stripe,
  // deno-lint-ignore no-explicit-any
  session: any,
  stripeEventId: string,
  requestId: string,
): Promise<void> {
  const purchaseId = extractPurchaseId(session);
  if (!purchaseId) {
    console.error(JSON.stringify({
      request_id: requestId, fn: FN,
      error_code: "MISSING_PURCHASE_ID",
      stripe_event_id: stripeEventId,
    }));
    return;
  }

  const paymentMethod = await resolvePaymentMethod(
    stripe,
    session.payment_intent,
  );

  // Resolve receipt/invoice URL from the Stripe charge
  let invoiceUrl: string | null = null;
  if (session.payment_intent) {
    try {
      const pi = await stripe.paymentIntents.retrieve(session.payment_intent, {
        expand: ["latest_charge"],
      });
      // deno-lint-ignore no-explicit-any
      const charge = pi.latest_charge as any;
      invoiceUrl = charge?.receipt_url ?? null;
    } catch {
      // Non-critical — receipt link just won't be available
    }
  }

  // L2: conditional update — only transitions from 'pending'
  // deno-lint-ignore no-explicit-any
  const updatePayload: any = {
    status: "paid",
    payment_method: paymentMethod,
    payment_reference: session.payment_intent ?? session.id,
    updated_at: new Date().toISOString(),
  };
  if (invoiceUrl) updatePayload.invoice_url = invoiceUrl;

  const { data: updated } = await db
    .from("billing_purchases")
    .update(updatePayload)
    .eq("id", purchaseId)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();

  // L1: insert billing_event (dedup via stripe_event_id UNIQUE)
  const isNew = await insertEvent(db, purchaseId, "payment_confirmed", stripeEventId, {
    stripe_session_id: session.id,
    stripe_payment_intent: session.payment_intent,
    payment_method: paymentMethod,
    amount_total: session.amount_total,
    currency: session.currency,
    request_id: requestId,
  });

  if (!isNew) return; // duplicate event — already fully processed

  if (!updated) {
    // Purchase was not in 'pending' — check if it needs fulfillment
    const { data: purchase } = await db
      .from("billing_purchases")
      .select("status")
      .eq("id", purchaseId)
      .maybeSingle();

    if (!purchase || purchase.status === "fulfilled" || purchase.status === "cancelled") {
      return; // fully processed or cancelled
    }
    // status = 'paid' from a previous attempt that failed fulfillment — retry below
  }

  // L3: fn_fulfill_purchase — paid → fulfilled + credit allocation (atomic)
  const { error: fulfillErr } = await db.rpc("fn_fulfill_purchase", {
    p_purchase_id: purchaseId,
  });

  if (fulfillErr) {
    const msg = fulfillErr.message ?? "";
    if (msg.includes("must be in paid status")) {
      // Already fulfilled — idempotent success
      return;
    }
    // Fulfillment failed — purchase stays 'paid', needs manual intervention
    console.error(JSON.stringify({
      request_id: requestId,
      fn: FN,
      error_code: "FULFILL_FAILED",
      purchase_id: purchaseId,
      detail: msg,
    }));
  }

  await trackBillingAnalytics(db, purchaseId, "billing_payment_confirmed", {
    payment_method: paymentMethod,
    amount_total: session.amount_total,
    currency: session.currency,
  });
}

async function handleSessionCancelled(
  db: DB,
  // deno-lint-ignore no-explicit-any
  session: any,
  stripeEventId: string,
  requestId: string,
): Promise<void> {
  const purchaseId = extractPurchaseId(session);
  if (!purchaseId) return;

  // Only cancel if still pending
  await db
    .from("billing_purchases")
    .update({
      status: "cancelled",
      updated_at: new Date().toISOString(),
    })
    .eq("id", purchaseId)
    .eq("status", "pending");

  await insertEvent(db, purchaseId, "cancelled", stripeEventId, {
    stripe_session_id: session.id,
    reason: session.status ?? "expired_or_failed",
    request_id: requestId,
  });

  const reason = session.status === "expired"
    ? "billing_checkout_expired"
    : "billing_payment_failed";
  await trackBillingAnalytics(db, purchaseId, reason, {
    stripe_status: session.status,
  });
}

async function handleChargeRefunded(
  db: DB,
  // deno-lint-ignore no-explicit-any
  charge: any,
  stripeEventId: string,
  requestId: string,
): Promise<void> {
  const paymentIntentId = charge.payment_intent;
  if (!paymentIntentId) return;

  const { data: purchase } = await db
    .from("billing_purchases")
    .select("id")
    .eq("payment_reference", paymentIntentId)
    .maybeSingle();

  if (!purchase) {
    console.error(JSON.stringify({
      request_id: requestId, fn: FN,
      error_code: "REFUND_PURCHASE_NOT_FOUND",
      payment_intent: paymentIntentId,
    }));
    return;
  }

  await insertEvent(db, purchase.id, "refunded", stripeEventId, {
    stripe_charge_id: charge.id,
    amount_refunded: charge.amount_refunded,
    currency: charge.currency,
    request_id: requestId,
  });
}

async function handleDisputeCreated(
  db: DB,
  // deno-lint-ignore no-explicit-any
  dispute: any,
  stripeEventId: string,
  requestId: string,
): Promise<void> {
  const paymentIntentId = dispute.payment_intent;
  if (!paymentIntentId) return;

  const { data: purchase } = await db
    .from("billing_purchases")
    .select("id")
    .eq("payment_reference", paymentIntentId)
    .maybeSingle();

  if (!purchase) {
    console.error(JSON.stringify({
      request_id: requestId, fn: FN,
      error_code: "DISPUTE_PURCHASE_NOT_FOUND",
      payment_intent: paymentIntentId,
    }));
    return;
  }

  await insertEvent(db, purchase.id, "note_added", stripeEventId, {
    stripe_dispute_id: dispute.id,
    reason: dispute.reason,
    amount: dispute.amount,
    currency: dispute.currency,
    status: dispute.status,
    request_id: requestId,
  });
}

// ─── Main Handler ────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Environment ──────────────────────────────────────────────────
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!stripeKey || !webhookSecret || !supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    // ── 2. Verify Stripe signature ──────────────────────────────────────
    const rawBody = await req.text();
    const sig = req.headers.get("stripe-signature");

    if (!sig) {
      status = 400;
      errorCode = "MISSING_SIGNATURE";
      return jsonErr(400, "MISSING_SIGNATURE", "Missing stripe-signature header", requestId);
    }

    const stripe = new Stripe(stripeKey, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    let event: Stripe.Event;
    try {
      event = await stripe.webhooks.constructEventAsync(
        rawBody,
        sig,
        webhookSecret,
        undefined,
        Stripe.createSubtleCryptoProvider(),
      );
    } catch {
      status = 400;
      errorCode = "INVALID_SIGNATURE";
      return jsonErr(400, "INVALID_SIGNATURE", "Webhook signature verification failed", requestId);
    }

    // ── 3. Service-role DB client ───────────────────────────────────────
    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    // ── 4. Global dedup check (L1 — query layer) ────────────────────────
    const { data: existing } = await db
      .from("billing_events")
      .select("id")
      .eq("stripe_event_id", event.id)
      .maybeSingle();

    if (existing) {
      return jsonOk({ already_processed: true, stripe_event_id: event.id }, requestId);
    }

    // ── 5. Route event ──────────────────────────────────────────────────
    switch (event.type) {
      case "checkout.session.completed": {
        // deno-lint-ignore no-explicit-any
        const session = event.data.object as any;
        if (session.payment_status === "paid") {
          await handlePaymentConfirmed(db, stripe, session, event.id, requestId);
        }
        // payment_status !== 'paid' → boleto awaiting payment, skip until async_payment_succeeded
        break;
      }

      case "checkout.session.async_payment_succeeded": {
        // deno-lint-ignore no-explicit-any
        const session = event.data.object as any;
        await handlePaymentConfirmed(db, stripe, session, event.id, requestId);
        break;
      }

      case "checkout.session.async_payment_failed": {
        // deno-lint-ignore no-explicit-any
        const session = event.data.object as any;
        await handleSessionCancelled(db, session, event.id, requestId);
        break;
      }

      case "checkout.session.expired": {
        // deno-lint-ignore no-explicit-any
        const session = event.data.object as any;
        await handleSessionCancelled(db, session, event.id, requestId);
        break;
      }

      case "charge.refunded": {
        await handleChargeRefunded(db, event.data.object, event.id, requestId);
        break;
      }

      case "charge.dispute.created": {
        await handleDisputeCreated(db, event.data.object, event.id, requestId);
        break;
      }

      default:
        break;
    }

    return jsonOk(
      { processed: true, event_type: event.type, stripe_event_id: event.id },
      requestId,
    );
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
