import { describe, expect, it, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import {
  canonicalize,
  IDEMPOTENCY_KEY_RE,
  IdempotencyKeyInvalidError,
  readIdempotencyKey,
  withIdempotency,
} from "./idempotency";

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(),
}));

vi.mock("@/lib/logger", () => ({
  logger: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
}));

import { createServiceClient } from "@/lib/supabase/service";

function mockRpcSequence(
  responses: Array<{ data?: unknown; error?: { message: string } | null }>,
) {
  const rpc = vi.fn();
  for (const r of responses) {
    rpc.mockResolvedValueOnce({
      data: r.data ?? null,
      error: r.error ?? null,
    });
  }
  (createServiceClient as unknown as ReturnType<typeof vi.fn>).mockReturnValue({
    rpc,
  });
  return rpc;
}

function makeReq(headers: Record<string, string> = {}): NextRequest {
  return new NextRequest("http://localhost/api/test", {
    method: "POST",
    headers,
  });
}

describe("canonicalize", () => {
  it("sorts top-level object keys", () => {
    expect(canonicalize({ b: 1, a: 2 })).toBe('{"a":2,"b":1}');
  });

  it("sorts nested object keys recursively", () => {
    expect(canonicalize({ z: { d: 1, b: 2 }, a: [3, { y: 1, x: 2 }] }))
      .toBe('{"a":[3,{"x":2,"y":1}],"z":{"b":2,"d":1}}');
  });

  it("preserves array order", () => {
    expect(canonicalize([3, 1, 2])).toBe("[3,1,2]");
  });

  it("skips undefined values to match JSON.stringify semantics", () => {
    expect(canonicalize({ a: undefined, b: 1 })).toBe('{"b":1}');
  });

  it("treats {a:1, b:2} === {b:2, a:1}", () => {
    expect(canonicalize({ a: 1, b: 2 })).toBe(canonicalize({ b: 2, a: 1 }));
  });

  it("handles primitives + null", () => {
    expect(canonicalize(null)).toBe("null");
    expect(canonicalize(42)).toBe("42");
    expect(canonicalize("x")).toBe('"x"');
    expect(canonicalize(true)).toBe("true");
  });
});

describe("IDEMPOTENCY_KEY_RE", () => {
  it("accepts UUID v4", () => {
    expect(IDEMPOTENCY_KEY_RE.test("550e8400-e29b-41d4-a716-446655440000"))
      .toBe(true);
  });

  it("accepts opaque [A-Za-z0-9_-]{8,128}", () => {
    expect(IDEMPOTENCY_KEY_RE.test("abc12345")).toBe(true);
    expect(IDEMPOTENCY_KEY_RE.test("ulid_01HXYZ_ABC")).toBe(true);
    expect(IDEMPOTENCY_KEY_RE.test("a".repeat(128))).toBe(true);
  });

  it("rejects too-short keys", () => {
    expect(IDEMPOTENCY_KEY_RE.test("short")).toBe(false);
    expect(IDEMPOTENCY_KEY_RE.test("a".repeat(7))).toBe(false);
  });

  it("rejects too-long keys", () => {
    expect(IDEMPOTENCY_KEY_RE.test("a".repeat(129))).toBe(false);
  });

  it("rejects whitespace / control chars / punctuation", () => {
    expect(IDEMPOTENCY_KEY_RE.test("hello world")).toBe(false);
    expect(IDEMPOTENCY_KEY_RE.test("hello\nworld")).toBe(false);
    expect(IDEMPOTENCY_KEY_RE.test("foo!bar123")).toBe(false);
  });
});

describe("readIdempotencyKey", () => {
  it("returns null when header absent", () => {
    expect(readIdempotencyKey(makeReq())).toBeNull();
  });

  it("returns null when header is empty / whitespace only", () => {
    expect(readIdempotencyKey(makeReq({ "x-idempotency-key": "" }))).toBeNull();
    expect(
      readIdempotencyKey(makeReq({ "x-idempotency-key": "   " })),
    ).toBeNull();
  });

  it("returns trimmed key when valid", () => {
    expect(
      readIdempotencyKey(
        makeReq({ "x-idempotency-key": " abc12345 " }),
      ),
    ).toBe("abc12345");
  });

  it("throws IdempotencyKeyInvalidError for invalid", () => {
    expect(() =>
      readIdempotencyKey(makeReq({ "x-idempotency-key": "bad!key" })),
    ).toThrow(IdempotencyKeyInvalidError);
  });
});

describe("withIdempotency wrapper", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls handler exactly once when no key sent and `required:false`", async () => {
    const handler = vi.fn().mockResolvedValue({ status: 200, body: { ok: true } });
    const res = await withIdempotency({
      request: makeReq(),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(handler).toHaveBeenCalledOnce();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("returns 400 IDEMPOTENCY_KEY_REQUIRED when missing and `required:true`", async () => {
    const handler = vi.fn();
    const res = await withIdempotency({
      request: makeReq(),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
      required: true,
    });
    expect(handler).not.toHaveBeenCalled();
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_KEY_REQUIRED");
  });

  it("returns 400 IDEMPOTENCY_KEY_INVALID for malformed header", async () => {
    const handler = vi.fn();
    const res = await withIdempotency({
      request: makeReq({ "x-idempotency-key": "bad!key" }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(handler).not.toHaveBeenCalled();
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_KEY_INVALID");
  });

  it("on action=execute calls handler then finalizes (cache miss)", async () => {
    const rpc = mockRpcSequence([
      { data: [{ action: "execute", replay_status: null, replay_body: null, stale_recovered: false }] },
      { data: true },
    ]);
    const handler = vi.fn().mockResolvedValue({
      status: 201,
      body: { id: "abc" },
    });
    const res = await withIdempotency({
      request: makeReq({ "x-idempotency-key": "abc12345" }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc.mock.calls[0][0]).toBe("fn_idem_begin");
    expect(rpc.mock.calls[1][0]).toBe("fn_idem_finalize");
    expect(handler).toHaveBeenCalledOnce();
    expect(res.status).toBe(201);
  });

  it("on action=replay returns cached response without calling handler", async () => {
    const rpc = mockRpcSequence([
      {
        data: [{
          action: "replay",
          replay_status: 200,
          replay_body: { cached: true },
          stale_recovered: false,
        }],
      },
    ]);
    const handler = vi.fn();
    const res = await withIdempotency({
      request: makeReq({ "x-idempotency-key": "abc12345" }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(handler).not.toHaveBeenCalled();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ cached: true });
    expect(res.headers.get("x-idempotent-replay")).toBe("true");
  });

  it("on action=mismatch returns 409 IDEMPOTENCY_KEY_CONFLICT", async () => {
    mockRpcSequence([
      {
        data: [{
          action: "mismatch",
          replay_status: null,
          replay_body: null,
          stale_recovered: false,
        }],
      },
    ]);
    const handler = vi.fn();
    const res = await withIdempotency({
      request: makeReq({ "x-idempotency-key": "abc12345" }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(handler).not.toHaveBeenCalled();
    expect(res.status).toBe(409);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_KEY_CONFLICT");
  });

  it("releases the claim if handler throws", async () => {
    const rpc = mockRpcSequence([
      { data: [{ action: "execute", replay_status: null, replay_body: null, stale_recovered: false }] },
      { data: true },
    ]);
    const handler = vi.fn().mockRejectedValue(new Error("boom"));
    await expect(
      withIdempotency({
        request: makeReq({ "x-idempotency-key": "abc12345" }),
        namespace: "test.foo",
        actorId: "00000000-0000-4000-8000-000000000001",
        requestBody: { x: 1 },
        handler,
      }),
    ).rejects.toThrow("boom");
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc.mock.calls[0][0]).toBe("fn_idem_begin");
    expect(rpc.mock.calls[1][0]).toBe("fn_idem_release");
  });

  it("returns 503 IDEMPOTENCY_BACKEND_ERROR when fn_idem_begin fails", async () => {
    mockRpcSequence([
      { error: { message: "connection refused" } },
    ]);
    const handler = vi.fn();
    const res = await withIdempotency({
      request: makeReq({ "x-idempotency-key": "abc12345" }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(handler).not.toHaveBeenCalled();
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error.code).toBe("IDEMPOTENCY_BACKEND_ERROR");
  });

  it("propagates x-request-id into the response", async () => {
    mockRpcSequence([
      { data: [{ action: "execute", replay_status: null, replay_body: null, stale_recovered: false }] },
      { data: true },
    ]);
    const handler = vi.fn().mockResolvedValue({ status: 200, body: { ok: true } });
    const res = await withIdempotency({
      request: makeReq({
        "x-idempotency-key": "abc12345",
        "x-request-id": "req-123",
      }),
      namespace: "test.foo",
      actorId: "00000000-0000-4000-8000-000000000001",
      requestBody: { x: 1 },
      handler,
    });
    expect(res.headers.get("x-request-id")).toBe("req-123");
  });
});
