/**
 * QA E2E — Concurrency (Section 4)
 *
 * L17-04 — split from the historical 842-line `qa-e2e.test.ts`. This
 * file pressurises the system with parallel scans, parallel burns and
 * duplicate ref_id races to show that invariants hold under load.
 * Shared fixtures live in `./__qa__/qa-e2e-fixtures`.
 *
 * These tests are deliberately expensive (1000 parallel burns). Keep
 * them here so CI can run smoke+idempotency+antifraud quickly in most
 * PRs and only pay the concurrency cost on full runs.
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

const { processBurnForClearing, executeBurnAtomic } = await import(
  "./clearing"
);

describe("4. Concurrency — parallel operations produce correct results", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    rewireMockRpc();
  });

  it("4.1 100 simultaneous scans of same token → exactly 1 burn", () => {
    createIntent({
      id: "concurrent-token-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "nonce-concurrent",
      ttlMs: 300_000,
    });

    const results = Array.from({ length: 100 }, () =>
      consumeIntent(
        "concurrent-token-1",
        "nonce-concurrent",
        "atletaA",
        "club-a",
      ),
    );

    const firstBurns = results.filter((r) => r.ok && !r.alreadyConsumed);
    const alreadyConsumed = results.filter((r) => r.ok && r.alreadyConsumed);
    const errors = results.filter((r) => !r.ok);

    expect(firstBurns).toHaveLength(1);
    expect(alreadyConsumed).toHaveLength(99);
    expect(errors).toHaveLength(0);
  });

  it("4.2 1000 burns with same issuer → no negative balance, invariants valid", async () => {
    state.accounts["club-b"].total_deposited_usd = 10000;
    state.accounts["club-b"].total_committed = 1000;

    const burnPromises = Array.from({ length: 1000 }, (_, i) =>
      processBurnForClearing({
        burnRefId: `stress-burn-${i}`,
        athleteUserId: "atletaA",
        redeemerGroupId: "club-a",
        totalCoins: 1,
        breakdown: [{ issuer_group_id: "club-a", amount: 1 }],
      }).catch((err: Error) => ({ error: err.message })),
    );

    await Promise.all(burnPromises);

    for (const acct of Object.values(state.accounts)) {
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(0);
      expect(acct.total_committed).toBeGreaterThanOrEqual(0);
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(
        acct.total_committed,
      );
    }
  });

  it("4.3 1000 interclub burns → no duplicate settlements, balances correct", async () => {
    state.accounts["club-b"].total_deposited_usd = 100_000;
    state.accounts["club-b"].total_committed = 10_000;
    state.accounts["club-a"].total_deposited_usd = 100_000;
    state.accounts["club-a"].total_committed = 10_000;

    const burnPromises = Array.from({ length: 1000 }, (_, i) =>
      processBurnForClearing({
        burnRefId: `interclub-stress-${i}`,
        athleteUserId: "atletaA",
        redeemerGroupId: "club-a",
        totalCoins: 10,
        breakdown: [{ issuer_group_id: "club-b", amount: 10 }],
      }).catch((err: Error) => ({ error: err.message })),
    );

    await Promise.all(burnPromises);

    // No duplicate settlement per event
    const eventSettlementCount = new Map<string, number>();
    for (const s of state.settlements) {
      eventSettlementCount.set(
        s.clearing_event_id,
        (eventSettlementCount.get(s.clearing_event_id) ?? 0) + 1,
      );
    }
    for (const [, count] of eventSettlementCount) {
      expect(count).toBe(1);
    }

    // Invariants hold
    for (const acct of Object.values(state.accounts)) {
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(0);
      expect(acct.total_committed).toBeGreaterThanOrEqual(0);
    }
  });

  it("4.4 Duplicate burn_ref_id across executeBurnAtomic → exactly 1 succeeds", async () => {
    const refId = "atomic-dup-ref";
    const results = await Promise.allSettled(
      Array.from({ length: 50 }, () =>
        executeBurnAtomic({
          userId: "atletaA",
          redeemerGroupId: "club-a",
          amount: 10,
          refId,
        }),
      ),
    );

    const successes = results.filter((r) => r.status === "fulfilled");
    const failures = results.filter((r) => r.status === "rejected");

    expect(successes).toHaveLength(1);
    expect(failures).toHaveLength(49);
    for (const f of failures) {
      expect((f as PromiseRejectedResult).reason.message).toContain(
        "duplicate key",
      );
    }
  });
});
