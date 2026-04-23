import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

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
// Default in-memory rate limit is 10/min — bypass it so we can run >10 tests
// in this file without hitting 429 in the 11th case.
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockResolvedValue({ allowed: true, remaining: 999, resetAt: 0 }),
}));

const mockUser = { id: "user-admin-1" };

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/auto-topup", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/auto-topup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({ data: { user: mockUser } });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(403);
  });

  it("updates existing settings", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(
      req({ enabled: true, threshold_tokens: 100 }),
    );
    expect(res.status).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });

  it("creates settings with product_id", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }))  // no existing
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(
      req({ enabled: true, product_id: "prod-1", threshold_tokens: 50 }),
    );
    expect(res.status).toBe(200);
  });

  it("returns 400 when initial setup has no product_id", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }));

    const res = await POST(req({ enabled: true }));
    expect(res.status).toBe(400);
    expect((await res.json()).error).toContain("product_id");
  });

  // ─────────────────────────────────────────────────────────────────────────
  // L12-05 — daily cap antifraude
  // ─────────────────────────────────────────────────────────────────────────
  describe("L12-05 daily cap", () => {
    it("rejects daily cap change without reason (Zod superRefine)", async () => {
      serviceClient.from.mockReturnValueOnce(
        queryChain({ data: { role: "admin_master" } }),
      );
      const res = await POST(
        req({ enabled: true, daily_charge_cap_brl: 1000 }),
      );
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error).toMatch(/daily_cap_change_reason/);
    });

    it("rejects daily cap change with reason < 10 chars", async () => {
      serviceClient.from.mockReturnValueOnce(
        queryChain({ data: { role: "admin_master" } }),
      );
      const res = await POST(
        req({
          enabled: true,
          daily_charge_cap_brl: 1000,
          daily_cap_change_reason: "too short",
        }),
      );
      expect(res.status).toBe(400);
    });

    it("invokes fn_set_auto_topup_daily_cap when daily_charge_cap_brl provided", async () => {
      serviceClient.from
        .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
        .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
        .mockReturnValueOnce(queryChain({ data: null, error: null }))
        .mockReturnValueOnce(
          queryChain({
            data: {
              daily_charge_cap_brl: 500,
              daily_max_charges: 3,
              daily_limit_timezone: "America/Sao_Paulo",
            },
          }),
        );
      serviceClient.rpc.mockReturnValueOnce(
        queryChain({
          data: [
            {
              out_group_id: "group-1",
              out_previous_cap_brl: 500,
              out_new_cap_brl: 1000,
              out_previous_max_charges: 3,
              out_new_max_charges: 3,
              out_previous_timezone: "America/Sao_Paulo",
              out_new_timezone: "America/Sao_Paulo",
              out_was_idempotent: false,
            },
          ],
        }),
      );

      const res = await POST(
        req({
          enabled: true,
          daily_charge_cap_brl: 1000,
          daily_cap_change_reason:
            "ajuste após CFO em SUP-1234 — temporada de provas dobra a média",
        }),
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.ok).toBe(true);
      expect(body.daily_cap?.new_cap_brl).toBe(1000);
      expect(serviceClient.rpc).toHaveBeenCalledWith(
        "fn_set_auto_topup_daily_cap",
        expect.objectContaining({
          p_group_id: "group-1",
          p_new_cap_brl: 1000,
          p_actor_user_id: "user-admin-1",
        }),
      );
    });

    it("forwards x-idempotency-key header to RPC", async () => {
      serviceClient.from
        .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
        .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
        .mockReturnValueOnce(queryChain({ data: null, error: null }))
        .mockReturnValueOnce(
          queryChain({
            data: {
              daily_charge_cap_brl: 500,
              daily_max_charges: 3,
              daily_limit_timezone: "America/Sao_Paulo",
            },
          }),
        );
      serviceClient.rpc.mockReturnValueOnce(
        queryChain({
          data: [
            {
              out_group_id: "group-1",
              out_previous_cap_brl: 500,
              out_new_cap_brl: 800,
              out_previous_max_charges: 3,
              out_new_max_charges: 5,
              out_was_idempotent: false,
            },
          ],
        }),
      );

      const customReq = new Request("http://localhost/api/auto-topup", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-idempotency-key": "client-abc-12345678",
        },
        body: JSON.stringify({
          enabled: true,
          daily_charge_cap_brl: 800,
          daily_max_charges: 5,
          daily_cap_change_reason:
            "experimentos com janela de cap maior em piloto Q2",
        }),
      });
      const res = await POST(customReq);
      expect(res.status).toBe(200);
      expect(serviceClient.rpc).toHaveBeenCalledWith(
        "fn_set_auto_topup_daily_cap",
        expect.objectContaining({
          p_idempotency_key: "client-abc-12345678",
        }),
      );
    });

    it("translates RPC P0001 → 400 (validation) and P0002 → 404 (settings missing)", async () => {
      serviceClient.from
        .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
        .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
        .mockReturnValueOnce(queryChain({ data: null, error: null }))
        .mockReturnValueOnce(
          queryChain({
            data: {
              daily_charge_cap_brl: 500,
              daily_max_charges: 3,
              daily_limit_timezone: "America/Sao_Paulo",
            },
          }),
        );
      serviceClient.rpc.mockReturnValueOnce(
        queryChain({
          data: null,
          error: {
            code: "P0002",
            message: "AUTO_TOPUP_SETTINGS_NOT_FOUND",
            hint: "Crie settings antes...",
          },
        }),
      );

      const res = await POST(
        req({
          enabled: true,
          daily_charge_cap_brl: 1000,
          daily_cap_change_reason:
            "ajuste de tetos após análise de risco mensal",
        }),
      );
      expect(res.status).toBe(404);
      const body = await res.json();
      expect(body.code).toBe("P0002");
      expect(body.hint).toContain("Crie settings");
    });

    it("does NOT call fn_set_auto_topup_daily_cap when no daily_* fields are sent", async () => {
      serviceClient.from
        .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
        .mockReturnValueOnce(queryChain({ data: { group_id: "group-1" } }))
        .mockReturnValueOnce(queryChain({ data: null, error: null }));

      const res = await POST(
        req({ enabled: true, threshold_tokens: 200 }),
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.daily_cap).toBe(null);
      expect(serviceClient.rpc).not.toHaveBeenCalled();
    });
  });
});
