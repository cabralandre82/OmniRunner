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

  describe("confirmDeposit", () => {
    it("calls confirm_custody_deposit RPC", async () => {
      mockRpc.mockResolvedValueOnce({ error: null });
      await confirmDeposit("dep-1");
      expect(mockRpc).toHaveBeenCalledWith("confirm_custody_deposit", {
        p_deposit_id: "dep-1",
      });
    });

    it("throws on RPC error", async () => {
      mockRpc.mockResolvedValueOnce({
        error: { message: "Deposit not found" },
      });
      await expect(confirmDeposit("dep-x")).rejects.toThrow(
        "Deposit not found",
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

  describe("createCustodyDeposit", () => {
    it("creates deposit with correct coins_equivalent", async () => {
      mockSingle.mockResolvedValueOnce({
        data: {
          id: "dep-1",
          group_id: "g1",
          amount_usd: 500.75,
          coins_equivalent: 500,
          payment_gateway: "stripe",
          status: "pending",
        },
        error: null,
      });

      const result = await createCustodyDeposit("g1", 500.75, "stripe");
      expect(result.deposit.coins_equivalent).toBe(500);
      expect(result.deposit.amount_usd).toBe(500.75);
    });

    it("throws on insert error", async () => {
      mockSingle.mockResolvedValueOnce({
        data: null,
        error: { message: "insert failed" },
      });
      await expect(
        createCustodyDeposit("g1", 100, "mercadopago"),
      ).rejects.toThrow("insert failed");
    });
  });
});
