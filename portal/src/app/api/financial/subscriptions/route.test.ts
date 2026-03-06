import { describe, it, expect, vi, beforeEach } from "vitest";
import { queryChain, makeMockClient } from "@/test/api-helpers";

const authClient = makeMockClient();

vi.mock("@/lib/supabase/server", () => ({
  createClient: () => authClient,
}));
vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
  }),
}));

const { POST } = await import("./route");

function makeReq(body: Record<string, unknown>) {
  return new Request("http://localhost/api/financial/subscriptions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("POST /api/financial/subscriptions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 400 when no group", async () => {
    vi.doMock("next/headers", () => ({
      cookies: () => ({ get: () => undefined }),
    }));
    const { POST: POST2 } = await import("./route");
    const res = await POST2(makeReq({ plan_id: "p1" }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when required fields missing", async () => {
    const res = await POST(makeReq({ plan_id: "p1" }));
    expect(res.status).toBe(400);
  });

  it("upserts subscriptions and returns subscription_ids", async () => {
    authClient.from.mockReturnValue(
      queryChain({ data: { id: "sub-uuid-1" }, error: null }),
    );

    const res = await POST(
      makeReq({
        plan_id: "p1",
        athlete_user_ids: ["u1", "u2"],
        started_at: "2026-03-01",
        next_due_date: "2026-04-01",
      }),
    );

    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.total).toBe(2);
    expect(body.success).toBe(2);
    expect(body.subscription_ids).toBeDefined();
    expect(body.subscription_ids.u1).toBe("sub-uuid-1");
    expect(body.subscription_ids.u2).toBe("sub-uuid-1");
  });

  it("handles partial failures", async () => {
    authClient.from
      .mockReturnValueOnce(queryChain({ data: { id: "sub-1" }, error: null }))
      .mockReturnValueOnce(
        queryChain({ data: null, error: { message: "conflict" } }),
      );

    const res = await POST(
      makeReq({
        plan_id: "p1",
        athlete_user_ids: ["u1", "u2"],
        started_at: "2026-03-01",
        next_due_date: "2026-04-01",
      }),
    );

    const body = await res.json();
    expect(body.success).toBe(1);
    expect(body.total).toBe(2);
    expect(body.results[1].ok).toBe(false);
  });
});
