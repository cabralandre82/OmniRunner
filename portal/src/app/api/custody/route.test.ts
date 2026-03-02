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
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));
vi.mock("@/lib/custody", () => ({
  getCustodyAccount: vi.fn().mockResolvedValue({
    id: "acc-1",
    group_id: "group-1",
    total_deposited_usd: 5000,
    total_committed: 2000,
    total_settled_usd: 500,
    is_blocked: false,
    available: 3000,
  }),
  getOrCreateCustodyAccount: vi.fn().mockResolvedValue({ id: "acc-1" }),
  createCustodyDeposit: vi.fn().mockResolvedValue({
    deposit: { id: "dep-1", amount_usd: 1000, status: "pending" },
  }),
  confirmDeposit: vi.fn().mockResolvedValue(undefined),
}));

const { GET, POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/custody", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
    },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

function mockAdminCheck() {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: { role: "admin_master" } }),
  );
}

describe("Custody API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
  });

  describe("GET", () => {
    it("returns custody account", async () => {
      mockAdminCheck();
      const res = await GET();
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.account).toBeDefined();
      expect(body.account.available).toBe(3000);
    });

    it("returns 401 when not authenticated", async () => {
      authClient.auth.getUser.mockResolvedValueOnce({
        data: { user: null },
      });
      const res = await GET();
      expect(res.status).toBe(401);
    });
  });

  describe("POST (deposit)", () => {
    it("creates deposit for valid input", async () => {
      mockAdminCheck();
      const res = await POST(req({ amount_usd: 1000, gateway: "stripe" }));
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.deposit).toBeDefined();
    });

    it("returns 400 for amount below minimum", async () => {
      mockAdminCheck();
      const res = await POST(req({ amount_usd: 5, gateway: "stripe" }));
      expect(res.status).toBe(400);
    });

    it("returns 400 for invalid gateway", async () => {
      mockAdminCheck();
      const res = await POST(req({ amount_usd: 1000, gateway: "paypal" }));
      expect(res.status).toBe(400);
    });
  });

  describe("POST (confirm)", () => {
    it("confirms deposit", async () => {
      mockAdminCheck();
      const res = await POST(
        req({ deposit_id: "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4" }),
      );
      expect(res.status).toBe(200);
    });
  });
});
