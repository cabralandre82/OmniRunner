/**
 * Tests for L14-02 — path-versioning helpers.
 */

import { describe, it, expect } from "vitest";
import { NextResponse } from "next/server";
import {
  CURRENT_API_VERSION,
  HEADER_API_VERSION,
  HEADER_DEPRECATION,
  HEADER_SUNSET,
  HEADER_LINK,
  DEFAULT_FINANCIAL_SUNSET,
  LEGACY_FINANCIAL_PATHS,
  toHttpDate,
  applyApiVersion,
  applyDeprecation,
  v1SuccessorFor,
  wrapV1Handler,
} from "./versioning";

describe("CURRENT_API_VERSION", () => {
  it("is set to 1 — bump intentionally and update consumers", () => {
    expect(CURRENT_API_VERSION).toBe(1);
  });
});

describe("toHttpDate", () => {
  it("formats a Date as RFC 7231 IMF-fixdate string ending in GMT", () => {
    const d = new Date(Date.UTC(2027, 0, 1, 0, 0, 0));
    const formatted = toHttpDate(d);
    expect(formatted).toMatch(/GMT$/);
    // Sanity check: the year and Jan 01 must appear in the formatted string.
    expect(formatted).toContain("2027");
    expect(formatted).toContain("Jan");
  });
});

describe("applyApiVersion", () => {
  it("stamps X-Api-Version with CURRENT_API_VERSION by default", () => {
    const res = NextResponse.json({ ok: true });
    applyApiVersion(res);
    expect(res.headers.get(HEADER_API_VERSION)).toBe(
      String(CURRENT_API_VERSION),
    );
  });

  it("stamps an explicit version when provided", () => {
    const res = NextResponse.json({ ok: true });
    applyApiVersion(res, 2);
    expect(res.headers.get(HEADER_API_VERSION)).toBe("2");
  });

  it("is idempotent — calling twice keeps the same value", () => {
    const res = NextResponse.json({ ok: true });
    applyApiVersion(res, 1);
    applyApiVersion(res, 1);
    expect(res.headers.get(HEADER_API_VERSION)).toBe("1");
  });

  it("returns the same response object (chainable)", () => {
    const res = NextResponse.json({ ok: true });
    expect(applyApiVersion(res)).toBe(res);
  });
});

describe("applyDeprecation", () => {
  it("emits Deprecation: true and Sunset by default", () => {
    const res = NextResponse.json({ ok: true });
    applyDeprecation(res);
    expect(res.headers.get(HEADER_DEPRECATION)).toBe("true");
    expect(res.headers.get(HEADER_SUNSET)).toBe(
      toHttpDate(DEFAULT_FINANCIAL_SUNSET),
    );
  });

  it("respects an explicit sunset date", () => {
    const res = NextResponse.json({ ok: true });
    const custom = new Date(Date.UTC(2030, 5, 15));
    applyDeprecation(res, { sunset: custom });
    expect(res.headers.get(HEADER_SUNSET)).toBe(toHttpDate(custom));
  });

  it("can suppress the Deprecation header (sunset-only)", () => {
    const res = NextResponse.json({ ok: true });
    applyDeprecation(res, { emitDeprecation: false });
    expect(res.headers.get(HEADER_DEPRECATION)).toBeNull();
    expect(res.headers.get(HEADER_SUNSET)).not.toBeNull();
  });

  it("emits Link with rel=successor-version when given a successor", () => {
    const res = NextResponse.json({ ok: true });
    applyDeprecation(res, { successor: "/api/v1/swap" });
    expect(res.headers.get(HEADER_LINK)).toBe(
      `</api/v1/swap>; rel="successor-version"`,
    );
  });

  it("appends the successor link rather than overwriting an existing Link", () => {
    const res = NextResponse.json({ ok: true });
    res.headers.set(HEADER_LINK, `</css/app.css>; rel="preload"`);
    applyDeprecation(res, { successor: "/api/v1/swap" });
    const link = res.headers.get(HEADER_LINK);
    expect(link).toContain(`</css/app.css>; rel="preload"`);
    expect(link).toContain(`</api/v1/swap>; rel="successor-version"`);
  });
});

describe("v1SuccessorFor", () => {
  it("maps each known legacy financial root to /api/v1/<same path>", () => {
    for (const legacy of LEGACY_FINANCIAL_PATHS) {
      const v1 = v1SuccessorFor(legacy);
      expect(v1).toBe(legacy.replace("/api/", "/api/v1/"));
    }
  });

  it("inherits the legacy root for nested subroutes", () => {
    expect(v1SuccessorFor("/api/custody/withdraw")).toBe(
      "/api/v1/custody/withdraw",
    );
    // Nested subroutes of `/api/custody` (e.g. /api/custody/anything)
    // get the v1 successor mapping even when not in the explicit set —
    // they inherit the root because they live under it.
    expect(v1SuccessorFor("/api/custody/sub/path")).toBe(
      "/api/v1/custody/sub/path",
    );
  });

  it("returns null for paths not in the legacy financial set", () => {
    expect(v1SuccessorFor("/api/health")).toBeNull();
    expect(v1SuccessorFor("/api/auth/callback")).toBeNull();
    expect(v1SuccessorFor("/api/v1/swap")).toBeNull();
    expect(v1SuccessorFor("/")).toBeNull();
  });

  it("does not falsely match a path that only shares a prefix substring", () => {
    // "/api/swapping" should NOT map to "/api/v1/swap" — the prefix
    // check requires either an exact match or a "/" delimiter.
    expect(v1SuccessorFor("/api/swapping")).toBeNull();
    expect(v1SuccessorFor("/api/clearings")).toBeNull();
  });
});

describe("wrapV1Handler", () => {
  it("invokes the legacy handler and tags the response with X-Api-Version: 1", async () => {
    const legacy = async () =>
      NextResponse.json({ ok: true, hello: "world" }, { status: 201 });
    const wrapped = wrapV1Handler(legacy);
    const res = await wrapped();
    expect(res.status).toBe(201);
    expect(res.headers.get(HEADER_API_VERSION)).toBe("1");
    const body = (await res.json()) as { ok: true; hello: string };
    expect(body).toEqual({ ok: true, hello: "world" });
  });

  it("preserves arbitrary status codes and headers from the legacy response", async () => {
    const legacy = async () =>
      new NextResponse(JSON.stringify({ ok: false }), {
        status: 422,
        headers: {
          "x-request-id": "rq-abc",
          "x-custom": "preserved",
        },
      });
    const wrapped = wrapV1Handler(legacy);
    const res = await wrapped();
    expect(res.status).toBe(422);
    expect(res.headers.get("x-request-id")).toBe("rq-abc");
    expect(res.headers.get("x-custom")).toBe("preserved");
    expect(res.headers.get(HEADER_API_VERSION)).toBe("1");
  });

  it("forwards the original arguments (e.g. NextRequest) to the legacy handler", async () => {
    const seen: unknown[] = [];
    const legacy = async (a: string, b: number) => {
      seen.push(a, b);
      return NextResponse.json({ ok: true });
    };
    const wrapped = wrapV1Handler(legacy);
    await wrapped("hello", 42);
    expect(seen).toEqual(["hello", 42]);
  });

  it("propagates a synchronous (non-promise) legacy return", async () => {
    const legacy = (): NextResponse =>
      NextResponse.json({ ok: true }, { status: 200 });
    const wrapped = wrapV1Handler(legacy);
    const res = await wrapped();
    expect(res.headers.get(HEADER_API_VERSION)).toBe("1");
  });
});

describe("LEGACY_FINANCIAL_PATHS", () => {
  it("contains the five canonical financial roots plus subroutes", () => {
    expect(LEGACY_FINANCIAL_PATHS.has("/api/swap")).toBe(true);
    expect(LEGACY_FINANCIAL_PATHS.has("/api/custody")).toBe(true);
    expect(LEGACY_FINANCIAL_PATHS.has("/api/custody/withdraw")).toBe(true);
    expect(LEGACY_FINANCIAL_PATHS.has("/api/distribute-coins")).toBe(true);
    expect(LEGACY_FINANCIAL_PATHS.has("/api/clearing")).toBe(true);
  });
});
