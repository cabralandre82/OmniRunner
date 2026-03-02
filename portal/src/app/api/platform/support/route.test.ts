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

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/support", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/support", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ action: "reply", ticket_id: "t1" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { platform_role: "user" } }),
    );
    const res = await POST(req({ action: "reply", ticket_id: "t1" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 when action is missing", async () => {
    const res = await POST(req({ ticket_id: "t1" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when ticket_id is missing", async () => {
    const res = await POST(req({ action: "reply" }));
    expect(res.status).toBe(400);
  });

  it("replies to ticket successfully", async () => {
    const res = await POST(
      req({ action: "reply", ticket_id: "t1", message: "We are looking into it" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("replied");
    expect(json.ticket_id).toBe("t1");
  });

  it("returns 400 when replying without message", async () => {
    const res = await POST(req({ action: "reply", ticket_id: "t1" }));
    expect(res.status).toBe(400);
    const json = await res.json();
    expect(json.error).toContain("Message is required");
  });

  it("closes ticket successfully", async () => {
    const res = await POST(req({ action: "close", ticket_id: "t1" }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("closed");
  });

  it("reopens ticket successfully", async () => {
    const res = await POST(req({ action: "reopen", ticket_id: "t1" }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("reopened");
  });

  it("returns 400 for invalid action", async () => {
    const res = await POST(req({ action: "delete", ticket_id: "t1" }));
    expect(res.status).toBe(400);
  });

  it("returns 500 when DB insert fails on reply", async () => {
    adminClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "db error" } }),
    );
    const res = await POST(
      req({ action: "reply", ticket_id: "t1", message: "Test" }),
    );
    expect(res.status).toBe(500);
  });
});
