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
  source: "both",
  active: true,
  last_status: "completed",
  started_at: "2026-04-19T14:00:00Z",
  finished_at: "2026-04-19T14:00:01Z",
  last_success_at: "2026-04-19T14:00:01Z",
  expected_interval_seconds: 60,
  seconds_since_last_success: 20,
  running_for_seconds: null,
  run_count: 12345,
  skip_count: 0,
  last_error: null,
  last_meta: { processed: 5 },
  severity: "ok",
};

const CRITICAL_ROW = {
  name: "reconcile-wallets-daily",
  schedule: "30 4 * * *",
  source: "both",
  active: true,
  last_status: "failed",
  started_at: "2026-04-17T04:30:00Z",
  finished_at: "2026-04-17T04:30:30Z",
  last_success_at: null,
  expected_interval_seconds: 86400,
  seconds_since_last_success: 360_000,
  running_for_seconds: null,
  run_count: 50,
  skip_count: 1,
  last_error: "rpc deadline exceeded",
  last_meta: { sqlstate: "57014" },
  severity: "critical",
};

function buildRequest(qs: string = ""): NextRequest {
  return new NextRequest(new URL(`http://localhost:3000/api/platform/cron-health${qs}`));
}

describe("/api/platform/cron-health (L06-04)", () => {
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
  });

  it("returns 403 when user is not a platform admin", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: null });
    const res = await GET(buildRequest());
    expect(res.status).toBe(403);
  });

  it("returns 400 on invalid severity_min", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    const res = await GET(buildRequest("?severity_min=oops"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("INVALID_QUERY");
    // RPC must NOT have been hit on a 400.
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns healthy=true with all-OK rows", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({
      data: [HEALTHY_ROW, { ...HEALTHY_ROW, name: "lifecycle-cron", schedule: "*/5 * * * *", expected_interval_seconds: 300 }],
      error: null,
    });

    const res = await GET(buildRequest());
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.healthy).toBe(true);
    expect(body.counts).toEqual({ ok: 2, warn: 0, critical: 0, unknown: 0 });
    expect(body.jobs).toHaveLength(2);
    expect(body.checked_at).toBeDefined();
    expect(body.request_id).toMatch(/[0-9a-f-]{36}/);
    expect(mockRpc).toHaveBeenCalledWith("fn_check_cron_health");
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
    expect(body.jobs.find((j: { name: string }) => j.name === "reconcile-wallets-daily")).toBeDefined();
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
    expect(body.jobs[0].name).toBe("reconcile-wallets-daily");
    // healthy still false because critical is present in the filtered set.
    expect(body.healthy).toBe(false);
  });

  it("returns 500 on RPC failure but still includes request_id", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockSelectSingle.mockResolvedValue({ data: { role: "admin" } });
    mockRpc.mockResolvedValueOnce({ data: null, error: { message: "lock_timeout exceeded" } });

    const res = await GET(buildRequest());
    expect(res.status).toBe(500);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("CRON_HEALTH_CHECK_FAILED");
    expect(body.error.message).toMatch(/lock_timeout/);
    expect(body.error.request_id).toMatch(/[0-9a-f-]{36}/);
  });
});
