import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

const authClient = makeMockClient(TEST_SESSION);
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
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }),
}));

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/team/remove", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/team/remove", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getSession.mockResolvedValue({
      data: { session: TEST_SESSION },
    });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getSession.mockResolvedValueOnce({
      data: { session: null },
    });
    const res = await POST(req({ member_id: "m-1" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller is not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "professor" } }),
    );
    const res = await POST(req({ member_id: "m-1" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 when member_id is missing", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(req({}));
    expect(res.status).toBe(400);
  });

  it("returns 404 when member not found", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }));
    const res = await POST(req({ member_id: "nonexistent" }));
    expect(res.status).toBe(404);
  });

  it("returns 400 when trying to remove self", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(
        queryChain({
          data: { id: "m-1", user_id: TEST_SESSION.user.id, role: "admin_master" },
        }),
      );
    const res = await POST(req({ member_id: "m-1" }));
    expect(res.status).toBe(400);
    expect((await res.json()).error).toContain("si mesmo");
  });

  it("returns 403 when trying to remove another admin_master", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(
        queryChain({
          data: { id: "m-2", user_id: "other-admin", role: "admin_master" },
        }),
      );
    const res = await POST(req({ member_id: "m-2" }));
    expect(res.status).toBe(403);
    expect((await res.json()).error).toContain("admin_master");
  });

  it("returns 200 on successful removal", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(
        queryChain({
          data: { id: "m-3", user_id: "athlete-1", role: "atleta" },
        }),
      )
      .mockReturnValueOnce(queryChain({ data: null, error: null }));
    const res = await POST(req({ member_id: "m-3" }));
    expect(res.status).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });
});
