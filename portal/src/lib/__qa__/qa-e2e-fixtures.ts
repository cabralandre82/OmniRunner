/**
 * Shared fixtures for the QA E2E verification suite.
 *
 * L17-04 — the historical `qa-e2e.test.ts` grew to 842 lines across 4
 * describe-blocks (smoke / idempotency / anti-fraud / concurrency) with
 * a large shared mock DB at the top. That shape made cherry-picking a
 * failing scenario slow (Vitest had to re-evaluate every test on any
 * diff) and encouraged "comment-out the block" survival tactics when
 * unrelated changes flipped one assertion.
 *
 * This module hosts **only** the deterministic mock-DB + token state +
 * RPC dispatcher used by the 4 split test files under
 * `src/lib/qa-e2e-*.test.ts`. The test files import from here AND call
 * `vi.mock(...)` at their top level with factories that delegate to
 * `makeFromMock` / `mockRpc` — `vi.mock` is hoisted per-test-file by
 * the Vitest plugin, so it cannot be moved into a helper.
 *
 * Invariants:
 *   - Numbers must be verified to the cent — any drift fails the test.
 *   - All fixture functions are pure over the module-level mutable
 *     `state`; `resetState()` + `resetIntents()` must be called in each
 *     describe-block's `beforeEach` to guarantee isolation.
 *   - `mockRpc` is a Vitest `vi.fn()` so individual tests can re-wire
 *     it via `mockRpc.mockResolvedValueOnce(...)` for anti-fraud /
 *     error-path cases.
 */

import { vi } from "vitest";

export interface MockAccount {
  group_id: string;
  total_deposited_usd: number;
  total_committed: number;
  total_settled_usd: number;
  is_blocked: boolean;
  blocked_reason: string | null;
}

export interface MockSettlement {
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

export interface MockEvent {
  id: string;
  burn_ref_id: string;
  redeemer_group_id: string;
  total_coins: number;
  breakdown: { issuer_group_id: string; amount: number }[];
}

export interface MockIntent {
  id: string;
  status: "OPEN" | "CONSUMED";
  type: string;
  group_id: string;
  amount: number;
  nonce: string;
  expires_at_ms: number;
  athlete_user_id: string | null;
}

/**
 * Mutable shared state. Exported as a single object so test files can
 * read `state.accounts["club-a"].total_committed` after calling helpers
 * that mutate it in place.
 */
export const state: {
  accounts: Record<string, MockAccount>;
  events: MockEvent[];
  settlements: MockSettlement[];
  platformRevenue: number;
  burnRefsSeen: Set<string>;
  settlementIdCounter: number;
  eventIdCounter: number;
  claimMap: Map<string, "OPEN" | "CONSUMED">;
  intents: Record<string, MockIntent>;
} = {
  accounts: {},
  events: [],
  settlements: [],
  platformRevenue: 0,
  burnRefsSeen: new Set(),
  settlementIdCounter: 0,
  eventIdCounter: 0,
  claimMap: new Map(),
  intents: {},
};

export function resetState(): void {
  state.accounts = {
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
  state.events = [];
  state.settlements = [];
  state.platformRevenue = 0;
  state.burnRefsSeen = new Set();
  state.settlementIdCounter = 0;
  state.eventIdCounter = 0;
  state.claimMap = new Map();
}

export function resetIntents(): void {
  state.intents = {};
}

export function handleRpc(
  name: string,
  params: Record<string, unknown>,
): { data?: unknown; error: { message: string } | null } {
  if (name === "check_custody_invariants") {
    const violations = [];
    for (const acct of Object.values(state.accounts)) {
      if (acct.total_deposited_usd < acct.total_committed) {
        violations.push({ group_id: acct.group_id, violation: "D < R" });
      }
    }
    return { data: violations, error: null };
  }

  if (name === "custody_release_committed") {
    const gid = params.p_group_id as string;
    const amt = params.p_coin_count as number;
    const acct = state.accounts[gid];
    if (!acct) return { error: { message: "No account" } };
    if (acct.total_committed < amt)
      return {
        error: {
          message: `Invariant violation: committed=${acct.total_committed} < release=${amt}`,
        },
      };
    acct.total_committed -= amt;
    return { error: null };
  }

  if (name === "settle_clearing") {
    const sid = params.p_settlement_id as string;
    const s = state.settlements.find((x) => x.id === sid);
    if (!s)
      return { error: { message: "Settlement not found or not pending" } };
    if (s.status !== "pending")
      return { error: { message: "Settlement not found or not pending" } };

    const debtor = state.accounts[s.debtor_group_id];
    const creditor = state.accounts[s.creditor_group_id];
    if (!debtor || !creditor) return { error: { message: "Account not found" } };

    debtor.total_deposited_usd -= s.gross_amount_usd;
    debtor.total_committed -= s.coin_amount;
    creditor.total_deposited_usd += s.net_amount_usd;
    creditor.total_settled_usd += s.net_amount_usd;
    state.platformRevenue += s.fee_amount_usd;
    s.status = "settled";
    return { error: null };
  }

  if (name === "execute_burn_atomic") {
    const refId = params.p_ref_id as string;
    if (state.burnRefsSeen.has(refId)) {
      return {
        data: null,
        error: { message: "duplicate key value violates unique constraint" },
      };
    }
    state.burnRefsSeen.add(refId);
    return {
      data: {
        event_id: `evt-${++state.eventIdCounter}`,
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
    const seller = state.accounts["club-a"];
    const buyerAcct = state.accounts[buyer];
    if (!seller || !buyerAcct)
      return { error: { message: "Account not found" } };
    if (seller.total_deposited_usd - seller.total_committed < 100) {
      return { error: { message: "Seller insufficient available backing" } };
    }
    seller.total_deposited_usd -= 100;
    buyerAcct.total_deposited_usd += 99;
    state.platformRevenue += 1;
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

export function createIntent(params: {
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
  state.intents[params.id] = intent;
  return intent;
}

export function consumeIntent(
  intentId: string,
  nonce: string,
  _userId: string,
  memberGroupId: string,
): { ok: boolean; error?: string; alreadyConsumed?: boolean } {
  const intent = state.intents[intentId];
  if (!intent) return { ok: false, error: "TOKEN_INVALID" };
  if (intent.nonce !== nonce) return { ok: false, error: "TOKEN_REPLAY" };
  if (Date.now() > intent.expires_at_ms)
    return { ok: false, error: "TOKEN_EXPIRED" };
  if (memberGroupId !== intent.group_id)
    return { ok: false, error: "NOT_AFFILIATED" };
  if (intent.status === "CONSUMED") return { ok: true, alreadyConsumed: true };

  intent.status = "CONSUMED";
  return { ok: true, alreadyConsumed: false };
}

/** Shared `vi.fn()` RPC mock. Each describe-block's beforeEach rewires
 *  it to point at {@link handleRpc}; individual tests may override via
 *  `mockRpc.mockResolvedValueOnce(...)` to simulate error paths. */
export const mockRpc = vi
  .fn()
  .mockImplementation((name: string, params: Record<string, unknown>) =>
    Promise.resolve(handleRpc(name, params)),
  );

export function rewireMockRpc(): void {
  mockRpc.mockImplementation((name: string, params: Record<string, unknown>) =>
    Promise.resolve(handleRpc(name, params)),
  );
}

export function makeFromMock(table: string): unknown {
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
          id: `event-${++state.eventIdCounter}`,
          burn_ref_id: data.burn_ref_id as string,
          redeemer_group_id: data.redeemer_group_id as string,
          total_coins: data.total_coins as number,
          breakdown: data.breakdown as {
            issuer_group_id: string;
            amount: number;
          }[],
        };
        state.events.push(evt);
        return {
          select: () => ({
            single: vi.fn().mockResolvedValue({ data: { id: evt.id } }),
          }),
        };
      },
      select: () => ({
        eq: () => ({
          order: () => ({
            then: (r: (...args: unknown[]) => unknown) =>
              r({ data: state.events }),
          }),
        }),
      }),
    };
  }
  if (table === "clearing_settlements") {
    return {
      insert: (data: Record<string, unknown>) => {
        const s: MockSettlement = {
          id: `settlement-${++state.settlementIdCounter}`,
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
        state.settlements.push(s);
        return { error: null };
      },
      select: () => {
        const chain: Record<string, unknown> = {};
        chain.eq = vi
          .fn()
          .mockImplementation((_col: string, val: string) => {
            chain._filters = chain._filters ?? {};
            (chain._filters as Record<string, string>)[_col] = val;
            return chain;
          });
        chain.gte = vi.fn().mockReturnValue(chain);
        chain.lt = vi.fn().mockReturnValue(chain);
        chain.or = vi.fn().mockReturnValue(chain);
        chain.order = vi.fn().mockReturnValue(chain);
        chain.then = (r: (...args: unknown[]) => unknown) => {
          const filters = (chain._filters ?? {}) as Record<string, string>;
          let result = state.settlements;
          if (filters.clearing_event_id) {
            result = result.filter(
              (s) => s.clearing_event_id === filters.clearing_event_id,
            );
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
            return Promise.resolve({ data: state.accounts["club-a"] ?? null });
          }),
        }),
      }),
    };
  }
  return {
    select: () => ({
      eq: () => ({
        maybeSingle: vi.fn().mockResolvedValue({ data: null }),
        order: () => ({
          then: (r: (...args: unknown[]) => unknown) => r({ data: [] }),
        }),
      }),
    }),
  };
}
