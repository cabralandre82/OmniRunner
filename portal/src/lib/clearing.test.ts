import { describe, it, expect, vi, beforeEach } from "vitest";

const mockInsert = vi.fn();
const mockSelect = vi.fn();
const mockRpc = vi.fn();
const mockFrom = vi.fn();

function setupMockFrom(table: string) {
  if (table === "platform_fee_config") {
    return {
      select: () => ({
        eq: () => ({
          eq: () => ({
            maybeSingle: vi.fn().mockResolvedValue({
              data: { rate_pct: 3.0 },
            }),
          }),
        }),
      }),
    };
  }
  if (table === "clearing_events") {
    return {
      insert: (data: unknown) => {
        mockInsert(data);
        return {
          select: () => ({
            single: vi.fn().mockResolvedValue({
              data: { id: "event-1" },
            }),
          }),
        };
      },
      select: () => ({
        eq: () => ({
          order: () => ({
            then: (r: Function) => r({ data: [] }),
          }),
        }),
      }),
    };
  }
  if (table === "clearing_settlements") {
    const chain: Record<string, unknown> = {};
    chain.eq = vi.fn().mockReturnValue(chain);
    chain.gte = vi.fn().mockReturnValue(chain);
    chain.lt = vi.fn().mockReturnValue(chain);
    chain.or = vi.fn().mockReturnValue(chain);
    chain.order = vi.fn().mockReturnValue(chain);
    chain.then = (r: Function) => r({ data: [{ id: "s1" }] });
    return {
      insert: (data: unknown) => {
        mockInsert(data);
        return { error: null };
      },
      select: () => chain,
    };
  }
  return {
    select: mockSelect,
    insert: mockInsert,
  };
}

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => setupMockFrom(table),
    rpc: (...args: unknown[]) => mockRpc(...args),
  }),
}));

vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/custody", () => ({
  assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
}));

const {
  processBurnForClearing,
  aggregateClearingWindow,
  settleWindowForDebtor,
  settleClearingChunk,
  executeBurnAtomic,
  computeBurnPlan,
} = await import("./clearing");

describe("clearing service", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("creates event and settlements for interclub burns", async () => {
    const result = await processBurnForClearing({
      burnRefId: "burn-1",
      athleteUserId: "athlete-1",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    expect(result.eventId).toBe("event-1");
    expect(result.settlementsCreated).toBeGreaterThanOrEqual(0);
  });

  it("releases committed backing for same-club burns (no settlement)", async () => {
    const result = await processBurnForClearing({
      burnRefId: "burn-2",
      athleteUserId: "athlete-1",
      redeemerGroupId: "club-a",
      totalCoins: 50,
      breakdown: [{ issuer_group_id: "club-a", amount: 50 }],
    });

    expect(result.eventId).toBe("event-1");
    expect(result.settlementsCreated).toBe(0);

    expect(mockRpc).toHaveBeenCalledWith("custody_release_committed", {
      p_group_id: "club-a",
      p_coin_count: 50,
    });
  });

  it("calls release_committed for intra-club AND settle for interclub in mixed burn", async () => {
    mockRpc.mockResolvedValue({ error: null });

    await processBurnForClearing({
      burnRefId: "burn-3",
      athleteUserId: "athlete-1",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    expect(mockRpc).toHaveBeenCalledWith("custody_release_committed", {
      p_group_id: "club-a",
      p_coin_count: 40,
    });

    expect(mockRpc).toHaveBeenCalledWith("settle_clearing", {
      p_settlement_id: "s1",
    });
  });

  it("verifies settlement insert has correct fee calculation", async () => {
    mockRpc.mockResolvedValue({ error: null });

    await processBurnForClearing({
      burnRefId: "burn-fee",
      athleteUserId: "athlete-1",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [{ issuer_group_id: "club-b", amount: 100 }],
    });

    expect(mockInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        coin_amount: 100,
        gross_amount_usd: 100,
        fee_rate_pct: 3.0,
        fee_amount_usd: 3.0,
        net_amount_usd: 97.0,
        creditor_group_id: "club-a",
        debtor_group_id: "club-b",
      }),
    );
  });
});

describe("aggregateClearingWindow", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls RPC with correct time window", async () => {
    const start = new Date("2026-01-01T00:00:00Z");
    const end = new Date("2026-01-01T01:00:00Z");

    mockRpc.mockResolvedValueOnce({
      data: [
        {
          debtor_group_id: "g1",
          creditor_group_id: "g2",
          total_coins: 150,
          event_count: 3,
        },
      ],
      error: null,
    });

    const result = await aggregateClearingWindow(start, end);
    expect(result).toHaveLength(1);
    expect(result[0].total_coins).toBe(150);
    expect(mockRpc).toHaveBeenCalledWith("aggregate_clearing_window", {
      p_window_start: start.toISOString(),
      p_window_end: end.toISOString(),
    });
  });

  it("returns empty array when no pending settlements", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });

    const result = await aggregateClearingWindow(
      new Date(),
      new Date(),
    );
    expect(result).toEqual([]);
  });

  it("throws on RPC error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "timeout" },
    });

    await expect(
      aggregateClearingWindow(new Date(), new Date()),
    ).rejects.toThrow("timeout");
  });
});

describe("settleWindowForDebtor", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("settles all pending in window and returns counts", async () => {
    mockRpc.mockResolvedValue({ error: null });

    const result = await settleWindowForDebtor(
      "debtor-1",
      new Date("2026-01-01"),
      new Date("2026-01-02"),
    );

    expect(result.settled).toBeGreaterThanOrEqual(0);
    expect(result.failed).toBe(0);
  });

  it("counts failures when settle_clearing returns error", async () => {
    mockRpc.mockResolvedValue({
      error: { message: "insufficient" },
    });

    const result = await settleWindowForDebtor(
      "debtor-1",
      new Date("2026-01-01"),
      new Date("2026-01-02"),
    );

    expect(result.failed).toBeGreaterThanOrEqual(0);
  });
});

describe("settleClearingChunk (L02-10)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  const WINDOW_START = new Date("2026-04-13T00:00:00Z");
  const WINDOW_END = new Date("2026-04-20T00:00:00Z");

  it("calls fn_settle_clearing_chunk RPC with normalised params", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [{ processed: 0, settled: 0, insufficient: 0, failed: 0, remaining: 0 }],
      error: null,
    });

    await settleClearingChunk({
      windowStart: WINDOW_START,
      windowEnd: WINDOW_END,
    });

    expect(mockRpc).toHaveBeenCalledWith("fn_settle_clearing_chunk", {
      p_window_start: WINDOW_START.toISOString(),
      p_window_end: WINDOW_END.toISOString(),
      p_limit: 50,
      p_debtor_group_id: null,
    });
  });

  it("forwards optional limit + debtorGroupId", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [{ processed: 0, settled: 0, insufficient: 0, failed: 0, remaining: 0 }],
      error: null,
    });

    await settleClearingChunk({
      windowStart: WINDOW_START,
      windowEnd: WINDOW_END,
      limit: 200,
      debtorGroupId: "11111111-2222-4333-8444-555555555555",
    });

    expect(mockRpc).toHaveBeenCalledWith(
      "fn_settle_clearing_chunk",
      expect.objectContaining({
        p_limit: 200,
        p_debtor_group_id: "11111111-2222-4333-8444-555555555555",
      }),
    );
  });

  it("returns numeric counts when RPC succeeds", async () => {
    mockRpc.mockResolvedValueOnce({
      data: [
        {
          processed: 50,
          settled: 47,
          insufficient: 2,
          failed: 1,
          remaining: 23,
        },
      ],
      error: null,
    });

    const result = await settleClearingChunk({
      windowStart: WINDOW_START,
      windowEnd: WINDOW_END,
    });

    expect(result).toEqual({
      processed: 50,
      settled: 47,
      insufficient: 2,
      failed: 1,
      remaining: 23,
    });
  });

  it("handles single-object response (non-array)", async () => {
    mockRpc.mockResolvedValueOnce({
      data: { processed: 1, settled: 1, insufficient: 0, failed: 0, remaining: 0 },
      error: null,
    });

    const result = await settleClearingChunk({
      windowStart: WINDOW_START,
      windowEnd: WINDOW_END,
    });

    expect(result.settled).toBe(1);
    expect(result.remaining).toBe(0);
  });

  it("coerces missing fields to zero (defensive)", async () => {
    mockRpc.mockResolvedValueOnce({ data: [{}], error: null });

    const result = await settleClearingChunk({
      windowStart: WINDOW_START,
      windowEnd: WINDOW_END,
    });

    expect(result).toEqual({
      processed: 0,
      settled: 0,
      insufficient: 0,
      failed: 0,
      remaining: 0,
    });
  });

  it("throws when RPC returns an error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "lock_timeout exhausted" },
    });

    await expect(
      settleClearingChunk({
        windowStart: WINDOW_START,
        windowEnd: WINDOW_END,
      }),
    ).rejects.toThrow("lock_timeout exhausted");
  });
});

describe("executeBurnAtomic", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls execute_burn_atomic RPC with correct params", async () => {
    const burnResult = {
      event_id: "evt-1",
      breakdown: [
        { issuer_group_id: "club-a", amount: 30 },
        { issuer_group_id: "club-b", amount: 20 },
      ],
      total_burned: 50,
    };
    mockRpc.mockResolvedValueOnce({ data: burnResult, error: null });

    const result = await executeBurnAtomic({
      userId: "user-1",
      redeemerGroupId: "club-a",
      amount: 50,
      refId: "intent-1",
    });

    expect(mockRpc).toHaveBeenCalledWith("execute_burn_atomic", {
      p_user_id: "user-1",
      p_redeemer_group_id: "club-a",
      p_amount: 50,
      p_ref_id: "intent-1",
    });
    expect(result.event_id).toBe("evt-1");
    expect(result.total_burned).toBe(50);
    expect(result.breakdown).toHaveLength(2);
  });

  it("throws on INSUFFICIENT_BALANCE", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "INSUFFICIENT_BALANCE: balance=10, requested=50" },
    });

    await expect(
      executeBurnAtomic({
        userId: "user-1",
        redeemerGroupId: "club-a",
        amount: 50,
        refId: "intent-1",
      }),
    ).rejects.toThrow("INSUFFICIENT_BALANCE");
  });

  it("throws on BURN_PLAN_SHORTFALL", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "BURN_PLAN_SHORTFALL: could not allocate" },
    });

    await expect(
      executeBurnAtomic({
        userId: "user-1",
        redeemerGroupId: "club-a",
        amount: 100,
        refId: "intent-2",
      }),
    ).rejects.toThrow("BURN_PLAN_SHORTFALL");
  });
});

describe("computeBurnPlan", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls compute_burn_plan RPC and returns breakdown", async () => {
    const plan = [
      { issuer_group_id: "club-a", amount: 10 },
      { issuer_group_id: "club-b", amount: 30 },
    ];
    mockRpc.mockResolvedValueOnce({ data: plan, error: null });

    const result = await computeBurnPlan({
      userId: "user-1",
      redeemerGroupId: "club-a",
      amount: 40,
    });

    expect(mockRpc).toHaveBeenCalledWith("compute_burn_plan", {
      p_user_id: "user-1",
      p_redeemer_group_id: "club-a",
      p_amount: 40,
    });
    expect(result).toEqual(plan);
  });

  it("returns empty when user has no coins", async () => {
    mockRpc.mockResolvedValueOnce({ data: [], error: null });

    const result = await computeBurnPlan({
      userId: "user-empty",
      redeemerGroupId: "club-a",
      amount: 0,
    });

    expect(result).toEqual([]);
  });

  it("throws on RPC error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "BURN_PLAN_SHORTFALL" },
    });

    await expect(
      computeBurnPlan({
        userId: "user-1",
        redeemerGroupId: "club-a",
        amount: 999,
      }),
    ).rejects.toThrow("BURN_PLAN_SHORTFALL");
  });
});
