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

/**
 * L06-02 / L01-07 — public /api/health MUST NOT leak operational state.
 *
 * The response body is restricted to `{ status, ts }`. No `checks`,
 * no `latencyMs`, no violation counts. The HTTP status code (200 vs
 * 503) is the only granular signal external callers can read.
 */
describe("GET /api/health (public)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 200 with status ok when all checks pass", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("ok");
    expect(json.ts).toBeTypeOf("number");
  });

  it("returns 503 with status degraded when invariants fail, without leaking the count", async () => {
    mockClient.rpc.mockResolvedValueOnce({
      data: [
        { group_id: "g1", issue: "D < R" },
        { group_id: "g2", issue: "D < R" },
        { group_id: "g3", issue: "D < R" },
      ] as unknown[],
      error: null,
    });

    const res = await GET();
    expect(res.status).toBe(503);
    const json = await res.json();
    expect(json.status).toBe("degraded");

    const serialized = JSON.stringify(json);
    expect(serialized).not.toContain("3 violation");
    expect(serialized).not.toContain("violation(s)");
    expect(serialized).not.toMatch(/violation/i);
  });

  it("returns 503 with status down when db query fails", async () => {
    mockClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "timeout" } }),
    );

    const res = await GET();
    expect(res.status).toBe(503);
    const json = await res.json();
    expect(json.status).toBe("down");
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

  it("body contains ONLY {status, ts} — no checks, latency, or counts leak to anonymous callers", async () => {
    const res = await GET();
    const json = await res.json();
    expect(Object.keys(json).sort()).toEqual(["status", "ts"]);
    expect(json).not.toHaveProperty("checks");
    expect(json).not.toHaveProperty("latencyMs");
    expect(json).not.toHaveProperty("latency_ms");
    expect(json).not.toHaveProperty("invariantCount");
    expect(json).not.toHaveProperty("invariant_count");
  });

  it("body shape is stable under invariant violations too (no new keys added on failure)", async () => {
    mockClient.rpc.mockResolvedValueOnce({
      data: [{ group_id: "gx", issue: "D < R" }] as unknown[],
      error: null,
    });
    const res = await GET();
    const json = await res.json();
    expect(Object.keys(json).sort()).toEqual(["status", "ts"]);
  });

  it("body shape is stable when the db is down (no new keys added on failure)", async () => {
    mockClient.from.mockImplementationOnce(() => {
      throw new Error("timeout");
    });
    const res = await GET();
    const json = await res.json();
    expect(Object.keys(json).sort()).toEqual(["status", "ts"]);
  });

  it("still runs checks server-side so status differentiates ok vs degraded vs down", async () => {
    const okRes = await GET();
    expect((await okRes.json()).status).toBe("ok");

    mockClient.rpc.mockResolvedValueOnce({
      data: [{ group_id: "gx" }] as unknown[],
      error: null,
    });
    const degradedRes = await GET();
    expect((await degradedRes.json()).status).toBe("degraded");

    mockClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "boom" } }),
    );
    const downRes = await GET();
    expect((await downRes.json()).status).toBe("down");
  });
});
