import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

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
  metrics: { gauge: vi.fn(), increment: vi.fn(), timing: vi.fn() },
}));

vi.mock("@/lib/logger", () => ({
  logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

const { GET } = await import("./route");

function makeReq(qs: string = "") {
  return new NextRequest(`http://localhost/api/platform/invariants/wallets${qs}`);
}

function authedAdmin() {
  mockGetUser.mockResolvedValue({ data: { user: { id: "admin-1" } } });
  mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
}

function setupRpc(args: {
  driftRows?: Array<unknown>;
  severity?: "ok" | "warn" | "critical";
  eventId?: string | null;
  driftError?: string;
} = {}) {
  mockRpc.mockImplementation((fn: string) => {
    if (fn === "fn_check_wallet_ledger_drift") {
      if (args.driftError) {
        return Promise.resolve({ data: null, error: { message: args.driftError } });
      }
      return Promise.resolve({ data: args.driftRows ?? [], error: null });
    }
    if (fn === "fn_classify_wallet_drift_severity") {
      return Promise.resolve({ data: args.severity ?? "ok", error: null });
    }
    if (fn === "fn_record_wallet_drift_event") {
      return Promise.resolve({ data: args.eventId ?? "evt-1", error: null });
    }
    return Promise.resolve({ data: null, error: null });
  });
}

describe("GET /api/platform/invariants/wallets (L08-07)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(makeReq());
    expect(res.status).toBe(401);
  });

  it("403 when not platform admin", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u" } } });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET(makeReq());
    expect(res.status).toBe(403);
  });

  it("400 on bad query (max_users out of range)", async () => {
    authedAdmin();
    setupRpc();
    const res = await GET(makeReq("?max_users=999999"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("BAD_REQUEST");
  });

  it("400 on unknown query parameter (.strict)", async () => {
    authedAdmin();
    setupRpc();
    const res = await GET(makeReq("?max_users=10&unknown=1"));
    expect(res.status).toBe(400);
  });

  it("returns healthy=true with empty rows when no drift", async () => {
    authedAdmin();
    setupRpc({ driftRows: [], severity: "ok" });
    const res = await GET(makeReq());
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.healthy).toBe(true);
    expect(body.severity).toBe("ok");
    expect(body.rows).toEqual([]);
    expect(body.count).toBe(0);
    expect(body.drift_event_id).toBeNull();
    expect(body.params.max_users).toBe(5000);
    expect(body.params.recent_hours).toBe(24);
    expect(body.params.warn_threshold).toBe(10);
  });

  it("returns FULL drift rows (no 50 cap) plus drift_event_id when severity != ok", async () => {
    authedAdmin();
    const rows = Array.from({ length: 60 }, (_, i) => ({
      user_id: `u-${i}`,
      balance_coins: i,
      ledger_sum: 0,
      drift: -i,
      last_reconciled_at_ms: null,
      recent_activity: true,
    }));
    setupRpc({ driftRows: rows, severity: "critical", eventId: "evt-big" });
    const res = await GET(makeReq("?max_users=100&recent_hours=6&warn_threshold=5"));
    const body = await res.json();
    expect(res.status).toBe(200);
    expect(body.healthy).toBe(false);
    expect(body.severity).toBe("critical");
    expect(body.count).toBe(60);
    expect(body.rows).toHaveLength(60);
    expect(body.drift_event_id).toBe("evt-big");
    expect(body.params.max_users).toBe(100);
    expect(body.params.recent_hours).toBe(6);
    expect(body.params.warn_threshold).toBe(5);
    expect(typeof body.duration_ms).toBe("number");
  });

  it("forwards parsed query knobs into the drift RPC call", async () => {
    authedAdmin();
    setupRpc({ driftRows: [], severity: "ok" });
    await GET(makeReq("?max_users=250&recent_hours=12&warn_threshold=3"));

    const driftCall = mockRpc.mock.calls.find(
      (c) => c[0] === "fn_check_wallet_ledger_drift",
    );
    expect(driftCall).toBeTruthy();
    expect(driftCall![1]).toEqual({ p_max_users: 250, p_recent_hours: 12 });

    const classifyCall = mockRpc.mock.calls.find(
      (c) => c[0] === "fn_classify_wallet_drift_severity",
    );
    expect(classifyCall).toBeTruthy();
    expect(classifyCall![1]).toEqual({
      p_drifted_count: 0,
      p_warn_threshold: 3,
    });
  });

  it("returns 500 with request_id when the drift RPC fails", async () => {
    authedAdmin();
    setupRpc({ driftError: "lock_timeout exceeded" });
    const res = await GET(makeReq());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error).toBe("INTERNAL");
    expect(body.detail).toMatch(/lock_timeout/);
    expect(body.request_id).toMatch(/[0-9a-f-]{36}/);
  });
});
