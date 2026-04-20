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
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));

const auditLog = vi.fn().mockResolvedValue(undefined);
vi.mock("@/lib/audit", () => ({ auditLog }));

vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

// L06-06 — kill switch lib mockada (cobertura em src/lib/feature-flags.test.ts).
vi.mock("@/lib/feature-flags", () => ({
  assertSubsystemEnabled: vi.fn().mockResolvedValue(undefined),
  isSubsystemEnabled: vi.fn().mockResolvedValue(true),
  FeatureDisabledError: class FeatureDisabledError extends Error {},
}));

const getAuthoritativeFxQuote = vi.fn();
vi.mock("@/lib/fx/quote", async () => {
  const actual = await vi.importActual<typeof import("@/lib/fx/quote")>(
    "@/lib/fx/quote",
  );
  return {
    ...actual,
    getAuthoritativeFxQuote,
  };
});

const createWithdrawal = vi.fn();
const executeWithdrawal = vi.fn();
const getWithdrawals = vi.fn().mockResolvedValue([]);
const assertInvariantsHealthy = vi.fn().mockResolvedValue(true);
const getFxSpreadRate = vi.fn().mockResolvedValue(0.75);

vi.mock("@/lib/custody", () => ({
  createWithdrawal,
  executeWithdrawal,
  getWithdrawals,
  assertInvariantsHealthy,
  getFxSpreadRate,
}));

const { POST, GET } = await import("./route");

/**
 * Default request helper. Sends a fresh `x-idempotency-key` (UUID v4)
 * per call so each request gets a unique key, simulating real client
 * behaviour. Pass `idempotencyKey: false` to opt out of the header
 * (e.g. to test the "missing header" 400 path).
 */
function req(
  body: unknown,
  opts: { idempotencyKey?: string | false } = {},
) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "x-forwarded-for": "127.0.0.1",
  };
  if (opts.idempotencyKey !== false) {
    headers["x-idempotency-key"] = opts.idempotencyKey ?? randomUUID();
  }
  return new Request("http://localhost/api/custody/withdraw", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

function mockAdmin() {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: { role: "admin_master" } }),
  );
}

function mockNonAdmin(role = "coach") {
  serviceClient.from.mockReturnValueOnce(queryChain({ data: { role } }));
}

/**
 * L18-02 — `withIdempotency` calls fn_idem_begin BEFORE the handler.
 * Tests that exercise the success / mutation path must enqueue a
 * begin response (action=execute) and a finalize ack so the wrapper
 * lifecycle completes cleanly.
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

describe("POST /api/custody/withdraw — L01-02 server-side FX rate", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-admin-1" } },
    });
    createWithdrawal.mockResolvedValue({
      id: "wd-1",
      group_id: "group-1",
      amount_usd: 100,
      target_currency: "BRL",
      fx_rate: 5.25,
      net_local_amount: 521.6,
      status: "pending",
    });
    executeWithdrawal.mockResolvedValue(undefined);
    getAuthoritativeFxQuote.mockResolvedValue({
      currency: "BRL",
      rate: 5.25,
      source: "ptax",
      fetchedAt: "2026-04-17T12:00:00Z",
      ageSeconds: 120,
    });
  });

  it("rejeita body com fx_rate (strict schema) — 400", async () => {
    mockAdmin();
    const res = await POST(
      req({
        amount_usd: 100,
        target_currency: "BRL",
        fx_rate: 10.0, // ← tentativa de fraude
      }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    // L14-05 — canonical envelope: error.message + error.code
    expect(body.error.message).toBe("Invalid input");
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("usa rate server-side, nunca rate fornecido pelo cliente", async () => {
    mockAdmin();
    mockIdemBeginExecute();
    mockIdemFinalize();
    const res = await POST(
      req({ amount_usd: 100, target_currency: "BRL" }),
    );
    expect(res.status).toBe(200);

    expect(getAuthoritativeFxQuote).toHaveBeenCalledWith("BRL");
    expect(createWithdrawal).toHaveBeenCalledWith(
      expect.objectContaining({
        fxRate: 5.25,
        targetCurrency: "BRL",
        amountUsd: 100,
      }),
    );
    expect(auditLog).toHaveBeenCalledWith(
      expect.objectContaining({
        action: "custody.withdrawal.executed",
        metadata: expect.objectContaining({
          fx_rate: 5.25,
          fx_source: "ptax",
          fx_age_seconds: 120,
        }),
      }),
    );
  });

  it("retorna 503 quando fx quote está stale (fail-closed)", async () => {
    const { FxQuoteStaleError } = await import("@/lib/fx/quote");
    mockAdmin();
    getAuthoritativeFxQuote.mockRejectedValueOnce(
      new FxQuoteStaleError("BRL", 100_000, 86400),
    );

    const res = await POST(
      req({ amount_usd: 100, target_currency: "BRL" }),
    );
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error.code).toBe("stale");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("retorna 503 quando fx quote está missing (fail-closed)", async () => {
    const { FxQuoteMissingError } = await import("@/lib/fx/quote");
    mockAdmin();
    getAuthoritativeFxQuote.mockRejectedValueOnce(
      new FxQuoteMissingError("BRL"),
    );

    const res = await POST(
      req({ amount_usd: 100, target_currency: "BRL" }),
    );
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error.code).toBe("missing");
  });

  it("aceita operação válida com target_currency default BRL", async () => {
    mockAdmin();
    mockIdemBeginExecute();
    mockIdemFinalize();
    const res = await POST(req({ amount_usd: 50 }));
    expect(res.status).toBe(200);
    expect(getAuthoritativeFxQuote).toHaveBeenCalledWith("BRL");
  });

  it("L18-02 — exige x-idempotency-key (400 IDEMPOTENCY_KEY_REQUIRED)", async () => {
    mockAdmin();
    const res = await POST(
      req(
        { amount_usd: 100, target_currency: "BRL" },
        { idempotencyKey: false },
      ),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_KEY_REQUIRED");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(executeWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("L18-02 — replay retorna response cacheada sem chamar createWithdrawal", async () => {
    mockAdmin();
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: [
          {
            action: "replay",
            replay_status: 200,
            replay_body: {
              withdrawal: {
                id: "wd-replayed",
                group_id: "group-1",
                amount_usd: 100,
                target_currency: "BRL",
                fx_rate: 5.25,
                net_local_amount: 521.6,
                status: "executed",
              },
            },
            stale_recovered: false,
          },
        ],
        error: null,
      }),
    );

    const res = await POST(
      req(
        { amount_usd: 100, target_currency: "BRL" },
        { idempotencyKey: "replay-key-original" },
      ),
    );
    expect(res.status).toBe(200);
    expect(res.headers.get("x-idempotent-replay")).toBe("true");
    const body = await res.json();
    expect(body.withdrawal.id).toBe("wd-replayed");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(executeWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("L18-02 — mismatch retorna 409 quando key reutilizada com body diferente", async () => {
    mockAdmin();
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
        { amount_usd: 999, target_currency: "BRL" },
        { idempotencyKey: "reused-key" },
      ),
    );
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_KEY_CONFLICT");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("rejeita target_currency inválido (zod enum) — 400", async () => {
    mockAdmin();
    const res = await POST(
      req({ amount_usd: 100, target_currency: "JPY" }),
    );
    expect(res.status).toBe(400);
    expect(getAuthoritativeFxQuote).not.toHaveBeenCalled();
  });

  it("rejeita usuário que não é admin_master — 403", async () => {
    mockNonAdmin("coach");
    const res = await POST(req({ amount_usd: 100 }));
    expect(res.status).toBe(403);
  });

  it("rejeita usuário não autenticado — 401", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ amount_usd: 100 }));
    expect(res.status).toBe(401);
  });

  it("rejeita amount acima do limite (> 1M USD)", async () => {
    mockAdmin();
    const res = await POST(req({ amount_usd: 2_000_000 }));
    expect(res.status).toBe(400);
    expect(getAuthoritativeFxQuote).not.toHaveBeenCalled();
  });

  it("rejeita provider_fee_usd se combinado com fx_rate (strict)", async () => {
    mockAdmin();
    const res = await POST(
      req({ amount_usd: 100, provider_fee_usd: 5, fx_rate: 5.25 }),
    );
    expect(res.status).toBe(400);
  });

  it("GET retorna lista de withdrawals para admin_master", async () => {
    mockAdmin();
    getWithdrawals.mockResolvedValueOnce([{ id: "wd-1" }]);
    // L17-01 — wrapper agora lê `req.headers`/`req.method`; passa req real.
    const getReq = new Request("http://localhost/api/custody/withdraw", {
      headers: { "x-forwarded-for": "127.0.0.1" },
    }) as unknown as import("next/server").NextRequest;
    const res = await GET(getReq);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.withdrawals).toHaveLength(1);
  });
});
