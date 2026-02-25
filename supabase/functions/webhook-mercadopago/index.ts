import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";

/**
 * webhook-mercadopago — Supabase Edge Function
 *
 * Receives Mercado Pago IPN/webhook notifications and processes billing:
 *   payment.approved   → pending → paid → fulfilled
 *   payment.cancelled  → pending → cancelled
 *   payment.refunded   → billing_event(refunded)
 *
 * Idempotency:
 *   L1 — billing_events dedup via mp_payment_id in metadata
 *   L2 — conditional UPDATE (WHERE status = 'pending') prevents re-transition
 *   L3 — fn_fulfill_purchase checks status = 'paid' with FOR UPDATE lock
 *
 * MP sends notifications to: {SUPABASE_URL}/functions/v1/webhook-mercadopago
 * Query param: ?type=payment&data.id=<payment_id>
 * OR JSON body: { action, type, data: { id } }
 */

const FN = "webhook-mercadopago";

// deno-lint-ignore no-explicit-any
type DB = any;

async function insertEvent(
  db: DB,
  purchaseId: string,
  eventType: string,
  metadata: Record<string, unknown>,
): Promise<boolean> {
  const { error } = await db.from("billing_events").insert({
    purchase_id: purchaseId,
    event_type: eventType,
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

async function trackAnalytics(
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
    // analytics failure must not block payment flow
  }
}

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

    const mpAccessToken = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");

    if (!mpAccessToken || !supabaseUrl || !serviceKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    // MP sends data as JSON body or query params
    let paymentId: string | null = null;
    let notificationType: string | null = null;

    const url = new URL(req.url);
    const queryType = url.searchParams.get("type") ?? url.searchParams.get("topic");
    const queryDataId = url.searchParams.get("data.id") ?? url.searchParams.get("id");

    if (queryType && queryDataId) {
      notificationType = queryType;
      paymentId = queryDataId;
    } else {
      try {
        const body = await req.json();
        notificationType = body.type ?? body.topic;
        paymentId = body.data?.id?.toString() ?? null;
      } catch {
        status = 400;
        return jsonErr(400, "BAD_REQUEST", "Invalid notification payload", requestId);
      }
    }

    if (!paymentId || notificationType !== "payment") {
      return jsonOk({ ignored: true, type: notificationType }, requestId);
    }

    // Fetch payment details from MP API
    const mpRes = await fetch(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      {
        headers: { Authorization: `Bearer ${mpAccessToken}` },
      },
    );

    if (!mpRes.ok) {
      const errText = await mpRes.text();
      console.error(
        JSON.stringify({
          request_id: requestId,
          fn: FN,
          error_code: "MP_FETCH_FAILED",
          mp_status: mpRes.status,
          detail: errText,
        }),
      );
      status = 502;
      errorCode = "MP_FETCH_FAILED";
      return jsonErr(502, "GATEWAY_ERROR", "Failed to fetch payment from MP", requestId);
    }

    const payment = await mpRes.json();
    const mpStatus = payment.status; // approved, pending, cancelled, refunded, rejected, etc.
    const externalReference = payment.external_reference; // our purchase_id

    if (!externalReference) {
      return jsonOk({ ignored: true, reason: "no_external_reference" }, requestId);
    }

    const purchaseId = externalReference;

    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    // Resolve payment method
    const paymentMethod =
      payment.payment_type_id === "account_money"
        ? "mercadopago"
        : payment.payment_type_id ?? "mercadopago";

    // Route based on MP payment status
    if (mpStatus === "approved") {
      // Payment confirmed → pending → paid → fulfilled

      // L2: conditional update
      const { data: updated } = await db
        .from("billing_purchases")
        .update({
          status: "paid",
          payment_method: paymentMethod,
          payment_reference: paymentId,
          updated_at: new Date().toISOString(),
        })
        .eq("id", purchaseId)
        .eq("status", "pending")
        .select("id")
        .maybeSingle();

      // L1: insert billing_event (dedup via metadata mp_payment_id)
      const isNew = await insertEvent(db, purchaseId, "payment_confirmed", {
        mp_payment_id: paymentId,
        mp_status: mpStatus,
        payment_method: paymentMethod,
        amount: payment.transaction_amount,
        currency: payment.currency_id,
        request_id: requestId,
      });

      if (!isNew) {
        return jsonOk({ already_processed: true, mp_payment_id: paymentId }, requestId);
      }

      if (!updated) {
        const { data: purchase } = await db
          .from("billing_purchases")
          .select("status")
          .eq("id", purchaseId)
          .maybeSingle();

        if (!purchase || purchase.status === "fulfilled" || purchase.status === "cancelled") {
          return jsonOk({ processed: true, already_terminal: true }, requestId);
        }
      }

      // L3: fn_fulfill_purchase — paid → fulfilled + credit allocation
      const { error: fulfillErr } = await db.rpc("fn_fulfill_purchase", {
        p_purchase_id: purchaseId,
      });

      if (fulfillErr) {
        const msg = fulfillErr.message ?? "";
        if (!msg.includes("must be in paid status")) {
          console.error(
            JSON.stringify({
              request_id: requestId,
              fn: FN,
              error_code: "FULFILL_FAILED",
              purchase_id: purchaseId,
              detail: msg,
            }),
          );
        }
      }

      await trackAnalytics(db, purchaseId, "billing_payment_confirmed", {
        payment_method: paymentMethod,
        amount: payment.transaction_amount,
        currency: payment.currency_id,
        gateway: "mercadopago",
      });
    } else if (
      mpStatus === "cancelled" ||
      mpStatus === "rejected" ||
      mpStatus === "expired"
    ) {
      await db
        .from("billing_purchases")
        .update({
          status: "cancelled",
          updated_at: new Date().toISOString(),
        })
        .eq("id", purchaseId)
        .eq("status", "pending");

      await insertEvent(db, purchaseId, "cancelled", {
        mp_payment_id: paymentId,
        mp_status: mpStatus,
        reason: payment.status_detail ?? mpStatus,
        request_id: requestId,
      });

      const eventName =
        mpStatus === "expired"
          ? "billing_checkout_expired"
          : "billing_payment_failed";
      await trackAnalytics(db, purchaseId, eventName, {
        mp_status: mpStatus,
        gateway: "mercadopago",
      });
    } else if (mpStatus === "refunded") {
      await insertEvent(db, purchaseId, "refunded", {
        mp_payment_id: paymentId,
        mp_status: mpStatus,
        amount_refunded: payment.transaction_amount_refunded ?? payment.transaction_amount,
        currency: payment.currency_id,
        request_id: requestId,
      });
    }
    // "pending", "in_process", "authorized" — no action needed, wait for final status

    return jsonOk(
      {
        processed: true,
        mp_payment_id: paymentId,
        mp_status: mpStatus,
        purchase_id: purchaseId,
      },
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
