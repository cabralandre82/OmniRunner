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

const { GET } = await import("./route");

describe("GET /api/export/athletes", () => {
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
    const res = await GET();
    expect(res.status).toBe(401);
  });

  it("returns 403 when caller is not admin or coach", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "athlete" } }),
    );
    const res = await GET();
    expect(res.status).toBe(403);
  });

  it("returns CSV with correct headers and content-type", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "admin_master" } }),
    );
    serviceClient.from.mockReturnValueOnce(
      queryChain({
        data: [
          { id: "m1", display_name: "João Silva", email: "joao@test.com", role: "athlete", joined_at_ms: 1700000000000 },
          { id: "m2", display_name: "Maria", email: "maria@test.com", role: "coach", joined_at_ms: 1700100000000 },
        ],
      }),
    );

    const res = await GET();
    expect(res.status).toBe(200);
    expect(res.headers.get("Content-Type")).toContain("text/csv");
    expect(res.headers.get("Content-Disposition")).toContain("attachment");

    const csv = await res.text();
    expect(csv).toContain("Nome,Email,Função,Membro desde");
    expect(csv).toContain("João Silva");
    expect(csv).toContain("joao@test.com");
  });

  it("returns CSV with empty data when no members", async () => {
    serviceClient.from.mockReturnValueOnce(
      queryChain({ data: { role: "coach" } }),
    );
    serviceClient.from.mockReturnValueOnce(queryChain({ data: [] }));

    const res = await GET();
    expect(res.status).toBe(200);
    const csv = await res.text();
    const lines = csv.trim().split("\n");
    expect(lines.length).toBe(1);
  });
});
