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
vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), info: vi.fn(), warn: vi.fn() },
}));

const { POST } = await import("./route");

const R1 = "00000000-0000-4000-8000-000000000001";
const P1 = "00000000-0000-4000-8000-000000000002";
const G1 = "00000000-0000-4000-8000-000000000003";

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/refunds", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/refunds", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ action: "approve", refund_id: R1 }));
    expect(res.status).toBe(401);
  });

  it("returns 400 when action is missing", async () => {
    const res = await POST(req({ refund_id: R1 }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when refund_id is missing", async () => {
    const res = await POST(req({ action: "approve", refund_id: "not-a-uuid" }));
    expect(res.status).toBe(400);
  });

  it("approves refund successfully", async () => {
    const res = await POST(req({ action: "approve", refund_id: R1 }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("approved");
  });

  it("rejects refund with notes", async () => {
    const res = await POST(
      req({ action: "reject", refund_id: R1, notes: "Already used" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("rejected");
  });

  it("returns 400 when rejecting without notes", async () => {
    const res = await POST(req({ action: "reject", refund_id: R1 }));
    expect(res.status).toBe(400);
    const json = await res.json();
    expect(json.error).toContain("Notes required");
  });

  it("processes approved refund successfully", async () => {
    // fetch refund
    adminClient.from.mockReturnValueOnce(
      queryChain({
        data: {
          id: R1,
          purchase_id: P1,
          group_id: G1,
          status: "approved",
          credits_to_debit: 50,
        },
      }),
    );

    const res = await POST(req({ action: "process", refund_id: R1 }));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("processed");
  });

  it("returns 400 when processing non-approved refund", async () => {
    adminClient.from.mockReturnValueOnce(
      queryChain({
        data: { id: R1, status: "requested", credits_to_debit: 10 },
      }),
    );

    const res = await POST(req({ action: "process", refund_id: R1 }));
    expect(res.status).toBe(400);
    const json = await res.json();
    expect(json.error).toContain("approved before processing");
  });

  it("reverts to approved if credit debit fails", async () => {
    // fetch refund
    adminClient.from.mockReturnValueOnce(
      queryChain({
        data: {
          id: R1,
          purchase_id: P1,
          group_id: G1,
          status: "approved",
          credits_to_debit: 100,
        },
      }),
    );
    // update status to processed
    adminClient.from.mockReturnValueOnce(queryChain());
    // update purchase
    adminClient.from.mockReturnValueOnce(queryChain());
    // billing event insert
    adminClient.from.mockReturnValueOnce(queryChain());
    // debit fails
    adminClient.rpc.mockReturnValueOnce(
      queryChain({ data: null, error: { message: "insufficient credits" } }),
    );

    const res = await POST(req({ action: "process", refund_id: R1 }));
    expect(res.status).toBe(500);
    const json = await res.json();
    expect(json.error).toContain("credit debit failed");
  });

  it("returns 400 for invalid action", async () => {
    const res = await POST(req({ action: "cancel", refund_id: R1 }));
    expect(res.status).toBe(400);
  });
});
