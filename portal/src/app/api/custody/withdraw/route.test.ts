import { describe, it, expect, vi, beforeEach } from "vitest";
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

function req(body: unknown) {
  return new Request("http://localhost/api/custody/withdraw", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
    },
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
    expect(body.error).toBe("Invalid input");
    expect(createWithdrawal).not.toHaveBeenCalled();
    expect(auditLog).not.toHaveBeenCalled();
  });

  it("usa rate server-side, nunca rate fornecido pelo cliente", async () => {
    mockAdmin();
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
    expect(body.code).toBe("stale");
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
    expect(body.code).toBe("missing");
  });

  it("aceita operação válida com target_currency default BRL", async () => {
    mockAdmin();
    const res = await POST(req({ amount_usd: 50 }));
    expect(res.status).toBe(200);
    expect(getAuthoritativeFxQuote).toHaveBeenCalledWith("BRL");
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
    const res = await GET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.withdrawals).toHaveLength(1);
  });
});
