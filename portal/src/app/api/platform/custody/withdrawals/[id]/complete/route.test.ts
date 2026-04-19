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
const PAYOUT_REF = "asaas_transfer_abc123";

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
  return new Request(`http://localhost/api/platform/custody/withdrawals/${id}/complete`, {
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

function mockCompleteRpc(data: unknown, error: unknown = null) {
  serviceClient.rpc.mockReturnValueOnce(queryChain({ data, error }));
}

describe("POST /api/platform/custody/withdrawals/[id]/complete — L02-06", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "platform-admin-1" } },
    });
  });

  it("401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(401);
  });

  it("403 when not platform admin", async () => {
    mockPlatformAdmin(null);
    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(403);
  });

  it("403 when platform_role is not 'admin'", async () => {
    mockPlatformAdmin("viewer");
    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(403);
  });

  it("400 for non-uuid path id", async () => {
    mockPlatformAdmin();
    const res = await POST(
      req({ payout_reference: PAYOUT_REF }, { id: "not-a-uuid" }),
      { params: { id: "not-a-uuid" } },
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
  });

  it("400 when payout_reference is missing", async () => {
    mockPlatformAdmin();
    const res = await POST(req({}), { params: { id: VALID_ID } });
    expect(res.status).toBe(400);
  });

  it("400 when payout_reference is too short", async () => {
    mockPlatformAdmin();
    const res = await POST(req({ payout_reference: "ab" }), { params: { id: VALID_ID } });
    expect(res.status).toBe(400);
  });

  it("400 for unknown body fields (strict schema)", async () => {
    mockPlatformAdmin();
    const res = await POST(
      req({ payout_reference: PAYOUT_REF, foreign_field: "x" }),
      { params: { id: VALID_ID } },
    );
    expect(res.status).toBe(400);
  });

  it("200 + audit log on happy path (processing → completed)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockCompleteRpc([
      {
        withdrawal_id: VALID_ID,
        status: "completed",
        was_terminal: false,
        completed_at: "2026-04-19T12:00:00Z",
      },
    ]);
    mockIdemFinalize();

    const res = await POST(
      req({ payout_reference: PAYOUT_REF, note: "Confirmed via Asaas dashboard" }),
      { params: { id: VALID_ID } },
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.status).toBe("completed");
    expect(body.data.was_terminal).toBe(false);
    expect(auditLog).toHaveBeenCalledWith(
      expect.objectContaining({
        actorId: "platform-admin-1",
        action: "platform.custody.withdrawal.complete",
        targetType: "custody_withdrawal",
        targetId: VALID_ID,
        metadata: expect.objectContaining({
          payout_reference: PAYOUT_REF,
          note: "Confirmed via Asaas dashboard",
          runbook: "WITHDRAW_STUCK_RUNBOOK#3.1",
        }),
      }),
    );
  });

  it("skips audit log when RPC reports already-terminal (idempotent re-click)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockCompleteRpc([
      {
        withdrawal_id: VALID_ID,
        status: "completed",
        was_terminal: true,
        completed_at: "2026-04-19T11:00:00Z",
      },
    ]);
    mockIdemFinalize();

    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.was_terminal).toBe(true);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("404 when RPC raises WITHDRAWAL_NOT_FOUND (P0002)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockCompleteRpc(null, { code: "P0002", message: "WITHDRAWAL_NOT_FOUND" });
    mockIdemFinalize();

    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.error.code).toBe("NOT_FOUND");
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("409 when RPC raises INVALID_TRANSITION (e.g. already cancelled)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockCompleteRpc(null, {
      code: "P0008",
      message: "INVALID_TRANSITION: cancelled → completed (only processing allowed)",
    });
    mockIdemFinalize();

    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_TRANSITION");
    expect(body.error.message).toContain("cancelled");
  });

  it("500 on unexpected DB error", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockCompleteRpc(null, { code: "XX000", message: "connection lost" });
    mockIdemFinalize();

    const res = await POST(req({ payout_reference: PAYOUT_REF }), { params: { id: VALID_ID } });
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
  });
});
