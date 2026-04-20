import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// L17-01 — withErrorHandler wrapper requires a NextRequest argument.
const req = () => new NextRequest("http://localhost/api/platform/invariants");

const mockGetUser = vi.fn();
const mockSelectSingle = vi.fn();
const mockRpc = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({
    auth: { getUser: mockGetUser },
    from: () => ({
      select: () => ({
        eq: () => ({ single: mockSelectSingle }),
      }),
    }),
  }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: mockRpc,
  }),
}));

vi.mock("@/lib/metrics", () => ({
  metrics: {
    gauge: vi.fn(),
    increment: vi.fn(),
    timing: vi.fn(),
  },
}));

vi.mock("@/lib/logger", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

const { GET } = await import("./route");

/**
 * RPC dispatcher used by every test that gets past auth: the route now
 * calls the custody RPC AND (via checkAndRecordWalletDrift) the wallet
 * drift RPCs. Tests that don't care about wallet drift can rely on the
 * default `clean` setup.
 */
function setupHealthyRpc() {
  mockRpc.mockImplementation((fn: string) => {
    if (fn === "check_custody_invariants") {
      return Promise.resolve({ data: [], error: null });
    }
    if (fn === "fn_check_wallet_ledger_drift") {
      return Promise.resolve({ data: [], error: null });
    }
    if (fn === "fn_classify_wallet_drift_severity") {
      return Promise.resolve({ data: "ok", error: null });
    }
    return Promise.resolve({ data: null, error: null });
  });
}

describe("/api/platform/invariants", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(req());
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET(req());
    expect(res.status).toBe(403);
  });

  it("returns healthy=true when there are no violations and no wallet drift", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    setupHealthyRpc();

    const res = await GET(req());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.healthy).toBe(true);
    expect(body.violations).toEqual([]);
    expect(body.wallet_drift.healthy).toBe(true);
    expect(body.wallet_drift.severity).toBe("ok");
    expect(body.wallet_drift.count).toBe(0);
    expect(body.wallet_drift.sample).toEqual([]);
    expect(body.wallet_drift.drift_event_id).toBeNull();
    expect(body.checked_at).toBeDefined();
    expect(body.request_id).toMatch(/[0-9a-f-]{36}/);
  });

  it("returns healthy=false with custody violations", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockImplementation((fn: string) => {
      if (fn === "check_custody_invariants") {
        return Promise.resolve({
          data: [
            {
              group_id: "g1",
              total_deposited: 100,
              total_committed: 200,
              computed_available: -100,
              violation: "deposited_less_than_committed",
            },
          ],
          error: null,
        });
      }
      if (fn === "fn_check_wallet_ledger_drift") {
        return Promise.resolve({ data: [], error: null });
      }
      if (fn === "fn_classify_wallet_drift_severity") {
        return Promise.resolve({ data: "ok", error: null });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const res = await GET(req());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.healthy).toBe(false);
    expect(body.violations).toHaveLength(1);
    expect(body.violations[0].violation).toBe("deposited_less_than_committed");
    expect(body.wallet_drift.healthy).toBe(true); // wallets fine even though custody violated
  });

  it("returns 500 on custody rpc error", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockImplementation((fn: string) => {
      if (fn === "check_custody_invariants") {
        return Promise.resolve({
          data: null,
          error: { message: "db failure" },
        });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const res = await GET(req());
    expect(res.status).toBe(500);
  });

  it("returns wallet_drift sample + drift_event_id when drift > 0", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockImplementation((fn: string, _args?: unknown) => {
      if (fn === "check_custody_invariants") {
        return Promise.resolve({ data: [], error: null });
      }
      if (fn === "fn_check_wallet_ledger_drift") {
        return Promise.resolve({
          data: [
            {
              user_id: "u-1",
              balance_coins: 100,
              ledger_sum: 50,
              drift: -50,
              last_reconciled_at_ms: 1_745_000_000_000,
              recent_activity: true,
            },
            {
              user_id: "u-2",
              balance_coins: 0,
              ledger_sum: 5,
              drift: 5,
              last_reconciled_at_ms: null,
              recent_activity: false,
            },
          ],
          error: null,
        });
      }
      if (fn === "fn_classify_wallet_drift_severity") {
        return Promise.resolve({ data: "warn", error: null });
      }
      if (fn === "fn_record_wallet_drift_event") {
        return Promise.resolve({ data: "evt-uuid-123", error: null });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const res = await GET(req());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.healthy).toBe(false);
    expect(body.wallet_drift.healthy).toBe(false);
    expect(body.wallet_drift.severity).toBe("warn");
    expect(body.wallet_drift.count).toBe(2);
    expect(body.wallet_drift.sample).toHaveLength(2);
    expect(body.wallet_drift.drift_event_id).toBe("evt-uuid-123");
  });

  it("caps the wallet_drift sample at 50 even when many rows drift", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    const bigDriftRows = Array.from({ length: 75 }, (_, i) => ({
      user_id: `u-${i}`,
      balance_coins: i,
      ledger_sum: 0,
      drift: -i,
      last_reconciled_at_ms: null,
      recent_activity: i % 2 === 0,
    }));
    mockRpc.mockImplementation((fn: string) => {
      if (fn === "check_custody_invariants") {
        return Promise.resolve({ data: [], error: null });
      }
      if (fn === "fn_check_wallet_ledger_drift") {
        return Promise.resolve({ data: bigDriftRows, error: null });
      }
      if (fn === "fn_classify_wallet_drift_severity") {
        return Promise.resolve({ data: "critical", error: null });
      }
      if (fn === "fn_record_wallet_drift_event") {
        return Promise.resolve({ data: "evt-big", error: null });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const res = await GET(req());
    const body = await res.json();

    expect(body.wallet_drift.count).toBe(75);
    expect(body.wallet_drift.sample).toHaveLength(50);
    expect(body.wallet_drift.severity).toBe("critical");
  });

  it("does NOT mask custody result when wallet drift check fails", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockImplementation((fn: string) => {
      if (fn === "check_custody_invariants") {
        return Promise.resolve({ data: [], error: null });
      }
      if (fn === "fn_check_wallet_ledger_drift") {
        return Promise.resolve({
          data: null,
          error: { message: "lock_timeout exceeded" },
        });
      }
      return Promise.resolve({ data: null, error: null });
    });

    const res = await GET(req());
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.violations).toEqual([]);
    expect(body.wallet_drift.healthy).toBe(false);
    expect(body.wallet_drift.error).toMatch(/lock_timeout/);
    expect(body.healthy).toBe(false); // overall healthy reflects the failure
  });
});
