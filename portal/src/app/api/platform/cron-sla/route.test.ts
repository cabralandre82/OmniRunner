import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

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
  createServiceClient: () => ({ rpc: mockRpc }),
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

const HEALTHY_ROW = {
  name: "settle-clearing-batch",
  schedule: "* * * * *",
  expected_interval_seconds: 60,
  source_thresholds: "configured",
  target_seconds: 15,
  breach_seconds: 50,
  enabled: true,
  run_count: 1440,
  failed_count: 0,
  avg_duration_seconds: 8.2,
  p50_duration_seconds: 8,
  p95_duration_seconds: 14,
  p99_duration_seconds: 20,
  max_duration_seconds: 27,
  last_duration_seconds: 9,
  last_finished_at: "2026-04-20T13:59:09Z",
  breach_count: 0,
  severity: "ok",
};

const CRITICAL_ROW = {
  name: "clearing-cron",
  schedule: "0 2 * * *",
  expected_interval_seconds: 86400,
  source_thresholds: "configured",
  target_seconds: 60,
  breach_seconds: 240,
  enabled: true,
  run_count: 1,
  failed_count: 0,
  avg_duration_seconds: 720,
  p50_duration_seconds: 720,
  p95_duration_seconds: 720,
  p99_duration_seconds: 720,
  max_duration_seconds: 720,
  last_duration_seconds: 720,
  last_finished_at: "2026-04-20T02:12:00Z",
  breach_count: 1,
  severity: "critical",
};

function buildRequest(qs: string = ""): NextRequest {
  return new NextRequest(
    new URL(`http://localhost:3000/api/platform/cron-sla${qs}`),
  );
}

describe("/api/platform/cron-sla (L12-04)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET(buildRequest());
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("UNAUTHORIZED");
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns 403 when user is not a platform admin", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET(buildRequest());
    expect(res.status).toBe(403);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns 400 on invalid severity_min (without hitting RPC)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    const res = await GET(buildRequest("?severity_min=oops"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_QUERY");
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns 400 on out-of-range window_hours (without hitting RPC)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });

    const tooHigh = await GET(buildRequest("?window_hours=10000"));
    expect(tooHigh.status).toBe(400);

    const tooLow = await GET(buildRequest("?window_hours=0"));
    expect(tooLow.status).toBe(400);

    const negative = await GET(buildRequest("?window_hours=-5"));
    expect(negative.status).toBe(400);

    const garbage = await GET(buildRequest("?window_hours=abc"));
    expect(garbage.status).toBe(400);

    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns healthy=true with all-OK rows and default 24h window", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({ data: [HEALTHY_ROW], error: null });

    const res = await GET(buildRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.healthy).toBe(true);
    expect(body.window_hours).toBe(24);
    expect(body.counts).toEqual({ ok: 1, warn: 0, critical: 0, unknown: 0 });
    expect(body.jobs).toHaveLength(1);
    expect(body.checked_at).toBeDefined();
    expect(body.request_id).toMatch(/[0-9a-f-]{36}/);
    expect(mockRpc).toHaveBeenCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 24,
    });
  });

  it("forwards explicit window_hours into the RPC", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({ data: [], error: null });

    const res = await GET(buildRequest("?window_hours=72"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.window_hours).toBe(72);
    expect(mockRpc).toHaveBeenCalledWith("fn_compute_cron_sla_stats", {
      p_window_hours: 72,
    });
  });

  it("returns healthy=false with critical rows + correct counts", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({
      data: [HEALTHY_ROW, CRITICAL_ROW],
      error: null,
    });

    const res = await GET(buildRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.healthy).toBe(false);
    expect(body.counts).toEqual({ ok: 1, warn: 0, critical: 1, unknown: 0 });
    const offending = body.jobs.find(
      (j: { name: string }) => j.name === "clearing-cron",
    );
    expect(offending).toBeDefined();
    expect(offending.severity).toBe("critical");
  });

  it("filters rows below severity_min when requested", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({
      data: [HEALTHY_ROW, CRITICAL_ROW],
      error: null,
    });

    const res = await GET(buildRequest("?severity_min=warn"));
    const body = await res.json();
    expect(body.jobs).toHaveLength(1);
    expect(body.jobs[0].name).toBe("clearing-cron");
    expect(body.healthy).toBe(false);
  });

  it("returns 500 on RPC failure but still includes request_id", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({
      data: null,
      error: { message: "statement_timeout exceeded" },
    });

    const res = await GET(buildRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("CRON_SLA_CHECK_FAILED");
    expect(body.error.message).toMatch(/statement_timeout/);
    expect(body.error.request_id).toMatch(/[0-9a-f-]{36}/);
  });
});
