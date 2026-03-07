import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import { classifyError } from "../_shared/errors.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";

/**
 * create-checkout-session — Supabase Edge Function
 *
 * Called by the billing portal when admin_master selects a credit package.
 * Creates a billing_purchase (pending) and a Stripe Checkout Session,
 * then returns the hosted checkout URL for redirect.
 *
 * POST /create-checkout-session
 * Body: { product_id, group_id }
 *
 * See DECISAO 049.
 */

const FN = "create-checkout-session";
const SESSION_TTL_SECONDS = 1800; // 30 min

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
      db, user.id,
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
        403, "FORBIDDEN",
        "Only admin_master can purchase credits",
        requestId,
      );
    }

    // ── 4. Look up product ──────────────────────────────────────────────
    const { data: product, error: prodErr } = await db
      .from("billing_products")
      .select("id, name, description, credits_amount, price_cents, currency, is_active")
      .eq("id", product_id)
      .maybeSingle();

    if (prodErr) {
      const classified = classifyError(prodErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    if (!product) {
      status = 404;
      return jsonErr(404, "PRODUCT_NOT_FOUND", "Product not found", requestId);
    }

    if (!product.is_active) {
      status = 400;
      return jsonErr(400, "PRODUCT_INACTIVE", "Product is no longer available", requestId);
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
        payment_method: "stripe_checkout",
        requested_by: user.id,
      })
      .select("id")
      .single();

    if (purchaseErr) {
      const classified = classifyError(purchaseErr);
      status = classified.httpStatus;
      errorCode = classified.code;
      return jsonErr(classified.httpStatus, classified.code, classified.message, requestId);
    }

    // ── 5b. Log billing_event (created) ─────────────────────────────────
    await db.from("billing_events").insert({
      purchase_id: purchase.id,
      event_type: "created",
      actor_id: user.id,
      metadata: {
        product_id: product.id,
        product_name: product.name,
        request_id: requestId,
      },
    });

    // ── 6. Create Stripe Checkout Session ────────────────────────────────
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeKey) {
      status = 500;
      errorCode = "STRIPE_CONFIG_MISSING";
      return jsonErr(500, "INTERNAL", "Payment service not configured", requestId);
    }

    const stripe = new Stripe(stripeKey, {
      apiVersion: "2023-10-16",
      httpClient: Stripe.createFetchHttpClient(),
    });

    const portalUrl = Deno.env.get("PORTAL_URL") ?? "https://portal.omnirunner.app";

    const paymentMethods: Stripe.Checkout.SessionCreateParams.PaymentMethodType[] =
      product.currency === "BRL"
        ? ["card", "boleto", "pix"]
        : ["card"];

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: paymentMethods,
      line_items: [
        {
          price_data: {
            currency: product.currency.toLowerCase(),
            unit_amount: product.price_cents,
            product_data: {
              name: product.name,
              description: product.description || undefined,
            },
          },
          quantity: 1,
        },
      ],
      metadata: {
        purchase_id: purchase.id,
        group_id,
        product_id: product.id,
        request_id: requestId,
      },
      success_url: `${portalUrl}/billing/success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${portalUrl}/billing/cancelled`,
      expires_at: Math.floor(Date.now() / 1000) + SESSION_TTL_SECONDS,
    });

    // ── 7. Update purchase with Stripe reference ────────────────────────
    await db
      .from("billing_purchases")
      .update({
        payment_reference: session.id,
        updated_at: new Date().toISOString(),
      })
      .eq("id", purchase.id);

    // ── 8. Analytics: billing_checkout_started ────────────────────────
    await db.from("product_events").insert({
      user_id: user.id,
      event_name: "billing_checkout_started",
      properties: {
        purchase_id: purchase.id,
        product_id: product.id,
        product_name: product.name,
        credits_amount: product.credits_amount,
        group_id,
        payment_methods: paymentMethods,
      },
    }).then(
      () => {},
      () => {},
    );

    return jsonOk(
      {
        purchase_id: purchase.id,
        checkout_url: session.url,
        session_id: session.id,
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
