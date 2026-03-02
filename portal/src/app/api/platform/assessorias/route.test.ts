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
  rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }),
}));

const { POST } = await import("./route");

const UUID = "00000000-0000-4000-8000-000000000001";

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/assessorias", {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-forwarded-for": "127.0.0.1" },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/assessorias", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ action: "approve", group_id: UUID }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { platform_role: "user" } }),
    );
    const res = await POST(req({ action: "approve", group_id: UUID }));
    expect(res.status).toBe(403);
  });

  it("returns 400 when action is missing", async () => {
    const res = await POST(req({ group_id: UUID }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when group_id is missing", async () => {
    const res = await POST(req({ action: "approve" }));
    expect(res.status).toBe(400);
  });

  it("approves group successfully", async () => {
    const res = await POST(req({ action: "approve", group_id: UUID }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("approved");
    expect(json.group_id).toBe(UUID);
  });

  it("rejects group successfully", async () => {
    const res = await POST(
      req({ action: "reject", group_id: UUID, reason: "Incomplete data" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("rejected");
  });

  it("suspends group successfully", async () => {
    const res = await POST(
      req({ action: "suspend", group_id: UUID, reason: "TOS violation" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("suspended");
  });

  it("returns 400 for invalid action", async () => {
    const res = await POST(req({ action: "delete", group_id: UUID }));
    expect(res.status).toBe(400);
  });

  it("returns 500 when DB update fails", async () => {
    adminClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "db error" } }),
    );
    const res = await POST(req({ action: "approve", group_id: UUID }));
    expect(res.status).toBe(500);
  });
});
