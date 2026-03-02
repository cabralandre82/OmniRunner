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

const { POST } = await import("./route");

function req(body: Record<string, unknown>) {
  return new Request("http://localhost/api/platform/liga", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  }) as unknown as import("next/server").NextRequest;
}

describe("POST /api/platform/liga", () => {
  beforeEach(() => vi.clearAllMocks());

  it("returns 401 when not authenticated", async () => {
    authClient.auth.getUser.mockResolvedValueOnce({ data: { user: null } });
    const res = await POST(req({ action: "create_season" }));
    expect(res.status).toBe(401);
  });

  it("returns 403 when not platform admin", async () => {
    authClient.from.mockReturnValueOnce(
      queryChain({ data: { platform_role: "user" } }),
    );
    const res = await POST(req({ action: "create_season" }));
    expect(res.status).toBe(403);
  });

  it("returns 400 when action is missing", async () => {
    const res = await POST(req({}));
    expect(res.status).toBe(400);
  });

  it("creates season successfully", async () => {
    const chain = queryChain({
      data: { id: "s1", name: "Season 1", status: "upcoming" },
    });
    adminClient.from.mockReturnValueOnce(chain);

    const res = await POST(
      req({
        action: "create_season",
        name: "Season 1",
        start_at_ms: 1700000000000,
        end_at_ms: 1702592000000,
      }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("created");
  });

  it("returns 400 when season fields are missing", async () => {
    const res = await POST(req({ action: "create_season", name: "S1" }));
    expect(res.status).toBe(400);
  });

  it("activates season and enrolls approved groups", async () => {
    // deactivate active
    adminClient.from.mockReturnValueOnce(queryChain());
    // activate target
    adminClient.from.mockReturnValueOnce(queryChain());
    // fetch approved groups
    adminClient.from.mockReturnValueOnce(
      queryChain({ data: [{ id: "g1" }, { id: "g2" }] }),
    );
    // upsert enrollments
    adminClient.from.mockReturnValueOnce(queryChain());
    adminClient.from.mockReturnValueOnce(queryChain());

    const res = await POST(
      req({ action: "activate_season", season_id: "s1" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("activated");
    expect(json.enrolled).toBe(2);
  });

  it("returns 400 when season_id is missing for activate", async () => {
    const res = await POST(req({ action: "activate_season" }));
    expect(res.status).toBe(400);
  });

  it("completes season successfully", async () => {
    const res = await POST(
      req({ action: "complete_season", season_id: "s1" }),
    );
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.status).toBe("completed");
  });

  it("returns 400 for invalid action", async () => {
    const res = await POST(req({ action: "delete_season" }));
    expect(res.status).toBe(400);
  });
});
