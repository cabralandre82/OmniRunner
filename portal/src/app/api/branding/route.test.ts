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

const { GET, POST } = await import("./route");

function postReq(body: Record<string, unknown>) {
  return new Request("http://localhost/api/branding", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("GET /api/branding", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns defaults when no branding row exists", async () => {
    authClient.from.mockReturnValueOnce(queryChain({ data: null }));
    const res = await GET();
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.primary_color).toBe("#2563eb");
    expect(json.logo_url).toBeNull();
  });

  it("returns stored branding data", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({
        data: {
          logo_url: "https://example.com/logo.png",
          primary_color: "#ff0000",
          sidebar_bg: "#000000",
          sidebar_text: "#ffffff",
          accent_color: "#00ff00",
        },
      }),
    );
    const res = await GET();
    const json = await res.json();
    expect(json.primary_color).toBe("#ff0000");
    expect(json.logo_url).toBe("https://example.com/logo.png");
  });
});

describe("POST /api/branding", () => {
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
    const res = await POST(postReq({ primary_color: "#ff0000" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller is not admin_master", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    const res = await POST(postReq({ primary_color: "#ff0000" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 for invalid primary_color", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(postReq({ primary_color: "red" }));
    expect(res.status).toBe(400);
    expect((await res.json()).error).toContain("hex");
  });

  it("returns 400 for invalid sidebar_bg", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(postReq({ sidebar_bg: "#GGG" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 for invalid accent_color", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(postReq({ accent_color: "123456" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 for logo_url too long", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    const res = await POST(postReq({ logo_url: "x".repeat(513) }));
    expect(res.status).toBe(400);
  });

  it("returns 200 on valid update", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(
      postReq({ primary_color: "#ff0000", accent_color: "#00ff00" }),
    );
    expect(res.status).toBe(200);
    expect((await res.json()).ok).toBe(true);
  });

  it("allows clearing logo_url with null", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ data: null, error: null }));

    const res = await POST(postReq({ logo_url: null }));
    expect(res.status).toBe(200);
  });

  it("returns 500 when upsert fails", async () => {
    serviceClient.from
      .mockReturnValueOnce(queryChain({ data: { role: "admin_master" } }))
      .mockReturnValueOnce(queryChain({ error: { message: "db error" } }));

    const res = await POST(postReq({ primary_color: "#ff0000" }));
    expect(res.status).toBe(500);
  });
});
