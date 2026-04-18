import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient();
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

const getAuthoritativeFxQuote = vi.fn();
vi.mock("@/lib/fx/quote", async () => {
  const actual = await vi.importActual<typeof import("@/lib/fx/quote")>(
    "@/lib/fx/quote",
  );
  return { ...actual, getAuthoritativeFxQuote };
});

const { GET } = await import("./route");

function req(currency = "BRL") {
  const url = `http://localhost/api/custody/fx-quote?currency=${currency}`;
  return new Request(url) as unknown as import("next/server").NextRequest;
}

function mockMembership(role: string | null = "coach") {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: role ? { role } : null }),
  );
}

describe("GET /api/custody/fx-quote — L01-02 read-only quote endpoint", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
  });

  it("retorna 200 com quote para membro autenticado", async () => {
    mockMembership("coach");
    getAuthoritativeFxQuote.mockResolvedValueOnce({
      currency: "BRL",
      rate: 5.25,
      source: "ptax",
      fetchedAt: "2026-04-17T12:00:00Z",
      ageSeconds: 600,
    });

    const res = await GET(req("BRL"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({
      currency: "BRL",
      rate: 5.25,
      source: "ptax",
      fetched_at: "2026-04-17T12:00:00Z",
      age_seconds: 600,
    });
    expect(res.headers.get("Cache-Control")).toContain("private");
  });

  it("default currency = BRL quando query param ausente", async () => {
    mockMembership("athlete");
    getAuthoritativeFxQuote.mockResolvedValueOnce({
      currency: "BRL",
      rate: 5.2,
      source: "seed",
      fetchedAt: "t",
      ageSeconds: 0,
    });
    const url = "http://localhost/api/custody/fx-quote";
    const res = await GET(
      new Request(url) as unknown as import("next/server").NextRequest,
    );
    expect(res.status).toBe(200);
    expect(getAuthoritativeFxQuote).toHaveBeenCalledWith("BRL");
  });

  it("retorna 401 para não autenticado", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await GET(req("BRL"));
    expect(res.status).toBe(401);
    expect(getAuthoritativeFxQuote).not.toHaveBeenCalled();
  });

  it("retorna 403 para usuário sem membership no grupo", async () => {
    mockMembership(null);
    const res = await GET(req("BRL"));
    expect(res.status).toBe(403);
    expect(getAuthoritativeFxQuote).not.toHaveBeenCalled();
  });

  it("retorna 400 para moeda inválida (JPY)", async () => {
    const { FxQuoteUnsupportedError } = await import("@/lib/fx/quote");
    mockMembership("coach");
    getAuthoritativeFxQuote.mockRejectedValueOnce(
      new FxQuoteUnsupportedError("JPY"),
    );

    const res = await GET(req("JPY"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.code).toBe("unsupported");
  });

  it("retorna 503 com code='stale' quando cotação expirada", async () => {
    const { FxQuoteStaleError } = await import("@/lib/fx/quote");
    mockMembership("coach");
    getAuthoritativeFxQuote.mockRejectedValueOnce(
      new FxQuoteStaleError("BRL", 100_000, 86400),
    );

    const res = await GET(req("BRL"));
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.code).toBe("stale");
  });

  it("retorna 503 com code='missing' quando não há cotação", async () => {
    const { FxQuoteMissingError } = await import("@/lib/fx/quote");
    mockMembership("coach");
    getAuthoritativeFxQuote.mockRejectedValueOnce(
      new FxQuoteMissingError("EUR"),
    );

    const res = await GET(req("EUR"));
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.code).toBe("missing");
  });
});
