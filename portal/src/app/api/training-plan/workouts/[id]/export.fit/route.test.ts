import { describe, it, expect, vi, beforeEach } from "vitest";
import { TEST_SESSION, makeMockClient, queryChain } from "@/test/api-helpers";

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
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockResolvedValue({ allowed: true, remaining: 10 }),
}));
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/logger", () => ({
  logger: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
  },
}));

const originalFetch = globalThis.fetch;
const fetchMock = vi.fn();

const { GET } = await import("./route");

function fitStub(): ArrayBuffer {
  const bytes = new Uint8Array([0x0e, 0x20, 0x60, 0x00, 0x46, 0x49, 0x54]);
  return bytes.buffer;
}

function okEdgeResponse(): Response {
  return new Response(fitStub(), {
    status: 200,
    headers: { "Content-Type": "application/octet-stream" },
  });
}

describe("GET /api/training-plan/workouts/[id]/export.fit", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: TEST_SESSION.user },
    });
    authClient.auth.getSession.mockResolvedValue({
      data: { session: TEST_SESSION },
    });
    authClient.from.mockReset();

    process.env.NEXT_PUBLIC_SUPABASE_URL = "https://stub.supabase.co";
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY = "stub-anon-key";

    fetchMock.mockReset();
    globalThis.fetch = fetchMock as unknown as typeof fetch;
  });

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns 403 when caller is not coach/admin", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "athlete" } }),
    );
    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(403);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns 404 when template does not belong to group", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    authClient.from.mockReturnValueOnce(queryChain({ data: null }));

    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-unknown" },
    });
    expect(res.status).toBe(404);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("returns 502 when edge function is unreachable", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { id: "tpl-1", name: "Tempo 10k" } }),
    );
    fetchMock.mockRejectedValueOnce(new Error("network down"));

    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(502);
  });

  it("returns 502 when edge function returns non-2xx", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { id: "tpl-1", name: "Tempo 10k" } }),
    );
    fetchMock.mockResolvedValueOnce(
      new Response("No workout blocks found", { status: 404 }),
    );

    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(502);
  });

  it("proxies .fit bytes with correct filename on success", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { id: "tpl-1", name: "Tempo 10k / Quinta" } }),
    );
    fetchMock.mockResolvedValueOnce(okEdgeResponse());

    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toBe("application/octet-stream");
    const cd = res.headers.get("Content-Disposition") ?? "";
    expect(cd).toContain("attachment");
    expect(cd).toContain(".fit");
    expect(cd).toMatch(/filename="[A-Za-z0-9_\- ]+\.fit"/);

    const body = new Uint8Array(await res.arrayBuffer());
    expect(body[0]).toBe(0x0e);
    expect(Array.from(body.slice(4, 7))).toEqual([0x46, 0x49, 0x54]);
  });

  it("forwards the user's JWT to the edge function (not service role)", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { id: "tpl-1", name: "Tempo" } }),
    );
    fetchMock.mockResolvedValueOnce(okEdgeResponse());

    await GET(new Request("http://localhost/x"), { params: { id: "tpl-1" } });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [calledUrl, init] = fetchMock.mock.calls[0] as [
      string,
      RequestInit,
    ];
    expect(calledUrl).toBe(
      "https://stub.supabase.co/functions/v1/generate-fit-workout",
    );
    const headers = init.headers as Record<string, string>;
    expect(headers.Authorization).toBe(`Bearer ${TEST_SESSION.access_token}`);
    expect(headers.apikey).toBe("stub-anon-key");
    expect(init.body).toBe(JSON.stringify({ template_id: "tpl-1" }));
  });

  it("returns 429 when rate-limited", async () => {
    const { rateLimit } = await import("@/lib/rate-limit");
    (rateLimit as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      allowed: false,
      remaining: 0,
    });

    const res = await GET(new Request("http://localhost/x"), {
      params: { id: "tpl-1" },
    });
    expect(res.status).toBe(429);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

// Teardown: restore global fetch for sibling tests.
globalThis.fetch = originalFetch;
