import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import {
  requireJson,
  requireFields,
  ValidationError,
} from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";

/**
 * create-checkout-mercadopago — Supabase Edge Function
 *
 * Creates a billing_purchase (pending) and a Mercado Pago Preference,
 * then returns the hosted checkout URL (init_point) for redirect.
 *
 * POST /create-checkout-mercadopago
 * Body: { product_id, group_id }
 */

const FN = "create-checkout-mercadopago";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

  if (req.method === 'GET' && new URL(req.url).pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok', version: '1.0.0' }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const requestId = crypto.randomUUID();
  const elapsed = startTimer();
  let userId: string | null = null;
  let status = 200;
  let errorCode: string | undefined;

  try {
    if (req.method !== "POST") {
      status = 405;
      return jsonErr(405, "METHOD_NOT_ALLOWED", "Use POST", requestId);
    }

    // ── 1. Auth ──────────────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let db: any;
    let user: { id: string; [key: string]: unknown };
    try {
      const auth = await requireUser(req);
      user = auth.user;
      db = auth.db;
      userId = user.id;
    } catch (e) {
      errorCode = "AUTH_ERROR";
      if (e instanceof AuthError) {
        status = e.status;
        return jsonErr(e.status, "AUTH_ERROR", e.message, requestId);
      }
      status = 500;
      return jsonErr(500, "AUTH_ERROR", "Authentication failed", requestId);
    }

    // ── 1b. Rate limit ──────────────────────────────────────────────────
    const rl = await checkRateLimit(
      db,
      user.id,
      { fn: FN, maxRequests: 10, windowSeconds: 60 },
      requestId,
    );
    if (!rl.allowed) {
      status = rl.status!;
      if (status >= 500) errorCode = "RATE_LIMIT_UNAVAILABLE";
      return rl.response!;
    }

    // ── 2. Parse body ───────────────────────────────────────────────────
    // deno-lint-ignore no-explicit-any
    let body: Record<string, any>;
    try {
      body = await requireJson(req);
      requireFields(body, ["product_id", "group_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { product_id, group_id } = body;

    // ── 3. Verify admin_master role ─────────────────────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || membership.role !== "admin_master") {
      status = 403;
      return jsonErr(
        403,
        "FORBIDDEN",
        "Only admin_master can purchase credits",
        requestId,
      );
    }

    // ── 4. Look up product ──────────────────────────────────────────────
    const { data: product, error: prodErr } = await db
      .from("billing_products")
      .select(
        "id, name, description, credits_amount, price_cents, currency, is_active",
      )
      .eq("id", product_id)
      .maybeSingle();

    if (prodErr) {
      const classified = classifyError(prodErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(
        classified.httpStatus,
        classified.code,
        classified.message,
        requestId,
      );
    }

    if (!product) {
      status = 404;
      return jsonErr(404, "PRODUCT_NOT_FOUND", "Product not found", requestId);
    }

    if (!product.is_active) {
      status = 400;
      return jsonErr(
        400,
        "PRODUCT_INACTIVE",
        "Product is no longer available",
        requestId,
      );
    }

    // ── 5. Create billing_purchase (pending) ────────────────────────────
    const { data: purchase, error: purchaseErr } = await db
      .from("billing_purchases")
      .insert({
        group_id,
        product_id: product.id,
        credits_amount: product.credits_amount,
        price_cents: product.price_cents,
        currency: product.currency,
        status: "pending",
        payment_method: "mercadopago",
        requested_by: user.id,
      })
      .select("id")
      .single();

    if (purchaseErr) {
      const classified = classifyError(purchaseErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(
        classified.httpStatus,
        classified.code,
        classified.message,
        requestId,
      );
    }

    await db.from("billing_events").insert({
      purchase_id: purchase.id,
      event_type: "created",
      actor_id: user.id,
      metadata: {
        product_id: product.id,
        product_name: product.name,
        gateway: "mercadopago",
        request_id: requestId,
      },
    });

    // ── 6. Create Mercado Pago Preference ───────────────────────────────
    const mpAccessToken = Deno.env.get("MERCADOPAGO_ACCESS_TOKEN");
    if (!mpAccessToken) {
      status = 500;
      errorCode = "MP_CONFIG_MISSING";
      return jsonErr(
        500,
        "INTERNAL",
        "Payment service not configured",
        requestId,
      );
    }

    const portalUrl =
      Deno.env.get("PORTAL_URL") ?? "https://omnirunner.app";
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

    const unitPrice = product.price_cents / 100;

    const preference = {
      items: [
        {
          id: product.id,
          title: product.name,
          description:
            product.description || `${product.credits_amount} OmniCoins`,
          quantity: 1,
          currency_id: product.currency,
          unit_price: unitPrice,
        },
      ],
      external_reference: purchase.id,
      metadata: {
        purchase_id: purchase.id,
        group_id,
        product_id: product.id,
        request_id: requestId,
      },
      back_urls: {
        success: `${portalUrl}/billing/success?gateway=mercadopago&purchase_id=${purchase.id}`,
        failure: `${portalUrl}/billing/cancelled?gateway=mercadopago`,
        pending: `${portalUrl}/billing/success?gateway=mercadopago&purchase_id=${purchase.id}&status=pending`,
      },
      auto_return: "approved",
      notification_url: `${supabaseUrl}/functions/v1/webhook-mercadopago`,
      statement_descriptor: "OMNIRUNNER",
      expires: true,
      expiration_date_from: new Date().toISOString(),
      expiration_date_to: new Date(
        Date.now() + 30 * 60 * 1000,
      ).toISOString(),
    };

    const mpRes = await fetch(
      "https://api.mercadopago.com/checkout/preferences",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${mpAccessToken}`,
        },
        body: JSON.stringify(preference),
      },
    );

    if (!mpRes.ok) {
      const errBody = await mpRes.text();
      console.error(
        JSON.stringify({
          request_id: requestId,
          fn: FN,
          error_code: "MP_PREFERENCE_FAILED",
          status: mpRes.status,
          detail: errBody,
        }),
      );
      status = 502;
      errorCode = "MP_PREFERENCE_FAILED";
      return jsonErr(
        502,
        "GATEWAY_ERROR",
        "Failed to create payment session",
        requestId,
      );
    }

    const mpData = await mpRes.json();
    const checkoutUrl = mpData.init_point;

    // ── 7. Update purchase with MP reference ────────────────────────────
    await db
      .from("billing_purchases")
      .update({
        payment_reference: mpData.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", purchase.id);

    // ── 8. Analytics ────────────────────────────────────────────────────
    await db
      .from("product_events")
      .insert({
        user_id: user.id,
        event_name: "billing_checkout_started",
        properties: {
          purchase_id: purchase.id,
          product_id: product.id,
          product_name: product.name,
          credits_amount: product.credits_amount,
          group_id,
          gateway: "mercadopago",
        },
      })
      .then(
        () => {},
        () => {},
      );

    return jsonOk(
      {
        purchase_id: purchase.id,
        checkout_url: checkoutUrl,
        preference_id: mpData.id,
      },
      requestId,
    );
  } catch (err) {
    status = 500;
    errorCode = "INTERNAL";
    logError({
      request_id: requestId,
      fn: FN,
      user_id: userId,
      error_code: `INTERNAL: ${(err as Error).message}`,
      duration_ms: elapsed(),
    });
    return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
  } finally {
    if (errorCode) {
      logError({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        error_code: errorCode,
        duration_ms: elapsed(),
      });
    } else {
      logRequest({
        request_id: requestId,
        fn: FN,
        user_id: userId,
        status,
        duration_ms: elapsed(),
      });
    }
  }
});
