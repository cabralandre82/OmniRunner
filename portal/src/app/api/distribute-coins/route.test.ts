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
vi.mock("@/lib/custody", () => ({
  assertInvariantsHealthy: vi.fn().mockResolvedValue(true),
}));

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/distribute-coins", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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

describe("POST /api/distribute-coins", () => {
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
    expect((await res.json()).error).toContain("inteiro");
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

  it("returns 422 when custody backing is insufficient", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    // custody_commit_coins fails with insufficient backing
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "Insufficient backing" } }),
    );
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(422);
    expect((await res.json()).error).toContain("Lastro insuficiente");
  });

  it("returns 422 when decrement_token_inventory fails (insufficient inventory)", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    // custody_commit_coins succeeds (or is skipped)
    serviceClient.rpc.mockReturnValueOnce(queryChain({ data: null, error: null }));
    // decrement_token_inventory fails with CHECK constraint
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: { code: "23514", message: "CHECK constraint violated" } }),
    );
    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(422);
    expect((await res.json()).error).toContain("Saldo insuficiente");
  });

  it("returns 500 when wallet credit fails", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    // custody_commit_coins succeeds
    serviceClient.rpc.mockReturnValueOnce(queryChain({ data: null, error: null }));
    // decrement_token_inventory succeeds
    serviceClient.rpc.mockReturnValueOnce(queryChain({ data: null, error: null }));
    // increment_wallet_balance fails
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "wallet error" } }),
    );

    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(500);
  });

  it("returns 200 on successful distribution", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    // custody, decrement, wallet all succeed
    serviceClient.rpc.mockReturnValue(queryChain({ data: null, error: null }));
    // ledger insert
    serviceClient.from.mockReturnValueOnce(queryChain({ data: null }));

    const res = await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 50 }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.amount).toBe(50);
  });

  it("passes issuer_group_id to coin_ledger insert", async () => {
    mockAdminCheck();
    mockAthleteFound(true);
    serviceClient.rpc.mockReturnValue(queryChain({ data: null, error: null }));

    let insertedPayload: Record<string, unknown> | null = null;
    const insertChain = queryChain({ data: null });
    (insertChain.insert as ReturnType<typeof vi.fn>).mockImplementation(
      (payload: Record<string, unknown>) => {
        insertedPayload = payload;
        return insertChain;
      },
    );
    serviceClient.from.mockReturnValueOnce(insertChain);

    await POST(req({ athlete_user_id: ATHLETE_UUID, amount: 3 }));

    expect(insertedPayload).not.toBeNull();
    expect((insertedPayload as Record<string, unknown>).issuer_group_id).toBe("group-1");
    expect((insertedPayload as Record<string, unknown>).reason).toBe("institution_token_issue");
    expect((insertedPayload as Record<string, unknown>).delta_coins).toBe(3);
  });
});
