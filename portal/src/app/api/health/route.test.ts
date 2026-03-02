import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain } from "@/test/api-helpers";

const mockClient = {
  from: vi.fn(() => queryChain({ data: [{ id: "1" }] })),
  rpc: vi.fn(() => Promise.resolve({ data: [], error: null })),
};

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => mockClient,
}));

vi.mock("@/lib/metrics", () => ({
  metrics: { timing: vi.fn(), gauge: vi.fn(), increment: vi.fn() },
}));

const { GET } = await import("./route");

describe("GET /api/health", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 200 with status ok when all checks pass", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("ok");
    expect(json.checks.db).toBe("connected");
    expect(json.checks.invariants).toBe("healthy");
    expect(json.ts).toBeTypeOf("number");
    expect(json.latencyMs).toBeTypeOf("number");
  });

  it("returns 503 degraded when invariants fail", async () => {
    mockClient.rpc.mockResolvedValueOnce({
      data: [{ group_id: "g1", issue: "D < R" }] as unknown[],
      error: null,
    });

    const res = await GET();
    expect(res.status).toBe(503);
    const json = await res.json();
    expect(json.status).toBe("degraded");
    expect(json.checks.invariants).toBe("1 violation(s)");
  });

  it("returns 503 with status down when db query fails", async () => {
    mockClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "timeout" } }),
    );

    const res = await GET();
    expect(res.status).toBe(503);
    const json = await res.json();
    expect(json.status).toBe("down");
    expect(json.checks.db).toBe("unreachable");
  });

  it("returns 503 when client throws", async () => {
    mockClient.from.mockImplementationOnce(() => {
      throw new Error("connection refused");
    });

    const res = await GET();
    expect(res.status).toBe(503);
    const json = await res.json();
    expect(json.status).toBe("down");
  });
});
