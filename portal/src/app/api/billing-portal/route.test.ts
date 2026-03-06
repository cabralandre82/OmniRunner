import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient(TEST_SESSION);

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));

const mockFetch = vi.fn();
vi.stubGlobal("fetch", mockFetch);

const { POST } = await import("./route");

describe("POST /api/billing-portal", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getSession.mockResolvedValue({
      data: { session: TEST_SESSION },
    });
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({
      data: { user: null },
    });
    const res = await POST();
    expect(res.status).toBe(401);
  });

  it("returns 200 with portal_url on success", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 200,
      json: async () => ({ ok: true, portal_url: "https://billing.example.com" }),
    });

    const res = await POST();
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.portal_url).toBe("https://billing.example.com");
  });

  it("returns error status when edge function fails", async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 500,
      json: async () => ({ error: { message: "Internal error" } }),
    });

    const res = await POST();
    expect(res.status).toBe(500);
    const json = await res.json();
    expect(json.error).toBe("Internal error");
  });
});
