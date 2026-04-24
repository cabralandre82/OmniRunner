import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain, makeMockClient } from "@/test/api-helpers";

/**
 * Tests for POST /api/financial/generate-cycle (L09-15)
 *
 * - 401 sem sessão
 * - 400 sem portal_group_id
 * - 403 quando role !== admin_master
 * - 400 pra period_month em formato inválido
 * - 400 pra period_month inválido pelo Postgres (P0001)
 * - 200 success path com echo dos counters
 */

const authClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));

vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));

const { POST } = await import("./route");

function makeReq(body: Record<string, unknown> = {}) {
  return new Request("http://localhost/api/financial/generate-cycle", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/financial/generate-cycle", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 400 when period_month has invalid format", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    const res = await POST(makeReq({ period_month: "abril/2026" }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_PERIOD_FORMAT");
  });

  it("returns 403 when user is not admin_master", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" }, error: null }),
    );
    const res = await POST(makeReq({}));
    expect(res.status).toBe(403);
  });

  it("returns 403 when user has no membership", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: null }),
    );
    const res = await POST(makeReq({}));
    expect(res.status).toBe(403);
  });

  it("returns 200 with RPC echo on success (default period)", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    authClient.rpc.mockResolvedValueOnce({
      data: {
        ok: true,
        period_month: "2026-04-01",
        group_id: "group-1",
        total_active_subs: 12,
        inserted: 10,
        skipped: 2,
      },
      error: null,
    });

    const res = await POST(makeReq({}));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.inserted).toBe(10);
    expect(body.data.skipped).toBe(2);
    expect(body.data.total_active_subs).toBe(12);

    expect(authClient.rpc).toHaveBeenCalledWith(
      "fn_subscription_admin_generate_cycle_scoped",
      { p_group_id: "group-1", p_period_month: null },
    );
  });

  it("passes custom period_month to RPC", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    authClient.rpc.mockResolvedValueOnce({
      data: {
        ok: true,
        period_month: "2026-05-01",
        group_id: "group-1",
        total_active_subs: 0,
        inserted: 0,
        skipped: 0,
      },
      error: null,
    });

    const res = await POST(makeReq({ period_month: "2026-05-01" }));
    expect(res.status).toBe(200);
    expect(authClient.rpc).toHaveBeenCalledWith(
      "fn_subscription_admin_generate_cycle_scoped",
      { p_group_id: "group-1", p_period_month: "2026-05-01" },
    );
  });

  it("maps Postgres P0001 (invariant) to 400 INVALID_PERIOD", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    authClient.rpc.mockResolvedValueOnce({
      data: null,
      error: {
        code: "P0001",
        message: "p_period_month must be the first day of a month",
      },
    });

    const res = await POST(makeReq({ period_month: "2026-04-15" }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_PERIOD");
  });

  it("maps Postgres 42501 to 403", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    authClient.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: "42501", message: "only admin_master" },
    });

    const res = await POST(makeReq({}));
    expect(res.status).toBe(403);
  });

  it("maps other RPC errors to 500 RPC_ERROR", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" }, error: null }),
    );
    authClient.rpc.mockResolvedValueOnce({
      data: null,
      error: { code: "XX000", message: "deadlock detected" },
    });

    const res = await POST(makeReq({}));
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.error.code).toBe("RPC_ERROR");
  });
});

describe("POST /api/financial/generate-cycle — edge auth", () => {
  it("returns 401 when there is no session", async () => {
    vi.resetModules();

    vi.doMock("@/lib/supabase/server", () => ({
      createClient: () => makeMockClient(null),
    }));
    vi.doMock("next/headers", () => ({
      cookies: () => ({ get: () => ({ value: "group-1" }) }),
    }));

    const { POST: POST2 } = await import("./route");
    const res = await POST2(
      new Request("http://localhost/api/financial/generate-cycle", {
        method: "POST",
        body: "{}",
      }),
    );
    expect(res.status).toBe(401);
  });

  it("returns 400 when there is no portal_group_id cookie", async () => {
    vi.resetModules();

    vi.doMock("@/lib/supabase/server", () => ({
      createClient: () => makeMockClient(),
    }));
    vi.doMock("next/headers", () => ({
      cookies: () => ({ get: () => undefined }),
    }));

    const { POST: POST2 } = await import("./route");
    const res = await POST2(
      new Request("http://localhost/api/financial/generate-cycle", {
        method: "POST",
        body: "{}",
      }),
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("NO_GROUP_SESSION");
  });
});
