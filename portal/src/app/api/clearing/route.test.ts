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
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

const mockGetSettlements = vi.fn();

vi.mock("@/lib/clearing", () => ({
  getSettlementsForGroup: (...args: unknown[]) => mockGetSettlements(...args),
}));

const { GET } = await import("./route");

function getReq(role?: string) {
  const url = role
    ? `http://localhost/api/clearing?role=${role}`
    : "http://localhost/api/clearing";
  const base = new Request(url, {
    headers: { "x-forwarded-for": "127.0.0.1" },
  });
  const parsed = new URL(url);
  return Object.assign(base, {
    nextUrl: parsed,
  }) as unknown as import("next/server").NextRequest;
}

function mockStaffCheck(role = "admin_master") {
  serviceClient.from.mockReturnValueOnce(queryChain({ data: { role } }));
}

describe("Clearing API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getSession.mockResolvedValue({
      data: { session: { user: { id: "user-1" } } },
    });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getSession.mockResolvedValueOnce({
      data: { session: null },
    });
    const res = await GET(getReq());
    expect(res.status).toBe(401);
  });

  it("returns 403 when not staff", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "athlete" } }),
    );
    const res = await GET(getReq());
    expect(res.status).toBe(403);
  });

  it("returns settlements for admin_master", async () => {
    mockStaffCheck();
    mockGetSettlements.mockResolvedValue([
      {
        id: "s1",
        creditor_group_id: "group-1",
        debtor_group_id: "group-2",
        coin_amount: 60,
        gross_amount_usd: 60,
        net_amount_usd: 58.2,
        fee_amount_usd: 1.8,
        status: "settled",
      },
    ]);

    const res = await GET(getReq());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.settlements).toHaveLength(1);
    expect(mockGetSettlements).toHaveBeenCalledWith("group-1", "both");
  });

  it("returns settlements for coach", async () => {
    mockStaffCheck("coach");
    mockGetSettlements.mockResolvedValue([]);

    const res = await GET(getReq());
    expect(res.status).toBe(200);
  });

  it("filters by creditor role", async () => {
    mockStaffCheck();
    mockGetSettlements.mockResolvedValue([]);

    await GET(getReq("creditor"));
    expect(mockGetSettlements).toHaveBeenCalledWith("group-1", "creditor");
  });

  it("filters by debtor role", async () => {
    mockStaffCheck();
    mockGetSettlements.mockResolvedValue([]);

    await GET(getReq("debtor"));
    expect(mockGetSettlements).toHaveBeenCalledWith("group-1", "debtor");
  });
});
