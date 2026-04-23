/**
 * QA E2E — Smoke test (Section 1)
 *
 * L17-04 — split from the historical 842-line `qa-e2e.test.ts`. This
 * file owns the deterministic happy-path scenario: seed → burn →
 * settlement → custody → invariants → FX → burn-plan. Shared fixtures
 * live in `./__qa__/qa-e2e-fixtures`.
 *
 * All tests use the shared mock DB. Numbers are verified to the cent —
 * any drift fails the test.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

import {
  state,
  mockRpc,
  makeFromMock,
  resetState,
  resetIntents,
  rewireMockRpc,
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

const { processBurnForClearing, computeBurnPlan } = await import("./clearing");
const { convertToUsdWithSpread, convertFromUsdWithSpread } = await import(
  "./custody"
);

describe("1. Smoke Test E2E — deterministic happy path", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    rewireMockRpc();
  });

  it("SEED: clubs A and B each have 1000 USD deposited, 100 coins committed", () => {
    expect(state.accounts["club-a"].total_deposited_usd).toBe(1000);
    expect(state.accounts["club-b"].total_deposited_usd).toBe(1000);
    expect(state.accounts["club-a"].total_committed).toBe(100);
    expect(state.accounts["club-b"].total_committed).toBe(100);
  });

  it("BURN: atletaA burns 100 coins (40 from A, 60 from B) via processBurnForClearing", async () => {
    const result = await processBurnForClearing({
      burnRefId: "burn-smoke-1",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    expect(result.eventId).toBeTruthy();
    expect(result.settlementsCreated).toBe(1);

    expect(state.events).toHaveLength(1);
    expect(state.events[0].burn_ref_id).toBe("burn-smoke-1");
    expect(state.events[0].total_coins).toBe(100);
    expect(state.events[0].breakdown).toEqual([
      { issuer_group_id: "club-a", amount: 40 },
      { issuer_group_id: "club-b", amount: 60 },
    ]);
  });

  it("SETTLEMENT: interclub 60 coins → bruto=60, fee=1.80 (3%), liquido=58.20", async () => {
    await processBurnForClearing({
      burnRefId: "burn-smoke-2",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    expect(state.settlements).toHaveLength(1);
    const s = state.settlements[0];
    expect(s.creditor_group_id).toBe("club-a");
    expect(s.debtor_group_id).toBe("club-b");
    expect(s.coin_amount).toBe(60);
    expect(s.gross_amount_usd).toBe(60);
    expect(s.fee_rate_pct).toBe(3.0);
    expect(s.fee_amount_usd).toBe(1.8);
    expect(s.net_amount_usd).toBe(58.2);
  });

  it("CUSTODY: after settlement, B total decreases 60, A total increases 58.20, platform revenue = 1.80", async () => {
    await processBurnForClearing({
      burnRefId: "burn-smoke-3",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    // Club A: intra-club 40 → committed -= 40 (1000, 60)
    // Club B: interclub settle → deposited -= 60, committed -= 60 (940, 40)
    // Club A: credited net → deposited += 58.20 (1058.20, 60)
    // Platform revenue += 1.80
    expect(state.accounts["club-a"].total_committed).toBe(60);
    expect(state.accounts["club-b"].total_deposited_usd).toBe(940);
    expect(state.accounts["club-b"].total_committed).toBe(40);
    expect(state.accounts["club-a"].total_deposited_usd).toBeCloseTo(
      1058.2,
      2,
    );
    expect(state.platformRevenue).toBeCloseTo(1.8, 2);
  });

  it("INVARIANTS: total = reservado + disponivel for both clubs after settlement", async () => {
    await processBurnForClearing({
      burnRefId: "burn-smoke-4",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 100,
      breakdown: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
    });

    for (const acct of Object.values(state.accounts)) {
      const available = acct.total_deposited_usd - acct.total_committed;
      expect(available).toBeGreaterThanOrEqual(0);
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(
        acct.total_committed,
      );
    }

    // A: 1058.20 - 60 = 998.20 ≥ 0
    expect(
      state.accounts["club-a"].total_deposited_usd -
        state.accounts["club-a"].total_committed,
    ).toBeCloseTo(998.2, 2);
    // B: 940 - 40 = 900 ≥ 0
    expect(
      state.accounts["club-b"].total_deposited_usd -
        state.accounts["club-b"].total_committed,
    ).toBe(900);
  });

  it("FX: BRL deposit with 0.75% spread → exact USD amount", () => {
    const result = convertToUsdWithSpread(1000, 5.0, 0.75);
    // 1000/5 = 200 raw, spread = 200*0.0075 = 1.50, net = 198.50
    expect(result.amountUsd).toBe(198.5);
    expect(result.spreadUsd).toBe(1.5);
  });

  it("FX: USD withdrawal with 0.75% spread → exact BRL amount", () => {
    const result = convertFromUsdWithSpread(100, 5.0, 0.75);
    // spread = 100*0.0075 = 0.75, net = 99.25, local = 99.25*5 = 496.25
    expect(result.spreadUsd).toBe(0.75);
    expect(result.localAmount).toBe(496.25);
  });

  it("COMPUTE BURN PLAN: deterministic same-club-first priority", async () => {
    const plan = await computeBurnPlan({
      userId: "atletaA",
      redeemerGroupId: "club-a",
      amount: 100,
    });

    expect(plan).toEqual([
      { issuer_group_id: "club-a", amount: 40 },
      { issuer_group_id: "club-b", amount: 60 },
    ]);
  });
});
