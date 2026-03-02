import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

const USER_UUID = "00000000-0000-4000-a000-000000000002";
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

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/verification/evaluate", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/verification/evaluate", () => {
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
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller has no permission", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "atleta" } }),
    );
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(403);
  });

  it("allows professor role", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "professor" } }))
      .mockReturnValueOnce(queryChain({ data: { user_id: USER_UUID } }));
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: null }),
    );
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(200);
  });

  it("returns 400 when user_id is missing", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(req({}));
    expect(res.status).toBe(400);
  });

  it("returns 404 when athlete not found in group", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null }));
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(404);
  });

  it("returns 500 when RPC fails", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: { user_id: USER_UUID } }));
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "rpc failed" } }),
    );
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(500);
    expect((await res.json()).error).toContain("rpc failed");
  });

  it("returns 200 on successful evaluation", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: { user_id: USER_UUID } }));
    serviceClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: null }),
    );
    const res = await POST(req({ user_id: USER_UUID }));
    expect(res.status).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });
});
