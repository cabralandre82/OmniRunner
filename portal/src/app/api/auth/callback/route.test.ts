import { describe, it, expect, vi, beforeEach } from "vitest";

let mockExchangeCode: ReturnType<typeof vi.fn>;
const mockCookieStore = {
  getAll: vi.fn().mockReturnValue([]),
};

vi.mock("next/headers", () => ({
  cookies: () => mockCookieStore,
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: (_url: string, _key: string, opts: { cookies: { setAll: (c: unknown[]) => void } }) => {
    return {
      auth: {
        exchangeCodeForSession: mockExchangeCode,
      },
    };
  },
}));

const { GET } = await import("./route");

function makeRequest(params: Record<string, string> = {}) {
  const url = new URL("http://localhost:3000/api/auth/callback");
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, v);
  }
  return new Request(url.toString());
}

describe("GET /api/auth/callback", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockExchangeCode = vi.fn().mockResolvedValue({ error: null });
  });

  it("redirects to /dashboard on successful code exchange", async () => {
    const res = await GET(makeRequest({ code: "valid-code" }));
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toContain("/dashboard");
    expect(mockExchangeCode).toHaveBeenCalledWith("valid-code");
  });

  it("redirects to custom next path when provided", async () => {
    const res = await GET(makeRequest({ code: "abc", next: "/settings" }));
    expect(res.status).toBe(307);
    expect(res.headers.get("location")).toContain("/settings");
  });

  it("redirects to /login with error when exchange fails", async () => {
    mockExchangeCode.mockResolvedValue({
      error: { message: "invalid_grant" },
    });

    const res = await GET(makeRequest({ code: "bad-code" }));
    expect(res.status).toBe(307);
    const location = res.headers.get("location")!;
    expect(location).toContain("/login");
    expect(location).toContain("error=auth");
    expect(location).toContain("invalid_grant");
  });

  it("redirects to /login with no_code when code is missing", async () => {
    const res = await GET(makeRequest({}));
    expect(res.status).toBe(307);
    const location = res.headers.get("location")!;
    expect(location).toContain("/login");
    expect(location).toContain("no_code");
  });
});
