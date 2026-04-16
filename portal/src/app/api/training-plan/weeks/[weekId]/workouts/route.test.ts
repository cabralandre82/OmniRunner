import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

// ── Mocks ─────────────────────────────────────────────────────────────────────

const mockGetUser = vi.fn();
const mockRpc = vi.fn();

vi.mock("next/headers", () => ({
  cookies: () => ({ getAll: () => [], get: () => undefined }),
}));

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: { getUser: mockGetUser },
    rpc: mockRpc,
  }),
}));

vi.mock("@/lib/logger", () => ({ logger: { error: vi.fn() } }));

const ATHLETE_ID   = "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11";
const TEMPLATE_ID  = "b1ffcd00-0d1c-4fe9-8c7e-7cc0ce491b22";

function makeReq(body: unknown, weekId = "week-uuid-0001-0002-0003-000400050006") {
  return new NextRequest(
    `http://localhost/api/training-plan/weeks/${weekId}/workouts`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-request-id": "test-id" },
      body: JSON.stringify(body),
    },
  );
}

function makeParams(weekId = "week-uuid-0001-0002-0003-000400050006") {
  return { params: { weekId } };
}

const DESCRIPTIVE_BODY = {
  athlete_id:     ATHLETE_ID,
  scheduled_date: "2026-04-21",
  workout_type:   "interval" as const,
  workout_label:  "Intervalado 4×1km",
  description:    "4 tiros de 1km em pace 4:30",
  coach_notes:    "Aquecimento obrigatório",
  workout_order:  1,
  blocks: [
    { order_index: 0, block_type: "warmup",   duration_seconds: 600, distance_meters: null,
      target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
      target_hr_zone: 2, rpe_target: 3, repeat_count: null, notes: null },
    { order_index: 1, block_type: "interval", distance_meters: 1000, duration_seconds: null,
      target_pace_min_sec_per_km: 255, target_pace_max_sec_per_km: 275,
      target_hr_zone: 4, rpe_target: 8, repeat_count: null, notes: null },
    { order_index: 2, block_type: "cooldown", duration_seconds: 600, distance_meters: null,
      target_pace_min_sec_per_km: null, target_pace_max_sec_per_km: null,
      target_hr_zone: 2, rpe_target: 3, repeat_count: null, notes: null },
  ],
};

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("POST /api/training-plan/weeks/[weekId]/workouts", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { POST } = await import("./route");
    const res = await POST(makeReq(DESCRIPTIVE_BODY), makeParams());
    expect(res.status).toBe(401);
  });

  it("returns 422 when athlete_id is missing", async () => {
    const { POST } = await import("./route");
    const body = { ...DESCRIPTIVE_BODY, athlete_id: undefined };
    const res = await POST(makeReq(body), makeParams());
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when scheduled_date format is invalid", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq({ ...DESCRIPTIVE_BODY, scheduled_date: "21/04/2026" }), makeParams());
    const json = await res.json();
    expect(res.status).toBe(422);
  });

  it("returns 422 when workout_label is missing for descriptive workout", async () => {
    const { POST } = await import("./route");
    const res = await POST(
      makeReq({ ...DESCRIPTIVE_BODY, workout_label: "   " }),
      makeParams(),
    );
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("calls fn_create_descriptive_workout with blocks as array (not string)", async () => {
    mockRpc.mockResolvedValue({ data: "new-release-id", error: null });

    const { POST } = await import("./route");
    await POST(makeReq(DESCRIPTIVE_BODY), makeParams());

    expect(mockRpc).toHaveBeenCalledWith(
      "fn_create_descriptive_workout",
      expect.objectContaining({
        p_blocks: expect.arrayContaining([
          expect.objectContaining({ block_type: "warmup" }),
        ]),
      }),
    );

    // Critical regression: p_blocks must NOT be a string (would cause
    // "cannot get array length of a scalar" in Postgres jsonb_array_length)
    const callArgs = mockRpc.mock.calls[0][1];
    expect(typeof callArgs.p_blocks).not.toBe("string");
    expect(Array.isArray(callArgs.p_blocks)).toBe(true);
  });

  it("sends empty array when no blocks provided", async () => {
    mockRpc.mockResolvedValue({ data: "new-release-id", error: null });

    const { POST } = await import("./route");
    const body = { ...DESCRIPTIVE_BODY, blocks: undefined };
    await POST(makeReq(body), makeParams());

    const callArgs = mockRpc.mock.calls[0][1];
    expect(callArgs.p_blocks).toEqual([]);
    expect(Array.isArray(callArgs.p_blocks)).toBe(true);
  });

  it("creates descriptive workout and returns 201", async () => {
    mockRpc.mockResolvedValue({ data: "new-release-id", error: null });

    const { POST } = await import("./route");
    const res = await POST(makeReq(DESCRIPTIVE_BODY), makeParams());
    const json = await res.json();

    expect(res.status).toBe(201);
    expect(json.ok).toBe(true);
    expect(json.data.id).toBe("new-release-id");
  });

  it("calls fn_create_plan_workout when template_id is provided", async () => {
    mockRpc.mockResolvedValue({ data: "template-release-id", error: null });

    const { POST } = await import("./route");
    const res = await POST(
      makeReq({ ...DESCRIPTIVE_BODY, template_id: TEMPLATE_ID, blocks: undefined }),
      makeParams(),
    );
    const json = await res.json();

    expect(res.status).toBe(201);
    expect(mockRpc).toHaveBeenCalledWith("fn_create_plan_workout", expect.any(Object));
  });

  it("maps forbidden DB error to 403", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "forbidden" } });

    const { POST } = await import("./route");
    const res = await POST(makeReq(DESCRIPTIVE_BODY), makeParams());
    const json = await res.json();

    expect(res.status).toBe(403);
    expect(json.error.code).toBe("FORBIDDEN");
  });

  it("maps date_outside_week DB error to 422", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "date_outside_week" } });

    const { POST } = await import("./route");
    const res = await POST(makeReq(DESCRIPTIVE_BODY), makeParams());
    const json = await res.json();

    expect(res.status).toBe(422);
    expect(json.error.code).toBe("DATE_OUTSIDE_WEEK");
  });

  it("reassigns order_index sequentially before sending blocks", async () => {
    mockRpc.mockResolvedValue({ data: "new-release-id", error: null });

    const { POST } = await import("./route");
    // Send blocks with scrambled order_index values
    const scrambled = DESCRIPTIVE_BODY.blocks.map((b, i) => ({ ...b, order_index: i * 10 }));
    await POST(makeReq({ ...DESCRIPTIVE_BODY, blocks: scrambled }), makeParams());

    const sent: { order_index: number }[] = mockRpc.mock.calls[0][1].p_blocks;
    expect(sent.map((b) => b.order_index)).toEqual([0, 1, 2]);
  });
});
