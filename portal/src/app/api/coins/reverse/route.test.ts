import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

// L03-13 — route-level tests for POST /api/coins/reverse.
//
// Cobre: auth, authz (só platform_admin), kill switch, rate-limit,
// schema (discriminated union), invariants, error mapping
// (LEDGER_NOT_FOUND, INSUFFICIENT_BALANCE, NOT_REVERSIBLE,
// INVARIANT_VIOLATION, INVALID_TARGET_STATE, CUSTODY_RECOMMIT_FAILED,
// lock_timeout) e happy path de cada kind (emission, burn, deposit).

const LEDGER_ID = "11111111-1111-4111-8111-111111111111";
const DEPOSIT_ID = "22222222-2222-4222-8222-222222222222";
const ATHLETE_ID = "33333333-3333-4333-8333-333333333333";
const GROUP_ID = "44444444-4444-4444-8444-444444444444";
const EVENT_ID = "55555555-5555-4555-8555-555555555555";
const REVERSAL_ID = "66666666-6666-4666-8666-666666666666";
const REVERSAL_LEDGER_ID = "77777777-7777-4777-8777-777777777777";

const LONG_REASON =
  "Chargeback Stripe CH_TEST_123 postmortem CFO #PR-4815";

const authClient = makeMockClient(TEST_SESSION);
const serviceClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => serviceClient,
}));
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockResolvedValue({ allowed: true, remaining: 9 }),
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
  return new Request("http://localhost/api/coins/reverse", {
    method: "POST",
    headers: { "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

function mockPlatformRole(role: string | null) {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: role ? { platform_role: role } : null }),
  );
}

function mockRpcOnce(
  data: unknown,
  error: { code?: string; message?: string } | null = null,
) {
  serviceClient.rpc.mockReturnValueOnce(
    queryChain({ data: data !== null ? [data] : null, error }),
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

const EMISSION_BODY = {
  kind: "emission" as const,
  original_ledger_id: LEDGER_ID,
  reason: LONG_REASON,
  idempotency_key: "rev-emi-abcdef1234",
};

const BURN_BODY = {
  kind: "burn" as const,
  burn_ref_id: "burn-ref-abc-123",
  reason: LONG_REASON,
  idempotency_key: "rev-burn-abcdef1234",
};

const DEPOSIT_BODY = {
  kind: "deposit" as const,
  deposit_id: DEPOSIT_ID,
  reason: LONG_REASON,
  idempotency_key: "rev-dep-abcdef1234",
};

describe("POST /api/coins/reverse (L03-13)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: TEST_SESSION.user },
    });
    (rateLimit as any).mockResolvedValue({
      allowed: true,
      remaining: 9,
      resetAt: Date.now() + 60_000,
    });
    (assertInvariantsHealthy as any).mockResolvedValue(true);
    (featureFlags.assertSubsystemEnabled as any).mockResolvedValue(undefined);
  });

  // ── cross-cutting concerns ────────────────────────────────────────────

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(401);
  });

  it("returns 503 when coins.reverse kill switch is off (L06-06)", async () => {
    const FlagErr = featureFlags.FeatureDisabledError as any;
    (featureFlags.assertSubsystemEnabled as any).mockRejectedValueOnce(
      new FlagErr("coins.reverse.enabled", "FEATURE_DISABLED", "off"),
    );
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("30");
  });

  it("returns 429 when rate-limited (10/min/actor)", async () => {
    (rateLimit as any).mockResolvedValueOnce({
      allowed: false,
      remaining: 0,
      resetAt: Date.now() + 5_000,
    });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(429);
  });

  it("returns 403 when caller is not platform_admin", async () => {
    mockPlatformRole("user");
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(403);
  });

  it("returns 403 when caller has no platform_role at all", async () => {
    mockPlatformRole(null);
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(403);
  });

  it("returns 400 on malformed JSON body", async () => {
    mockPlatformRole("admin");
    const res = await POST(req("{not json", {}) as any);
    expect(res.status).toBe(400);
  });

  it("returns 400 on unknown kind", async () => {
    mockPlatformRole("admin");
    const res = await POST(
      req({ kind: "refund", reason: LONG_REASON }) as any,
    );
    expect(res.status).toBe(400);
  });

  it("returns 400 on short reason (<10 chars)", async () => {
    mockPlatformRole("admin");
    const res = await POST(
      req({ ...EMISSION_BODY, reason: "short" }) as any,
    );
    expect(res.status).toBe(400);
  });

  it("returns 400 when idempotency_key missing from body AND header", async () => {
    mockPlatformRole("admin");
    const { idempotency_key: _, ...bodyWithoutKey } = EMISSION_BODY;
    const res = await POST(req(bodyWithoutKey) as any);
    expect(res.status).toBe(400);
    expect((await res.json()).error.message).toMatch(/idempotency/i);
  });

  it("accepts idempotency key from x-idempotency-key header", async () => {
    mockPlatformRole("admin");
    mockIdemBeginExecute();
    mockRpcOnce({
      reversal_id: REVERSAL_ID,
      reversal_ledger_id: REVERSAL_LEDGER_ID,
      athlete_user_id: ATHLETE_ID,
      reversed_amount: 100,
      new_balance: 900,
      was_idempotent: false,
    });
    mockIdemFinalize();
    const { idempotency_key: _, ...bodyWithoutKey } = EMISSION_BODY;
    const res = await POST(
      req(bodyWithoutKey, {
        "x-idempotency-key": "hdr-rev-abcdef1234",
      }) as any,
    );
    expect(res.status).toBe(200);
  });

  it("replays idempotent response without invoking RPC (x-idempotency-key repeat)", async () => {
    mockPlatformRole("admin");
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: [
          {
            action: "replay",
            replay_status: 200,
            replay_body: {
              ok: true,
              kind: "emission",
              reversal_id: REVERSAL_ID,
              was_idempotent: false,
            },
            stale_recovered: false,
          },
        ],
        error: null,
      }),
    );
    const { idempotency_key: _, ...bodyWithoutKey } = EMISSION_BODY;
    const res = await POST(
      req(bodyWithoutKey, {
        "x-idempotency-key": "hdr-rev-abcdef1234",
      }) as any,
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("x-idempotent-replay")).toBe("true");
    const json = await res.json();
    expect(json.reversal_id).toBe(REVERSAL_ID);
    expect(serviceClient.rpc).toHaveBeenCalledTimes(1);
  });

  it("returns 503 when invariants are unhealthy", async () => {
    mockPlatformRole("admin");
    (assertInvariantsHealthy as any).mockResolvedValueOnce(false);
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(503);
  });

  // ── emission flavor ───────────────────────────────────────────────────

  it("emission: returns 200 happy path and calls reverse_coin_emission_atomic", async () => {
    mockPlatformRole("admin");
    mockRpcOnce({
      reversal_id: REVERSAL_ID,
      reversal_ledger_id: REVERSAL_LEDGER_ID,
      athlete_user_id: ATHLETE_ID,
      reversed_amount: 100,
      new_balance: 900,
      was_idempotent: false,
    });

    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.kind).toBe("emission");
    expect(json.reversal_id).toBe(REVERSAL_ID);
    expect(json.reversed_amount).toBe(100);
    expect(json.new_balance).toBe(900);

    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("reverse_coin_emission_atomic");
    expect(call[1]).toMatchObject({
      p_original_ledger_id: LEDGER_ID,
      p_reason: LONG_REASON,
      p_actor_user_id: TEST_SESSION.user.id,
      p_idempotency_key: "rev-emi-abcdef1234",
    });

    expect(auditLog).toHaveBeenCalledTimes(1);
    const meta: any = (auditLog as any).mock.calls[0][0];
    expect(meta.action).toBe("coins.reverse.emission");
    expect(meta.targetId).toBe(LEDGER_ID);
  });

  it("emission: does NOT audit on idempotent replay", async () => {
    mockPlatformRole("admin");
    mockRpcOnce({
      reversal_id: REVERSAL_ID,
      reversal_ledger_id: REVERSAL_LEDGER_ID,
      athlete_user_id: ATHLETE_ID,
      reversed_amount: 100,
      new_balance: 900,
      was_idempotent: true,
    });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.was_idempotent).toBe(true);
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("emission: maps LEDGER_NOT_FOUND (P0002) to 404", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, { code: "P0002", message: "LEDGER_NOT_FOUND" });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(404);
    expect((await res.json()).error.code).toBe("NOT_FOUND");
  });

  it("emission: maps INSUFFICIENT_BALANCE (P0003) to 422", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "P0003",
      message: "INSUFFICIENT_BALANCE: wallet=40, need=100",
    });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("INSUFFICIENT_BALANCE");
  });

  it("emission: maps INVALID_TARGET_REASON to 422", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "P0008",
      message: "INVALID_TARGET_REASON: only emission reasons",
    });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("INVALID_TARGET_STATE");
  });

  // ── burn flavor ───────────────────────────────────────────────────────

  it("burn: returns 200 happy path and calls reverse_burn_atomic", async () => {
    mockPlatformRole("admin");
    mockRpcOnce({
      reversal_id: REVERSAL_ID,
      clearing_event_id: EVENT_ID,
      athlete_user_id: ATHLETE_ID,
      reversed_amount: 50,
      new_balance: 1050,
      settlements_cancelled: 2,
      was_idempotent: false,
    });
    const res = await POST(req(BURN_BODY) as any);
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.kind).toBe("burn");
    expect(json.clearing_event_id).toBe(EVENT_ID);
    expect(json.settlements_cancelled).toBe(2);

    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("reverse_burn_atomic");
    expect(call[1].p_burn_ref_id).toBe(BURN_BODY.burn_ref_id);
  });

  it("burn: maps NOT_REVERSIBLE to 422 (settlements already settled)", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "P0005",
      message: "NOT_REVERSIBLE: clearing_settlement already settled",
    });
    const res = await POST(req(BURN_BODY) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("NOT_REVERSIBLE");
  });

  it("burn: maps CUSTODY_RECOMMIT_FAILED to 422", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "P0009",
      message: "CUSTODY_RECOMMIT_FAILED: backing insufficient",
    });
    const res = await POST(req(BURN_BODY) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("CUSTODY_RECOMMIT_FAILED");
  });

  // ── deposit flavor ────────────────────────────────────────────────────

  it("deposit: returns 200 happy path and calls reverse_custody_deposit_atomic", async () => {
    mockPlatformRole("admin");
    mockRpcOnce({
      reversal_id: REVERSAL_ID,
      deposit_id: DEPOSIT_ID,
      group_id: GROUP_ID,
      refunded_usd: "1500.00",
      was_idempotent: false,
    });
    const res = await POST(req(DEPOSIT_BODY) as any);
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.kind).toBe("deposit");
    expect(json.deposit_id).toBe(DEPOSIT_ID);
    expect(json.refunded_usd).toBe("1500.00");

    const call = serviceClient.rpc.mock.calls[0];
    expect(call[0]).toBe("reverse_custody_deposit_atomic");
    expect(call[1].p_deposit_id).toBe(DEPOSIT_ID);
  });

  it("deposit: maps INVARIANT_VIOLATION to 422", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "P0006",
      message:
        "INVARIANT_VIOLATION: total_deposited_usd < total_committed after refund",
    });
    const res = await POST(req(DEPOSIT_BODY) as any);
    expect(res.status).toBe(422);
    expect((await res.json()).error.code).toBe("INVARIANT_VIOLATION");
  });

  it("deposit: maps DEPOSIT_NOT_FOUND (P0002) to 404", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, { code: "P0002", message: "DEPOSIT_NOT_FOUND" });
    const res = await POST(req(DEPOSIT_BODY) as any);
    expect(res.status).toBe(404);
  });

  // ── common error mapping ──────────────────────────────────────────────

  it("maps lock_timeout (55P03) to 503 with Retry-After", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, {
      code: "55P03",
      message: "canceling statement due to lock timeout",
    });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("2");
  });

  it("maps unmapped RPC error to 500", async () => {
    mockPlatformRole("admin");
    mockRpcOnce(null, { message: "totally unexpected" });
    const res = await POST(req(EMISSION_BODY) as any);
    expect(res.status).toBe(500);
  });
});
