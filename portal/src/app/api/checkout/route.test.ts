import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient(TEST_SESSION);

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }),
}));

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/checkout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/checkout", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getSession.mockResolvedValue({
      data: { session: TEST_SESSION },
    });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getSession.mockResolvedValueOnce({
      data: { session: null },
    });
    const res = await POST(req({ product_id: "prod-1" }));
    expect(res.status).toBe(401);
  });

  it("returns 400 when product_id is missing", async () => {
    const res = await POST(req({}));
    expect(res.status).toBe(400);
  });

  it("returns 200 with checkout_url on success (mercadopago default)", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        ok: true,
        checkout_url: "https://mp.com/pay",
        purchase_id: "pur-1",
      }),
    });

    const res = await POST(req({ product_id: "prod-1" }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.checkout_url).toBe("https://mp.com/pay");
    expect(json.purchase_id).toBe("pur-1");

    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("create-checkout-mercadopago"),
      expect.any(Object),
    );
  });

  it("uses stripe function when gateway=stripe", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({
        ok: true,
        checkout_url: "https://stripe.com/pay",
        purchase_id: "pur-2",
      }),
    });

    const res = await POST(req({ product_id: "prod-1", gateway: "stripe" }));
    expect(res.status).toBe(200);

    expect(mockFetch).toHaveBeenCalledWith(
      expect.stringContaining("create-checkout-session"),
      expect.any(Object),
    );
  });

  it("returns 502 when gateway returns non-JSON", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => {
        throw new Error("not json");
      },
      text: async () => "internal error",
    });

    const res = await POST(req({ product_id: "prod-1" }));
    expect(res.status).toBe(502);
    const json = await res.json();
    expect(json.error).toContain("Gateway error");
  });

  it("returns error status when gateway returns error JSON", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 422,
      json: async () => ({ ok: false, message: "Invalid product" }),
    });

    const res = await POST(req({ product_id: "prod-1" }));
    expect(res.status).toBe(422);
    const json = await res.json();
    expect(json.error).toBe("Invalid product");
  });
});
