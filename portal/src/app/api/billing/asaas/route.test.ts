import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient();
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

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

const { POST } = await import("./route");

function makeReq(body: Record<string, unknown>) {
  return new Request("http://localhost/api/billing/asaas", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }) as import("next/server").NextRequest;
}

function mockStaff(role = "admin_master") {
  serviceClient.from.mockReturnValueOnce(queryChain({ data: { role } }));
}

describe("POST /api/billing/asaas", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
    authClient.auth.getSession.mockResolvedValue({
      data: { session: { access_token: "tok-123" } },
    });
  });

  it("returns 401 when unauthenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(makeReq({ action: "test_connection" }));
    expect(res.status).toBe(401);
  });

  it("returns 400 when action missing", async () => {
    const res = await POST(makeReq({}));
    expect(res.status).toBe(400);
  });

  it("returns 403 for non-staff user", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "athlete" } }),
    );
    const res = await POST(makeReq({ action: "disconnect" }));
    expect(res.status).toBe(403);
  });

  it("save_config delegates to fn_ppc_save_api_key RPC (L01-17)", async () => {
    mockStaff();
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: { rotated: false, secret_id: "uuid" }, error: null }),
    );
    const res = await POST(
      makeReq({
        action: "save_config",
        api_key: "test-key",
        environment: "sandbox",
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(serviceClient.rpc).toHaveBeenCalledWith(
      "fn_ppc_save_api_key",
      expect.objectContaining({
        p_group_id: "group-1",
        p_api_key: "test-key",
        p_environment: "sandbox",
      }),
    );
  });

  it("save_config requires api_key", async () => {
    mockStaff();
    const res = await POST(makeReq({ action: "save_config" }));
    expect(res.status).toBe(400);
  });

  it("disconnect sets is_active to false", async () => {
    mockStaff();
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: null }),
    );
    const res = await POST(makeReq({ action: "disconnect" }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  it("test_connection forwards to edge function", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, connected: true }),
    });
    const res = await POST(
      makeReq({
        action: "test_connection",
        api_key: "k",
        environment: "sandbox",
      }),
    );
    expect(res.status).toBe(200);
    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url] = mockFetch.mock.calls[0];
    expect(url).toContain("/functions/v1/asaas-sync");
  });

  it("setup_webhook forwards to edge function", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, webhook_configured: true }),
    });
    const res = await POST(makeReq({ action: "setup_webhook" }));
    expect(res.status).toBe(200);
  });

  it("create_customer forwards to edge function", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, asaas_customer_id: "cus_123" }),
    });
    const res = await POST(
      makeReq({
        action: "create_customer",
        athlete_user_id: "u1",
        name: "João",
        cpf: "111.222.333-44",
        email: "j@test.com",
      }),
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.asaas_customer_id).toBe("cus_123");
  });

  it("create_subscription forwards to edge function", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, asaas_subscription_id: "sub_456" }),
    });
    const res = await POST(
      makeReq({
        action: "create_subscription",
        subscription_id: "s1",
        asaas_customer_id: "cus_123",
        value: 150,
        next_due_date: "2026-04-01",
      }),
    );
    expect(res.status).toBe(200);
  });

  it("cancel_subscription forwards to edge function", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, cancelled: true }),
    });
    const res = await POST(
      makeReq({ action: "cancel_subscription", subscription_id: "s1" }),
    );
    expect(res.status).toBe(200);
  });

  it("returns 400 for unknown action", async () => {
    mockStaff();
    const res = await POST(makeReq({ action: "explode" }));
    expect(res.status).toBe(400);
  });

  it("returns 401 when session expired on edge call", async () => {
    mockStaff();
    authClient.auth.getSession.mockResolvedValueOnce({
      data: { session: null },
    });
    const res = await POST(makeReq({ action: "setup_webhook" }));
    expect(res.status).toBe(401);
  });

  it("handles edge function error gracefully", async () => {
    mockStaff();
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 502,
      json: async () => ({ error: "Asaas unavailable" }),
    });
    const res = await POST(
      makeReq({ action: "test_connection", api_key: "k", environment: "sandbox" }),
    );
    expect(res.status).toBe(502);
  });

  it("disconnect returns 500 on DB error", async () => {
    mockStaff();
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "DB down" } }),
    );
    const res = await POST(makeReq({ action: "disconnect" }));
    expect(res.status).toBe(500);
  });
});
