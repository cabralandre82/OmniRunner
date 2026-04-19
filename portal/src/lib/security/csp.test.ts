import { describe, it, expect } from "vitest";
import { buildCsp, buildReportToHeader, generateNonce } from "./csp";

/**
 * L01-38 / L10-05 — Content-Security-Policy builder regression tests.
 *
 * The two findings ride on the same builder, so we keep their tests
 * together: L01-38 cares that production never carries
 * `'unsafe-inline'` or `'unsafe-eval'` in `script-src`; L10-05 cares
 * that violations actually have a place to land (`report-uri` +
 * `report-to`).
 *
 * Test style: every property under audit is asserted both positively
 * ("the production policy contains X") AND negatively ("the production
 * policy does NOT contain Y"). Negative assertions matter most — a
 * future contributor adding `'unsafe-inline'` "just for one rollout"
 * is the failure mode this test exists to block.
 */

const NONCE = "deadBEEFcafe1234"; // 16 chars, no forbidden symbols

describe("buildCsp — production posture (L01-38)", () => {
  const csp = buildCsp({ nonce: NONCE, isDev: false });

  it("emits script-src with nonce + strict-dynamic", () => {
    expect(csp).toMatch(
      new RegExp(
        `script-src 'self' 'nonce-${NONCE}' 'strict-dynamic'(?: |;|$)`,
      ),
    );
  });

  it("does NOT carry 'unsafe-inline' in script-src", () => {
    const scriptSrcLine = csp
      .split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("script-src "));
    expect(scriptSrcLine).toBeDefined();
    expect(scriptSrcLine).not.toContain("'unsafe-inline'");
  });

  it("does NOT carry 'unsafe-eval' in script-src (production)", () => {
    const scriptSrcLine = csp
      .split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("script-src "));
    expect(scriptSrcLine).toBeDefined();
    expect(scriptSrcLine).not.toContain("'unsafe-eval'");
  });

  it("retains style-src 'unsafe-inline' (documented trade-off)", () => {
    expect(csp).toMatch(/style-src 'self' 'unsafe-inline'/);
  });

  it("ships frame-ancestors 'none' + base-uri 'self' + object-src 'none'", () => {
    expect(csp).toContain("frame-ancestors 'none'");
    expect(csp).toContain("base-uri 'self'");
    expect(csp).toContain("object-src 'none'");
  });

  it("ships upgrade-insecure-requests as a value-less directive", () => {
    expect(csp).toMatch(/(?:^|; )upgrade-insecure-requests(?:;|$)/);
  });

  it("connect-src includes Supabase REST + WS + Sentry direct fallback", () => {
    expect(csp).toContain("https://*.supabase.co");
    expect(csp).toContain("wss://*.supabase.co");
    expect(csp).toContain("https://*.sentry.io");
  });

  it("does NOT allow ws:// or http:// localhost in production", () => {
    expect(csp).not.toContain("ws://localhost");
    expect(csp).not.toContain("http://localhost");
  });

  it("emits report-uri + report-to (L10-05)", () => {
    expect(csp).toContain("report-uri /api/csp-report");
    expect(csp).toContain("report-to csp-endpoint");
  });

  it("can omit reporting when explicitly asked", () => {
    const noReport = buildCsp({
      nonce: NONCE,
      isDev: false,
      reportEndpoint: null,
    });
    expect(noReport).not.toContain("report-uri");
    expect(noReport).not.toContain("report-to");
  });
});

describe("buildCsp — development posture", () => {
  const csp = buildCsp({ nonce: NONCE, isDev: true });

  it("DOES carry 'unsafe-eval' (Next Fast Refresh / React Refresh)", () => {
    const scriptSrcLine = csp
      .split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("script-src "));
    expect(scriptSrcLine).toContain("'unsafe-eval'");
  });

  it("still does NOT carry 'unsafe-inline' (nonce works in dev too)", () => {
    const scriptSrcLine = csp
      .split(";")
      .map((s) => s.trim())
      .find((s) => s.startsWith("script-src "));
    expect(scriptSrcLine).not.toContain("'unsafe-inline'");
  });

  it("allows ws:// + http:// localhost for HMR transport", () => {
    expect(csp).toContain("ws://localhost:*");
    expect(csp).toContain("http://localhost:*");
  });
});

describe("buildCsp — defensive guards", () => {
  it("rejects an empty nonce", () => {
    expect(() => buildCsp({ nonce: "", isDev: false })).toThrow(/nonce/i);
  });

  it("rejects a nonce containing whitespace", () => {
    expect(() => buildCsp({ nonce: "abc def", isDev: false })).toThrow(
      /forbidden/i,
    );
  });

  it("rejects a nonce containing a single quote (would close the directive)", () => {
    expect(() =>
      buildCsp({ nonce: "abc'def", isDev: false }),
    ).toThrow(/forbidden/i);
  });

  it("rejects a nonce containing a less-than (HTML injection attempt)", () => {
    expect(() => buildCsp({ nonce: "abc<def", isDev: false })).toThrow(
      /forbidden/i,
    );
  });

  it("emits extraConnectSrc verbatim (CSP is opt-in, not free-form)", () => {
    const csp = buildCsp({
      nonce: NONCE,
      isDev: false,
      extraConnectSrc: ["https://staging.omnirunner.app"],
    });
    expect(csp).toContain("https://staging.omnirunner.app");
  });
});

describe("buildReportToHeader", () => {
  it("returns null when reporting is disabled", () => {
    expect(buildReportToHeader(null)).toBeNull();
  });

  it("returns a JSON string with group + max_age + endpoints + include_subdomains", () => {
    const raw = buildReportToHeader("/api/csp-report");
    expect(raw).not.toBeNull();
    const parsed = JSON.parse(raw!);
    expect(parsed.group).toBe("csp-endpoint");
    expect(parsed.endpoints).toEqual([{ url: "/api/csp-report" }]);
    expect(parsed.max_age).toBeGreaterThan(0);
    expect(parsed.include_subdomains).toBe(true);
  });

  it("uses the endpoint URL passed in (not a hardcoded constant)", () => {
    const raw = buildReportToHeader("https://example.com/csp");
    const parsed = JSON.parse(raw!);
    expect(parsed.endpoints).toEqual([{ url: "https://example.com/csp" }]);
  });
});

describe("generateNonce", () => {
  it("produces a non-empty string with safe characters only", () => {
    const n = generateNonce();
    expect(n.length).toBeGreaterThan(0);
    expect(n).not.toMatch(/[\s"'<>]/);
  });

  it("is unique across many invocations (CSPRNG sanity check)", () => {
    const nonces = new Set<string>();
    for (let i = 0; i < 1000; i++) {
      nonces.add(generateNonce());
    }
    // 1000 16-byte CSPRNG draws colliding is astronomically unlikely;
    // anything less than 1000 unique values means the underlying RNG
    // has been replaced by a Math.random() shim — the exact failure
    // mode the assertion in `generateNonce` is meant to detect.
    expect(nonces.size).toBe(1000);
  });

  it("produces 16-byte (24-char base64) values", () => {
    // 16 bytes encoded in base64 = ceil(16/3)*4 = 24 chars (with
    // single trailing '=' if the input length is a multiple of 1
    // mod 3 — for 16 bytes it ends with '==').
    expect(generateNonce()).toHaveLength(24);
  });
});
