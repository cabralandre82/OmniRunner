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
  return new Request("http://localhost/api/team/invite", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/team/invite", () => {
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
    const res = await POST(req({ email: "a@b.com", role: "coach" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller is not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    const res = await POST(req({ email: "a@b.com", role: "coach" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 for invalid email", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(req({ email: "not-an-email", role: "coach" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 for invalid role", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(req({ email: "a@b.com", role: "admin_master" }));
    expect(res.status).toBe(400);
  });

  it("returns 404 when user is not found", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: null }),
    );
    const res = await POST(req({ email: "new@example.com", role: "coach" }));
    expect(res.status).toBe(404);
  });

  it("returns 409 when user is already a member", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(
        queryChain({ data: { id: "member-1", role: "athlete" } }),
      );
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: { id: "target-user", display_name: "João" } }),
    );
    const res = await POST(req({ email: "joao@example.com", role: "coach" }));
    expect(res.status).toBe(409);
    expect((await res.json()).error).toContain("já é membro");
  });

  it("returns 200 on successful invite", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null })) // no existing member
      .mockReturnValueOnce(queryChain({ data: null, error: null })); // insert
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({
        data: { id: "target-user", display_name: "Maria" },
      }),
    );
    const res = await POST(
      req({ email: "maria@example.com", role: "assistant" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.ok).toBe(true);
    expect(json.role).toBe("assistant");
  });
});
