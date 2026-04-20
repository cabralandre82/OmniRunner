import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

const A1 = "00000000-0000-4000-a000-000000000001";
const A2 = "00000000-0000-4000-a000-000000000002";
const A3 = "00000000-0000-4000-a000-000000000003";

const authClient = makeMockClient(TEST_SESSION);
const serviceClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => serviceClient,
}));
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockResolvedValue({ allowed: true, remaining: 5 }),
}));
vi.mock("@/lib/feature-flags", () => ({
  assertSubsystemEnabled: vi.fn().mockResolvedValue(undefined),
  isSubsystemEnabled: vi.fn().mockResolvedValue(true),
  FeatureDisabledError: class FeatureDisabledError extends Error {
    constructor(
      public readonly key: string,
      public readonly code: string,
      public readonly hint: string,
    ) {
      super(hint);
    }
  },
}));
vi.mock("@/lib/custody", () => ({
  assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
}));

const { POST } = await import("./route");
const { auditLog } = await import("@/lib/audit");
const { rateLimit } = await import("@/lib/rate-limit");
const { assertInvariantsHealthy } = await import("@/lib/custody");
const featureFlags = await import("@/lib/feature-flags");

function req(
  body: unknown,
  headers: Record<string, string> = {},
): Request {
  return new Request("http://localhost/api/distribute-coins/batch", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function mockAdminCheck(role = "admin_master") {
  serviceClient.from.mockReturnValueOnce(queryChain({ data: { role } }));
}

function mockBatchRpc(
  result:
    | {
        total_amount: number;
        total_distributions: number;
        batch_was_idempotent: boolean;
        items: Array<{
          athlete_user_id: string;
          amount: number;
          new_balance: number;
          was_idempotent: boolean;
          ledger_id: string;
        }>;
      }
    | null,
  error: { code?: string; message?: string } | null = null,
) {
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({ data: result ? [result] : null, error }),
  );
}

function mockIdemBeginExecute() {
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({
      data: [
        {
          action: "execute",
          replay_status: null,
          replay_body: null,
          stale_recovered: false,
        },
      ],
      error: null,
    }),
  );
}

function mockIdemFinalize() {
  serviceClient.rpc.mockReturnValueOnce(queryChain({ data: true, error: null }));
}

const SAMPLE_BATCH = {
  items: [
    { athlete_user_id: A1, amount: 10 },
    { athlete_user_id: A2, amount: 20 },
  ],
};

describe("POST /api/distribute-coins/batch (L05-03)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: TEST_SESSION.user },
    });
    (rateLimit as any).mockResolvedValue({
      allowed: true,
      remaining: 5,
      resetAt: Date.now() + 60_000,
    });
    (assertInvariantsHealthy as any).mockResolvedValue(true);
    (featureFlags.assertSubsystemEnabled as any).mockResolvedValue(undefined);
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(401);
  });

  it("returns 503 when distribute_coins kill switch is off (L06-06)", async () => {
    const FlagErr = featureFlags.FeatureDisabledError as any;
    (featureFlags.assertSubsystemEnabled as any).mockRejectedValueOnce(
      new FlagErr("distribute_coins.enabled", "FEATURE_DISABLED", "off"),
    );
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("30");
  });

  it("returns 429 when rate-limited", async () => {
    (rateLimit as any).mockResolvedValueOnce({
      allowed: false,
      remaining: 0,
      resetAt: Date.now() + 5_000,
    });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(429);
  });

  it("returns 403 when caller is not admin_master", async () => {
    mockAdminCheck("athlete");
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(403);
  });

  it("returns 400 on malformed JSON body", async () => {
    mockAdminCheck();
    const res = await POST(req("{not json", {}) as any);
    expect(res.status).toBe(400);
  });

  it("returns 400 on empty items array", async () => {
    mockAdminCheck();
    const res = await POST(req({ items: [] }) as any);
    expect(res.status).toBe(400);
  });

  it("returns 400 on duplicate athlete_user_id", async () => {
    mockAdminCheck();
    const res = await POST(
      req({
        items: [
          { athlete_user_id: A1, amount: 10 },
          { athlete_user_id: A1, amount: 5 },
        ],
      }) as any,
    );
    expect(res.status).toBe(400);
    expect((await res.json()).error.message).toContain("duplicado");
  });

  it("returns 400 on per-item amount exceeding cap", async () => {
    mockAdminCheck();
    const res = await POST(
      req({ items: [{ athlete_user_id: A1, amount: 100_001 }] }) as any,
    );
    expect(res.status).toBe(400);
  });

  it("returns 503 when invariants are unhealthy", async () => {
    mockAdminCheck();
    (assertInvariantsHealthy as any).mockResolvedValueOnce(false);
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(503);
  });

  it("returns 422 when RPC reports CUSTODY_FAILED (P0002) — entire batch rolls back", async () => {
    mockAdminCheck();
    mockBatchRpc(null, {
      code: "P0002",
      message: "CUSTODY_FAILED: Insufficient backing for batch",
    });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("CUSTODY_FAILED");
    // No audit log on rollback.
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("returns 422 when RPC reports INVENTORY_INSUFFICIENT (P0003)", async () => {
    mockAdminCheck();
    mockBatchRpc(null, { code: "P0003", message: "INVENTORY_INSUFFICIENT" });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("INVENTORY_INSUFFICIENT");
  });

  it("returns 503 with Retry-After when RPC hits lock_timeout (55P03)", async () => {
    mockAdminCheck();
    mockBatchRpc(null, {
      code: "55P03",
      message: "canceling statement due to lock timeout",
    });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("2");
  });

  it("returns 200 and credits all athletes in a single transaction (happy path)", async () => {
    mockAdminCheck();
    mockBatchRpc({
      total_amount: 30,
      total_distributions: 2,
      batch_was_idempotent: false,
      items: [
        {
          athlete_user_id: A1,
          amount: 10,
          new_balance: 110,
          was_idempotent: false,
          ledger_id: "ledger-1",
        },
        {
          athlete_user_id: A2,
          amount: 20,
          new_balance: 220,
          was_idempotent: false,
          ledger_id: "ledger-2",
        },
      ],
    });

    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.total_amount).toBe(30);
    expect(json.total_distributions).toBe(2);
    expect(json.batch_was_idempotent).toBe(false);
    expect(json.items).toHaveLength(2);
    expect(json.items[0].new_balance).toBe(110);
    // L05-03 — bulk audit fires once per non-idempotent batch.
    expect(auditLog).toHaveBeenCalledTimes(1);
    const meta: any = (auditLog as any).mock.calls[0][0];
    expect(meta.action).toBe("coins.distribute.batch");
    expect(meta.metadata.total_distributions).toBe(2);
    expect(meta.metadata.new_distributions).toBe(2);
  });

  it("does NOT call audit when batch is fully idempotent (replay)", async () => {
    mockAdminCheck();
    mockIdemBeginExecute();
    mockBatchRpc({
      total_amount: 30,
      total_distributions: 2,
      batch_was_idempotent: true,
      items: [
        {
          athlete_user_id: A1,
          amount: 10,
          new_balance: 110,
          was_idempotent: true,
          ledger_id: "ledger-1",
        },
        {
          athlete_user_id: A2,
          amount: 20,
          new_balance: 220,
          was_idempotent: true,
          ledger_id: "ledger-2",
        },
      ],
    });
    mockIdemFinalize();

    const res = await POST(
      req(SAMPLE_BATCH, { "x-idempotency-key": "weekly-bonus-w17-2026" }) as any,
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.batch_was_idempotent).toBe(true);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("logs audit ONLY for new items when batch mixes new + idempotent items", async () => {
    mockAdminCheck();
    mockBatchRpc({
      total_amount: 35,
      total_distributions: 3,
      batch_was_idempotent: false,
      items: [
        {
          athlete_user_id: A1,
          amount: 10,
          new_balance: 110,
          was_idempotent: true,
          ledger_id: "ledger-1",
        },
        {
          athlete_user_id: A2,
          amount: 20,
          new_balance: 220,
          was_idempotent: false,
          ledger_id: "ledger-2",
        },
        {
          athlete_user_id: A3,
          amount: 5,
          new_balance: 305,
          was_idempotent: false,
          ledger_id: "ledger-3",
        },
      ],
    });

    const res = await POST(
      req({
        items: [
          { athlete_user_id: A1, amount: 10 },
          { athlete_user_id: A2, amount: 20 },
          { athlete_user_id: A3, amount: 5 },
        ],
      }) as any,
    );
    expect(res.status).toBe(200);
    expect(auditLog).toHaveBeenCalledTimes(1);
    const meta: any = (auditLog as any).mock.calls[0][0];
    expect(meta.metadata.new_distributions).toBe(2);
    expect(meta.metadata.replayed_distributions).toBe(1);
    expect(meta.metadata.items).toHaveLength(2);
  });

  it("calls distribute_coins_batch_atomic with correct parameters", async () => {
    mockAdminCheck();
    mockBatchRpc({
      total_amount: 30,
      total_distributions: 2,
      batch_was_idempotent: false,
      items: [
        {
          athlete_user_id: A1,
          amount: 10,
          new_balance: 110,
          was_idempotent: false,
          ledger_id: "L1",
        },
        {
          athlete_user_id: A2,
          amount: 20,
          new_balance: 220,
          was_idempotent: false,
          ledger_id: "L2",
        },
      ],
    });

    await POST(
      req({
        items: SAMPLE_BATCH.items,
        ref_id: "weekly-bonus-w17-2026",
      }) as any,
    );

    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("distribute_coins_batch_atomic");
    expect(call[1]).toMatchObject({
      p_group_id: "group-1",
      p_caller_user_id: TEST_SESSION.user.id,
      p_batch_ref_id: "weekly-bonus-w17-2026",
    });
    expect(call[1].p_items).toHaveLength(2);
    expect(call[1].p_items[0].athlete_user_id).toBe(A1);
  });

  it("falls back to derived ref_id when neither body.ref_id nor x-idempotency-key is present", async () => {
    mockAdminCheck();
    mockBatchRpc({
      total_amount: 30,
      total_distributions: 2,
      batch_was_idempotent: false,
      items: [
        {
          athlete_user_id: A1,
          amount: 10,
          new_balance: 110,
          was_idempotent: false,
          ledger_id: "L1",
        },
        {
          athlete_user_id: A2,
          amount: 20,
          new_balance: 220,
          was_idempotent: false,
          ledger_id: "L2",
        },
      ],
    });

    await POST(req(SAMPLE_BATCH) as any);
    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("distribute_coins_batch_atomic");
    expect(call[1].p_batch_ref_id).toMatch(/^portal_batch_.*_\d+$/);
  });

  it("returns 500 when the RPC errors with an unmapped failure", async () => {
    mockAdminCheck();
    mockBatchRpc(null, { message: "unexpected database error" });
    const res = await POST(req(SAMPLE_BATCH) as any);
    expect(res.status).toBe(500);
  });
});
