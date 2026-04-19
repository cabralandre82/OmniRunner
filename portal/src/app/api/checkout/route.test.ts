import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, queryChain, makeMockClient } from "@/test/api-helpers";

const VALID_PRODUCT_ID = "550e8400-e29b-41d4-a716-446655440000";
const VALID_IDEMPOTENCY_KEY = "550e8400-e29b-41d4-a716-446655440001";

const authClient = makeMockClient(TEST_SESSION);
const serviceClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => serviceClient,
}));
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockResolvedValue({ allowed: true, remaining: 10 }),
}));

const loggerMocks = vi.hoisted(() => ({
  info: vi.fn(),
  warn: vi.fn(),
  error: vi.fn(),
}));
vi.mock("@/lib/logger", () => ({ logger: loggerMocks }));

const metricsIncrementMock = vi.hoisted(() => vi.fn());
vi.mock("@/lib/metrics", () => ({
  metrics: { increment: metricsIncrementMock },
}));

// Bypass the idempotency wrapper's RPC dance: just run the handler and
// build a NextResponse from its `{ status, body }`. All idempotency-
// specific behaviour (replay, mismatch, missing header → 400 when
// required) is tested separately in `lib/api/idempotency.test.ts`. Here
// we focus on the proxy logic.
vi.mock("@/lib/api/idempotency", () => ({
  withIdempotency: vi.fn(async (opts: { handler: () => Promise<{ status: number; body: unknown }> }) => {
    const result = await opts.handler();
    const { NextResponse } = await import("next/server");
    return NextResponse.json(result.body, { status: result.status });
  }),
}));

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

const { POST } = await import("./route");
const { rateLimit } = await import("@/lib/rate-limit");
const { withIdempotency } = await import("@/lib/api/idempotency");

const PRODUCT_ROW = {
  id: VALID_PRODUCT_ID,
  is_active: true,
  currency: "BRL",
  price_cents: 5000,
};

const ADMIN_MEMBER = { role: "admin_master" };

function req(body: unknown, headers: Record<string, string> = {}) {
  return new Request("http://localhost/api/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

/** Wire up the service client `from()` calls for the happy path:
 *  1st call: coaching_members lookup → admin_master
 *  2nd call: billing_products lookup → active product
 */
function mockHappyPathServiceCalls(overrides?: {
  membership?: { data: unknown; error?: unknown };
  product?: { data: unknown; error?: unknown };
}) {
  const membership = overrides?.membership ?? { data: ADMIN_MEMBER, error: null };
  const product = overrides?.product ?? { data: PRODUCT_ROW, error: null };
  serviceClient.from.mockReset();
  serviceClient.from
    .mockReturnValueOnce(queryChain(membership))
    .mockReturnValueOnce(queryChain(product));
}

beforeEach(() => {
  vi.clearAllMocks();
  authClient.auth.getUser.mockResolvedValue({
    data: { user: TEST_SESSION.user },
  });
  authClient.auth.getSession.mockResolvedValue({
    data: { session: TEST_SESSION },
  });
  (rateLimit as unknown as ReturnType<typeof vi.fn>).mockResolvedValue({
    allowed: true,
    remaining: 10,
  });
  mockHappyPathServiceCalls();
  process.env.NEXT_PUBLIC_SUPABASE_URL = "http://localhost:54321";
});

describe("POST /api/checkout (L01-09 hardened)", () => {
  // ── Auth / rate limit / cookie ──────────────────────────────────────

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error.code).toBe("UNAUTHORIZED");
  });

  it("returns 429 when rate limit exceeded", async () => {
    (rateLimit as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      allowed: false,
      remaining: 0,
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("60");
    const body = await res.json();
    expect(body.error.code).toBe("RATE_LIMITED");
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "rate_limit",
    });
  });

  // ── Schema hardening ────────────────────────────────────────────────

  it("returns 400 VALIDATION_FAILED when product_id is missing", async () => {
    const res = await POST(req({}));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "schema",
    });
  });

  it("returns 400 when product_id is not a UUID (L01-09 tightening)", async () => {
    const res = await POST(req({ product_id: "prod-1" }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.details.issues[0].message).toMatch(/UUID/);
  });

  it("returns 400 when body has unknown extra fields (.strict)", async () => {
    const res = await POST(
      req({ product_id: VALID_PRODUCT_ID, malicious_field: "<script>" }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
  });

  it("returns 400 when body is not valid JSON", async () => {
    const res = await POST(req("{not-json"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "invalid_json",
    });
  });

  it("returns 413 when body exceeds 4 KiB", async () => {
    const huge = "x".repeat(5 * 1024);
    const res = await POST(req({ product_id: VALID_PRODUCT_ID, _padding: huge }));
    expect(res.status).toBe(413);
    const body = await res.json();
    expect(body.error.code).toBe("PAYLOAD_TOO_LARGE");
  });

  // ── Cookie / context ────────────────────────────────────────────────

  it("returns 400 when group cookie missing", async () => {
    vi.doMock("next/headers", () => ({
      cookies: () => ({ get: () => undefined }),
    }));
    vi.resetModules();
    try {
      const { POST: P2 } = await import("./route");
      const res = await P2(req({ product_id: VALID_PRODUCT_ID }));
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error.code).toBe("BAD_REQUEST");
    } finally {
      vi.doUnmock("next/headers");
      vi.resetModules();
    }
  });

  // ── Pre-validation: role ────────────────────────────────────────────

  it("returns 403 when caller is not admin_master of the cookie-bound group", async () => {
    mockHappyPathServiceCalls({
      membership: { data: { role: "professor" }, error: null },
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error.code).toBe("FORBIDDEN");
    expect(mockFetch).not.toHaveBeenCalled();
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "not_admin_master",
    });
  });

  it("returns 403 when caller has no membership in the cookie-bound group", async () => {
    mockHappyPathServiceCalls({
      membership: { data: null, error: null },
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(403);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it("returns 500 when membership lookup errors", async () => {
    mockHappyPathServiceCalls({
      membership: { data: null, error: { message: "boom" } },
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(500);
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "membership_error",
    });
  });

  // ── Pre-validation: product ─────────────────────────────────────────

  it("returns 404 when product does not exist (no Edge call)", async () => {
    mockHappyPathServiceCalls({ product: { data: null, error: null } });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error.code).toBe("NOT_FOUND");
    expect(mockFetch).not.toHaveBeenCalled();
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "product_not_found",
    });
  });

  it("returns 410 GONE when product is inactive (no Edge call)", async () => {
    mockHappyPathServiceCalls({
      product: { data: { ...PRODUCT_ROW, is_active: false }, error: null },
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(410);
    const body = await res.json();
    expect(body.error.code).toBe("GONE");
    expect(mockFetch).not.toHaveBeenCalled();
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "product_inactive",
    });
  });

  it("returns 500 when product lookup errors", async () => {
    mockHappyPathServiceCalls({
      product: { data: null, error: { message: "kaboom" } },
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(500);
    expect(metricsIncrementMock).toHaveBeenCalledWith("checkout.proxy.blocked", {
      reason: "product_lookup_error",
    });
  });

  // ── Happy paths ─────────────────────────────────────────────────────

  it("returns 200 on successful MercadoPago checkout (default gateway)", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        ok: true,
        checkout_url: "https://mp.com/pay",
        purchase_id: "pur-1",
      }),
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.checkout_url).toBe("https://mp.com/pay");
    expect(body.data.purchase_id).toBe("pur-1");
    expect(body.data.gateway).toBe("mercadopago");
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("create-checkout-mercadopago"),
      expect.any(Object),
    );
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "checkout.proxy.gateway_called",
      { gateway: "mercadopago" },
    );
  });

  it("uses Stripe Edge function when gateway=stripe", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        ok: true,
        checkout_url: "https://stripe.com/pay",
        purchase_id: "pur-2",
      }),
    });
    const res = await POST(
      req({ product_id: VALID_PRODUCT_ID, gateway: "stripe" }),
    );
    expect(res.status).toBe(200);
    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("create-checkout-session"),
      expect.any(Object),
    );
    const body = await res.json();
    expect(body.data.gateway).toBe("stripe");
  });

  it("propagates x-request-id header to Edge function", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, checkout_url: "u", purchase_id: "p" }),
    });
    await POST(
      req({ product_id: VALID_PRODUCT_ID }, { "x-request-id": "req-trace-123" }),
    );
    const callHeaders = mockFetch.mock.calls[0][1].headers as Record<string, string>;
    expect(callHeaders["x-request-id"]).toBe("req-trace-123");
  });

  // ── Idempotency wiring ──────────────────────────────────────────────

  it("dispatches through withIdempotency with correct namespace + actor + body", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, checkout_url: "u", purchase_id: "p" }),
    });
    await POST(
      req(
        { product_id: VALID_PRODUCT_ID, gateway: "stripe" },
        { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
      ),
    );
    expect(withIdempotency).toHaveBeenCalledWith(
      expect.objectContaining({
        namespace: "checkout.proxy",
        actorId: TEST_SESSION.user.id,
        requestBody: {
          product_id: VALID_PRODUCT_ID,
          group_id: "group-1",
          gateway: "stripe",
        },
      }),
    );
  });

  // ── Edge function failure modes ─────────────────────────────────────

  it("returns 504 GATEWAY_TIMEOUT when Edge function aborts", async () => {
    mockFetch.mockImplementationOnce(() =>
      Promise.reject(Object.assign(new Error("aborted"), { name: "AbortError" })),
    );
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(504);
    const body = await res.json();
    expect(body.error.code).toBe("GATEWAY_TIMEOUT");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "checkout.proxy.gateway_error",
      { gateway: "mercadopago", reason: "timeout" },
    );
  });

  it("returns 504 GATEWAY_UNREACHABLE when fetch fails (network)", async () => {
    mockFetch.mockRejectedValueOnce(new Error("ECONNREFUSED"));
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(504);
    const body = await res.json();
    expect(body.error.code).toBe("GATEWAY_UNREACHABLE");
    expect(metricsIncrementMock).toHaveBeenCalledWith(
      "checkout.proxy.gateway_error",
      { gateway: "mercadopago", reason: "network" },
    );
  });

  it("returns 502 GATEWAY_BAD_RESPONSE when Edge function returns non-JSON", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => {
        throw new Error("not json");
      },
      text: async () => "internal error",
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(502);
    const body = await res.json();
    expect(body.error.code).toBe("GATEWAY_BAD_RESPONSE");
    expect(body.error.message).toContain("internal error");
  });

  it("propagates Edge function 4xx error envelope ({error:{code,message}})", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      json: async () => ({
        ok: false,
        error: { code: "PRODUCT_INACTIVE", message: "Product is no longer available" },
      }),
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(422);
    const body = await res.json();
    expect(body.error.code).toBe("PRODUCT_INACTIVE");
    expect(body.error.message).toBe("Product is no longer available");
  });

  it("falls back to data.message when Edge function uses legacy shape", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      json: async () => ({ ok: false, message: "Something broke" }),
    });
    const res = await POST(req({ product_id: VALID_PRODUCT_ID }));
    expect(res.status).toBe(422);
    const body = await res.json();
    expect(body.error.message).toBe("Something broke");
  });
});
