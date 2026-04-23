import { describe, it, expect } from "vitest";
import {
  evaluateWaf,
  shouldBlockPath,
  shouldBlockUserAgent,
  WAF_BLOCKED_PATH_FRAGMENTS,
  WAF_BLOCKED_UA_SUBSTRINGS,
} from "./waf";

/**
 * L10-04 — In-process WAF regression tests.
 *
 * The WAF module is the "last line" complement to Vercel's edge
 * firewall. Tests here double-enforce the default-allow posture:
 *   1. Legitimate requests (Chrome, iOS Safari, our own crawlers)
 *      must pass.
 *   2. Every declared blocked UA substring and path fragment must
 *      actually block.
 *   3. Allow-list entries must always pass even when they sit near a
 *      blocked fragment (defensive ordering test).
 */

describe("shouldBlockUserAgent", () => {
  it("allows empty or missing UA", () => {
    expect(shouldBlockUserAgent(null).ok).toBe(true);
    expect(shouldBlockUserAgent(undefined).ok).toBe(true);
    expect(shouldBlockUserAgent("").ok).toBe(true);
  });

  it("allows common browser UAs", () => {
    const uas = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) Mobile",
      "Dart/3.3 (dart:io)",
    ];
    for (const ua of uas) {
      expect(shouldBlockUserAgent(ua).ok).toBe(true);
    }
  });

  it.each(WAF_BLOCKED_UA_SUBSTRINGS.map((s) => [s]))(
    "blocks UA containing %p (case-insensitive)",
    (needle) => {
      const ua = `Mozilla/5.0 ${needle.toUpperCase()} attacker`;
      const verdict = shouldBlockUserAgent(ua);
      expect(verdict.ok).toBe(false);
      if (!verdict.ok) {
        expect(verdict.rule).toBe("ua");
      }
    },
  );
});

describe("shouldBlockPath", () => {
  it("allows portal routes", () => {
    const paths = [
      "/",
      "/login",
      "/platform/users",
      "/api/v1/custody",
      "/api/custody/webhook",
      "/dashboard/overview",
    ];
    for (const p of paths) {
      expect(shouldBlockPath(p).ok).toBe(true);
    }
  });

  it.each(WAF_BLOCKED_PATH_FRAGMENTS.map((f) => [f]))(
    "blocks path containing %p",
    (fragment) => {
      const p = `/${fragment.replace(/^\//, "")}/index.html`;
      const verdict = shouldBlockPath(p);
      expect(verdict.ok).toBe(false);
      if (!verdict.ok) expect(verdict.rule).toBe("path");
    },
  );

  it("allow-list wins: /.well-known/security.txt passes even though /.env exists", () => {
    expect(shouldBlockPath("/.well-known/security.txt").ok).toBe(true);
  });
});

describe("evaluateWaf — combined", () => {
  it("UA verdict wins over path when UA is blocked", () => {
    const verdict = evaluateWaf({
      userAgent: "sqlmap/1.7",
      pathname: "/",
    });
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.rule).toBe("ua");
  });

  it("path check runs when UA is clean", () => {
    const verdict = evaluateWaf({
      userAgent: "Mozilla/5.0",
      pathname: "/wp-admin/login.php",
    });
    expect(verdict.ok).toBe(false);
    if (!verdict.ok) expect(verdict.rule).toBe("path");
  });

  it("clean request passes", () => {
    expect(
      evaluateWaf({ userAgent: "Mozilla/5.0", pathname: "/dashboard" }).ok,
    ).toBe(true);
  });
});
