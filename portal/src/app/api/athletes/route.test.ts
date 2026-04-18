/**
 * Tests for GET /api/athletes (L14-06 cursor-based pagination + L14-05
 * canonical envelope). The route uses `@supabase/ssr` directly, so we
 * mock that module to control the query result.
 */

import { describe, it, expect, vi, beforeEach } from "vitest";

const queryFn = vi.fn();
const orderFn = vi.fn(() => ({ order: orderFn, or: orFn, limit: limitFn }));
const orFn = vi.fn(() => ({ limit: limitFn }));
const limitFn = vi.fn();

const fromFn = vi.fn(() => ({
  select: () => ({
    eq: () => ({
      in: () => ({
        order: orderFn,
      }),
    }),
  }),
}));

const getUserFn = vi.fn();

vi.mock("@supabase/ssr", () => ({
  createServerClient: () => ({
    auth: { getUser: getUserFn },
    from: fromFn,
  }),
}));

vi.mock("next/headers", () => ({
  cookies: () => ({
    get: (name: string) =>
      name === "portal_group_id" ? { value: "group-1" } : undefined,
    getAll: () => [],
  }),
}));

const { GET } = await import("./route");

function makeReq(query = ""): import("next/server").NextRequest {
  const url = `http://localhost/api/athletes${query ? `?${query}` : ""}`;
  // NextRequest extends Request and exposes nextUrl with searchParams.
  // We construct via the server module's NextRequest to keep the
  // searchParams resolution identical to production.
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { NextRequest } = require("next/server");
  return new NextRequest(url);
}

beforeEach(() => {
  vi.clearAllMocks();
  getUserFn.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
  queryFn.mockReset();
  // wire `limit()` to `queryFn` so each test can reseed the result
  limitFn.mockImplementation(async (_n: number) => queryFn());
});

describe("GET /api/athletes — L14-05 envelope + L14-06 pagination", () => {
  it("returns paginated items wrapped in canonical { ok, data } envelope", async () => {
    queryFn.mockResolvedValueOnce({
      data: [
        { user_id: "u1", display_name: "Alice", profiles: null },
        { user_id: "u2", display_name: "Bob", profiles: null },
      ],
      error: null,
    });
    const res = await GET(makeReq("limit=10"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.ok).toBe(true);
    expect(body.data.items).toHaveLength(2);
    expect(body.data.has_more).toBe(false);
    expect(body.data.next_cursor).toBeNull();
  });

  it("trims over-fetched sentinel and emits next_cursor when has_more", async () => {
    queryFn.mockResolvedValueOnce({
      data: [
        { user_id: "u1", display_name: "Alice", profiles: null },
        { user_id: "u2", display_name: "Bob", profiles: null },
        { user_id: "u3", display_name: "Carol", profiles: null }, // sentinel
      ],
      error: null,
    });
    const res = await GET(makeReq("limit=2"));
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.data.items).toHaveLength(2);
    expect(body.data.has_more).toBe(true);
    expect(body.data.next_cursor).not.toBeNull();
  });

  it("returns 403 NO_GROUP_SESSION when cookie missing", async () => {
    vi.doMock("next/headers", () => ({
      cookies: () => ({
        get: () => undefined,
        getAll: () => [],
      }),
    }));
    vi.resetModules();
    const { GET: GetNoGroup } = await import("./route");
    const res = await GetNoGroup(makeReq());
    expect(res.status).toBe(403);
    const body = await res.json();
    expect(body.error.code).toBe("NO_GROUP_SESSION");
    vi.doUnmock("next/headers");
  });

  it("returns 400 VALIDATION_FAILED for malformed cursor", async () => {
    const res = await GET(makeReq("cursor=***bad***"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.ok).toBe(false);
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.details).toMatchObject({ code: "INVALID_CURSOR" });
  });

  it("returns 400 VALIDATION_FAILED for non-numeric limit", async () => {
    const res = await GET(makeReq("limit=abc"));
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.details).toMatchObject({ code: "INVALID_LIMIT" });
  });

  it("clamps limit > 100 silently to MAX_PAGE_LIMIT", async () => {
    queryFn.mockResolvedValueOnce({ data: [], error: null });
    const res = await GET(makeReq("limit=9999"));
    expect(res.status).toBe(200);
    // first call to limit() should be 101 (max 100 + over-fetch sentinel)
    expect(limitFn).toHaveBeenCalledWith(101);
  });

  it("uses default limit 50 when not provided", async () => {
    queryFn.mockResolvedValueOnce({ data: [], error: null });
    await GET(makeReq());
    expect(limitFn).toHaveBeenCalledWith(51);
  });
});
