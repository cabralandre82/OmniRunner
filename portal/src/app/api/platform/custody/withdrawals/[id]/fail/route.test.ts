import { describe, it, expect, vi, beforeEach } from "vitest";
import { randomUUID } from "node:crypto";
import { queryChain, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient();
const serviceClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => serviceClient,
}));

const auditLog = vi.fn().mockResolvedValue(undefined);
vi.mock("@/lib/audit", () => ({ auditLog }));

vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 30, resetAt: Date.now() + 60_000 }),
}));

vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));

const { POST } = await import("./route");

const VALID_ID = "11111111-2222-4333-8444-555555555555";
const REASON = "Bank rejected: invalid routing number";

function req(
  body: unknown,
  opts: { idempotencyKey?: string | false; id?: string } = {},
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "x-forwarded-for": "127.0.0.1",
  };
  if (opts.idempotencyKey !== false) {
    headers["x-idempotency-key"] = opts.idempotencyKey ?? randomUUID();
  }
  const id = opts.id ?? VALID_ID;
  return new Request(`http://localhost/api/platform/custody/withdrawals/${id}/fail`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

function mockPlatformAdmin(role: string | null = "admin") {
  authClient.from.mockReturnValueOnce(
    queryChain({ data: role ? { platform_role: role } : null }),
  );
}

function mockIdemBeginExecute() {
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({
      data: [{ action: "execute", replay_status: null, replay_body: null, stale_recovered: false }],
      error: null,
    }),
  );
}

function mockIdemFinalize() {
  serviceClient.rpc.mockReturnValueOnce(queryChain({ data: true, error: null }));
}

function mockFailRpc(data: unknown, error: unknown = null) {
  serviceClient.rpc.mockReturnValueOnce(queryChain({ data, error }));
}

describe("POST /api/platform/custody/withdrawals/[id]/fail — L02-06", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "platform-admin-1" } },
    });
  });

  it("401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(401);
  });

  it("403 when not platform admin", async () => {
    mockPlatformAdmin(null);
    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(403);
  });

  it("400 for non-uuid path id", async () => {
    mockPlatformAdmin();
    const res = await POST(req({ reason: REASON }, { id: "not-a-uuid" }), {
      params: { id: "not-a-uuid" },
    });
    expect(res.status).toBe(400);
  });

  it("400 when reason is missing", async () => {
    mockPlatformAdmin();
    const res = await POST(req({}), { params: { id: VALID_ID } });
    expect(res.status).toBe(400);
  });

  it("400 when reason is too short", async () => {
    mockPlatformAdmin();
    const res = await POST(req({ reason: "no" }), { params: { id: VALID_ID } });
    expect(res.status).toBe(400);
  });

  it("200 + audit log on happy path with refund + revenue rollback", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc([
      {
        withdrawal_id: VALID_ID,
        status: "failed",
        was_terminal: false,
        refunded_usd: "250.00",
        revenue_reversed: "1.88",
      },
    ]);
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.status).toBe("failed");
    expect(body.data.refunded_usd).toBe(250);
    expect(body.data.revenue_reversed_usd).toBe(1.88);
    expect(auditLog).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "platform.custody.withdrawal.fail",
        targetId: VALID_ID,
        metadata: expect.objectContaining({
          reason: REASON,
          refunded_usd: 250,
          revenue_reversed_usd: 1.88,
          runbook: "WITHDRAW_STUCK_RUNBOOK#3.3",
        }),
      }),
    );
  });

  it("skips audit log on idempotent re-click (was_terminal=true)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc([
      {
        withdrawal_id: VALID_ID,
        status: "failed",
        was_terminal: true,
        refunded_usd: 0,
        revenue_reversed: 0,
      },
    ]);
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.was_terminal).toBe(true);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("404 when RPC raises WITHDRAWAL_NOT_FOUND", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc(null, { code: "P0002", message: "WITHDRAWAL_NOT_FOUND" });
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error.code).toBe("NOT_FOUND");
  });

  it("409 INVALID_TRANSITION when withdrawal not in 'processing'", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc(null, {
      code: "P0008",
      message: "INVALID_TRANSITION: pending → failed (only processing allowed)",
    });
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_TRANSITION");
  });

  it("409 INVARIANT_VIOLATION when refund would unbalance custody", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc(null, {
      code: "P0008",
      message: "INVARIANT_VIOLATION: refund would unbalance custody for group abc",
    });
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error.code).toBe("INVARIANT_VIOLATION");
    expect(body.error.details).toMatchObject({
      hint: expect.stringContaining("WITHDRAW_STUCK_RUNBOOK"),
    });
  });

  it("500 on unexpected DB error", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockFailRpc(null, { code: "XX000", message: "deadlock detected" });
    mockIdemFinalize();

    const res = await POST(req({ reason: REASON }), { params: { id: VALID_ID } });
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
  });
});
