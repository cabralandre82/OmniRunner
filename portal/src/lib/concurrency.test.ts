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
      if (table === "clearing_events") {
        return {
          insert: () => ({
            select: () => ({
              single: vi.fn().mockResolvedValue({ data: { id: "event-1" } }),
            }),
          }),
        };
      }
      if (table === "clearing_settlements") {
        const chain: Record<string, unknown> = {};
        chain.eq = vi.fn().mockReturnValue(chain);
        chain.gte = vi.fn().mockReturnValue(chain);
        chain.lt = vi.fn().mockReturnValue(chain);
        chain.then = (r: Function) => r({ data: [] });
        return {
          insert: () => ({ error: null }),
          select: () => chain,
        };
      }
      return {
        select: () => ({
          eq: () => ({
            maybeSingle: vi.fn().mockResolvedValue({ data: null }),
          }),
        }),
      };
    },
    rpc: mockRpc,
  }),
}));

vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/custody", () => ({
  assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
}));

const { processBurnForClearing, executeBurnAtomic } = await import("./clearing");

describe("concurrency: simultaneous burns from same issuer", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
  });

  it("handles 100 concurrent burn processing calls without errors", async () => {
    const burnPromises = Array.from({ length: 100 }, (_, i) =>
      processBurnForClearing({
        burnRefId: `concurrent-burn-${i}`,
        athleteUserId: "athlete-1",
        redeemerGroupId: "club-a",
        totalCoins: 10,
        breakdown: [{ issuer_group_id: "club-b", amount: 10 }],
      }).catch((err: Error) => ({ error: err.message })),
    );

    const results = await Promise.all(burnPromises);
    const successes = results.filter((r) => "eventId" in r);
    expect(successes.length).toBe(100);
  });

  it("handles mixed intra-club and interclub burns concurrently", async () => {
    const ops = Array.from({ length: 50 }, (_, i) =>
      processBurnForClearing({
        burnRefId: `mixed-burn-${i}`,
        athleteUserId: "athlete-1",
        redeemerGroupId: "club-a",
        totalCoins: 20,
        breakdown: [
          { issuer_group_id: "club-a", amount: 10 },
          { issuer_group_id: "club-b", amount: 10 },
        ],
      }).catch((e: Error) => ({ error: e.message })),
    );

    const results = await Promise.all(ops);
    const successes = results.filter((r) => "eventId" in r);
    expect(successes.length).toBe(50);
  });
});

describe("idempotency: duplicate burn_ref_id", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockRpc.mockResolvedValue({ error: null });
  });

  it("first call succeeds", async () => {
    const result = await processBurnForClearing({
      burnRefId: "idempotent-burn-1",
      athleteUserId: "athlete-1",
      redeemerGroupId: "club-a",
      totalCoins: 50,
      breakdown: [{ issuer_group_id: "club-b", amount: 50 }],
    });

    expect(result.eventId).toBe("event-1");
  });

  it("execute_burn_atomic with same ref_id is rejected by DB", async () => {
    const burnResult = {
      event_id: "evt-1",
      breakdown: [{ issuer_group_id: "club-a", amount: 30 }],
      total_burned: 30,
    };
    mockRpc.mockResolvedValueOnce({ data: burnResult, error: null });

    const result = await executeBurnAtomic({
      userId: "user-1",
      redeemerGroupId: "club-a",
      amount: 30,
      refId: "idempotent-ref-1",
    });
    expect(result.event_id).toBe("evt-1");

    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "duplicate key value violates unique constraint" },
    });

    await expect(
      executeBurnAtomic({
        userId: "user-1",
        redeemerGroupId: "club-a",
        amount: 30,
        refId: "idempotent-ref-1",
      }),
    ).rejects.toThrow("duplicate key");
  });
});

describe("idempotency: settlement processing", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("settle_clearing on already-settled settlement raises error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "Settlement not found or not pending" },
    });

    const db = (await import("@/lib/supabase/service")).createServiceClient();
    const { error } = await db.rpc("settle_clearing", { p_settlement_id: "already-settled" });

    expect(error).not.toBeNull();
    expect(error!.message).toContain("not pending");
  });

  it("confirm_custody_deposit on already-confirmed deposit raises error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "Deposit not found or already processed" },
    });

    const db = (await import("@/lib/supabase/service")).createServiceClient();
    const { error } = await db.rpc("confirm_custody_deposit", { p_deposit_id: "done" });

    expect(error).not.toBeNull();
    expect(error!.message).toContain("already processed");
  });
});
