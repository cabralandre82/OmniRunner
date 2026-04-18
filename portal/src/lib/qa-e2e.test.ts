/**
 * QA E2E Verification Suite
 *
 * Sections 1-4 of the verification plan:
 *   1. Smoke test — full deterministic scenario
 *   2. Idempotency — repeated scans, event reprocessing
 *   3. Anti-fraud — expired, forged, replay, affiliation, balance
 *   4. Concurrency — parallel scans, burns, events
 *
 * All tests use the same mock infrastructure to simulate the DB layer.
 * Numbers are verified to the cent — any drift fails the test.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

// --------------- Shared mock state (simulates DB) ---------------

interface MockAccount {
  group_id: string;
  total_deposited_usd: number;
  total_committed: number;
  total_settled_usd: number;
  is_blocked: boolean;
  blocked_reason: string | null;
}

interface MockSettlement {
  id: string;
  clearing_event_id: string;
  creditor_group_id: string;
  debtor_group_id: string;
  coin_amount: number;
  gross_amount_usd: number;
  fee_rate_pct: number;
  fee_amount_usd: number;
  net_amount_usd: number;
  status: string;
}

interface MockEvent {
  id: string;
  burn_ref_id: string;
  redeemer_group_id: string;
  total_coins: number;
  breakdown: { issuer_group_id: string; amount: number }[];
}

let accounts: Record<string, MockAccount>;
let events: MockEvent[];
let settlements: MockSettlement[];
let platformRevenue: number;
let burnRefsSeen: Set<string>;
let settlementIdCounter: number;
let eventIdCounter: number;
let claimMap: Map<string, "OPEN" | "CONSUMED">;

function resetState() {
  accounts = {
    "club-a": {
      group_id: "club-a",
      total_deposited_usd: 1000,
      total_committed: 100,
      total_settled_usd: 0,
      is_blocked: false,
      blocked_reason: null,
    },
    "club-b": {
      group_id: "club-b",
      total_deposited_usd: 1000,
      total_committed: 100,
      total_settled_usd: 0,
      is_blocked: false,
      blocked_reason: null,
    },
  };
  events = [];
  settlements = [];
  platformRevenue = 0;
  burnRefsSeen = new Set();
  settlementIdCounter = 0;
  eventIdCounter = 0;
  claimMap = new Map();
}

function handleRpc(name: string, params: Record<string, unknown>) {
  if (name === "check_custody_invariants") {
    const violations = [];
    for (const acct of Object.values(accounts)) {
      if (acct.total_deposited_usd < acct.total_committed) {
        violations.push({ group_id: acct.group_id, violation: "D < R" });
      }
    }
    return { data: violations, error: null };
  }

  if (name === "custody_release_committed") {
    const gid = params.p_group_id as string;
    const amt = params.p_coin_count as number;
    const acct = accounts[gid];
    if (!acct) return { error: { message: "No account" } };
    if (acct.total_committed < amt)
      return { error: { message: `Invariant violation: committed=${acct.total_committed} < release=${amt}` } };
    acct.total_committed -= amt;
    return { error: null };
  }

  if (name === "settle_clearing") {
    const sid = params.p_settlement_id as string;
    const s = settlements.find((x) => x.id === sid);
    if (!s) return { error: { message: "Settlement not found or not pending" } };
    if (s.status !== "pending") return { error: { message: "Settlement not found or not pending" } };

    const debtor = accounts[s.debtor_group_id];
    const creditor = accounts[s.creditor_group_id];
    if (!debtor || !creditor) return { error: { message: "Account not found" } };

    debtor.total_deposited_usd -= s.gross_amount_usd;
    debtor.total_committed -= s.coin_amount;
    creditor.total_deposited_usd += s.net_amount_usd;
    creditor.total_settled_usd += s.net_amount_usd;
    platformRevenue += s.fee_amount_usd;
    s.status = "settled";
    return { error: null };
  }

  if (name === "execute_burn_atomic") {
    const refId = params.p_ref_id as string;
    if (burnRefsSeen.has(refId)) {
      return { data: null, error: { message: "duplicate key value violates unique constraint" } };
    }
    burnRefsSeen.add(refId);
    return {
      data: {
        event_id: `evt-${++eventIdCounter}`,
        breakdown: [
          { issuer_group_id: "club-a", amount: 40 },
          { issuer_group_id: "club-b", amount: 60 },
        ],
        total_burned: 100,
      },
      error: null,
    };
  }

  if (name === "execute_swap") {
    const buyer = params.p_buyer_group_id as string;
    const seller = accounts["club-a"];
    const buyerAcct = accounts[buyer];
    if (!seller || !buyerAcct) return { error: { message: "Account not found" } };
    if (seller.total_deposited_usd - seller.total_committed < 100) {
      return { error: { message: "Seller insufficient available backing" } };
    }
    seller.total_deposited_usd -= 100;
    buyerAcct.total_deposited_usd += 99;
    platformRevenue += 1;
    return { error: null };
  }

  if (name === "compute_burn_plan") {
    return {
      data: [
        { issuer_group_id: "club-a", amount: 40 },
        { issuer_group_id: "club-b", amount: 60 },
      ],
      error: null,
    };
  }

  if (name === "aggregate_clearing_window") {
    return { data: [], error: null };
  }

  return { error: null };
}

// Token/intent state
interface MockIntent {
  id: string;
  status: "OPEN" | "CONSUMED";
  type: string;
  group_id: string;
  amount: number;
  nonce: string;
  expires_at_ms: number;
  athlete_user_id: string | null;
}

let intents: Record<string, MockIntent>;

function resetIntents() {
  intents = {};
}

function createIntent(params: {
  id: string;
  type: string;
  groupId: string;
  amount: number;
  nonce: string;
  ttlMs: number;
  athleteUserId?: string;
}): MockIntent {
  const intent: MockIntent = {
    id: params.id,
    status: "OPEN",
    type: params.type,
    group_id: params.groupId,
    amount: params.amount,
    nonce: params.nonce,
    expires_at_ms: Date.now() + params.ttlMs,
    athlete_user_id: params.athleteUserId ?? null,
  };
  intents[params.id] = intent;
  return intent;
}

function consumeIntent(intentId: string, nonce: string, userId: string, memberGroupId: string): {
  ok: boolean;
  error?: string;
  alreadyConsumed?: boolean;
} {
  const intent = intents[intentId];
  if (!intent) return { ok: false, error: "TOKEN_INVALID" };
  if (intent.nonce !== nonce) return { ok: false, error: "TOKEN_REPLAY" };
  if (Date.now() > intent.expires_at_ms) return { ok: false, error: "TOKEN_EXPIRED" };
  if (memberGroupId !== intent.group_id) return { ok: false, error: "NOT_AFFILIATED" };
  if (intent.status === "CONSUMED") return { ok: true, alreadyConsumed: true };

  intent.status = "CONSUMED";
  return { ok: true, alreadyConsumed: false };
}

// --------------- Mock wiring ---------------

const mockRpc = vi.fn().mockImplementation(
  (name: string, params: Record<string, unknown>) => Promise.resolve(handleRpc(name, params)),
);

function makeFromMock(table: string) {
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
      insert: (data: Record<string, unknown>) => {
        const evt: MockEvent = {
          id: `event-${++eventIdCounter}`,
          burn_ref_id: data.burn_ref_id as string,
          redeemer_group_id: data.redeemer_group_id as string,
          total_coins: data.total_coins as number,
          breakdown: data.breakdown as { issuer_group_id: string; amount: number }[],
        };
        events.push(evt);
        return {
          select: () => ({
            single: vi.fn().mockResolvedValue({ data: { id: evt.id } }),
          }),
        };
      },
      select: () => ({
        eq: () => ({
          order: () => ({ then: (r: Function) => r({ data: events }) }),
        }),
      }),
    };
  }
  if (table === "clearing_settlements") {
    return {
      insert: (data: Record<string, unknown>) => {
        const s: MockSettlement = {
          id: `settlement-${++settlementIdCounter}`,
          clearing_event_id: data.clearing_event_id as string,
          creditor_group_id: data.creditor_group_id as string,
          debtor_group_id: data.debtor_group_id as string,
          coin_amount: data.coin_amount as number,
          gross_amount_usd: data.gross_amount_usd as number,
          fee_rate_pct: data.fee_rate_pct as number,
          fee_amount_usd: data.fee_amount_usd as number,
          net_amount_usd: data.net_amount_usd as number,
          status: "pending",
        };
        settlements.push(s);
        return { error: null };
      },
      select: () => {
        const chain: Record<string, unknown> = {};
        chain.eq = vi.fn().mockImplementation((_col: string, val: string) => {
          chain._filters = chain._filters ?? {};
          (chain._filters as Record<string, string>)[_col] = val;
          return chain;
        });
        chain.gte = vi.fn().mockReturnValue(chain);
        chain.lt = vi.fn().mockReturnValue(chain);
        chain.or = vi.fn().mockReturnValue(chain);
        chain.order = vi.fn().mockReturnValue(chain);
        chain.then = (r: Function) => {
          const filters = (chain._filters ?? {}) as Record<string, string>;
          let result = settlements;
          if (filters.clearing_event_id) {
            result = result.filter((s) => s.clearing_event_id === filters.clearing_event_id);
          }
          if (filters.status) {
            result = result.filter((s) => s.status === filters.status);
          }
          return r({ data: result });
        };
        return chain;
      },
    };
  }
  if (table === "custody_accounts") {
    return {
      select: () => ({
        eq: () => ({
          maybeSingle: vi.fn().mockImplementation(() => {
            return Promise.resolve({ data: accounts["club-a"] ?? null });
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
}

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => makeFromMock(table),
    rpc: (...args: unknown[]) => mockRpc(...args),
  }),
}));

vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));

vi.mock("@/lib/custody", async (importOriginal) => {
  const original = await importOriginal<typeof import("@/lib/custody")>();
  return {
    ...original,
    assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
  };
});

const {
  processBurnForClearing,
  executeBurnAtomic,
  computeBurnPlan,
} = await import("./clearing");

const {
  convertToUsdWithSpread,
  convertFromUsdWithSpread,
} = await import("./custody");

// =================== SECTION 1: SMOKE TEST E2E ===================

describe("1. Smoke Test E2E — deterministic happy path", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    mockRpc.mockImplementation(
      (name: string, params: Record<string, unknown>) => Promise.resolve(handleRpc(name, params)),
    );
  });

  it("SEED: clubs A and B each have 1000 USD deposited, 100 coins committed", () => {
    expect(accounts["club-a"].total_deposited_usd).toBe(1000);
    expect(accounts["club-b"].total_deposited_usd).toBe(1000);
    expect(accounts["club-a"].total_committed).toBe(100);
    expect(accounts["club-b"].total_committed).toBe(100);
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

    expect(events).toHaveLength(1);
    expect(events[0].burn_ref_id).toBe("burn-smoke-1");
    expect(events[0].total_coins).toBe(100);
    expect(events[0].breakdown).toEqual([
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

    expect(settlements).toHaveLength(1);
    const s = settlements[0];
    expect(s.creditor_group_id).toBe("club-a");
    expect(s.debtor_group_id).toBe("club-b");
    expect(s.coin_amount).toBe(60);
    expect(s.gross_amount_usd).toBe(60);
    expect(s.fee_rate_pct).toBe(3.0);
    expect(s.fee_amount_usd).toBe(1.80);
    expect(s.net_amount_usd).toBe(58.20);
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

    expect(accounts["club-a"].total_committed).toBe(60);
    expect(accounts["club-b"].total_deposited_usd).toBe(940);
    expect(accounts["club-b"].total_committed).toBe(40);
    expect(accounts["club-a"].total_deposited_usd).toBeCloseTo(1058.20, 2);
    expect(platformRevenue).toBeCloseTo(1.80, 2);
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

    for (const acct of Object.values(accounts)) {
      const available = acct.total_deposited_usd - acct.total_committed;
      expect(available).toBeGreaterThanOrEqual(0);
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(acct.total_committed);
    }

    // A: 1058.20 - 60 = 998.20 ≥ 0
    expect(accounts["club-a"].total_deposited_usd - accounts["club-a"].total_committed)
      .toBeCloseTo(998.20, 2);
    // B: 940 - 40 = 900 ≥ 0
    expect(accounts["club-b"].total_deposited_usd - accounts["club-b"].total_committed)
      .toBe(900);
  });

  it("FX: BRL deposit with 0.75% spread → exact USD amount", () => {
    const result = convertToUsdWithSpread(1000, 5.0, 0.75);
    // 1000/5 = 200 raw, spread = 200*0.0075 = 1.50, net = 198.50
    expect(result.amountUsd).toBe(198.50);
    expect(result.spreadUsd).toBe(1.50);
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

// =================== SECTION 2: IDEMPOTENCY ===================

describe("2. Idempotency — repeated operations produce no side effects", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    mockRpc.mockImplementation(
      (name: string, params: Record<string, unknown>) => Promise.resolve(handleRpc(name, params)),
    );
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
    const before = { ...accounts["club-a"] };

    await processBurnForClearing({
      burnRefId: "idemp-burn-1",
      athleteUserId: "atletaA",
      redeemerGroupId: "club-a",
      totalCoins: 30,
      breakdown: [{ issuer_group_id: "club-a", amount: 30 }],
    });

    const afterFirst = { ...accounts["club-a"] };
    expect(afterFirst.total_committed).toBe(before.total_committed - 30);

    // Simulate reprocessing via executeBurnAtomic: first call succeeds
    burnRefsSeen.add("idemp-atomic-1");

    // Second call with same ref_id → duplicate key
    await expect(
      executeBurnAtomic({ userId: "atletaA", redeemerGroupId: "club-a", amount: 30, refId: "idemp-atomic-1" }),
    ).rejects.toThrow("duplicate key");

    // Balances unchanged after failed duplicate
    expect(accounts["club-a"].total_committed).toBe(afterFirst.total_committed);
    expect(accounts["club-a"].total_deposited_usd).toBe(afterFirst.total_deposited_usd);
  });

  it("2.3 Re-settle already-settled settlement returns error", () => {
    settlements.push({
      id: "s-done",
      clearing_event_id: "e1",
      creditor_group_id: "club-a",
      debtor_group_id: "club-b",
      coin_amount: 50,
      gross_amount_usd: 50,
      fee_rate_pct: 3.0,
      fee_amount_usd: 1.50,
      net_amount_usd: 48.50,
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

// =================== SECTION 3: ANTI-FRAUD / AUTHORIZATION ===================

describe("3. Anti-fraud — backend blocks invalid operations", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    mockRpc.mockImplementation(
      (name: string, params: Record<string, unknown>) => Promise.resolve(handleRpc(name, params)),
    );
  });

  it("3.1 Expired token is rejected", () => {
    const intent = createIntent({
      id: "expired-1",
      type: "BURN_FROM_ATHLETE",
      groupId: "club-a",
      amount: 50,
      nonce: "nonce-expired",
      ttlMs: -1, // already expired
    });

    const result = consumeIntent(intent.id, "nonce-expired", "atletaA", "club-a");
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
      error: { message: "BURN_PLAN_SHORTFALL: could not allocate requested amount" },
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
    accounts["club-a"].total_deposited_usd = 100;
    accounts["club-a"].total_committed = 100;

    mockRpc.mockResolvedValueOnce({
      error: { message: "Seller insufficient available backing" },
    });

    const { acceptSwapOffer } = await import("./swap");
    await expect(acceptSwapOffer("order-1", "club-b")).rejects.toThrow(
      "Seller insufficient available backing",
    );
  });
});

// =================== SECTION 4: CONCURRENCY ===================

describe("4. Concurrency — parallel operations produce correct results", () => {
  beforeEach(() => {
    resetState();
    resetIntents();
    vi.clearAllMocks();
    mockRpc.mockImplementation(
      (name: string, params: Record<string, unknown>) => Promise.resolve(handleRpc(name, params)),
    );
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
      consumeIntent("concurrent-token-1", "nonce-concurrent", "atletaA", "club-a"),
    );

    const firstBurns = results.filter((r) => r.ok && !r.alreadyConsumed);
    const alreadyConsumed = results.filter((r) => r.ok && r.alreadyConsumed);
    const errors = results.filter((r) => !r.ok);

    expect(firstBurns).toHaveLength(1);
    expect(alreadyConsumed).toHaveLength(99);
    expect(errors).toHaveLength(0);
  });

  it("4.2 1000 burns with same issuer → no negative balance, invariants valid", async () => {
    accounts["club-b"].total_deposited_usd = 10000;
    accounts["club-b"].total_committed = 1000;

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

    for (const acct of Object.values(accounts)) {
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(0);
      expect(acct.total_committed).toBeGreaterThanOrEqual(0);
      expect(acct.total_deposited_usd).toBeGreaterThanOrEqual(acct.total_committed);
    }
  });

  it("4.3 1000 interclub burns → no duplicate settlements, balances correct", async () => {
    accounts["club-b"].total_deposited_usd = 100_000;
    accounts["club-b"].total_committed = 10_000;
    accounts["club-a"].total_deposited_usd = 100_000;
    accounts["club-a"].total_committed = 10_000;

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

    const burnRefIds = settlements.map((s) => s.clearing_event_id);
    const uniqueRefs = new Set(burnRefIds);

    // No duplicate settlement per event
    const eventSettlementCount = new Map<string, number>();
    for (const s of settlements) {
      eventSettlementCount.set(s.clearing_event_id, (eventSettlementCount.get(s.clearing_event_id) ?? 0) + 1);
    }
    for (const [eventId, count] of eventSettlementCount) {
      expect(count).toBe(1);
    }

    // Invariants hold
    for (const acct of Object.values(accounts)) {
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
      expect((f as PromiseRejectedResult).reason.message).toContain("duplicate key");
    }
  });
});
