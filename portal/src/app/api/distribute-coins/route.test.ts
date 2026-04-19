import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

const ATHLETE_UUID = "00000000-0000-4000-a000-000000000001";
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
  rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }),
}));

// L06-06 — kill switch lib mockada (cobertura em src/lib/feature-flags.test.ts).
vi.mock("@/lib/feature-flags", () => ({
  assertSubsystemEnabled: vi.fn().mockResolvedValue(undefined),
  isSubsystemEnabled: vi.fn().mockResolvedValue(true),
  FeatureDisabledError: class FeatureDisabledError extends Error {},
}));
vi.mock("@/lib/custody", () => ({
  assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
}));

const { POST } = await import("./route");
const { auditLog } = await import("@/lib/audit");

function req(body: Record<string, unknown>, headers: Record<string, string> = {}) {
  return new Request("http://localhost/api/distribute-coins", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: JSON.stringify(body),
  });
}

function mockAdminCheck(role = "admin_master") {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: { role } }),
  );
}

function mockAthleteFound(found = true) {
  serviceClient.from.mockReturnValueOnce(
    queryChain(
      found
        ? { data: { user_id: "athlete-1", display_name: "João" } }
        : { data: null },
    ),
  );
}

function mockEmitCoinsAtomic(
  result:
    | { ledger_id: string; new_balance: number; was_idempotent: boolean }
    | null,
  error: { code?: string; message?: string } | null = null,
) {
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({ data: result ? [result] : null, error }),
  );
}

/**
 * L18-02 — when the caller sends `x-idempotency-key`, the
 * `withIdempotency` wrapper calls fn_idem_begin BEFORE the
 * handler. Tests must enqueue the begin response (action=execute)
 * and the post-handler finalize ack so the mock RPC queue is
 * consumed in the right order. For action=replay tests use
 * `mockIdemBeginReplay` instead.
 */
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
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({ data: true, error: null }),
  );
}

describe("POST /api/distribute-coins (L02-01: atomic RPC)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getSession.mockResolvedValue({ data: { session: TEST_SESSION } });
    authClient.auth.getUser.mockResolvedValue({ data: { user: TEST_SESSION.user } });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 10 }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller is not admin_master", async () => {
    mockAdminCheck("athlete");
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 10 }));
    expect(res.status).toBe(403);
  });

  it("returns 400 when athlete_user_id is missing", async () => {
    mockAdminCheck();
    const res = await POST(req({ amount: 10 }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when amount is not integer", async () => {
    mockAdminCheck();
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 10.5 }));
    expect(res.status).toBe(400);
    // L14-05 — canonical envelope: error.message
    expect((await res.json()).error.message).toContain("inteiro");
  });

  it("returns 400 when amount exceeds 1000", async () => {
    mockAdminCheck();
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 1001 }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when amount is zero", async () => {
    mockAdminCheck();
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 0 }));
    expect(res.status).toBe(400);
  });

  it("returns 404 when athlete not found in group", async () => {
    mockAdminCheck();
    mockAthleteFound(false);
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 10 }));
    expect(res.status).toBe(404);
  });

  it("returns 422 when custody backing is insufficient (P0002)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic(null, {
      code: "P0002",
      message: "CUSTODY_FAILED: Insufficient backing: available=0, requested=50",
    });
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(422);
    expect((await res.json()).error.message).toContain("Lastro insuficiente");
  });

  it("returns 422 when inventory is insufficient (P0003)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic(null, {
      code: "P0003",
      message: "INVENTORY_INSUFFICIENT",
    });
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(422);
    expect((await res.json()).error.message).toContain("Saldo insuficiente");
  });

  it("returns 500 when RPC fails with unexpected error", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic(null, { message: "unexpected database error" });

    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(500);
  });

  it("L19-05: returns 503 with Retry-After when RPC hits lock_timeout (55P03)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic(null, {
      code: "55P03",
      message: "canceling statement due to lock timeout",
    });
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("2");
    expect((await res.json()).error.message).toMatch(/em uso.*tente novamente/i);
    // audit log NÃO deve ser chamado em 503 (operação não committada)
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("L19-05: also maps lock_not_available message (without code) to 503", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic(null, {
      message: "lock_not_available: could not obtain lock on row",
    });
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("2");
  });

  it("returns 200 on successful distribution (first call, not idempotent)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockIdemBeginExecute();
    mockEmitCoinsAtomic({
      ledger_id: "ledger-uuid-1",
      new_balance: 150,
      was_idempotent: false,
    });
    mockIdemFinalize();

    const res = await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 50 },
        { "x-idempotency-key": "key-12345678" },
      ),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.amount).toBe(50);
    expect(json.idempotent).toBe(false);
    expect(json.new_balance).toBe(150);
    expect(auditLog).toHaveBeenCalledTimes(1);
  });

  it("returns 200 and idempotent=true on replay with same ref_id", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockIdemBeginExecute();
    mockEmitCoinsAtomic({
      ledger_id: "ledger-uuid-1",
      new_balance: 150,
      was_idempotent: true,
    });
    mockIdemFinalize();

    const res = await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 50 },
        { "x-idempotency-key": "key-12345678" },
      ),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.idempotent).toBe(true);
    expect(json.new_balance).toBe(150);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("calls emit_coins_atomic with correct parameters including ref_id", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockIdemBeginExecute();
    mockEmitCoinsAtomic({
      ledger_id: "ledger-uuid-1",
      new_balance: 3,
      was_idempotent: false,
    });
    mockIdemFinalize();

    await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 3 },
        { "x-idempotency-key": "idem-xyz1" },
      ),
    );

    // L18-02 — RPC sequence: fn_idem_begin → emit_coins_atomic → fn_idem_finalize.
    expect(serviceClient.rpc.mock.calls[1][0]).toBe("emit_coins_atomic");
    expect(serviceClient.rpc.mock.calls[1][1]).toMatchObject({
      p_group_id: "group-1",
      p_athlete_user_id: ATHLETE_UUID,
      p_amount: 3,
      p_ref_id: "idem-xyz1",
    });
  });

  it("generates a ref_id when client does not provide x-idempotency-key", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockEmitCoinsAtomic({
      ledger_id: "ledger-uuid-1",
      new_balance: 3,
      was_idempotent: false,
    });

    await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 3 }));

    // L18-02 — without x-idempotency-key the wrapper degrades gracefully:
    // no fn_idem_begin/finalize calls; the RPC queue starts at emit_coins_atomic.
    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("emit_coins_atomic");
    expect(call[1].p_ref_id).toMatch(/^portal_.*_\d+$/);
  });

  it("does NOT call audit log on idempotent retry (prevents duplicate audit entries)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    mockIdemBeginExecute();
    mockEmitCoinsAtomic({
      ledger_id: "ledger-uuid-1",
      new_balance: 100,
      was_idempotent: true,
    });
    mockIdemFinalize();

    await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 50 },
        { "x-idempotency-key": "replay-key-1" },
      ),
    );

    expect(auditLog).not.toHaveBeenCalled();
  });

  it("L18-02 — wrapper replays cached response without re-running emit_coins_atomic", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: [
          {
            action: "replay",
            replay_status: 200,
            replay_body: {
              ok: true,
              athlete_user_id: ATHLETE_UUID,
              amount: 50,
              athlete_name: "João",
              idempotent: true,
              new_balance: 150,
            },
            stale_recovered: false,
          },
        ],
        error: null,
      }),
    );

    const res = await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 50 },
        { "x-idempotency-key": "replay-original" },
      ),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("x-idempotent-replay")).toBe("true");
    const json = await res.json();
    expect(json.idempotent).toBe(true);
    expect(json.new_balance).toBe(150);
    // emit_coins_atomic NEVER called on replay path.
    const calls = serviceClient.rpc.mock.calls.map((c: unknown[]) => c[0]);
    expect(calls).toEqual(["fn_idem_begin"]);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("L18-02 — wrapper returns 409 when same key is reused with different body", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: [
          {
            action: "mismatch",
            replay_status: null,
            replay_body: null,
            stale_recovered: false,
          },
        ],
        error: null,
      }),
    );

    const res = await POST(
      req(
        { athlete_user_id: ATHLETE_UUID, amount: 99 },
        { "x-idempotency-key": "reused-key-1" },
      ),
    );
    expect(res.status).toBe(409);
    const json = await res.json();
    expect(json.error.code).toBe("IDEMPOTENCY_KEY_CONFLICT");
    expect(auditLog).not.toHaveBeenCalled();
  });
});
