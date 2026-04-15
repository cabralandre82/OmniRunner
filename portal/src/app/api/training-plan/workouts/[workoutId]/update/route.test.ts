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

vi.mock("@/lib/audit", () => ({ auditLog: vi.fn() }));
vi.mock("@/lib/logger", () => ({ logger: { error: vi.fn() } }));

function makeReq(body: unknown, workoutId = "workout-uuid") {
  return new NextRequest(
    `http://localhost/api/training-plan/workouts/${workoutId}/update`,
    {
      method: "PATCH",
      headers: { "content-type": "application/json", "x-request-id": "test-id" },
      body: JSON.stringify(body),
    }
  );
}

function makeParams(workoutId = "workout-uuid") {
  return { params: { workoutId } };
}

function mockSelectChain(data: unknown, error: unknown = null) {
  const chain = {
    select: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    single: vi.fn().mockResolvedValue({ data, error }),
  };
  return chain;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("PATCH /api/training-plan/workouts/[workoutId]/update", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { PATCH } = await import("./route");
    const res = await PATCH(makeReq({ workout_label: "New" }), makeParams());
    const json = await res.json();
    expect(res.status).toBe(401);
    expect(json.error.code).toBe("UNAUTHORIZED");
  });

  it("returns 422 on validation error (label too long)", async () => {
    const { PATCH } = await import("./route");
    const res = await PATCH(
      makeReq({ workout_label: "a".repeat(121) }),
      makeParams()
    );
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("updates label and notes", async () => {
    const updateChain = {
      update: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      select: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({
        data: { id: "workout-uuid", workout_label: "Updated", coach_notes: "Note", content_snapshot: null, content_version: 1 },
        error: null,
      }),
    };
    mockFrom.mockReturnValue(updateChain);

    const { PATCH } = await import("./route");
    const res = await PATCH(
      makeReq({ workout_label: "Updated", coach_notes: "Note" }),
      makeParams()
    );
    const json = await res.json();
    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.workout_label).toBe("Updated");
  });

  it("updates blocks and merges into content_snapshot", async () => {
    const existingSnapshot = {
      template_name: "Original",
      blocks: [{ order_index: 0, block_type: "warmup", duration_seconds: 300 }],
    };

    let callCount = 0;
    mockFrom.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        // first call: fetch current snapshot
        return mockSelectChain({ content_snapshot: existingSnapshot });
      }
      // second call: update
      return {
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockReturnThis(),
        select: vi.fn().mockReturnThis(),
        single: vi.fn().mockResolvedValue({
          data: {
            id: "workout-uuid",
            workout_label: null,
            coach_notes: null,
            content_snapshot: { ...existingSnapshot, blocks: [{ order_index: 0, block_type: "interval", distance_meters: 1000 }] },
            content_version: 2,
          },
          error: null,
        }),
      };
    });

    const { PATCH } = await import("./route");
    const res = await PATCH(
      makeReq({
        blocks: [{ order_index: 0, block_type: "interval", distance_meters: 1000, duration_seconds: null,
          target_pace_min_sec_per_km: 255, target_pace_max_sec_per_km: 275 }],
      }),
      makeParams()
    );
    const json = await res.json();
    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.content_version).toBe(2);
  });

  it("returns 422 when blocks exceed 30 items", async () => {
    const tooMany = Array.from({ length: 31 }, (_, i) => ({
      order_index: i,
      block_type: "interval",
      distance_meters: 500,
    }));
    const { PATCH } = await import("./route");
    const res = await PATCH(makeReq({ blocks: tooMany }), makeParams());
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });
});
