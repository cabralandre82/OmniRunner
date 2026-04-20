import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { queryChain } from "@/test/api-helpers";

// L17-01 — withErrorHandler wrapper requires a NextRequest argument.
// Helper centralises the construction so each test stays compact.
const req = () => new NextRequest("http://localhost/api/platform/health");

const mockGetUser = vi.fn();
const mockSelectSingle = vi.fn();
const mockServiceFrom = vi.fn(() => queryChain({ data: [{ id: "1" }] }));
const mockServiceRpc = vi.fn(() =>
  Promise.resolve({ data: [], error: null }),
);

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
    from: mockServiceFrom,
    rpc: mockServiceRpc,
  }),
}));

vi.mock("@/lib/metrics", () => ({
  metrics: {
    gauge: vi.fn(),
    increment: vi.fn(),
    timing: vi.fn(),
  },
}));

vi.mock("@/lib/logger", () => ({
  logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

const { GET } = await import("./route");

function asAdmin() {
  mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
  mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
}

describe("/api/platform/health (L06-02)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockServiceFrom.mockImplementation(() =>
      queryChain({ data: [{ id: "1" }] }),
    );
    mockServiceRpc.mockImplementation(() =>
      Promise.resolve({ data: [], error: null }),
    );
  });

  it("returns 401 when not authenticated (and does not touch the service client)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(req());
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("UNAUTHORIZED");
    expect(mockServiceFrom).not.toHaveBeenCalled();
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  it("returns 403 when user is not a platform admin (and does not touch the service client)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET(req());
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("UNAUTHORIZED");
    expect(mockServiceFrom).not.toHaveBeenCalled();
    expect(mockServiceRpc).not.toHaveBeenCalled();
  });

  it("returns 200 status=ok with detailed check payload for admins when healthy", async () => {
    asAdmin();
    const res = await GET(req());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.status).toBe("ok");
    expect(body.ts).toBeTypeOf("number");
    expect(body.latency_ms).toBeTypeOf("number");
    expect(body.checks.db).toBe("connected");
    expect(body.checks.invariants).toBe("healthy");
    expect(body.invariant_count).toBe(0);
    expect(body.request_id).toMatch(/[0-9a-f-]{36}/);
    expect(body.checked_at).toBeDefined();
  });

  it("returns 503 status=degraded with exact invariant_count when violations present", async () => {
    asAdmin();
    mockServiceRpc.mockResolvedValueOnce({
      data: [
        { group_id: "g1", issue: "D < R" },
        { group_id: "g2", issue: "D < R" },
        { group_id: "g3", issue: "D < R" },
      ] as unknown[],
      error: null,
    });

    const res = await GET(req());
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("degraded");
    expect(body.checks.db).toBe("connected");
    expect(body.checks.invariants).toBe("violations");
    expect(body.invariant_count).toBe(3);
  });

  it("returns 503 status=down when db is unreachable", async () => {
    asAdmin();
    mockServiceFrom.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "timeout" } }),
    );

    const res = await GET(req());
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("down");
    expect(body.checks.db).toBe("unreachable");
  });

  it("returns 503 status=down when the service client throws", async () => {
    asAdmin();
    mockServiceFrom.mockImplementationOnce(() => {
      throw new Error("connection refused");
    });

    const res = await GET(req());
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("down");
    expect(body.checks.db).toBe("unreachable");
  });

  it("never re-uses invariant_count from a previous call (no leaky state)", async () => {
    asAdmin();
    mockServiceRpc.mockResolvedValueOnce({
      data: [{ group_id: "g1", issue: "D < R" }] as unknown[],
      error: null,
    });
    const first = await GET(req());
    const firstBody = await first.json();
    expect(firstBody.invariant_count).toBe(1);

    const second = await GET(req());
    const secondBody = await second.json();
    expect(secondBody.invariant_count).toBe(0);
    expect(secondBody.status).toBe("ok");
  });

  it("exposes `invariants: \"violations\"` (not the raw count string) in the checks breakdown", async () => {
    asAdmin();
    mockServiceRpc.mockResolvedValueOnce({
      data: [{ group_id: "g1" }, { group_id: "g2" }] as unknown[],
      error: null,
    });

    const res = await GET(req());
    const body = await res.json();
    expect(body.checks.invariants).toBe("violations");
    expect(JSON.stringify(body.checks)).not.toMatch(/violation\(s\)/);
    expect(JSON.stringify(body.checks)).not.toMatch(/\d+ violation/);
  });
});
