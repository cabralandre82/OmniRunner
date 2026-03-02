import { describe, it, expect, vi, beforeEach } from "vitest";
import { makePlatformMocks } from "@/test/platform-helpers";
import { queryChain } from "@/test/api-helpers";

const { authClient, adminClient } = makePlatformMocks();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("@/lib/supabase/admin", () => ({
  createAdminClient: () => adminClient,
}));
vi.mock("@/lib/audit", () => ({
  auditLog: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("@/lib/rate-limit", () => ({
  rateLimit: vi.fn().mockReturnValue({ allowed: true, remaining: 10 }),
}));

const { POST } = await import("./route");

const PROD_ID = "00000000-0000-4000-8000-000000000001";

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/products", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/products", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ action: "create", name: "Pack" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { platform_role: "user" } }),
    );
    const res = await POST(req({ action: "create", name: "Pack" }));
    expect(res.status).toBe(403);
  });

  it("creates product successfully", async () => {
    const res = await POST(
      req({
        action: "create",
        name: "Pack 50",
        credits_amount: 50,
        price_cents: 4990,
      }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("created");
  });

  it("returns 400 when required fields are missing for create", async () => {
    const res = await POST(req({ action: "create", name: "Pack" }));
    expect(res.status).toBe(400);
  });

  it("toggles product active status", async () => {
    const res = await POST(
      req({ action: "toggle_active", product_id: PROD_ID, is_active: false }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("updated");
  });

  it("returns 400 when product_id is missing for toggle", async () => {
    const res = await POST(req({ action: "toggle_active" }));
    expect(res.status).toBe(400);
  });

  it("updates product successfully", async () => {
    const res = await POST(
      req({ action: "update", product_id: PROD_ID, name: "Pack 100" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("updated");
  });

  it("deletes product successfully", async () => {
    const res = await POST(req({ action: "delete", product_id: PROD_ID }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("deleted");
  });

  it("returns 400 for invalid action", async () => {
    const res = await POST(req({ action: "archive" }));
    expect(res.status).toBe(400);
  });

  it("returns 500 when DB insert fails", async () => {
    adminClient.from.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "constraint violation" } }),
    );
    const res = await POST(
      req({ action: "create", name: "P", credits_amount: 10, price_cents: 990 }),
    );
    expect(res.status).toBe(500);
  });
});
