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

const mockUser = { id: "user-admin-1" };

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/auto-topup", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/auto-topup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({ data: { user: mockUser } });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(403);
  });

  it("updates existing settings", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(
      req({ enabled: true, threshold_tokens: 100 }),
    );
    expect(res.status).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });

  it("creates settings with product_id", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }))  // no existing
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(
      req({ enabled: true, product_id: "prod-1", threshold_tokens: 50 }),
    );
    expect(res.status).toBe(200);
  });

  it("returns 400 when initial setup has no product_id", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }));

    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(400);
    expect((await res.json()).error).toContain("product_id");
  });
});
