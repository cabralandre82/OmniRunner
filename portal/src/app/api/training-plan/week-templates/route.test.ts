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

function makeReq(method: string, body?: unknown, url = "http://localhost/api/training-plan/week-templates") {
  return new NextRequest(url, {
    method,
    headers: { "x-request-id": "test-id", ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("GET /api/training-plan/week-templates", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { GET } = await import("./route");
    const res = await GET(makeReq("GET"));
    expect(res.status).toBe(401);
  });

  it("returns template list with workouts sorted by day_of_week", async () => {
    const fakeTemplates = [
      {
        id: "tpl-1",
        name: "Semana Base",
        description: null,
        created_at: "2026-04-16",
        updated_at: "2026-04-16",
        workouts: [
          { id: "w1", day_of_week: 2, workout_order: 1, workout_type: "run", workout_label: "Intervalado", description: null, coach_notes: null, blocks: [] },
          { id: "w2", day_of_week: 0, workout_order: 1, workout_type: "run", workout_label: "Rodagem", description: null, coach_notes: null, blocks: [] },
        ],
      },
    ];

    const chain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      order: vi.fn().mockResolvedValue({ data: fakeTemplates, error: null }),
    };
    mockFrom.mockReturnValue(chain);

    const { GET } = await import("./route");
    const res = await GET(makeReq("GET"));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data).toHaveLength(1);
    expect(json.data[0].name).toBe("Semana Base");
    expect(json.data[0].workout_count).toBe(2);
    // workouts sorted by day_of_week: Mon (0) before Wed (2)
    expect(json.data[0].workouts[0].day_of_week).toBe(0);
    expect(json.data[0].days_with_workouts).toEqual([0, 2]);
  });

  it("returns 500 on DB error", async () => {
    const chain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      order: vi.fn().mockResolvedValue({ data: null, error: { message: "DB down" } }),
    };
    mockFrom.mockReturnValue(chain);

    const { GET } = await import("./route");
    const res = await GET(makeReq("GET"));
    expect(res.status).toBe(500);
  });
});

describe("POST /api/training-plan/week-templates", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 422 when name is empty", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", { name: "" }));
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when name is missing", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", {}));
    expect(res.status).toBe(422);
  });

  it("creates a new template and returns 201", async () => {
    const chain = {
      insert: vi.fn().mockReturnThis(),
      select: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({
        data: { id: "new-tpl-id", name: "Semana Velocidade", description: null, created_at: "2026-04-16" },
        error: null,
      }),
    };
    mockFrom.mockReturnValue(chain);

    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", { name: "Semana Velocidade" }));
    const json = await res.json();

    expect(res.status).toBe(201);
    expect(json.ok).toBe(true);
    expect(json.data.id).toBe("new-tpl-id");
    expect(json.data.name).toBe("Semana Velocidade");
  });

  it("passes description when provided", async () => {
    const chain = {
      insert: vi.fn().mockReturnThis(),
      select: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({
        data: { id: "tpl-2", name: "Semana Base", description: "Foco em volume", created_at: "2026-04-16" },
        error: null,
      }),
    };
    mockFrom.mockReturnValue(chain);

    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", { name: "Semana Base", description: "Foco em volume" }));
    const json = await res.json();

    expect(res.status).toBe(201);
    expect(json.data.description).toBe("Foco em volume");
  });
});
