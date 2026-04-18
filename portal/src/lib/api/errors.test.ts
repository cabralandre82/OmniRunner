/**
 * Tests for L14-05 — canonical API error envelope.
 */

import { describe, it, expect } from "vitest";
import { NextRequest } from "next/server";
import {
  apiError,
  apiOk,
  apiUnauthorized,
  apiForbidden,
  apiNotFound,
  apiValidationFailed,
  apiRateLimited,
  apiInternalError,
  apiServiceUnavailable,
  apiNoGroupSession,
  resolveRequestId,
  COMMON_ERROR_CODES,
  type ApiErrorBody,
} from "./errors";

function makeRequest(headers: Record<string, string> = {}): NextRequest {
  const h = new Headers();
  for (const [k, v] of Object.entries(headers)) h.set(k, v);
  return new NextRequest("https://example.com/api/x", { headers: h });
}

async function bodyOf(res: Response): Promise<ApiErrorBody> {
  return (await res.json()) as ApiErrorBody;
}

describe("resolveRequestId", () => {
  it("returns null for null/undefined source", () => {
    expect(resolveRequestId(null)).toBeNull();
    expect(resolveRequestId(undefined)).toBeNull();
  });

  it("returns the string itself when given a string", () => {
    expect(resolveRequestId("abc-123")).toBe("abc-123");
  });

  it("returns null when string is empty", () => {
    expect(resolveRequestId("")).toBeNull();
  });

  it("reads x-request-id from a NextRequest", () => {
    const req = makeRequest({ "x-request-id": "req-42" });
    expect(resolveRequestId(req)).toBe("req-42");
  });

  it("returns null when NextRequest has no x-request-id", () => {
    const req = makeRequest();
    expect(resolveRequestId(req)).toBeNull();
  });
});

describe("apiError — envelope shape", () => {
  it("always returns ok=false + error.code + error.message + error.request_id", async () => {
    const req = makeRequest({ "x-request-id": "rid-1" });
    const res = apiError(req, "MY_CODE", "Boom", 422);
    expect(res.status).toBe(422);
    const body = await bodyOf(res);
    expect(body).toEqual({
      ok: false,
      error: {
        code: "MY_CODE",
        message: "Boom",
        request_id: "rid-1",
      },
    });
  });

  it("sets request_id to null when no source has one", async () => {
    const res = apiError(null, "X", "y", 400);
    const body = await bodyOf(res);
    expect(body.error.request_id).toBeNull();
  });

  it("honours an explicit requestId override (even null)", async () => {
    const req = makeRequest({ "x-request-id": "from-header" });
    const overridden = apiError(req, "X", "y", 400, { requestId: "explicit" });
    expect((await bodyOf(overridden)).error.request_id).toBe("explicit");

    const cleared = apiError(req, "X", "y", 400, { requestId: null });
    expect((await bodyOf(cleared)).error.request_id).toBeNull();
  });

  it("includes details when provided", async () => {
    const res = apiError(null, "VALIDATION_FAILED", "bad", 400, {
      details: { field: "email" },
    });
    const body = await bodyOf(res);
    expect(body.error.details).toEqual({ field: "email" });
  });

  it("omits details when not provided (no undefined leak)", async () => {
    const res = apiError(null, "X", "y", 400);
    const body = await bodyOf(res);
    expect(Object.prototype.hasOwnProperty.call(body.error, "details")).toBe(
      false,
    );
  });

  it("sets extra response headers when provided", () => {
    const res = apiError(null, "RATE_LIMITED", "slow down", 429, {
      headers: { "Retry-After": "30" },
    });
    expect(res.headers.get("Retry-After")).toBe("30");
  });

  it("accepts a string as request id source", async () => {
    const res = apiError("trace-7", "X", "y", 500);
    expect((await bodyOf(res)).error.request_id).toBe("trace-7");
  });
});

describe("apiOk", () => {
  it("wraps payload as { ok: true, data }", async () => {
    const res = apiOk({ items: [1, 2, 3] });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ ok: true, data: { items: [1, 2, 3] } });
  });

  it("forwards init.status", () => {
    const res = apiOk({ created: true }, { status: 201 });
    expect(res.status).toBe(201);
  });
});

describe("convenience helpers", () => {
  it("apiUnauthorized → 401 + UNAUTHORIZED", async () => {
    const res = apiUnauthorized(null);
    expect(res.status).toBe(401);
    expect((await bodyOf(res)).error.code).toBe("UNAUTHORIZED");
  });

  it("apiForbidden → 403 + FORBIDDEN", async () => {
    const res = apiForbidden(null);
    expect(res.status).toBe(403);
    expect((await bodyOf(res)).error.code).toBe("FORBIDDEN");
  });

  it("apiNotFound → 404 + NOT_FOUND", async () => {
    const res = apiNotFound(null);
    expect(res.status).toBe(404);
    expect((await bodyOf(res)).error.code).toBe("NOT_FOUND");
  });

  it("apiValidationFailed → 400 + VALIDATION_FAILED + details", async () => {
    const res = apiValidationFailed(null, "Bad input", { field: "x" });
    expect(res.status).toBe(400);
    const body = await bodyOf(res);
    expect(body.error.code).toBe("VALIDATION_FAILED");
    expect(body.error.details).toEqual({ field: "x" });
  });

  it("apiRateLimited → 429 + Retry-After header when given", async () => {
    const res = apiRateLimited(null, 45);
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("45");
    expect((await bodyOf(res)).error.code).toBe("RATE_LIMITED");
  });

  it("apiRateLimited rounds fractional retry-after up", () => {
    const res = apiRateLimited(null, 0.4);
    expect(res.headers.get("Retry-After")).toBe("1");
  });

  it("apiRateLimited omits Retry-After when not provided", () => {
    const res = apiRateLimited(null);
    expect(res.headers.has("Retry-After")).toBe(false);
  });

  it("apiInternalError → 500 + INTERNAL_ERROR", async () => {
    const res = apiInternalError(null);
    expect(res.status).toBe(500);
    expect((await bodyOf(res)).error.code).toBe("INTERNAL_ERROR");
  });

  it("apiServiceUnavailable → 503 + SERVICE_UNAVAILABLE + Retry-After", async () => {
    const res = apiServiceUnavailable(null, "down", 60);
    expect(res.status).toBe(503);
    expect(res.headers.get("Retry-After")).toBe("60");
    expect((await bodyOf(res)).error.code).toBe("SERVICE_UNAVAILABLE");
  });

  it("apiNoGroupSession → 403 + NO_GROUP_SESSION", async () => {
    const res = apiNoGroupSession(null);
    expect(res.status).toBe(403);
    expect((await bodyOf(res)).error.code).toBe("NO_GROUP_SESSION");
  });
});

describe("COMMON_ERROR_CODES registry", () => {
  it("contains the must-have cross-cutting codes", () => {
    expect(COMMON_ERROR_CODES).toContain("UNAUTHORIZED");
    expect(COMMON_ERROR_CODES).toContain("FORBIDDEN");
    expect(COMMON_ERROR_CODES).toContain("RATE_LIMITED");
    expect(COMMON_ERROR_CODES).toContain("VALIDATION_FAILED");
    expect(COMMON_ERROR_CODES).toContain("INTERNAL_ERROR");
    expect(COMMON_ERROR_CODES).toContain("NO_GROUP_SESSION");
  });

  it("uses SCREAMING_SNAKE codes only", () => {
    for (const code of COMMON_ERROR_CODES) {
      expect(code).toMatch(/^[A-Z][A-Z0-9_]*$/);
    }
  });
});
