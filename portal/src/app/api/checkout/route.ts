import { type NextRequest } from "next/server";

import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { rateLimit } from "@/lib/rate-limit";
import { checkoutSchema } from "@/lib/schemas";
import { withIdempotency } from "@/lib/api/idempotency";
import { apiError, resolveRequestId } from "@/lib/api/errors";
import { logger } from "@/lib/logger";
import { metrics } from "@/lib/metrics";
import { withErrorHandler } from "@/lib/api-handler";

/**
 * Maximum body size for the checkout proxy. Body schema is two short
 * strings; 4 KiB is already 100x headroom but caps probe-style attacks.
 */
const MAX_BODY_BYTES = 4 * 1024;

const CHECKOUT_GATEWAY_TIMEOUT_MS = 15_000;

/**
 * POST /api/checkout (L01-09 hardened)
 *
 * Portal-side proxy that creates a hosted checkout session via the
 * `create-checkout-{session,mercadopago}` Supabase Edge Functions.
 *
 * Defence-in-depth layered on top of the Edge Functions (which already
 * validate every input — see `supabase/functions/create-checkout-*`).
 * The portal layer adds:
 *
 *   1. **Strict body schema** — `product_id` must be a UUID (was: any
 *      non-empty string), `gateway` whitelist, `.strict()` rejects
 *      unknown fields. Closes parameter pollution / probe vectors.
 *
 *   2. **Body size cap** — 4 KiB; protects against proxy-burning
 *      payloads (the Edge Function would also reject, but only after a
 *      cross-region invocation we'd rather not pay for).
 *
 *   3. **Pre-validation of product** — query `billing_products` via the
 *      service-role client to confirm the product exists and is
 *      `is_active=true` BEFORE invoking the Edge Function. Without this
 *      a user can fire 5 requests/min (rate-limit cap) burning Edge +
 *      Stripe API calls each time — even though the Edge Function
 *      eventually rejects with 404. Fail-fast saves real $.
 *
 *   4. **Pre-validation of admin_master role** — query
 *      `coaching_members` to confirm the caller is admin_master of the
 *      cookie-bound group. Edge Function does the same, but failing
 *      fast at the portal layer eliminates burned invocations from
 *      misconfigured CI / scrapers / curious athletes.
 *
 *   5. **Idempotency** — wraps the entire flow with `withIdempotency`
 *      (L18-02). Clients SHOULD send `x-idempotency-key`; double-clicks
 *      replay the cached response (the Stripe/MP session) instead of
 *      creating two `billing_purchases` rows + two payment sessions.
 *      Header is recommended (not required) so existing clients keep
 *      working — the rate limit (5/60s) is the floor protection.
 *
 *   6. **Canonical error envelope** — `apiError`/`apiOk` with
 *      `request_id` propagation (L13-06/L14-05). Edge Function error
 *      shapes are folded into the canonical envelope so callers don't
 *      have to special-case `data.error.code` vs `data.error.message`
 *      vs `data.message`.
 *
 *   7. **Structured metrics** — `checkout.proxy.{validated,blocked,
 *      gateway_called,gateway_error,replayed}` with reason tags for
 *      operability.
 */
// L17-01 — outermost safety-net: throws inesperados (createClient,
// JSON.parse de session, fetch crashes não capturados) viram 500
// INTERNAL_ERROR canônico em vez de stack trace cru.
export const POST = withErrorHandler(_post, "api.checkout.post");

async function _post(request: NextRequest) {
  const requestId = resolveRequestId(request);

  // ── 1. Auth ────────────────────────────────────────────────────────
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return apiError(request, "UNAUTHORIZED", "Authentication required", 401);
  }

  // ── 2. Rate limit (per-user, 5/min) ────────────────────────────────
  const rl = await rateLimit(`checkout:${user.id}`, { maxRequests: 5, windowMs: 60_000 });
  if (!rl.allowed) {
    metrics.increment("checkout.proxy.blocked", { reason: "rate_limit" });
    return apiError(request, "RATE_LIMITED", "Too many checkout requests", 429, {
      headers: { "Retry-After": "60" },
    });
  }

  // ── 3. Group cookie ────────────────────────────────────────────────
  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    metrics.increment("checkout.proxy.blocked", { reason: "no_group" });
    return apiError(request, "BAD_REQUEST", "No group selected", 400);
  }

  // ── 4. Body — bounded read ─────────────────────────────────────────
  const declaredLen = request.headers.get("content-length");
  if (declaredLen) {
    const n = Number.parseInt(declaredLen, 10);
    if (Number.isFinite(n) && n > MAX_BODY_BYTES) {
      metrics.increment("checkout.proxy.blocked", { reason: "body_too_large" });
      return apiError(
        request,
        "PAYLOAD_TOO_LARGE",
        `Body exceeds ${MAX_BODY_BYTES} bytes`,
        413,
      );
    }
  }
  const rawBody = await request.text();
  if (Buffer.byteLength(rawBody, "utf8") > MAX_BODY_BYTES) {
    metrics.increment("checkout.proxy.blocked", { reason: "body_too_large" });
    return apiError(
      request,
      "PAYLOAD_TOO_LARGE",
      `Body exceeds ${MAX_BODY_BYTES} bytes`,
      413,
    );
  }

  // ── 5. Schema validation (strict UUID + .strict) ───────────────────
  let parsedBody: unknown;
  try {
    parsedBody = JSON.parse(rawBody);
  } catch {
    metrics.increment("checkout.proxy.blocked", { reason: "invalid_json" });
    return apiError(request, "VALIDATION_FAILED", "Body is not valid JSON", 400);
  }
  const parsed = checkoutSchema.safeParse(parsedBody);
  if (!parsed.success) {
    metrics.increment("checkout.proxy.blocked", { reason: "schema" });
    return apiError(
      request,
      "VALIDATION_FAILED",
      parsed.error.issues[0]?.message ?? "Invalid request",
      400,
      { details: { issues: parsed.error.issues.map((i) => ({ path: i.path, message: i.message })) } },
    );
  }
  const { product_id: productId, gateway } = parsed.data;

  // ── 6. Pre-validate role (admin_master of the cookie-bound group) ──
  const service = createServiceClient();
  const { data: membership, error: memberErr } = await service
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (memberErr) {
    logger.error("checkout.proxy.membership_lookup_failed", memberErr, {
      request_id: requestId,
      user_id: user.id,
      group_id: groupId,
    });
    metrics.increment("checkout.proxy.blocked", { reason: "membership_error" });
    return apiError(request, "INTERNAL_ERROR", "Membership check failed", 500);
  }
  if (!membership || membership.role !== "admin_master") {
    metrics.increment("checkout.proxy.blocked", { reason: "not_admin_master" });
    return apiError(
      request,
      "FORBIDDEN",
      "Only admin_master can purchase credits",
      403,
    );
  }

  // ── 7. Pre-validate product (exists + is_active) ───────────────────
  const { data: product, error: productErr } = await service
    .from("billing_products")
    .select("id, is_active, currency, price_cents")
    .eq("id", productId)
    .maybeSingle();
  if (productErr) {
    logger.error("checkout.proxy.product_lookup_failed", productErr, {
      request_id: requestId,
      product_id: productId,
    });
    metrics.increment("checkout.proxy.blocked", { reason: "product_lookup_error" });
    return apiError(request, "INTERNAL_ERROR", "Product lookup failed", 500);
  }
  if (!product) {
    metrics.increment("checkout.proxy.blocked", { reason: "product_not_found" });
    return apiError(request, "NOT_FOUND", "Product not available", 404);
  }
  if (!product.is_active) {
    metrics.increment("checkout.proxy.blocked", { reason: "product_inactive" });
    return apiError(request, "GONE", "Product is no longer available", 410);
  }

  metrics.increment("checkout.proxy.validated", { gateway });

  // ── 8. Idempotent dispatch to Edge Function ────────────────────────
  return withIdempotency({
    request,
    namespace: "checkout.proxy",
    actorId: user.id,
    requestBody: { product_id: productId, group_id: groupId, gateway },
    handler: async () => {
      const { data: { session } } = await supabase.auth.getSession();
      const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
      const fnName =
        gateway === "stripe" ? "create-checkout-session" : "create-checkout-mercadopago";

      let edgeRes: Response;
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), CHECKOUT_GATEWAY_TIMEOUT_MS);
      try {
        edgeRes = await fetch(`${supabaseUrl}/functions/v1/${fnName}`, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${session?.access_token ?? ""}`,
            ...(requestId ? { "x-request-id": requestId } : {}),
          },
          body: JSON.stringify({ product_id: productId, group_id: groupId }),
          signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        const aborted = (err as Error)?.name === "AbortError";
        logger.error("checkout.proxy.gateway_unreachable", err, {
          request_id: requestId,
          gateway,
          aborted,
        });
        metrics.increment("checkout.proxy.gateway_error", {
          gateway,
          reason: aborted ? "timeout" : "network",
        });
        return {
          status: 504,
          body: {
            ok: false,
            error: {
              code: aborted ? "GATEWAY_TIMEOUT" : "GATEWAY_UNREACHABLE",
              message: aborted
                ? `Edge function did not respond within ${CHECKOUT_GATEWAY_TIMEOUT_MS}ms`
                : "Could not reach payment gateway",
              request_id: requestId,
            },
          },
        };
      } finally {
        clearTimeout(timer);
      }

      let edgeData: Record<string, unknown> | null;
      try {
        edgeData = (await edgeRes.json()) as Record<string, unknown>;
      } catch {
        const text = await edgeRes.text().catch(() => "");
        logger.error("checkout.proxy.gateway_non_json", undefined, {
          request_id: requestId,
          gateway,
          status: edgeRes.status,
          excerpt: text.slice(0, 200),
        });
        metrics.increment("checkout.proxy.gateway_error", { gateway, reason: "non_json" });
        return {
          status: 502,
          body: {
            ok: false,
            error: {
              code: "GATEWAY_BAD_RESPONSE",
              message: `Gateway error (${edgeRes.status}): ${text || "empty response"}`,
              request_id: requestId,
            },
          },
        };
      }

      if (!edgeRes.ok || edgeData?.ok === false) {
        const errObj = edgeData?.error as
          | { code?: string; message?: string }
          | undefined;
        logger.warn("checkout.proxy.gateway_error", {
          request_id: requestId,
          gateway,
          status: edgeRes.status,
          edge_code: errObj?.code,
        });
        metrics.increment("checkout.proxy.gateway_error", {
          gateway,
          reason: errObj?.code ?? `http_${edgeRes.status}`,
        });
        return {
          status: edgeRes.status >= 400 ? edgeRes.status : 502,
          body: {
            ok: false,
            error: {
              code: errObj?.code ?? "GATEWAY_ERROR",
              message:
                errObj?.message ??
                (typeof edgeData?.message === "string"
                  ? (edgeData.message as string)
                  : `Checkout failed (${edgeRes.status})`),
              request_id: requestId,
            },
          },
        };
      }

      metrics.increment("checkout.proxy.gateway_called", { gateway });
      return {
        status: 200,
        body: {
          ok: true,
          data: {
            checkout_url: edgeData.checkout_url,
            purchase_id: edgeData.purchase_id,
            gateway,
          },
        },
      };
    },
  });
}
