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

const updateChain = () => ({
  update: vi.fn().mockReturnValue({
    eq: vi.fn().mockReturnValue({
      eq: vi.fn().mockReturnValue({
        eq: vi.fn().mockResolvedValue({ error: null }),
      }),
    }),
  }),
});

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    rpc: mockRpc,
  }),
}));

const { createSwapOffer, acceptSwapOffer, cancelSwapOffer } = await import(
  "./swap"
);

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
      expect(result.id).toBe("order-1");
      expect(result.amount_usd).toBe(500);
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

  describe("acceptSwapOffer", () => {
    it("calls execute_swap RPC atomically", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });

      await acceptSwapOffer("order-1", "buyer-1");

      expect(mockRpc).toHaveBeenCalledWith("execute_swap", {
        p_order_id: "order-1",
        p_buyer_group_id: "buyer-1",
      });
    });

    it("throws on RPC error", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { message: "Seller insufficient available backing" },
      });

      await expect(
        acceptSwapOffer("order-1", "buyer-1"),
      ).rejects.toThrow("Seller insufficient available backing");
    });
  });

  describe("cancelSwapOffer", () => {
    it("cancels open offer owned by seller", async () => {
      mockFrom.mockReturnValueOnce(updateChain());

      await expect(
        cancelSwapOffer("order-1", "seller-1"),
      ).resolves.toBeUndefined();
    });
  });
});
