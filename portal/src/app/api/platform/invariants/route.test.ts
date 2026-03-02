import { describe, it, expect, vi, beforeEach } from "vitest";

const mockGetUser = vi.fn();
const mockSelectSingle = vi.fn();
const mockRpc = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({
    auth: { getUser: mockGetUser },
    from: () => ({
      select: () => ({
        eq: () => ({ single: mockSelectSingle }),
      }),
    }),
  }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    rpc: mockRpc,
  }),
}));

const { GET } = await import("./route");

describe("/api/platform/invariants", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u1" } },
    });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET();
    expect(res.status).toBe(403);
  });

  it("returns healthy=true when no violations", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u1" } },
    });
    mockSelectSingle.mockResolvedValue({
      data: { role: "admin" },
    });
    mockRpc.mockResolvedValue({ data: [], error: null });

    const res = await GET();
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.healthy).toBe(true);
    expect(body.violations).toEqual([]);
    expect(body.checked_at).toBeDefined();
  });

  it("returns healthy=false with violations", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u1" } },
    });
    mockSelectSingle.mockResolvedValue({
      data: { role: "admin" },
    });
    mockRpc.mockResolvedValue({
      data: [
        {
          group_id: "g1",
          total_deposited: 100,
          total_committed: 200,
          computed_available: -100,
          violation: "deposited_less_than_committed",
        },
      ],
      error: null,
    });

    const res = await GET();
    const body = await res.json();

    expect(res.status).toBe(200);
    expect(body.healthy).toBe(false);
    expect(body.violations).toHaveLength(1);
    expect(body.violations[0].violation).toBe(
      "deposited_less_than_committed",
    );
  });

  it("returns 500 on rpc error", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: "u1" } },
    });
    mockSelectSingle.mockResolvedValue({
      data: { role: "admin" },
    });
    mockRpc.mockResolvedValue({
      data: null,
      error: { message: "db failure" },
    });

    const res = await GET();
    expect(res.status).toBe(500);
  });
});
