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

const { GET, PATCH } = await import("./route");

const VALID_GROUP = "11111111-2222-4333-8444-555555555555";

function patchReq(
  body: unknown,
  opts: { idempotencyKey?: string | false; groupId?: string } = {},
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "x-forwarded-for": "127.0.0.1",
  };
  if (opts.idempotencyKey !== false) {
    headers["x-idempotency-key"] = opts.idempotencyKey ?? randomUUID();
  }
  const groupId = opts.groupId ?? VALID_GROUP;
  return new Request(
    `http://localhost/api/platform/custody/${groupId}/daily-cap`,
    {
      method: "PATCH",
      headers,
      body: JSON.stringify(body),
    },
  ) as unknown as import("next/server").NextRequest;
}

function getReq(opts: { groupId?: string } = {}) {
  const groupId = opts.groupId ?? VALID_GROUP;
  return new Request(
    `http://localhost/api/platform/custody/${groupId}/daily-cap`,
    { headers: { "x-forwarded-for": "127.0.0.1" } },
  ) as unknown as import("next/server").NextRequest;
}

function mockPlatformAdmin(role: string | null = "admin") {
  authClient.from.mockReturnValueOnce(
    queryChain({ data: role ? { platform_role: role } : null }),
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

function mockSetCapRpc(data: unknown, error: unknown = null) {
  serviceClient.rpc.mockReturnValueOnce(queryChain({ data, error }));
}

describe("GET /api/platform/custody/[groupId]/daily-cap — L05-09", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "platform-admin-1" } },
    });
  });

  it("401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await GET(getReq(), { params: { groupId: VALID_GROUP } });
    expect(res.status).toBe(401);
  });

  it("403 when not platform admin", async () => {
    mockPlatformAdmin(null);
    const res = await GET(getReq(), { params: { groupId: VALID_GROUP } });
    expect(res.status).toBe(403);
  });

  it("400 for invalid groupId (non-UUID)", async () => {
    mockPlatformAdmin();
    const res = await GET(getReq({ groupId: "not-a-uuid" }), {
      params: { groupId: "not-a-uuid" },
    });
    expect(res.status).toBe(400);
  });

  it("404 when no custody account exists for the group", async () => {
    mockPlatformAdmin();
    serviceClient.from.mockReturnValueOnce(queryChain({ data: null }));
    const res = await GET(getReq(), { params: { groupId: VALID_GROUP } });
    expect(res.status).toBe(404);
  });

  it("200 returns account + window snapshot + history", async () => {
    mockPlatformAdmin();
    serviceClient.from.mockReturnValueOnce(
      queryChain({
        data: {
          group_id: VALID_GROUP,
          daily_deposit_limit_usd: 50000,
          daily_limit_timezone: "America/Sao_Paulo",
          daily_limit_updated_at: "2026-04-21T12:00:00Z",
          daily_limit_updated_by: "actor-1",
        },
      }),
    );
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: [
          {
            current_total_usd: 1500,
            daily_limit_usd: 50000,
            available_today_usd: 48500,
            would_exceed: false,
            window_start_utc: "2026-04-21T03:00:00Z",
            window_end_utc: "2026-04-22T03:00:00Z",
            timezone: "America/Sao_Paulo",
          },
        ],
      }),
    );
    serviceClient.from.mockReturnValueOnce(
      queryChain({
        data: [
          {
            previous_cap_usd: 25000,
            new_cap_usd: 50000,
            actor_user_id: "actor-1",
            reason: "Black Friday — assessoria com volume sazonal alto",
            changed_at: "2026-04-21T12:00:00Z",
          },
        ],
      }),
    );

    const res = await GET(getReq(), { params: { groupId: VALID_GROUP } });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.account.daily_deposit_limit_usd).toBe(50000);
    expect(body.data.window.current_total_usd).toBe(1500);
    expect(body.data.window.would_exceed).toBe(false);
    expect(body.data.history).toHaveLength(1);
  });
});

describe("PATCH /api/platform/custody/[groupId]/daily-cap — L05-09", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "platform-admin-1" } },
    });
  });

  it("401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await PATCH(
      patchReq({ daily_deposit_limit_usd: 100000, reason: "ten chars min" }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(401);
  });

  it("403 when platform_role is not 'admin'", async () => {
    mockPlatformAdmin("viewer");
    const res = await PATCH(
      patchReq({ daily_deposit_limit_usd: 100000, reason: "ten chars min" }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(403);
  });

  it("400 for invalid groupId path", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq(
        { daily_deposit_limit_usd: 100000, reason: "ten chars min" },
        { groupId: "not-a-uuid" },
      ),
      { params: { groupId: "not-a-uuid" } },
    );
    expect(res.status).toBe(400);
  });

  it("400 for reason < 10 chars", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq({ daily_deposit_limit_usd: 100000, reason: "short" }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
  });

  it("400 for negative cap", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq({ daily_deposit_limit_usd: -1, reason: "ten chars min" }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
  });

  it("400 for cap above absolute ceiling (10M)", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq(
        { daily_deposit_limit_usd: 10_000_001, reason: "ten chars min" },
        {},
      ),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
  });

  it("400 for unknown body fields (strict schema)", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq({
        daily_deposit_limit_usd: 100000,
        reason: "valid postmortem text here",
        evil_field: "x",
      }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
  });

  it("400 when x-idempotency-key header is missing (delegated to L18-02)", async () => {
    mockPlatformAdmin();
    const res = await PATCH(
      patchReq(
        { daily_deposit_limit_usd: 100000, reason: "valid postmortem text" },
        { idempotencyKey: false },
      ),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
  });

  it("200 + audit log on happy path (50000 → 100000)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockSetCapRpc([
      {
        out_group_id: VALID_GROUP,
        out_previous_cap_usd: 50000,
        out_new_cap_usd: 100000,
        out_changed_at: "2026-04-21T12:00:00Z",
      },
    ]);
    mockIdemFinalize();

    const res = await PATCH(
      patchReq({
        daily_deposit_limit_usd: 100000,
        reason: "Black Friday — assessoria sazonal de alto volume",
      }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.previous_cap_usd).toBe(50000);
    expect(body.data.new_cap_usd).toBe(100000);
    expect(auditLog).toHaveBeenCalledWith(
      expect.objectContaining({
        actorId: "platform-admin-1",
        groupId: VALID_GROUP,
        action: "platform.custody.daily-cap.set",
        targetType: "custody_account",
        targetId: VALID_GROUP,
        metadata: expect.objectContaining({
          previous_cap_usd: 50000,
          new_cap_usd: 100000,
          reason: "Black Friday — assessoria sazonal de alto volume",
          runbook: "CUSTODY_DAILY_CAP_RUNBOOK",
        }),
      }),
    );
  });

  it("400 when RPC raises P0001 (validation passes through)", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockSetCapRpc(null, {
      code: "P0001",
      message: "p_reason must be >= 10 chars",
    });
    mockIdemFinalize();

    const res = await PATCH(
      patchReq({
        daily_deposit_limit_usd: 100000,
        reason: "ten chars+ ok",
      }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("VALIDATION_FAILED");
  });

  it("500 INTERNAL_ERROR when RPC fails unexpectedly", async () => {
    mockPlatformAdmin();
    mockIdemBeginExecute();
    mockSetCapRpc(null, { code: "P9999", message: "unexpected" });
    mockIdemFinalize();

    const res = await PATCH(
      patchReq({
        daily_deposit_limit_usd: 100000,
        reason: "valid postmortem text",
      }),
      { params: { groupId: VALID_GROUP } },
    );
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("INTERNAL_ERROR");
  });
});
