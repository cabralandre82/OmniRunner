import { describe, it, expect, vi, beforeEach } from "vitest";

const mockFrom = vi.fn();
const mockRpc = vi.fn();

const feeConfigChain = () => ({
  select: () => ({
    eq: () => ({
      eq: () => ({
        maybeSingle: vi.fn().mockResolvedValue({ data: { rate_pct: 1.0 } }),
      }),
    }),
  }),
});

const custodyAccountChain = (available: number) => ({
  select: () => ({
    eq: () => ({
      maybeSingle: vi.fn().mockResolvedValue({
        data: {
          total_deposited_usd: available + 200,
          total_committed: 200,
        },
      }),
    }),
  }),
});

const insertChain = (result: { data?: unknown; error?: unknown }) => ({
  insert: vi.fn().mockReturnValue({
    select: () => ({
      single: vi.fn().mockResolvedValue(result),
    }),
  }),
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    rpc: mockRpc,
  }),
}));

const {
  createSwapOffer,
  acceptSwapOffer,
  cancelSwapOffer,
  SwapError,
} = await import("./swap");

describe("swap service", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("createSwapOffer", () => {
    it("creates offer when seller has sufficient available", async () => {
      const mockOrder = {
        id: "order-1",
        seller_group_id: "seller-1",
        amount_usd: 500,
        fee_rate_pct: 1.0,
        fee_amount_usd: 5,
        status: "open",
      };

      mockFrom
        .mockReturnValueOnce(custodyAccountChain(1000))
        .mockReturnValueOnce(feeConfigChain())
        .mockReturnValueOnce(insertChain({ data: mockOrder }));

      const result = await createSwapOffer("seller-1", 500);
      expect(result?.id).toBe("order-1");
      expect(result?.amount_usd).toBe(500);
    });

    it("throws when seller has insufficient available", async () => {
      mockFrom.mockReturnValueOnce(custodyAccountChain(100));

      await expect(createSwapOffer("seller-1", 500)).rejects.toThrow(
        "Insufficient available backing",
      );
    });

    it("throws when seller has no custody account", async () => {
      mockFrom.mockReturnValueOnce({
        select: () => ({
          eq: () => ({
            maybeSingle: vi.fn().mockResolvedValue({ data: null }),
          }),
        }),
      });

      await expect(createSwapOffer("seller-1", 500)).rejects.toThrow(
        "Insufficient available backing",
      );
    });
  });

  describe("acceptSwapOffer — L05-01 SQLSTATE mapping", () => {
    it("calls execute_swap RPC with order_id and buyer_group_id", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });
      await acceptSwapOffer("order-1", "buyer-1");
      expect(mockRpc).toHaveBeenCalledWith("execute_swap", {
        p_order_id: "order-1",
        p_buyer_group_id: "buyer-1",
      });
    });

    it("maps P0002 → SwapError code='not_found'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { code: "P0002", message: "SWAP_NOT_FOUND: order x does not exist" },
      });
      await expect(acceptSwapOffer("o", "b")).rejects.toMatchObject({
        code: "not_found",
        sqlstate: "P0002",
      });
    });

    it("maps P0001 → SwapError code='not_open' com current_status no detail", async () => {
      mockRpc.mockResolvedValueOnce({
        error: {
          code: "P0001",
          message: "SWAP_NOT_OPEN: order x is in status=cancelled",
          hint: "cancelled",
        },
      });
      try {
        await acceptSwapOffer("o", "b");
        expect.fail("deveria ter lançado");
      } catch (err) {
        expect(err).toBeInstanceOf(SwapError);
        const e = err as InstanceType<typeof SwapError>;
        expect(e.code).toBe("not_open");
        expect(e.detail?.current_status).toBe("cancelled");
      }
    });

    it("maps P0003 em accept → 'self_buy'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: {
          code: "P0003",
          message: "SWAP_SELF_BUY: buyer x is the seller of order y",
        },
      });
      await expect(acceptSwapOffer("o", "b")).rejects.toMatchObject({
        code: "self_buy",
      });
    });

    it("maps P0004 → 'insufficient_backing'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: {
          code: "P0004",
          message: "SWAP_INSUFFICIENT_BACKING: seller x avail=0, needed=500",
        },
      });
      await expect(acceptSwapOffer("o", "b")).rejects.toMatchObject({
        code: "insufficient_backing",
      });
    });

    it("maps 55P03 → 'lock_not_available'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { code: "55P03", message: "lock_not_available" },
      });
      await expect(acceptSwapOffer("o", "b")).rejects.toMatchObject({
        code: "lock_not_available",
      });
    });

    it("desconhecido → code='unknown'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { code: "ZZZZZ", message: "some other failure" },
      });
      await expect(acceptSwapOffer("o", "b")).rejects.toMatchObject({
        code: "unknown",
      });
    });
  });

  describe("cancelSwapOffer — L05-01 RPC-backed with race-safe semantics", () => {
    it("chama cancel_swap_order RPC (não UPDATE direto)", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          {
            order_id: "order-1",
            previous_status: "open",
            new_status: "cancelled",
            cancelled_at: "2026-04-17T12:00:00Z",
          },
        ],
        error: null,
      });

      const res = await cancelSwapOffer("order-1", "seller-1");
      expect(mockRpc).toHaveBeenCalledWith("cancel_swap_order", {
        p_order_id: "order-1",
        p_seller_group_id: "seller-1",
      });
      expect(mockFrom).not.toHaveBeenCalled();
      expect(res.previousStatus).toBe("open");
      expect(res.newStatus).toBe("cancelled");
    });

    it("aceita shape não-array (single row)", async () => {
      mockRpc.mockResolvedValueOnce({
        data: {
          order_id: "order-1",
          previous_status: "open",
          new_status: "cancelled",
          cancelled_at: "t",
        },
        error: null,
      });
      const res = await cancelSwapOffer("order-1", "seller-1");
      expect(res.newStatus).toBe("cancelled");
    });

    it("P0001 (não mais open) → not_open com current_status='settled'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: {
          code: "P0001",
          message: "SWAP_NOT_OPEN: order is in status=settled",
          hint: "settled",
        },
      });
      try {
        await cancelSwapOffer("o", "s");
        expect.fail("deveria lançar");
      } catch (err) {
        expect(err).toBeInstanceOf(SwapError);
        const e = err as InstanceType<typeof SwapError>;
        expect(e.code).toBe("not_open");
        expect(e.detail?.current_status).toBe("settled");
      }
    });

    it("P0003 em cancel → 'not_owner' (diferente de self_buy em accept)", async () => {
      mockRpc.mockResolvedValueOnce({
        error: {
          code: "P0003",
          message: "SWAP_NOT_OWNER: group x is not the seller of order y",
        },
      });
      await expect(cancelSwapOffer("o", "s")).rejects.toMatchObject({
        code: "not_owner",
      });
    });

    it("P0002 → 'not_found'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { code: "P0002", message: "SWAP_NOT_FOUND: order" },
      });
      await expect(cancelSwapOffer("o", "s")).rejects.toMatchObject({
        code: "not_found",
      });
    });

    it("55P03 → 'lock_not_available'", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { code: "55P03", message: "canceling statement due to lock timeout" },
      });
      await expect(cancelSwapOffer("o", "s")).rejects.toMatchObject({
        code: "lock_not_available",
      });
    });

    it("data vazia (shouldn't happen mas é defensive) → erro unknown", async () => {
      mockRpc.mockResolvedValueOnce({ data: null, error: null });
      await expect(cancelSwapOffer("o", "s")).rejects.toMatchObject({
        code: "unknown",
      });
    });
  });
});
