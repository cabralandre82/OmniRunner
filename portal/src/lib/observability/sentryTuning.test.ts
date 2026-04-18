import { describe, it, expect } from "vitest";
import {
  classifySeverity,
  enrichWithSeverity,
  sampleRateForPath,
  tracesSampler,
} from "./sentryTuning";

describe("classifySeverity (L20-05)", () => {
  it("returns P1 for custody routes (money paths)", () => {
    expect(classifySeverity("/api/custody/deposit")).toBe("P1");
    expect(classifySeverity("/api/custody/withdraw")).toBe("P1");
    expect(classifySeverity("/api/custody/webhook")).toBe("P1");
  });

  it("returns P1 for swap, distribute, billing, auth", () => {
    expect(classifySeverity("/api/swap/execute")).toBe("P1");
    expect(classifySeverity("/api/distribute-coins")).toBe("P1");
    expect(classifySeverity("/api/withdraw")).toBe("P1");
    expect(classifySeverity("/api/billing/webhook")).toBe("P1");
    expect(classifySeverity("/api/auth/callback")).toBe("P1");
    expect(classifySeverity("/api/auth/login")).toBe("P1");
  });

  it("returns P2 for coaching/sessions/runs/platform", () => {
    expect(classifySeverity("/api/coaching/invite")).toBe("P2");
    expect(classifySeverity("/api/sessions/upload")).toBe("P2");
    expect(classifySeverity("/api/runs/import")).toBe("P2");
    expect(classifySeverity("/api/platform/feature-flags")).toBe("P2");
  });

  it("returns P4 for health, liveness, monitoring, static assets", () => {
    expect(classifySeverity("/api/health")).toBe("P4");
    expect(classifySeverity("/api/liveness")).toBe("P4");
    expect(classifySeverity("/_next/static/foo.js")).toBe("P4");
    expect(classifySeverity("/monitoring")).toBe("P4");
    expect(classifySeverity("/favicon.ico")).toBe("P4");
  });

  it("defaults to P3 for unrecognized routes", () => {
    expect(classifySeverity("/api/unknown/route")).toBe("P3");
    expect(classifySeverity("/")).toBe("P3");
    expect(classifySeverity("/dashboard")).toBe("P3");
  });

  it("handles undefined/null/empty input safely", () => {
    expect(classifySeverity(undefined)).toBe("P3");
    expect(classifySeverity(null)).toBe("P3");
    expect(classifySeverity("")).toBe("P3");
  });
});

describe("sampleRateForPath (L20-04)", () => {
  it("samples 100% on money/security routes (P1)", () => {
    expect(sampleRateForPath("/api/custody/deposit")).toBe(1.0);
    expect(sampleRateForPath("/api/swap/execute")).toBe(1.0);
    expect(sampleRateForPath("/api/auth/callback")).toBe(1.0);
  });

  it("samples 50% on critical paths (P2)", () => {
    expect(sampleRateForPath("/api/coaching/invite")).toBe(0.5);
    expect(sampleRateForPath("/api/sessions/upload")).toBe(0.5);
  });

  it("samples 10% on default paths (P3)", () => {
    expect(sampleRateForPath("/api/unknown")).toBe(0.1);
    expect(sampleRateForPath("/dashboard")).toBe(0.1);
  });

  it("samples 0% on noise (P4 — health probes, static)", () => {
    expect(sampleRateForPath("/api/health")).toBe(0);
    expect(sampleRateForPath("/api/liveness")).toBe(0);
    expect(sampleRateForPath("/_next/static/foo.js")).toBe(0);
  });
});

describe("tracesSampler (L20-04)", () => {
  it("honors parent decision when present (sampled=true)", () => {
    expect(
      tracesSampler({
        // @ts-expect-error — minimal context shape for unit test
        parentSampled: true,
        name: "/api/health",
      }),
    ).toBe(1.0);
  });

  it("honors parent decision when present (sampled=false even on P1)", () => {
    expect(
      tracesSampler({
        // @ts-expect-error — minimal context shape for unit test
        parentSampled: false,
        name: "/api/custody/deposit",
      }),
    ).toBe(0);
  });

  it("uses route severity when no parent decision", () => {
    expect(
      tracesSampler({
        // @ts-expect-error — minimal context shape for unit test
        name: "/api/custody/deposit",
      }),
    ).toBe(1.0);
    expect(
      tracesSampler({
        // @ts-expect-error — minimal context shape for unit test
        name: "/api/health",
      }),
    ).toBe(0);
    expect(
      tracesSampler({
        // @ts-expect-error — minimal context shape for unit test
        name: "/api/foo/bar",
      }),
    ).toBe(0.1);
  });

  it("falls back to P3 default when name is missing", () => {
    expect(
      tracesSampler({
        // @ts-expect-error — empty context
      }),
    ).toBe(0.1);
  });
});

describe("enrichWithSeverity (L20-05)", () => {
  it("adds severity tag derived from request URL", () => {
    const event = enrichWithSeverity({
      request: { url: "https://omnirunner.com/api/custody/deposit" },
    });
    expect(event.tags?.severity).toBe("P1");
  });

  it("adds severity tag derived from transaction name", () => {
    const event = enrichWithSeverity({ transaction: "/api/sessions/upload" });
    expect(event.tags?.severity).toBe("P2");
  });

  it("preserves existing tags", () => {
    const event = enrichWithSeverity({
      request: { url: "https://omnirunner.com/api/health" },
      tags: { custom: "value" },
    });
    expect(event.tags).toEqual({ custom: "value", severity: "P4" });
  });

  it("returns event unchanged when no URL/transaction", () => {
    const event = enrichWithSeverity({ tags: { existing: "tag" } });
    expect(event.tags).toEqual({ existing: "tag" });
  });

  it("handles malformed URLs gracefully", () => {
    const event = enrichWithSeverity({ request: { url: "not-a-url-or-path" } });
    expect(event.tags?.severity).toBe("P3");
  });

  it("handles relative path URLs", () => {
    const event = enrichWithSeverity({ request: { url: "/api/withdraw" } });
    expect(event.tags?.severity).toBe("P1");
  });
});
