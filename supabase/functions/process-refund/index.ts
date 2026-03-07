import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";

/**
 * process-refund — Supabase Edge Function
 *
 * Executes an approved refund request:
 *   1. Validates the refund request is in 'approved' status
 *   2. Verifies the purchase is fulfilled and has a payment_reference
 *   3. Checks inventory has enough credits to debit (RF-1)
 *   4. Calls Stripe Refunds API (full or partial)
 *   5. Debits coaching_token_inventory via decrement_token_inventory RPC
 *   6. Updates billing_purchases.status → 'refunded' (full) or keeps 'fulfilled'
 *   7. Updates billing_refund_requests.status → 'processed'
 *   8. Inserts billing_event + analytics
 *
 * Auth: service-role key only (platform team operation).
 *
 * POST /process-refund
 * Headers: Authorization: Bearer <service_role_key>
 * Body: { refund_request_id }
 *
 * See DECISAO 051.
 */

const FN = "process-refund";

// deno-lint-ignore no-explicit-any
type DB = any;

interface RefundRequest {
  id: string;
  purchase_id: string;
  group_id: string;
  status: string;
  refund_type: string;
  amount_cents: number | null;
  credits_to_debit: number | null;
}

interface Purchase {
  id: string;
  group_id: string;
  credits_amount: number;
  price_cents: number;
  currency: string;
  status: string;
  payment_reference: string | null;
}

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

    // ── 1. Environment ────────────────────────────────────────────────────
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey =
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SERVICE_ROLE_KEY");
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");

    if (!supabaseUrl || !serviceKey || !stripeKey) {
      status = 500;
      errorCode = "CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Server misconfiguration", requestId);
    }

    // ── 2. Auth (service-role only) ───────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace(/^Bearer\s+/i, "").trim();
    if (token !== serviceKey) {
      status = 401;
      errorCode = "UNAUTHORIZED";
      return jsonErr(401, "UNAUTHORIZED", "Service role key required", requestId);
    }

    // ── 3. Parse body ─────────────────────────────────────────────────────
    let body: Record<string, unknown>;
    try {
      const text = await req.text();
      body = text.trim() ? JSON.parse(text) : {};
    } catch {
      status = 400;
      return jsonErr(400, "BAD_REQUEST", "Invalid JSON", requestId);
    }

    const refundRequestId = body.refund_request_id;
    if (!refundRequestId || typeof refundRequestId !== "string") {
      status = 400;
      return jsonErr(400, "MISSING_FIELDS", "refund_request_id is required", requestId);
    }

    // ── 4. DB + Stripe clients ────────────────────────────────────────────
    const db = createClient(supabaseUrl, serviceKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });

    const stripe = new Stripe(stripeKey, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    // ── 5. Load and validate refund request ───────────────────────────────
    const { data: refundReq, error: rrErr } = await db
      .from("billing_refund_requests")
      .select("id, purchase_id, group_id, status, refund_type, amount_cents, credits_to_debit")
      .eq("id", refundRequestId)
      .maybeSingle();

    if (rrErr) throw rrErr;

    if (!refundReq) {
      status = 404;
      return jsonErr(404, "NOT_FOUND", "Refund request not found", requestId);
    }

    const rr = refundReq as RefundRequest;

    if (rr.status !== "approved") {
      status = 409;
      return jsonErr(
        409, "INVALID_STATUS",
        `Refund request must be approved, got: ${rr.status}`,
        requestId,
      );
    }

    // ── 6. Load and validate purchase ─────────────────────────────────────
    const { data: purchase, error: pErr } = await db
      .from("billing_purchases")
      .select("id, group_id, credits_amount, price_cents, currency, status, payment_reference")
      .eq("id", rr.purchase_id)
      .maybeSingle();

    if (pErr) throw pErr;

    if (!purchase) {
      status = 404;
      return jsonErr(404, "PURCHASE_NOT_FOUND", "Linked purchase not found", requestId);
    }

    const p = purchase as Purchase;

    if (p.status !== "fulfilled") {
      status = 409;
      return jsonErr(
        409, "PURCHASE_NOT_FULFILLED",
        `Purchase must be fulfilled for refund, got: ${p.status}`,
        requestId,
      );
    }

    if (!p.payment_reference) {
      status = 400;
      return jsonErr(
        400, "NO_PAYMENT_REFERENCE",
        "Purchase has no Stripe payment reference",
        requestId,
      );
    }

    // ── 7. Calculate credits to debit ─────────────────────────────────────
    let creditsToDebit: number;
    let refundAmountCents: number;

    if (rr.refund_type === "full") {
      creditsToDebit = p.credits_amount;
      refundAmountCents = p.price_cents;
    } else {
      refundAmountCents = rr.amount_cents ?? p.price_cents;
      creditsToDebit = rr.credits_to_debit ??
        Math.floor(p.credits_amount * refundAmountCents / p.price_cents);
    }

    // ── 8. Check inventory (RF-1: never negative) ─────────────────────────
    const { data: inventory } = await db
      .from("coaching_token_inventory")
      .select("available_tokens")
      .eq("group_id", rr.group_id)
      .maybeSingle();

    const balance = inventory?.available_tokens ?? 0;

    if (balance < creditsToDebit) {
      status = 409;
      errorCode = "INSUFFICIENT_CREDITS";
      return jsonErr(
        409, "INSUFFICIENT_CREDITS",
        `Cannot debit ${creditsToDebit} credits, only ${balance} available (RF-1)`,
        requestId,
        { balance, credits_to_debit: creditsToDebit },
      );
    }

    // ── 9. Execute Stripe Refund ──────────────────────────────────────────
    let stripeRefund: Stripe.Refund;
    try {
      // deno-lint-ignore no-explicit-any
      const refundParams: any = {
        payment_intent: p.payment_reference,
        metadata: {
          refund_request_id: rr.id,
          purchase_id: p.id,
          group_id: rr.group_id,
          credits_debited: creditsToDebit,
          request_id: requestId,
        },
      };

      if (rr.refund_type === "partial") {
        refundParams.amount = refundAmountCents;
      }

      stripeRefund = await stripe.refunds.create(refundParams);
    } catch (stripeErr: unknown) {
      const msg = stripeErr instanceof Error ? stripeErr.message : String(stripeErr);
      status = 502;
      errorCode = "STRIPE_REFUND_FAILED";
      logError({
        request_id: requestId,
        fn: FN,
        user_id: null,
        error_code: `STRIPE_REFUND_FAILED: ${msg}`,
        duration_ms: elapsed(),
      });
      return jsonErr(502, "STRIPE_REFUND_FAILED", msg, requestId);
    }

    // ── 10. Debit credits from inventory ──────────────────────────────────
    if (creditsToDebit > 0) {
      const { error: debitErr } = await db.rpc("decrement_token_inventory", {
        p_group_id: rr.group_id,
        p_amount: creditsToDebit,
      });

      if (debitErr) {
        logError({
          request_id: requestId,
          fn: FN,
          user_id: null,
          error_code: `DEBIT_FAILED: ${debitErr.message}`,
          duration_ms: elapsed(),
        });
        // Stripe refund already issued — log critical for manual reconciliation
        return jsonErr(
          500, "DEBIT_FAILED",
          "Stripe refund succeeded but credit debit failed. Manual reconciliation required.",
          requestId,
          {
            stripe_refund_id: stripeRefund.id,
            credits_to_debit: creditsToDebit,
            group_id: rr.group_id,
          },
        );
      }
    }

    // ── 11. Update purchase status ────────────────────────────────────────
    if (rr.refund_type === "full") {
      await db
        .from("billing_purchases")
        .update({
          status: "refunded",
          updated_at: new Date().toISOString(),
        })
        .eq("id", p.id);
    }

    // ── 12. Update refund request → processed ─────────────────────────────
    await db
      .from("billing_refund_requests")
      .update({
        status: "processed",
        credits_to_debit: creditsToDebit,
        processed_at: new Date().toISOString(),
      })
      .eq("id", rr.id);

    // ── 13. Insert billing_event ──────────────────────────────────────────
    await db.from("billing_events").insert({
      purchase_id: p.id,
      event_type: "refunded",
      metadata: {
        refund_request_id: rr.id,
        stripe_refund_id: stripeRefund.id,
        refund_type: rr.refund_type,
        amount_refunded_cents: rr.refund_type === "full" ? p.price_cents : refundAmountCents,
        credits_debited: creditsToDebit,
        stripe_refund_status: stripeRefund.status,
        request_id: requestId,
      },
    });

    // ── 14. Analytics (fire-and-forget) ───────────────────────────────────
    db.from("product_events")
      .insert({
        user_id: null,
        event_name: "billing_refund_processed",
        properties: {
          refund_request_id: rr.id,
          purchase_id: p.id,
          group_id: rr.group_id,
          refund_type: rr.refund_type,
          amount_refunded_cents: rr.refund_type === "full" ? p.price_cents : refundAmountCents,
          credits_debited: creditsToDebit,
          stripe_refund_id: stripeRefund.id,
        },
      })
      .then(
        () => {},
        () => {},
      );

    return jsonOk(
      {
        refund_request_id: rr.id,
        purchase_id: p.id,
        stripe_refund_id: stripeRefund.id,
        stripe_refund_status: stripeRefund.status,
        refund_type: rr.refund_type,
        amount_refunded_cents: rr.refund_type === "full" ? p.price_cents : refundAmountCents,
        credits_debited: creditsToDebit,
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
