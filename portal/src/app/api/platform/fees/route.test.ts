import { describe, it, expect, vi, beforeEach } from "vitest";

const mockGetUser = vi.fn();
const mockSelectSingle = vi.fn();
const mockAdminFrom = vi.fn();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => ({
    auth: { getUser: mockGetUser },
    from: () => ({
      select: () => ({
        eq: () => ({ single: mockSelectSingle }),
      }),
    }),
  }),
}));

const adminQueryChain = (result: { data?: unknown; error?: unknown }) => {
  const self: Record<string, unknown> = {};
  const methods = ["select", "update", "eq", "order"];
  for (const m of methods) {
    self[m] = vi.fn().mockReturnValue(self);
  }
  self.then = (resolve: (v: unknown) => void) => resolve(result);
  return self;
};

vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => ({
    from: mockAdminFrom,
  }),
}));

vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

const { GET, POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/fees", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
    },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

function mockPlatformAdmin() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: "admin-1" } },
  });
  mockSelectSingle.mockResolvedValue({
    data: { role: "admin" },
  });
}

describe("Platform Fees API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe("GET", () => {
    it("returns 401 when not authenticated", async () => {
      mockGetUser.mockResolvedValue({ data: { user: null } });
      const res = await GET();
      expect(res.status).toBe(401);
    });

    it("returns 403 when not platform admin", async () => {
      mockGetUser.mockResolvedValue({
        data: { user: { id: "u1" } },
      });
      mockSelectSingle.mockResolvedValue({ data: null });
      const res = await GET();
      expect(res.status).toBe(403);
    });

    it("returns fees list", async () => {
      mockPlatformAdmin();
      const fees = [
        { fee_type: "clearing", rate_pct: 3.0, is_active: true },
        { fee_type: "swap", rate_pct: 1.0, is_active: true },
      ];
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ data: fees }),
      );

      const res = await GET();
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.fees).toHaveLength(2);
    });
  });

  describe("POST", () => {
    it("updates fee rate", async () => {
      mockPlatformAdmin();
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ error: null }),
      );

      const res = await POST(
        req({ fee_type: "clearing", rate_pct: 5.0 }),
      );
      expect(res.status).toBe(200);
    });

    it("updates fee rate and active status", async () => {
      mockPlatformAdmin();
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ error: null }),
      );

      const res = await POST(
        req({ fee_type: "swap", rate_pct: 2.0, is_active: false }),
      );
      expect(res.status).toBe(200);
    });

    it("returns 400 for invalid fee_type", async () => {
      mockPlatformAdmin();
      const res = await POST(
        req({ fee_type: "invalid", rate_pct: 1.0 }),
      );
      expect(res.status).toBe(400);
    });

    it("returns 400 for rate out of range", async () => {
      mockPlatformAdmin();
      const res = await POST(
        req({ fee_type: "clearing", rate_pct: 150 }),
      );
      expect(res.status).toBe(400);
    });

    it("returns 400 for negative rate", async () => {
      mockPlatformAdmin();
      const res = await POST(
        req({ fee_type: "clearing", rate_pct: -5 }),
      );
      expect(res.status).toBe(400);
    });

    it("returns 500 on db error", async () => {
      mockPlatformAdmin();
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ error: { message: "db down" } }),
      );

      const res = await POST(
        req({ fee_type: "clearing", rate_pct: 3.0 }),
      );
      expect(res.status).toBe(500);
    });

    it("updates maintenance fee with rate_usd", async () => {
      mockPlatformAdmin();
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ error: null }),
      );

      const res = await POST(
        req({ fee_type: "maintenance", rate_usd: 3.5, is_active: true }),
      );
      expect(res.status).toBe(200);
    });

    it("accepts rate_usd = 0 for maintenance", async () => {
      mockPlatformAdmin();
      mockAdminFrom.mockReturnValueOnce(
        adminQueryChain({ error: null }),
      );

      const res = await POST(
        req({ fee_type: "maintenance", rate_usd: 0 }),
      );
      expect(res.status).toBe(200);
    });

    it("rejects rate_usd > 10", async () => {
      mockPlatformAdmin();
      const res = await POST(
        req({ fee_type: "maintenance", rate_usd: 15 }),
      );
      expect(res.status).toBe(400);
    });

    it("rejects negative rate_usd", async () => {
      mockPlatformAdmin();
      const res = await POST(
        req({ fee_type: "maintenance", rate_usd: -1 }),
      );
      expect(res.status).toBe(400);
    });
  });
});
