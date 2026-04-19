/**
 * Unit tests for L01-06 CSRF helpers.
 *
 * The helpers are split into pure functions (`shouldEnforceCsrf`,
 * `isWellFormedCsrfToken`, `generateCsrfToken`) and request-bound
 * functions (`verifyCsrf`, `ensureCsrfCookie`, `clearCsrfCookie`).
 * The pure ones are trivial; we focus the test suite on the
 * request-bound surface where regressions actually hurt — the
 * security boundary lives there.
 */

import { describe, it, expect } from "vitest";
import { NextRequest, NextResponse } from "next/server";
import {
  CSRF_COOKIE_NAME,
  CSRF_EXEMPT_PREFIXES,
  CSRF_HEADER_NAME,
  CSRF_PROTECTED_PREFIXES,
  clearCsrfCookie,
  ensureCsrfCookie,
  generateCsrfToken,
  isWellFormedCsrfToken,
  shouldEnforceCsrf,
  verifyCsrf,
} from "./csrf";

function makeReq(opts: {
  method?: string;
  pathname?: string;
  headers?: Record<string, string>;
  cookies?: Record<string, string>;
}): NextRequest {
  const url = `http://localhost${opts.pathname ?? "/api/test"}`;
  const cookieHeader = opts.cookies
    ? Object.entries(opts.cookies)
        .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
        .join("; ")
    : undefined;
  const headers = new Headers(opts.headers);
  if (cookieHeader) headers.set("cookie", cookieHeader);
  return new NextRequest(url, {
    method: opts.method ?? "POST",
    headers,
  });
}

describe("generateCsrfToken", () => {
  it("returns 64-char hex strings", () => {
    const t = generateCsrfToken();
    expect(t).toMatch(/^[a-f0-9]{64}$/);
    expect(t.length).toBe(64);
  });

  it("returns distinct values across calls (not constant)", () => {
    const a = generateCsrfToken();
    const b = generateCsrfToken();
    expect(a).not.toBe(b);
  });
});

describe("isWellFormedCsrfToken", () => {
  it("accepts a freshly generated token", () => {
    expect(isWellFormedCsrfToken(generateCsrfToken())).toBe(true);
  });

  it("rejects empty / wrong-length / non-hex / non-string", () => {
    expect(isWellFormedCsrfToken("")).toBe(false);
    expect(isWellFormedCsrfToken("a".repeat(63))).toBe(false);
    expect(isWellFormedCsrfToken("a".repeat(65))).toBe(false);
    expect(isWellFormedCsrfToken("Z".repeat(64))).toBe(false); // capital Z not in [a-f0-9]
    expect(isWellFormedCsrfToken("g".repeat(64))).toBe(false);
    expect(isWellFormedCsrfToken(null)).toBe(false);
    expect(isWellFormedCsrfToken(undefined)).toBe(false);
    expect(isWellFormedCsrfToken(42)).toBe(false);
  });
});

describe("shouldEnforceCsrf", () => {
  it("skips safe methods (GET/HEAD/OPTIONS) regardless of path", () => {
    for (const m of ["GET", "HEAD", "OPTIONS", "get", "head"]) {
      expect(shouldEnforceCsrf(m, "/api/custody/withdraw")).toBe(false);
    }
  });

  it("enforces on POST/PUT/PATCH/DELETE for protected prefixes", () => {
    for (const m of ["POST", "PUT", "PATCH", "DELETE", "post"]) {
      expect(shouldEnforceCsrf(m, "/api/custody/withdraw")).toBe(true);
      expect(shouldEnforceCsrf(m, "/api/swap")).toBe(true);
      expect(shouldEnforceCsrf(m, "/api/clearing")).toBe(true);
      expect(shouldEnforceCsrf(m, "/api/distribute-coins")).toBe(true);
    }
  });

  it("enforces on platform custody endpoints (L02-06 routes)", () => {
    expect(
      shouldEnforceCsrf(
        "POST",
        "/api/platform/custody/withdrawals/abc/complete",
      ),
    ).toBe(true);
    expect(
      shouldEnforceCsrf(
        "POST",
        "/api/platform/custody/withdrawals/abc/fail",
      ),
    ).toBe(true);
  });

  it("does NOT enforce on exempt prefixes even when method is unsafe", () => {
    for (const exempt of CSRF_EXEMPT_PREFIXES) {
      expect(shouldEnforceCsrf("POST", exempt)).toBe(false);
      expect(shouldEnforceCsrf("POST", `${exempt}/anything`)).toBe(false);
    }
  });

  it("does NOT enforce on routes outside the allow-list (open by default for non-financial)", () => {
    // Today this is a deliberate scoping decision: the CSRF gate is an
    // allow-list of financial routes (L01-06). Non-financial mutation
    // routes (e.g. /api/announcements) keep working without the header
    // until/unless the allow-list grows.
    expect(shouldEnforceCsrf("POST", "/api/announcements")).toBe(false);
    expect(shouldEnforceCsrf("POST", "/api/team/invite")).toBe(false);
    expect(shouldEnforceCsrf("POST", "/api/branding")).toBe(false);
  });

  it("matches both exact and prefix paths for protected entries", () => {
    for (const p of CSRF_PROTECTED_PREFIXES) {
      expect(shouldEnforceCsrf("POST", p)).toBe(true);
      expect(shouldEnforceCsrf("POST", `${p}/sub/path`)).toBe(true);
    }
  });
});

describe("verifyCsrf", () => {
  it("returns CSRF_COOKIE_MISSING when no cookie present", () => {
    const r = makeReq({ headers: { [CSRF_HEADER_NAME]: generateCsrfToken() } });
    const v = verifyCsrf(r);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.code).toBe("CSRF_COOKIE_MISSING");
  });

  it("returns CSRF_HEADER_MISSING when cookie present but header absent", () => {
    const token = generateCsrfToken();
    const r = makeReq({ cookies: { [CSRF_COOKIE_NAME]: token } });
    const v = verifyCsrf(r);
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.code).toBe("CSRF_HEADER_MISSING");
  });

  it("returns CSRF_TOKEN_MALFORMED when either side is the wrong shape", () => {
    const good = generateCsrfToken();
    const bad = "not-hex";
    expect(
      verifyCsrf(
        makeReq({
          cookies: { [CSRF_COOKIE_NAME]: bad },
          headers: { [CSRF_HEADER_NAME]: good },
        }),
      ),
    ).toMatchObject({ ok: false, code: "CSRF_TOKEN_MALFORMED" });
    expect(
      verifyCsrf(
        makeReq({
          cookies: { [CSRF_COOKIE_NAME]: good },
          headers: { [CSRF_HEADER_NAME]: bad },
        }),
      ),
    ).toMatchObject({ ok: false, code: "CSRF_TOKEN_MALFORMED" });
  });

  it("returns CSRF_TOKEN_MISMATCH when cookie != header (both well-formed)", () => {
    const cookie = generateCsrfToken();
    const header = generateCsrfToken(); // different token
    const v = verifyCsrf(
      makeReq({
        cookies: { [CSRF_COOKIE_NAME]: cookie },
        headers: { [CSRF_HEADER_NAME]: header },
      }),
    );
    expect(v.ok).toBe(false);
    if (!v.ok) expect(v.code).toBe("CSRF_TOKEN_MISMATCH");
  });

  it("returns ok when cookie === header (the only path that grants entry)", () => {
    const token = generateCsrfToken();
    const v = verifyCsrf(
      makeReq({
        cookies: { [CSRF_COOKIE_NAME]: token },
        headers: { [CSRF_HEADER_NAME]: token },
      }),
    );
    expect(v.ok).toBe(true);
  });

  it("treats header case-insensitively (HTTP semantics)", () => {
    const token = generateCsrfToken();
    const r = new NextRequest("http://localhost/api/test", {
      method: "POST",
      headers: {
        cookie: `${CSRF_COOKIE_NAME}=${token}`,
        "X-CSRF-TOKEN": token, // upper-cased
      },
    });
    expect(verifyCsrf(r)).toEqual({ ok: true });
  });
});

describe("ensureCsrfCookie", () => {
  it("mints a fresh token when the request has no cookie", () => {
    const req = makeReq({});
    const res = NextResponse.next();
    const token = ensureCsrfCookie(req, res, { secure: false });
    expect(isWellFormedCsrfToken(token)).toBe(true);
    const set = res.cookies.get(CSRF_COOKIE_NAME);
    expect(set?.value).toBe(token);
  });

  it("is idempotent — preserves an already-valid cookie", () => {
    const existing = generateCsrfToken();
    const req = makeReq({ cookies: { [CSRF_COOKIE_NAME]: existing } });
    const res = NextResponse.next();
    const token = ensureCsrfCookie(req, res, { secure: false });
    expect(token).toBe(existing);
    // No new Set-Cookie should have been emitted.
    expect(res.cookies.get(CSRF_COOKIE_NAME)).toBeUndefined();
  });

  it("rotates a malformed cookie value to a fresh well-formed one", () => {
    const req = makeReq({ cookies: { [CSRF_COOKIE_NAME]: "garbage" } });
    const res = NextResponse.next();
    const token = ensureCsrfCookie(req, res, { secure: false });
    expect(token).not.toBe("garbage");
    expect(isWellFormedCsrfToken(token)).toBe(true);
    expect(res.cookies.get(CSRF_COOKIE_NAME)?.value).toBe(token);
  });

  it("sets sameSite=strict + httpOnly=false on the issued cookie", () => {
    const req = makeReq({});
    const res = NextResponse.next();
    ensureCsrfCookie(req, res, { secure: false });
    const cookie = res.cookies.get(CSRF_COOKIE_NAME);
    expect(cookie?.sameSite).toBe("strict");
    // httpOnly must be FALSE so client JS can read the cookie to mirror
    // it as the x-csrf-token header (double-submit pattern).
    expect(cookie?.httpOnly).toBe(false);
  });
});

describe("clearCsrfCookie", () => {
  it("emits a Max-Age=0 Set-Cookie that browsers will delete", () => {
    const res = NextResponse.next();
    clearCsrfCookie(res, { secure: false });
    const cookie = res.cookies.get(CSRF_COOKIE_NAME);
    expect(cookie?.value).toBe("");
    expect(cookie?.maxAge).toBe(0);
  });
});
