import { describe, it, expect, vi, beforeEach } from "vitest";

const mockMaybeSingle = vi.fn();
const mockRpc = vi.fn();
const mockInsert = vi.fn();
const mockSingle = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({
          maybeSingle: mockMaybeSingle,
          order: () => ({ then: (r: Function) => r({ data: [] }) }),
        }),
      }),
      insert: (data: unknown) => {
        mockInsert(data);
        return {
          select: () => ({
            single: mockSingle,
          }),
        };
      },
    }),
    rpc: mockRpc,
  }),
}));

const {
  getCustodyAccount,
  isEmissionAllowed,
  commitCoins,
  confirmDeposit,
  releaseCommitted,
  checkInvariants,
  createCustodyDeposit,
  convertToUsdWithSpread,
  convertFromUsdWithSpread,
  assertInvariantsHealthy,
} = await import("./custody");

describe("custody service", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("getCustodyAccount", () => {
    it("returns null when no account exists", async () => {
      mockMaybeSingle.mockResolvedValue({ data: null });
      const result = await getCustodyAccount("group-1");
      expect(result).toBeNull();
    });

    it("returns account with computed available", async () => {
      mockMaybeSingle.mockResolvedValue({
        data: {
          id: "a1",
          group_id: "group-1",
          total_deposited_usd: 5000,
          total_committed: 2000,
          total_settled_usd: 500,
          is_blocked: false,
          blocked_reason: null,
        },
      });

      const result = await getCustodyAccount("group-1");
      expect(result).not.toBeNull();
      expect(result!.available).toBe(3000);
      expect(result!.total_deposited_usd).toBe(5000);
      expect(result!.total_committed).toBe(2000);
    });
  });

  describe("isEmissionAllowed", () => {
    it("returns false when no account", async () => {
      mockMaybeSingle.mockResolvedValue({ data: null });
      expect(await isEmissionAllowed("g1", 100)).toBe(false);
    });

    it("returns false when blocked", async () => {
      mockMaybeSingle.mockResolvedValue({
        data: {
          id: "a1",
          group_id: "g1",
          total_deposited_usd: 5000,
          total_committed: 0,
          total_settled_usd: 0,
          is_blocked: true,
          blocked_reason: "test",
        },
      });
      expect(await isEmissionAllowed("g1", 100)).toBe(false);
    });

    it("returns false when insufficient available", async () => {
      mockMaybeSingle.mockResolvedValue({
        data: {
          id: "a1",
          group_id: "g1",
          total_deposited_usd: 100,
          total_committed: 80,
          total_settled_usd: 0,
          is_blocked: false,
          blocked_reason: null,
        },
      });
      expect(await isEmissionAllowed("g1", 50)).toBe(false);
    });

    it("returns true when sufficient available", async () => {
      mockMaybeSingle.mockResolvedValue({
        data: {
          id: "a1",
          group_id: "g1",
          total_deposited_usd: 1000,
          total_committed: 200,
          total_settled_usd: 0,
          is_blocked: false,
          blocked_reason: null,
        },
      });
      expect(await isEmissionAllowed("g1", 500)).toBe(true);
    });
  });

  describe("commitCoins", () => {
    it("calls custody_commit_coins RPC", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });
      await commitCoins("g1", 100);
      expect(mockRpc).toHaveBeenCalledWith("custody_commit_coins", {
        p_group_id: "g1",
        p_coin_count: 100,
      });
    });

    it("throws on RPC error", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { message: "Insufficient backing" },
      });
      await expect(commitCoins("g1", 9999)).rejects.toThrow(
        "Insufficient backing",
      );
    });
  });

  describe("confirmDeposit (L01-04)", () => {
    it("calls confirm_custody_deposit RPC with deposit_id + group_id", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });
      await confirmDeposit("dep-1", "group-1");
      expect(mockRpc).toHaveBeenCalledWith("confirm_custody_deposit", {
        p_deposit_id: "dep-1",
        p_group_id: "group-1",
      });
    });

    it("throws on RPC error (cross-group, etc)", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { message: "Deposit not found, wrong group, or already processed" },
      });
      await expect(confirmDeposit("dep-x", "group-y")).rejects.toThrow(
        /wrong group/,
      );
    });
  });

  describe("releaseCommitted", () => {
    it("calls custody_release_committed RPC", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });
      await releaseCommitted("g1", 50);
      expect(mockRpc).toHaveBeenCalledWith("custody_release_committed", {
        p_group_id: "g1",
        p_coin_count: 50,
      });
    });

    it("throws on invariant violation", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { message: "Invariant violation: committed=30 < release=50" },
      });
      await expect(releaseCommitted("g1", 50)).rejects.toThrow(
        "Invariant violation",
      );
    });
  });

  describe("checkInvariants", () => {
    it("returns empty array when system is healthy", async () => {
      mockRpc.mockResolvedValueOnce({ data: [], error: null });
      const result = await checkInvariants();
      expect(result).toEqual([]);
    });

    it("returns violations when found", async () => {
      const violations = [
        {
          group_id: "g1",
          total_deposited: 100,
          total_committed: 200,
          computed_available: -100,
          violation: "deposited_less_than_committed",
        },
      ];
      mockRpc.mockResolvedValueOnce({ data: violations, error: null });
      const result = await checkInvariants();
      expect(result).toHaveLength(1);
      expect(result[0].violation).toBe("deposited_less_than_committed");
    });

    it("throws on RPC error", async () => {
      mockRpc.mockResolvedValueOnce({
        data: null,
        error: { message: "db error" },
      });
      await expect(checkInvariants()).rejects.toThrow("db error");
    });
  });

  describe("createCustodyDeposit (L01-04)", () => {
    const VALID_KEY = "550e8400-e29b-41d4-a716-446655440000";

    it("calls fn_create_custody_deposit_idempotent and returns wasIdempotent=false on first call", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          {
            deposit_id: "dep-1",
            was_idempotent: false,
            status: "pending",
            amount_usd: 500.75,
            coins_equivalent: 500,
            payment_gateway: "stripe",
            payment_reference: null,
            created_at: "2026-04-17T00:00:00Z",
          },
        ],
        error: null,
      });

      const result = await createCustodyDeposit("g1", 500.75, "stripe", VALID_KEY);
      expect(mockRpc).toHaveBeenCalledWith(
        "fn_create_custody_deposit_idempotent",
        {
          p_group_id: "g1",
          p_amount_usd: 500.75,
          p_coins_equivalent: 500,
          p_payment_gateway: "stripe",
          p_idempotency_key: VALID_KEY,
        },
      );
      expect(result?.deposit.coins_equivalent).toBe(500);
      expect(result?.wasIdempotent).toBe(false);
    });

    it("returns wasIdempotent=true on replay with same key", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          {
            deposit_id: "dep-1",
            was_idempotent: true,
            status: "pending",
            amount_usd: 500.75,
            coins_equivalent: 500,
            payment_gateway: "stripe",
            payment_reference: null,
            created_at: "2026-04-17T00:00:00Z",
          },
        ],
        error: null,
      });

      const result = await createCustodyDeposit("g1", 500.75, "stripe", VALID_KEY);
      expect(result?.wasIdempotent).toBe(true);
      expect(result?.deposit.id).toBe("dep-1");
    });

    it("throws on RPC error", async () => {
      mockRpc.mockResolvedValueOnce({
        data: null,
        error: { message: "p_idempotency_key must be >= 8 chars" },
      });
      await expect(
        createCustodyDeposit("g1", 100, "mercadopago", "x"),
      ).rejects.toThrow("p_idempotency_key");
    });
  });

  describe("convertToUsdWithSpread", () => {
    it("applies spread on BRL → USD conversion", () => {
      const result = convertToUsdWithSpread(1000, 5.0, 0.75);
      // 1000 / 5 = 200 USD raw, spread = 200 * 0.0075 = 1.50
      expect(result.amountUsd).toBe(198.5);
      expect(result.spreadUsd).toBe(1.5);
    });

    it("returns full amount with 0% spread", () => {
      const result = convertToUsdWithSpread(500, 5.0, 0);
      expect(result.amountUsd).toBe(100);
      expect(result.spreadUsd).toBe(0);
    });
  });

  describe("convertFromUsdWithSpread", () => {
    it("applies spread on USD → BRL conversion", () => {
      const result = convertFromUsdWithSpread(100, 5.0, 0.75);
      // spread = 100 * 0.0075 = 0.75 USD, net = 99.25, local = 99.25 * 5 = 496.25
      expect(result.spreadUsd).toBe(0.75);
      expect(result.localAmount).toBe(496.25);
    });

    it("returns full amount with 0% spread", () => {
      const result = convertFromUsdWithSpread(200, 5.0, 0);
      expect(result.spreadUsd).toBe(0);
      expect(result.localAmount).toBe(1000);
    });
  });

  describe("assertInvariantsHealthy", () => {
    it("returns true when no violations", async () => {
      mockRpc.mockResolvedValueOnce({ data: [], error: null });
      const healthy = await assertInvariantsHealthy();
      expect(healthy).toBe(true);
    });

    it("returns false when violations exist", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [{ group_id: "g1", violation: "deposited_negative" }],
        error: null,
      });
      const healthy = await assertInvariantsHealthy();
      expect(healthy).toBe(false);
    });
  });
});
