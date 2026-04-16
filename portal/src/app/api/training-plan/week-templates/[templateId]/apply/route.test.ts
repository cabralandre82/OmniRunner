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

vi.mock("@/lib/audit",  () => ({ auditLog: vi.fn() }));
vi.mock("@/lib/logger", () => ({ logger: { error: vi.fn() } }));

const VALID_BODY = {
  plan_week_id:    "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
  athlete_id:      "b1ffcd00-0d1c-4fe9-8c7e-7cc0ce491b22",
  week_start_date: "2026-04-21",
  auto_release:    false,
  overrides:       [],
};

function makeReq(body: unknown, templateId = "c2aade11-1e2d-4ef8-aa8f-8dd1df502c33") {
  return new NextRequest(
    `http://localhost/api/training-plan/week-templates/${templateId}/apply`,
    {
      method: "POST",
      headers: { "content-type": "application/json", "x-request-id": "test-id" },
      body: JSON.stringify(body),
    },
  );
}

function makeParams(templateId = "c2aade11-1e2d-4ef8-aa8f-8dd1df502c33") {
  return { params: { templateId } };
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe("POST /api/training-plan/week-templates/[templateId]/apply", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockGetUser.mockResolvedValue({ data: { user: { id: "coach-1" } }, error: null });
  });

  it("returns 401 when not authenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: new Error("no session") });
    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    expect(res.status).toBe(401);
  });

  it("returns 422 when plan_week_id is not a UUID", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq({ ...VALID_BODY, plan_week_id: "not-a-uuid" }), makeParams());
    expect(res.status).toBe(422);
  });

  it("returns 422 when week_start_date format is invalid", async () => {
    const { POST } = await import("./route");
    const res = await POST(makeReq({ ...VALID_BODY, week_start_date: "21/04/2026" }), makeParams());
    expect(res.status).toBe(422);
  });

  it("calls fn_apply_week_template with correct parameters", async () => {
    mockRpc.mockResolvedValue({ data: 3, error: null });
    const { POST } = await import("./route");
    await POST(makeReq(VALID_BODY), makeParams());

    expect(mockRpc).toHaveBeenCalledWith("fn_apply_week_template", expect.objectContaining({
      p_plan_week_id:    VALID_BODY.plan_week_id,
      p_athlete_id:      VALID_BODY.athlete_id,
      p_week_start_date: "2026-04-21",
      p_auto_release:    false,
    }));
  });

  it("returns workouts_created count on success", async () => {
    mockRpc.mockResolvedValue({ data: 4, error: null });
    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.ok).toBe(true);
    expect(json.data.workouts_created).toBe(4);
  });

  it("maps template_not_found DB error to 404", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "template_not_found" } });
    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    expect(res.status).toBe(404);
    expect((await res.json()).error.code).toBe("TEMPLATE_NOT_FOUND");
  });

  it("maps forbidden DB error to 403", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "forbidden" } });
    const { POST } = await import("./route");
    const res = await POST(makeReq(VALID_BODY), makeParams());
    expect(res.status).toBe(403);
    expect((await res.json()).error.code).toBe("FORBIDDEN");
  });

  it("passes overrides to the RPC", async () => {
    mockRpc.mockResolvedValue({ data: 2, error: null });
    const overrides = [{ template_workout_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11", remove: true }];
    const { POST } = await import("./route");
    await POST(makeReq({ ...VALID_BODY, overrides }), makeParams());

    const callArgs = mockRpc.mock.calls[0][1];
    expect(callArgs.p_overrides).toHaveLength(1);
    expect(callArgs.p_overrides[0].remove).toBe(true);
  });
});
