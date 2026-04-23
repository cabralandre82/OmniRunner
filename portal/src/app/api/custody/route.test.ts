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
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: () => ({ allowed: true, remaining: 10 }),
}));

const createCustodyDepositMock = vi.fn().mockResolvedValue({
  deposit: { id: "dep-1", amount_usd: 1000, status: "pending" },
  wasIdempotent: false,
});
const confirmDepositMock = vi.fn().mockResolvedValue(undefined);

vi.mock("@/lib/custody", () => ({
  getCustodyAccount: vi.fn().mockResolvedValue({
    id: "acc-1",
    group_id: "group-1",
    total_deposited_usd: 5000,
    total_committed: 2000,
    total_settled_usd: 500,
    is_blocked: false,
    available: 3000,
  }),
  getOrCreateCustodyAccount: vi.fn().mockResolvedValue({ id: "acc-1" }),
  createCustodyDeposit: createCustodyDepositMock,
  confirmDeposit: confirmDepositMock,
}));

const { GET, POST } = await import("./route");

const VALID_IDEMPOTENCY_KEY = "550e8400-e29b-41d4-a716-446655440000";

function req(
  body: Record<string, unknown>,
  headers: Record<string, string> = {},
) {
  return new Request("http://localhost/api/custody", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-forwarded-for": "127.0.0.1",
      ...headers,
    },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

// L17-01 — wrapper now reads `req.headers`/`req.method` to derive
// request_id; GET helpers must pass a real request object.
function getReq() {
  return new Request("http://localhost/api/custody", {
    headers: { "x-forwarded-for": "127.0.0.1" },
  }) as unknown as import("next/server").NextRequest;
}

function mockAdminCheck() {
  serviceClient.from.mockReturnValueOnce(
    queryChain({ data: { role: "admin_master" } }),
  );
}

describe("Custody API", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authClient.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
    });
    createCustodyDepositMock.mockResolvedValue({
      deposit: { id: "dep-1", amount_usd: 1000, status: "pending" },
      wasIdempotent: false,
    });
    confirmDepositMock.mockResolvedValue(undefined);
  });

  describe("GET", () => {
    it("returns custody account", async () => {
      mockAdminCheck();
      const res = await GET(getReq());
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.account).toBeDefined();
      expect(body.account.available).toBe(3000);
    });

    it("returns 401 when not authenticated", async () => {
      authClient.auth.getUser.mockResolvedValueOnce({
        data: { user: null },
      });
      const res = await GET(getReq());
      expect(res.status).toBe(401);
    });
  });

  describe("POST (deposit) — L01-04 idempotency", () => {
    it("creates deposit for valid input with idempotency-key", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.deposit).toBeDefined();
      expect(body.idempotent).toBe(false);
      expect(res.headers.get("Idempotent-Replayed")).toBe(null);
      expect(createCustodyDepositMock).toHaveBeenCalledWith(
        "group-1",
        1000,
        "stripe",
        VALID_IDEMPOTENCY_KEY,
      );
    });

    it("returns 400 when x-idempotency-key header is missing", async () => {
      mockAdminCheck();
      const res = await POST(req({ amount_usd: 1000, gateway: "stripe" }));
      expect(res.status).toBe(400);
      const body = await res.json();
      // L14-05 — canonical envelope: error.code
      expect(body.error.code).toBe("IDEMPOTENCY_KEY_REQUIRED");
    });

    it("returns 400 when x-idempotency-key is too short", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": "short" },
        ),
      );
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error.code).toBe("IDEMPOTENCY_KEY_INVALID");
    });

    it("returns 400 when x-idempotency-key has invalid chars", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": "invalid key with spaces and special!@#chars" },
        ),
      );
      expect(res.status).toBe(400);
      const body = await res.json();
      expect(body.error.code).toBe("IDEMPOTENCY_KEY_INVALID");
    });

    it("accepts opaque 16+ char keys (ULID, nanoid)", async () => {
      mockAdminCheck();
      const ulid = "01HFYC8Q3T_ABC-1234XYZ"; // 22 chars, valid set
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": ulid },
        ),
      );
      expect(res.status).toBe(200);
    });

    it("returns idempotent=true and Idempotent-Replayed header on replay", async () => {
      createCustodyDepositMock.mockResolvedValueOnce({
        deposit: { id: "dep-1", amount_usd: 1000, status: "pending" },
        wasIdempotent: true,
      });
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.idempotent).toBe(true);
      expect(res.headers.get("Idempotent-Replayed")).toBe("true");
    });

    it("returns 400 for amount below minimum", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 5, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(400);
    });

    it("returns 400 for invalid gateway", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "paypal" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(400);
    });

    it("rejects unknown fields (strict schema)", async () => {
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe", evil_field: "bypass" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(400);
    });

    // L05-09 — daily deposit cap antifraud guardrail
    it("returns 422 DAILY_DEPOSIT_CAP_EXCEEDED when RPC raises P0010", async () => {
      const pgErr = Object.assign(
        new Error("DAILY_DEPOSIT_CAP_EXCEEDED: group=group-1 would_total=51000 limit=50000"),
        {
          code: "P0010",
          hint: "Cap diário de US$ 50000 atingido. Aumente via PATCH /api/platform/custody/[groupId]/daily-cap",
        },
      );
      createCustodyDepositMock.mockRejectedValueOnce(pgErr);
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 49000, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(422);
      const body = await res.json();
      expect(body.error.code).toBe("DAILY_DEPOSIT_CAP_EXCEEDED");
      expect(body.error.details.hint).toMatch(/Aumente.*PATCH/);
    });

    it("matches DAILY_DEPOSIT_CAP_EXCEEDED by message even without code", async () => {
      const pgErr = Object.assign(
        new Error("DAILY_DEPOSIT_CAP_EXCEEDED on insert"),
        {},
      );
      createCustodyDepositMock.mockRejectedValueOnce(pgErr);
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(422);
      const body = await res.json();
      expect(body.error.code).toBe("DAILY_DEPOSIT_CAP_EXCEEDED");
    });

    it("rethrows non-P0010 errors (caught by withErrorHandler → 500)", async () => {
      // Outermost withErrorHandler wraps this and returns 500 INTERNAL_ERROR.
      const pgErr = Object.assign(new Error("unexpected DB error"), {
        code: "P9999",
      });
      createCustodyDepositMock.mockRejectedValueOnce(pgErr);
      mockAdminCheck();
      const res = await POST(
        req(
          { amount_usd: 1000, gateway: "stripe" },
          { "x-idempotency-key": VALID_IDEMPOTENCY_KEY },
        ),
      );
      expect(res.status).toBe(500);
      const body = await res.json();
      // Canonical envelope, no `e.message` leak.
      expect(body.error.code).toBe("INTERNAL_ERROR");
    });
  });

  describe("POST (confirm) — L01-04 cross-group block", () => {
    it("propagates groupId to confirmDeposit (cross-group block)", async () => {
      mockAdminCheck();
      const depositId = "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4";
      const res = await POST(req({ deposit_id: depositId }));
      expect(res.status).toBe(200);
      expect(confirmDepositMock).toHaveBeenCalledWith(depositId, "group-1");
    });

    it("returns 422 when confirm fails (e.g. wrong group from RPC)", async () => {
      confirmDepositMock.mockRejectedValueOnce(
        new Error("Deposit not found, wrong group, or already processed"),
      );
      mockAdminCheck();
      const res = await POST(
        req({ deposit_id: "a0a0a0a0-b1b1-4c2c-8d3d-e4e4e4e4e4e4" }),
      );
      expect(res.status).toBe(422);
      const body = await res.json();
      // L14-05 — canonical envelope wraps the message under error.message;
      // the error code becomes a stable token for clients.
      expect(body.error.message).toMatch(/wrong group/);
      expect(body.error.code).toBe("CUSTODY_CONFIRM_FAILED");
    });
  });
});
