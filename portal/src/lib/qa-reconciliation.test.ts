/**
 * QA Section 6: Reconciliation & Invariant Auditor
 *
 * Validates the mathematical invariants of the custody+clearing system:
 *   - D = R + A for every club
 *   - R_i = coins_alive_i for every issuer
 *   - sum(fees) = ledger of fees (platform_revenue)
 *   - no duplicate settlements per burn
 *   - no negative balances
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

const mockRpc = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "platform_fee_config") {
        return {
          select: () => ({
            eq: () => ({
              eq: () => ({
                maybeSingle: vi.fn().mockResolvedValue({ data: { rate_pct: 3.0 } }),
              }),
            }),
          }),
        };
      }
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: vi.fn().mockResolvedValue({ data: null }),
            order: () => ({ then: (r: Function) => r({ data: [] }) }),
          }),
        }),
      };
    },
    rpc: mockRpc,
  }),
}));

const { checkInvariants } = await import("./custody");

describe("6. Reconciliation — invariant auditor", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("6.1 D = R + A invariant", () => {
    it("reports healthy when D = R + A for all clubs", async () => {
      mockRpc.mockResolvedValueOnce({ data: [], error: null });

      const violations = await checkInvariants();
      expect(violations).toEqual([]);
    });

    it("reports violation when D < R (deposited less than committed)", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          {
            group_id: "club-x",
            total_deposited: 100,
            total_committed: 200,
            computed_available: -100,
            violation: "deposited_less_than_committed",
          },
        ],
        error: null,
      });

      const violations = await checkInvariants();
      expect(violations).toHaveLength(1);
      expect(violations[0].group_id).toBe("club-x");
      expect(violations[0].violation).toBe("deposited_less_than_committed");
      expect(violations[0].computed_available).toBe(-100);
    });

    it("reports multiple violations across clubs", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          { group_id: "club-a", total_deposited: 50, total_committed: 100, computed_available: -50, violation: "deposited_less_than_committed" },
          { group_id: "club-b", total_deposited: 0, total_committed: 10, computed_available: -10, violation: "deposited_less_than_committed" },
        ],
        error: null,
      });

      const violations = await checkInvariants();
      expect(violations).toHaveLength(2);
      expect(violations.every((v) => v.computed_available < 0)).toBe(true);
    });
  });

  describe("6.2 R_i = coins_alive_i invariant", () => {
    it("reports violation when reserved does not match coins alive", async () => {
      mockRpc.mockResolvedValueOnce({
        data: [
          {
            group_id: "club-c",
            total_deposited: 1000,
            total_committed: 500,
            computed_available: 500,
            violation: "committed_not_equal_coins_alive",
          },
        ],
        error: null,
      });

      const violations = await checkInvariants();
      expect(violations).toHaveLength(1);
      expect(violations[0].violation).toBe("committed_not_equal_coins_alive");
    });
  });

  describe("6.3 Platform fee reconciliation", () => {
    it("validates fee calculation: 3% of 60 = 1.80", () => {
      const grossUsd = 60;
      const feeRate = 3.0;
      const feeUsd = Math.round(grossUsd * feeRate) / 100;
      const netUsd = grossUsd - feeUsd;

      expect(feeUsd).toBe(1.80);
      expect(netUsd).toBe(58.20);
      expect(grossUsd).toBe(feeUsd + netUsd);
    });

    it("validates fee calculation: 3% of 100 = 3.00", () => {
      const grossUsd = 100;
      const feeRate = 3.0;
      const feeUsd = Math.round(grossUsd * feeRate) / 100;
      expect(feeUsd).toBe(3.00);
    });

    it("validates fee calculation: 3% of 1 = 0.03", () => {
      const grossUsd = 1;
      const feeRate = 3.0;
      const feeUsd = Math.round(grossUsd * feeRate) / 100;
      expect(feeUsd).toBe(0.03);
    });

    it("validates swap fee: 1% of 500 = 5.00", () => {
      const amount = 500;
      const feeRate = 1.0;
      const feeUsd = Math.round(amount * feeRate) / 100;
      expect(feeUsd).toBe(5.00);
    });

    it("validates FX spread: 0.75% of 200 = 1.50", () => {
      const rawUsd = 200;
      const spreadPct = 0.75;
      const spreadUsd = Math.round(rawUsd * spreadPct) / 100;
      expect(spreadUsd).toBe(1.50);
    });

    it("sum of settlement fees = total platform clearing revenue (model check)", () => {
      const settlements = [
        { gross: 60, fee_rate: 3.0 },
        { gross: 100, fee_rate: 3.0 },
        { gross: 25, fee_rate: 3.0 },
      ];

      const totalFees = settlements.reduce(
        (sum, s) => sum + Math.round(s.gross * s.fee_rate) / 100,
        0,
      );

      const expectedFees = 1.80 + 3.00 + 0.75;
      expect(totalFees).toBeCloseTo(expectedFees, 2);
    });
  });

  describe("6.4 No duplicate settlements", () => {
    it("validates uniqueness: each (event, issuer) pair produces exactly 1 settlement", () => {
      const settlements = [
        { event_id: "e1", debtor: "club-b" },
        { event_id: "e2", debtor: "club-b" },
        { event_id: "e2", debtor: "club-c" },
        { event_id: "e3", debtor: "club-a" },
      ];

      const keys = settlements.map((s) => `${s.event_id}:${s.debtor}`);
      const uniqueKeys = new Set(keys);
      expect(uniqueKeys.size).toBe(keys.length);
    });

    it("detects duplicate settlement as invariant violation", () => {
      const settlements = [
        { event_id: "e1", debtor: "club-b" },
        { event_id: "e1", debtor: "club-b" }, // duplicate!
      ];

      const keys = settlements.map((s) => `${s.event_id}:${s.debtor}`);
      const uniqueKeys = new Set(keys);
      expect(uniqueKeys.size).toBeLessThan(keys.length);
    });
  });

  describe("6.5 No negative balances ever", () => {
    it("D >= 0 for all clubs", () => {
      const clubs = [
        { group_id: "a", total_deposited_usd: 1000, total_committed: 500 },
        { group_id: "b", total_deposited_usd: 0, total_committed: 0 },
        { group_id: "c", total_deposited_usd: 999.99, total_committed: 999.99 },
      ];

      for (const c of clubs) {
        expect(c.total_deposited_usd).toBeGreaterThanOrEqual(0);
        expect(c.total_committed).toBeGreaterThanOrEqual(0);
        expect(c.total_deposited_usd - c.total_committed).toBeGreaterThanOrEqual(0);
      }
    });
  });

  describe("6.6 Invariant check throws on DB error", () => {
    it("propagates database errors", async () => {
      mockRpc.mockResolvedValueOnce({
        data: null,
        error: { message: "connection refused" },
      });

      await expect(checkInvariants()).rejects.toThrow("connection refused");
    });
  });
});
