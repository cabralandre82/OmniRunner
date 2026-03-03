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

const mockCreateSwapOffer = vi.fn();
const mockAcceptSwapOffer = vi.fn();
const mockGetOpenSwapOffers = vi.fn();
const mockCancelSwapOffer = vi.fn();

vi.mock("@/lib/swap", () => ({
  createSwapOffer: (...args: unknown[]) => mockCreateSwapOffer(...args),
  acceptSwapOffer: (...args: unknown[]) => mockAcceptSwapOffer(...args),
  getOpenSwapOffers: (...args: unknown[]) => mockGetOpenSwapOffers(...args),
  cancelSwapOffer: (...args: unknown[]) => mockCancelSwapOffer(...args),
}));

const { GET, POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/swap", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
    },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

function getReq() {
  return new Request("http://localhost/api/swap", {
    headers: { "x-forwarded-for": "127.0.0.1" },
  }) as unknown as import("next/server").NextRequest;
}

function mockAdminCheck() {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: { role: "admin_master" } }),
  );
}

describe("Swap API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
  });

  describe("GET", () => {
    it("returns open swap offers", async () => {
      mockAdminCheck();
      mockGetOpenSwapOffers.mockResolvedValue([
        { id: "o1", amount_usd: 500, status: "open" },
      ]);

      const res = await GET(getReq());
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.offers).toHaveLength(1);
    });

    it("returns 401 when not authenticated", async () => {
      authClient.auth.getUser.mockResolvedValueOnce({
        data: { user: null },
      });
      const res = await GET(getReq());
      expect(res.status).toBe(401);
    });

    it("returns 403 when not admin_master", async () => {
      serviceClient.from.mockReturnValueOnce(
        queryChain({ data: { role: "coach" } }),
      );
      const res = await GET(getReq());
      expect(res.status).toBe(403);
    });
  });

  describe("POST create", () => {
    it("creates swap offer for valid input", async () => {
      mockAdminCheck();
      mockCreateSwapOffer.mockResolvedValue({
        id: "o1",
        amount_usd: 1000,
        status: "open",
      });

      const res = await POST(
        req({ action: "create", amount_usd: 1000 }),
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.order.id).toBe("o1");
    });

    it("returns 400 for amount below minimum", async () => {
      mockAdminCheck();
      const res = await POST(req({ action: "create", amount_usd: 10 }));
      expect(res.status).toBe(400);
    });

    it("returns 422 when service throws", async () => {
      mockAdminCheck();
      mockCreateSwapOffer.mockRejectedValue(
        new Error("Insufficient available backing"),
      );

      const res = await POST(
        req({ action: "create", amount_usd: 1000 }),
      );
      expect(res.status).toBe(422);
      const body = await res.json();
      expect(body.error).toContain("Insufficient");
    });
  });

  describe("POST accept", () => {
    it("accepts swap offer", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockResolvedValue(undefined);

      const res = await POST(
        req({
          action: "accept",
          order_id: "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4",
        }),
      );
      expect(res.status).toBe(200);
    });

    it("returns 400 for invalid UUID", async () => {
      mockAdminCheck();
      const res = await POST(
        req({ action: "accept", order_id: "not-a-uuid" }),
      );
      expect(res.status).toBe(400);
    });
  });

  describe("POST cancel", () => {
    it("cancels swap offer", async () => {
      mockAdminCheck();
      mockCancelSwapOffer.mockResolvedValue(undefined);

      const res = await POST(
        req({
          action: "cancel",
          order_id: "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4",
        }),
      );
      expect(res.status).toBe(200);
    });
  });

  describe("POST invalid", () => {
    it("returns 400 for unknown action", async () => {
      mockAdminCheck();
      const res = await POST(req({ action: "explode" }));
      expect(res.status).toBe(400);
    });
  });
});
