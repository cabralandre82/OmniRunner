import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// ── Mocks ─────────────────────────────────────────────────────────────────────

const mockGetUser = vi.fn();
const mockRpc = vi.fn();

vi.mock("next/headers", () => ({
  cookies: () => ({
    getAll: () => [],
    get: (key: string) => (key === "portal_group_id" ? { value: "group-uuid" } : undefined),
  }),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  }),
}));

vi.mock("@/lib/audit", () => ({ auditLog: vi.fn() }));
vi.mock("@/lib/logger", () => ({ logger: { error: vi.fn() } }));

function makeReq(body: unknown, workoutId = "workout-uuid") {
  return new NextRequest(
    `http://localhost/api/training-plan/workouts/${workoutId}/distribute`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-request-id": "test-id" },
      body: JSON.stringify(body),
    },
  );
}

function makeParams(workoutId = "workout-uuid") {
  return { params: { workoutId } };
}

const ATHLETE_1 = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11";
const ATHLETE_2 = "b1ffcd00-0d1c-4fe9-8c7e-7cc0ce491b22";
const GROUP_ID  = "c2aade11-1e2d-4ef8-aa8f-8dd1df502c33";

const VALID_BODY = {
  target_athlete_ids: [ATHLETE_1, ATHLETE_2],
  target_date: "2026-04-20",
  group_id: GROUP_ID,
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("POST /api/training-plan/workouts/[workoutId]/distribute", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    const json = await res.json();
    expect(res.status).toBe(401);
    expect(json.error.code).toBe("UNAUTHORIZED");
  });

  it("returns 422 when target_athlete_ids is empty", async () => {
    const { POST } = await import("./route");
    const res = await POST(
      makeReq({ ...VALID_BODY, target_athlete_ids: [] }),
      makeParams(),
    );
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when target_date format is invalid", async () => {
    const { POST } = await import("./route");
    const res = await POST(
      makeReq({ ...VALID_BODY, target_date: "20-04-2026" }),
      makeParams(),
    );
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when group_id is not a uuid", async () => {
    const { POST } = await import("./route");
    const res = await POST(
      makeReq({ ...VALID_BODY, group_id: "not-a-uuid" }),
      makeParams(),
    );
    const json = await res.json();
    expect(res.status).toBe(422);
  });

  it("returns per-athlete results on success", async () => {
    mockRpc.mockResolvedValue({ data: "new-release-id", error: null });

    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    const json = await res.json();
    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.success_count).toBe(2);
    expect(json.data.results).toHaveLength(2);
    expect(json.data.results[0].success).toBe(true);
    expect(json.data.results[0].new_release_id).toBe("new-release-id");
  });

  it("reports partial success when one athlete fails", async () => {
    let call = 0;
    mockRpc.mockImplementation(() => {
      call++;
      if (call === 1) return Promise.resolve({ data: "new-id", error: null });
      return Promise.resolve({ data: null, error: { message: "athlete not found" } });
    });

    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.data.success_count).toBe(1);
    expect(json.data.results[0].success).toBe(true);
    expect(json.data.results[1].success).toBe(false);
    expect(json.data.results[1].error).toBe("athlete not found");
  });

  it("calls fn_distribute_workout with correct parameters", async () => {
    mockRpc.mockResolvedValue({ data: "some-id", error: null });

    const { POST } = await import("./route");
    await POST(makeReq({ ...VALID_BODY, target_athlete_ids: [ATHLETE_1] }), makeParams("src-workout-id"));

    expect(mockRpc).toHaveBeenCalledWith("fn_distribute_workout", {
      p_source_id:         "src-workout-id",
      p_target_athlete_id: ATHLETE_1,
      p_target_date:       "2026-04-20",
      p_group_id:          GROUP_ID,
    });
  });
});
