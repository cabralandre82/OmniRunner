import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

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
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));

const { GET, POST } = await import("./route");

function postReq(body: Record<string, unknown>) {
  return new Request("http://localhost/api/gateway-preference", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const mockUser = { id: "user-admin-1" };

describe("GET /api/gateway-preference", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({ data: { user: mockUser } });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
  });

  it("returns default mercadopago when no record", async () => {
    serviceClient.from.mockReturnValueOnce(queryChain({ data: null }));
    const res = await GET();
    const json = await res.json();
    expect(json.preferred_gateway).toBe("mercadopago");
  });

  it("returns stored preference", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { preferred_gateway: "stripe" } }),
    );
    const res = await GET();
    expect((await res.json()).preferred_gateway).toBe("stripe");
  });
});

describe("POST /api/gateway-preference", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({ data: { user: mockUser } });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(postReq({ preferred_gateway: "stripe" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "athlete" } }),
    );
    const res = await POST(postReq({ preferred_gateway: "stripe" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 for invalid gateway", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(postReq({ preferred_gateway: "paypal" }));
    expect(res.status).toBe(400);
  });

  it("updates existing record", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(postReq({ preferred_gateway: "stripe" }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.preferred_gateway).toBe("stripe");
  });

  it("creates new record with profile lookup", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }))   // no existing billing_customers
      .mockReturnValueOnce(queryChain({ data: { display_name: "John", email: "john@x.com" } }))
      .mockReturnValueOnce(queryChain({ data: { name: "Assessoria Top" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(postReq({ preferred_gateway: "mercadopago" }));
    expect(res.status).toBe(200);
  });
});
