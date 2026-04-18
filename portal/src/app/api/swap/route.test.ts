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

const auditLog = vi.fn().mockResolvedValue(undefined);
vi.mock("@/lib/audit", () => ({ auditLog }));

vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

// L06-06 — kill switch lib é mockada como sempre-permitido nestes testes
// para isolar lógica de swap. Cobertura do assert vive em
// src/lib/feature-flags.test.ts.
vi.mock("@/lib/feature-flags", () => ({
  assertSubsystemEnabled: vi.fn().mockResolvedValue(undefined),
  isSubsystemEnabled: vi.fn().mockResolvedValue(true),
  FeatureDisabledError: class FeatureDisabledError extends Error {},
}));

const mockCreateSwapOffer = vi.fn();
const mockAcceptSwapOffer = vi.fn();
const mockGetOpenSwapOffers = vi.fn();
const mockCancelSwapOffer = vi.fn();

vi.mock("@/lib/swap", async () => {
  const actual = await vi.importActual<typeof import("@/lib/swap")>(
    "@/lib/swap",
  );
  return {
    ...actual,
    createSwapOffer: (...args: unknown[]) => mockCreateSwapOffer(...args),
    acceptSwapOffer: (...args: unknown[]) => mockAcceptSwapOffer(...args),
    getOpenSwapOffers: (...args: unknown[]) => mockGetOpenSwapOffers(...args),
    cancelSwapOffer: (...args: unknown[]) => mockCancelSwapOffer(...args),
  };
});

const { GET, POST } = await import("./route");
const { SwapError } = await import("@/lib/swap");

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

const UUID1 = "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4";

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
      expect(body.error).toBe("Operação falhou. Tente novamente.");
    });

    it("rejeita campos extras (strict schema) — 400", async () => {
      mockAdminCheck();
      const res = await POST(
        req({ action: "create", amount_usd: 1000, evil_field: true }),
      );
      expect(res.status).toBe(400);
    });

    // ───── L05-02 ─────
    it("L05-02: aceita expires_in_days canônico e propaga para createSwapOffer", async () => {
      mockAdminCheck();
      mockCreateSwapOffer.mockResolvedValue({
        id: "o2",
        amount_usd: 200,
        status: "open",
        expires_at: "2026-04-18T00:00:00Z",
      });

      const res = await POST(
        req({ action: "create", amount_usd: 200, expires_in_days: 1 }),
      );
      expect(res.status).toBe(200);
      expect(mockCreateSwapOffer).toHaveBeenCalledWith("group-1", 200, 1);
      expect(auditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "swap.offer.created",
          metadata: expect.objectContaining({
            expires_in_days: 1,
            expires_at: "2026-04-18T00:00:00Z",
          }),
        }),
      );
    });

    it("L05-02: usa default 7d quando expires_in_days omitido", async () => {
      mockAdminCheck();
      mockCreateSwapOffer.mockResolvedValue({
        id: "o3",
        amount_usd: 1000,
        status: "open",
        expires_at: "2026-04-24T00:00:00Z",
      });

      const res = await POST(req({ action: "create", amount_usd: 1000 }));
      expect(res.status).toBe(200);
      expect(mockCreateSwapOffer).toHaveBeenCalledWith("group-1", 1000, 7);
    });

    it("L05-02: rejeita expires_in_days fora dos canônicos (1/7/30/90)", async () => {
      mockAdminCheck();
      const res = await POST(
        req({ action: "create", amount_usd: 1000, expires_in_days: 14 }),
      );
      expect(res.status).toBe(400);
    });
  });

  describe("POST accept — L05-01 error mapping", () => {
    it("accepts swap offer (happy path)", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockResolvedValue(undefined);

      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(200);
      expect(auditLog).toHaveBeenCalledWith(
        expect.objectContaining({ action: "swap.offer.accepted" }),
      );
    });

    it("404 quando order não existe (not_found)", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_NOT_FOUND", "not_found", "P0002"),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(404);
      const body = await res.json();
      expect(body.code).toBe("not_found");
      expect(auditLog).toHaveBeenCalledWith(
        expect.objectContaining({ action: "swap.offer.accept_failed" }),
      );
    });

    it("409 quando order já foi cancelled/settled (not_open) — race com cancel", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_NOT_OPEN", "not_open", "P0001", {
          current_status: "cancelled",
        }),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(409);
      const body = await res.json();
      expect(body.code).toBe("not_open");
      expect(body.detail.current_status).toBe("cancelled");
      expect(auditLog).not.toHaveBeenCalledWith(
        expect.objectContaining({ action: "swap.offer.accepted" }),
      );
    });

    it("400 quando buyer = seller (self_buy)", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_SELF_BUY", "self_buy", "P0003"),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(400);
    });

    it("422 quando seller sem backing (insufficient_backing)", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_INSUFFICIENT_BACKING", "insufficient_backing", "P0004"),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(422);
    });

    it("503 com Retry-After quando lock_not_available", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError("lock timeout", "lock_not_available", "55P03"),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(503);
      expect(res.headers.get("Retry-After")).toBe("2");
    });

    it("L05-02: 410 Gone quando oferta expirou (expired)", async () => {
      mockAdminCheck();
      mockAcceptSwapOffer.mockRejectedValueOnce(
        new SwapError(
          "SWAP_EXPIRED: order o expired at 2026-04-10",
          "expired",
          "P0005",
          { expired_at: "2026-04-10T00:00:00Z" },
        ),
      );
      const res = await POST(req({ action: "accept", order_id: UUID1 }));
      expect(res.status).toBe(410);
      const body = await res.json();
      expect(body.code).toBe("expired");
      expect(body.detail.expired_at).toBe("2026-04-10T00:00:00Z");
      expect(auditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "swap.offer.accept_failed",
          metadata: expect.objectContaining({ code: "expired" }),
        }),
      );
    });

    it("returns 400 for invalid UUID", async () => {
      mockAdminCheck();
      const res = await POST(req({ action: "accept", order_id: "not-a-uuid" }));
      expect(res.status).toBe(400);
    });
  });

  describe("POST cancel — L05-01 race-safe semantics", () => {
    it("cancels offer and retorna previous/new status", async () => {
      mockAdminCheck();
      mockCancelSwapOffer.mockResolvedValue({
        orderId: UUID1,
        previousStatus: "open",
        newStatus: "cancelled",
        cancelledAt: "2026-04-17T12:00:00Z",
      });

      const res = await POST(req({ action: "cancel", order_id: UUID1 }));
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.previous_status).toBe("open");
      expect(body.new_status).toBe("cancelled");
      expect(auditLog).toHaveBeenCalledWith(
        expect.objectContaining({
          action: "swap.offer.cancelled",
          metadata: expect.objectContaining({
            previous_status: "open",
            new_status: "cancelled",
          }),
        }),
      );
    });

    it("409 quando race com accept — order já settled (not_open)", async () => {
      mockAdminCheck();
      mockCancelSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_NOT_OPEN", "not_open", "P0001", {
          current_status: "settled",
        }),
      );
      const res = await POST(req({ action: "cancel", order_id: UUID1 }));
      expect(res.status).toBe(409);
      const body = await res.json();
      expect(body.detail.current_status).toBe("settled");
    });

    it("403 quando caller não é seller (not_owner)", async () => {
      mockAdminCheck();
      mockCancelSwapOffer.mockRejectedValueOnce(
        new SwapError("SWAP_NOT_OWNER", "not_owner", "P0003"),
      );
      const res = await POST(req({ action: "cancel", order_id: UUID1 }));
      expect(res.status).toBe(403);
    });

    it("503 retry quando lock_not_available", async () => {
      mockAdminCheck();
      mockCancelSwapOffer.mockRejectedValueOnce(
        new SwapError("canceling statement", "lock_not_available", "55P03"),
      );
      const res = await POST(req({ action: "cancel", order_id: UUID1 }));
      expect(res.status).toBe(503);
      expect(res.headers.get("Retry-After")).toBe("2");
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
