import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { requireUser, AuthError } from "../_shared/auth.ts";
import { jsonOk, jsonErr } from "../_shared/http.ts";
import { handleCors } from "../_shared/cors.ts";
import { checkRateLimit } from "../_shared/rate_limit.ts";
import { startTimer, logRequest, logError } from "../_shared/obs.ts";
import { requireJson, requireFields, ValidationError } from "../_shared/validate.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";

/**
 * create-portal-session — Supabase Edge Function
 *
 * Creates a Stripe Customer Portal session so the admin_master can:
 *   - view past invoices / receipts
 *   - update their default payment method (card for auto top-up)
 *
 * If the group doesn't have a Stripe Customer yet, one is created
 * and stored in billing_customers.stripe_customer_id.
 *
 * POST /create-portal-session
 * Body: { group_id }
 * Auth: Bearer JWT (admin_master)
 */

const FN = "create-portal-session";

serve(async (req: Request) => {
  const cors = handleCors(req);
  if (cors) return cors;

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
      requireFields(body, ["group_id"]);
    } catch (e) {
      status = 400;
      if (e instanceof ValidationError) {
        return jsonErr(400, e.code, e.message, requestId);
      }
      return jsonErr(400, "BAD_REQUEST", "Invalid request", requestId);
    }

    const { group_id } = body;

    // ── 3. Verify admin_master role ─────────────────────────────────────
    const { data: membership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", group_id)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || membership.role !== "admin_master") {
      status = 403;
      return jsonErr(403, "FORBIDDEN", "Only admin_master can access billing portal", requestId);
    }

    // ── 4. Stripe client ────────────────────────────────────────────────
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

    // ── 5. Ensure billing_customers + Stripe Customer exist ─────────────
    let { data: customer } = await db
      .from("billing_customers")
      .select("group_id, stripe_customer_id, email, legal_name")
      .eq("group_id", group_id)
      .maybeSingle();

    if (!customer) {
      const { data: profile } = await db
        .from("profiles")
        .select("display_name, email")
        .eq("id", user.id)
        .maybeSingle();

      const { data: group } = await db
        .from("coaching_groups")
        .select("name")
        .eq("id", group_id)
        .maybeSingle();

      const email = profile?.email ?? (user as { email?: string }).email ?? "admin@omnirunner.app";
      const legalName = group?.name ?? profile?.display_name ?? "Assessoria";

      const { data: newCustomer, error: insertErr } = await db
        .from("billing_customers")
        .insert({
          group_id,
          legal_name: legalName,
          email,
        })
        .select("group_id, stripe_customer_id, email, legal_name")
        .single();

      if (insertErr) {
        status = 500;
        errorCode = "BILLING_CUSTOMER_CREATE_FAILED";
        return jsonErr(500, "INTERNAL", "Failed to create billing profile", requestId);
      }
      customer = newCustomer;
    }

    let stripeCustomerId = customer.stripe_customer_id;

    if (!stripeCustomerId) {
      const stripeCustomer = await stripe.customers.create({
        email: customer.email,
        name: customer.legal_name,
        metadata: { group_id, source: "portal" },
      });
      stripeCustomerId = stripeCustomer.id;

      await db
        .from("billing_customers")
        .update({
          stripe_customer_id: stripeCustomerId,
          updated_at: new Date().toISOString(),
        })
        .eq("group_id", group_id);
    }

    // ── 6. Create Billing Portal session ────────────────────────────────
    const portalUrl = Deno.env.get("PORTAL_URL") ?? "https://portal.omnirunner.app";

    const portalSession = await stripe.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: `${portalUrl}/settings`,
    });

    // ── 7. Analytics (fire-and-forget) ──────────────────────────────────
    db.from("product_events")
      .insert({
        user_id: user.id,
        event_name: "billing_portal_opened",
        properties: {
          group_id,
          stripe_customer_id: stripeCustomerId,
          request_id: requestId,
        },
      })
      .then(
        () => {},
        () => {},
      );

    return jsonOk({ portal_url: portalSession.url }, requestId);
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
