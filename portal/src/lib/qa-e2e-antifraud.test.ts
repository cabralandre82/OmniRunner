/**
 * QA E2E — Anti-fraud / Authorization (Section 3)
 *
 * L17-04 — split from the historical 842-line `qa-e2e.test.ts`. This
 * file exercises every backend gate that should REJECT a malicious or
 * malformed operation: expired / forged / replay tokens, non-affiliated
 * athletes, insufficient balance, burn-plan shortfall, invariant-
 * violation blocks, and swap insufficient-backing. Shared fixtures live
 * in `./__qa__/qa-e2e-fixtures`.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

import {
  state,
  mockRpc,
  makeFromMock,
  resetState,
  resetIntents,
  rewireMockRpc,
  createIntent,
  consumeIntent,
} from "./__qa__/qa-e2e-fixtures";

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => makeFromMock(table),
    rpc: (...args: unknown[]) =>
      (mockRpc as unknown as (...a: unknown[]) => Promise<unknown>)(...args),
  }),
}));

vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("@/lib/custody", async (importOriginal) => {
  const original = await importOriginal<typeof import("./custody")>();
  return {
    ...original,
    assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
  };
});

const { executeBurnAtomic, processBurnForClearing } = await import(
  "./clearing"
);

describe("3. Anti-fraud — backend blocks invalid operations", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    rewireMockRpc();
  });

  it("3.1 Expired token is rejected", () => {
    const intent = createIntent({
      id: "expired-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "nonce-expired",
      ttlMs: -1,
    });

    const result = consumeIntent(
      intent.id,
      "nonce-expired",
      "atletaA",
      "club-a",
    );
    expect(result.ok).toBe(false);
    expect(result.error).toBe("TOKEN_EXPIRED");
  });

  it("3.2 Forged/invalid token ID is rejected", () => {
    const result = consumeIntent("nonexistent-id", "any-nonce", "atletaA", "club-a");
    expect(result.ok).toBe(false);
    expect(result.error).toBe("TOKEN_INVALID");
  });

  it("3.3 Replay attack (wrong nonce) is rejected", () => {
    createIntent({
      id: "replay-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "correct-nonce",
      ttlMs: 300_000,
    });

    const result = consumeIntent("replay-1", "wrong-nonce", "atletaA", "club-a");
    expect(result.ok).toBe(false);
    expect(result.error).toBe("TOKEN_REPLAY");
  });

  it("3.4 Non-affiliated athlete (wrong club) is rejected", () => {
    createIntent({
      id: "affil-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "nonce-affil",
      ttlMs: 300_000,
    });

    const result = consumeIntent("affil-1", "nonce-affil", "atletaB", "club-b");
    expect(result.ok).toBe(false);
    expect(result.error).toBe("NOT_AFFILIATED");
  });

  it("3.5 Insufficient balance at burn time → INSUFFICIENT_BALANCE error", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "INSUFFICIENT_BALANCE: balance=10, requested=100" },
    });

    await expect(
      executeBurnAtomic({
        userId: "atletaA",
        redeemerGroupId: "club-a",
        amount: 100,
        refId: "insuf-1",
      }),
    ).rejects.toThrow("INSUFFICIENT_BALANCE");
  });

  it("3.6 Burn plan shortfall (not enough coins per issuer) → BURN_PLAN_SHORTFALL", async () => {
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: {
        message: "BURN_PLAN_SHORTFALL: could not allocate requested amount",
      },
    });

    await expect(
      executeBurnAtomic({
        userId: "atletaA",
        redeemerGroupId: "club-a",
        amount: 999,
        refId: "shortfall-1",
      }),
    ).rejects.toThrow("BURN_PLAN_SHORTFALL");
  });

  it("3.7 Invariant violation blocks clearing", async () => {
    const { assertInvariantsHealthy } = await import("@/lib/custody");
    vi.mocked(assertInvariantsHealthy).mockResolvedValueOnce(false);

    await expect(
      processBurnForClearing({
        burnRefId: "invariant-block-1",
        athleteUserId: "atletaA",
        redeemerGroupId: "club-a",
        totalCoins: 50,
        breakdown: [{ issuer_group_id: "club-b", amount: 50 }],
      }),
    ).rejects.toThrow("Invariant violation detected");
  });

  it("3.8 Swap blocked when seller has insufficient available", async () => {
    state.accounts["club-a"].total_deposited_usd = 100;
    state.accounts["club-a"].total_committed = 100;

    mockRpc.mockResolvedValueOnce({
      error: { message: "Seller insufficient available backing" },
    });

    const { acceptSwapOffer } = await import("./swap");
    await expect(acceptSwapOffer("order-1", "club-b")).rejects.toThrow(
      "Seller insufficient available backing",
    );
  });
});
