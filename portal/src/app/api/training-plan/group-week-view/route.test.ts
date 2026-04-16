import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// ── Mocks ─────────────────────────────────────────────────────────────────────

const mockGetUser = vi.fn();
const mockFrom = vi.fn();

vi.mock("next/headers", () => ({
  cookies: () => ({
    getAll: () => [],
    get: (key: string) => (key === "portal_group_id" ? { value: "group-uuid" } : undefined),
  }),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  }),
}));

vi.mock("@/lib/logger", () => ({ logger: { error: vi.fn() } }));

function makeReq(weekStart?: string) {
  const url = weekStart
    ? `http://localhost/api/training-plan/group-week-view?weekStart=${weekStart}`
    : "http://localhost/api/training-plan/group-week-view";
  return new NextRequest(url, { headers: { "x-request-id": "test-id" } });
}

/** Creates a Supabase-like query builder chain that resolves with `result`. */
function makeChain(result: unknown) {
  const chain: Record<string, unknown> = {};
  const self = () => chain;
  chain.select = vi.fn().mockReturnValue(chain);
  chain.eq     = vi.fn().mockReturnValue(chain);
  chain.in     = vi.fn().mockReturnValue(chain);
  chain.lte    = vi.fn().mockReturnValue(chain);
  chain.gte    = vi.fn().mockReturnValue(chain);
  chain.not    = vi.fn().mockReturnValue(chain);
  chain.order  = vi.fn().mockResolvedValue(result);
  chain.single = vi.fn().mockResolvedValue(result);
  // Make the chain itself awaitable (thenable):
  chain.then = (resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) =>
    Promise.resolve(result).then(resolve, reject);
  return chain;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("GET /api/training-plan/group-week-view", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { GET } = await import("./route");
    const res = await GET(makeReq("2026-04-14"));
    const json = await res.json();
    expect(res.status).toBe(401);
    expect(json.error.code).toBe("UNAUTHORIZED");
  });

  it("returns empty athletes array when group has no athletes", async () => {
    mockFrom.mockReturnValue(makeChain({ data: [], error: null }));

    const { GET } = await import("./route");
    const res = await GET(makeReq("2026-04-14"));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.athletes).toHaveLength(0);
    expect(json.data.week_start).toBe("2026-04-14");
  });

  it("uses the provided weekStart date and computes week_end", async () => {
    mockFrom.mockReturnValue(makeChain({ data: [], error: null }));

    const { GET } = await import("./route");
    const res = await GET(makeReq("2026-04-21"));
    const json = await res.json();

    expect(json.data.week_start).toBe("2026-04-21");
    expect(json.data.week_end).toBe("2026-04-27");
  });

  it("assembles athlete list with workouts on success", async () => {
    const calls = [
      { data: [{ user_id: "athlete-1" }], error: null },                                          // coaching_members
      { data: [{ id: "athlete-1", display_name: "João", avatar_url: null }], error: null },       // profiles
      { data: [{ id: "plan-1", athlete_user_id: "athlete-1" }], error: null },                    // training_plans
      { data: [{ id: "week-1", plan_id: "plan-1" }], error: null },                               // training_plan_weeks
      { data: [{ id: "rel-1", athlete_user_id: "athlete-1", scheduled_date: "2026-04-14",        // plan_workout_releases
                  workout_type: "run", workout_label: "Rodagem", release_status: "released",
                  template: { name: "Rodagem Leve" } }], error: null },
    ];
    let idx = 0;
    mockFrom.mockImplementation(() => makeChain(calls[idx++] ?? { data: [], error: null }));

    const { GET } = await import("./route");
    const res = await GET(makeReq("2026-04-14"));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.athletes).toHaveLength(1);
    expect(json.data.athletes[0].display_name).toBe("João");
    expect(json.data.athletes[0].workouts).toHaveLength(1);
  });

  it("returns 500 on members query error", async () => {
    mockFrom.mockReturnValue(makeChain({ data: null, error: { message: "DB down" } }));

    const { GET } = await import("./route");
    const res = await GET(makeReq("2026-04-14"));
    const json = await res.json();

    expect(res.status).toBe(500);
    expect(json.error.code).toBe("DB_ERROR");
  });
});
