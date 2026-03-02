import { describe, it, expect, vi, beforeEach } from "vitest";
import { makePlatformMocks } from "@/test/platform-helpers";
import { queryChain } from "@/test/api-helpers";

const { authClient, adminClient } = makePlatformMocks();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => adminClient,
}));
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

const { POST } = await import("./route");

const validId = "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4";

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/feature-flags", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
    },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/feature-flags", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ id: validId, enabled: true, rollout_pct: 50 }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    authClient.from.mockReturnValueOnce(queryChain({ data: null }));
    const res = await POST(req({ id: validId, enabled: true, rollout_pct: 50 }));
    expect(res.status).toBe(403);
  });

  it("returns 400 for invalid input (missing id)", async () => {
    const res = await POST(req({ enabled: true, rollout_pct: 50 }));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Invalid input");
  });

  it("returns 400 for rollout_pct out of range", async () => {
    const res = await POST(req({ id: validId, enabled: true, rollout_pct: 200 }));
    expect(res.status).toBe(400);
  });

  it("returns 400 for non-uuid id", async () => {
    const res = await POST(req({ id: "not-a-uuid", enabled: true, rollout_pct: 50 }));
    expect(res.status).toBe(400);
  });

  it("updates flag and returns ok for valid input", async () => {
    adminClient.from.mockReturnValueOnce(queryChain({ error: null }));

    const res = await POST(req({ id: validId, enabled: false, rollout_pct: 75 }));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
  });

  it("returns 500 when database update fails", async () => {
    adminClient.from.mockReturnValueOnce(
      queryChain({ error: { message: "DB error" } }),
    );

    const res = await POST(req({ id: validId, enabled: true, rollout_pct: 50 }));
    expect(res.status).toBe(500);
  });
});
