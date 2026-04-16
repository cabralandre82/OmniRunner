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
    const json = await res.json();
    expect(res.status).toBe(401);
    expect(json.error.code).toBe("UNAUTHORIZED");
  });

  it("returns template list filtered by group", async () => {
    const fakeWeeks = [
      {
        id: "week-1",
        week_number: 1,
        starts_on: "2026-04-07",
        ends_on: "2026-04-13",
        label: "Base",
        template_name: "Semana Base",
        plan: { group_id: "group-uuid" },
        workouts: [
          { id: "w1", scheduled_date: "2026-04-07", workout_type: "run", workout_label: null, release_status: "draft", template: { name: "Rodagem" } },
          { id: "w2", scheduled_date: "2026-04-09", workout_type: "run", workout_label: "Tiro", release_status: "cancelled", template: null },
        ],
      },
      {
        id: "week-2",
        week_number: 2,
        starts_on: "2026-04-14",
        ends_on: "2026-04-20",
        label: "Velocidade",
        template_name: "Semana Velocidade",
        plan: { group_id: "other-group" },
        workouts: [],
      },
    ];

    mockFrom.mockReturnValue({
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      mockResolvedValue: vi.fn(),
    });

    const chain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockResolvedValue({ data: fakeWeeks, error: null }),
    };
    mockFrom.mockReturnValue(chain);

    const { GET } = await import("./route");
    const res = await GET(makeReq("GET"));
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data).toHaveLength(1);
    expect(json.data[0].template_name).toBe("Semana Base");
    expect(json.data[0].workout_count).toBe(1);
  });
});

describe("POST /api/training-plan/week-templates", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 422 when template_name is empty", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", { week_id: "some-uuid", template_name: "" }));
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("VALIDATION_ERROR");
  });

  it("returns 422 when week_id is not a uuid", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq("POST", { week_id: "not-a-uuid", template_name: "Semana" }));
    const json = await res.json();
    expect(res.status).toBe(422);
  });

  it("returns 403 when week belongs to a different group", async () => {
    const selectChain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({
        data: { id: "week-1", plan: { group_id: "other-group" } },
        error: null,
      }),
    };
    mockFrom.mockReturnValue(selectChain);

    const { POST } = await import("./route");
    const res = await POST(
      makeReq("POST", { week_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", template_name: "Minha Semana" }),
    );
    const json = await res.json();
    expect(res.status).toBe(403);
    expect(json.error.code).toBe("FORBIDDEN");
  });

  it("saves template flag successfully", async () => {
    let callCount = 0;
    mockFrom.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        return {
          select: vi.fn().mockReturnThis(),
          eq: vi.fn().mockReturnThis(),
          single: vi.fn().mockResolvedValue({
            data: { id: "week-1", plan: { group_id: "group-uuid" } },
            error: null,
          }),
        };
      }
      return {
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockResolvedValue({ error: null }),
      };
    });

    const { POST } = await import("./route");
    const res = await POST(
      makeReq("POST", { week_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", template_name: "Semana Intensidade" }),
    );
    const json = await res.json();
    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.template_name).toBe("Semana Intensidade");
  });
});

describe("DELETE /api/training-plan/week-templates", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 422 when weekId is missing", async () => {
    const { DELETE } = await import("./route");
    const res = await DELETE(makeReq("DELETE"));
    const json = await res.json();
    expect(res.status).toBe(422);
    expect(json.error.code).toBe("MISSING_WEEK_ID");
  });

  it("returns 403 when week belongs to a different group", async () => {
    const selectChain = {
      select: vi.fn().mockReturnThis(),
      eq: vi.fn().mockReturnThis(),
      single: vi.fn().mockResolvedValue({
        data: { id: "week-1", plan: { group_id: "other-group" } },
        error: null,
      }),
    };
    mockFrom.mockReturnValue(selectChain);

    const { DELETE } = await import("./route");
    const res = await DELETE(makeReq("DELETE", undefined, "http://localhost/api/training-plan/week-templates?weekId=week-1"));
    const json = await res.json();
    expect(res.status).toBe(403);
  });

  it("removes template flag successfully", async () => {
    let callCount = 0;
    mockFrom.mockImplementation(() => {
      callCount++;
      if (callCount === 1) {
        return {
          select: vi.fn().mockReturnThis(),
          eq: vi.fn().mockReturnThis(),
          single: vi.fn().mockResolvedValue({
            data: { id: "week-1", plan: { group_id: "group-uuid" } },
            error: null,
          }),
        };
      }
      return {
        update: vi.fn().mockReturnThis(),
        eq: vi.fn().mockResolvedValue({ error: null }),
      };
    });

    const { DELETE } = await import("./route");
    const res = await DELETE(makeReq("DELETE", undefined, "http://localhost/api/training-plan/week-templates?weekId=week-1"));
    const json = await res.json();
    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
  });
});
