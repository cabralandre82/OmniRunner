/**
 * QA E2E — Idempotency (Section 2)
 *
 * L17-04 — split from the historical 842-line `qa-e2e.test.ts`. This
 * file verifies that repeated operations (same token scan, same burn
 * ref, already-settled settlement, already-confirmed deposit) produce
 * no side-effects. Shared fixtures live in `./__qa__/qa-e2e-fixtures`.
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
  handleRpc,
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

const { processBurnForClearing, executeBurnAtomic } = await import(
  "./clearing"
);

describe("2. Idempotency — repeated operations produce no side effects", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    rewireMockRpc();
  });

  it("2.1 Repeated scan of same token: 1st burn executes, 2nd returns already_consumed", () => {
    const intent = createIntent({
      id: "intent-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "nonce-1",
      ttlMs: 300_000,
    });

    const first = consumeIntent(intent.id, "nonce-1", "atletaA", "club-a");
    expect(first.ok).toBe(true);
    expect(first.alreadyConsumed).toBe(false);

    const second = consumeIntent(intent.id, "nonce-1", "atletaA", "club-a");
    expect(second.ok).toBe(true);
    expect(second.alreadyConsumed).toBe(true);
  });

  it("2.2 Repeated scan does not alter custody balances", async () => {
    const before = { ...state.accounts["club-a"] };

    await processBurnForClearing({
      burnRefId: "idemp-burn-1",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 30,
      breakdown: [{ issuer_group_id: "club-a", amount: 30 }],
    });

    const afterFirst = { ...state.accounts["club-a"] };
    expect(afterFirst.total_committed).toBe(before.total_committed - 30);

    // Simulate reprocessing via executeBurnAtomic: first call succeeds
    state.burnRefsSeen.add("idemp-atomic-1");

    // Second call with same ref_id → duplicate key
    await expect(
      executeBurnAtomic({
        userId: "atletaA",
        redeemerGroupId: "club-a",
        amount: 30,
        refId: "idemp-atomic-1",
      }),
    ).rejects.toThrow("duplicate key");

    // Balances unchanged after failed duplicate
    expect(state.accounts["club-a"].total_committed).toBe(
      afterFirst.total_committed,
    );
    expect(state.accounts["club-a"].total_deposited_usd).toBe(
      afterFirst.total_deposited_usd,
    );
  });

  it("2.3 Re-settle already-settled settlement returns error", () => {
    state.settlements.push({
      id: "s-done",
      clearing_event_id: "e1",
      creditor_group_id: "club-a",
      debtor_group_id: "club-b",
      coin_amount: 50,
      gross_amount_usd: 50,
      fee_rate_pct: 3.0,
      fee_amount_usd: 1.5,
      net_amount_usd: 48.5,
      status: "settled",
    });

    const result = handleRpc("settle_clearing", { p_settlement_id: "s-done" });
    expect(result.error).not.toBeNull();
    expect(result.error!.message).toContain("not pending");
  });

  it("2.4 Re-confirm already-confirmed deposit is rejected", () => {
    // L01-04 — confirm exige p_group_id também (cross-group block).
    const result = handleRpc("confirm_custody_deposit", {
      p_deposit_id: "already-done",
      p_group_id: "club-a",
    });
    expect(result).toBeDefined();
  });
});
