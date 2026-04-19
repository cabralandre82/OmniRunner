import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// Hoisted mocks: vi.mock factories run before module imports, so we expose
// the spies through hoisted variables to assert against them in each test.
const sentryMocks = vi.hoisted(() => {
  const tagBag: Record<string, string> = {};
  const extraBag: Record<string, unknown> = {};
  const captureException = vi.fn();
  const setTag = vi.fn((k: string, v: string) => {
    tagBag[k] = v;
  });
  const setExtra = vi.fn((k: string, v: unknown) => {
    extraBag[k] = v;
  });
  const withScope = vi.fn((cb: (scope: { setTag: typeof setTag; setExtra: typeof setExtra }) => void) => {
    cb({ setTag, setExtra });
  });
  return { captureException, setTag, setExtra, withScope, tagBag, extraBag };
});

vi.mock("@sentry/nextjs", () => ({
  withScope: sentryMocks.withScope,
  captureException: sentryMocks.captureException,
}));

import { reportClientError } from "./reportClientError";

describe("reportClientError (L06-07)", () => {
  let consoleErrorSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    sentryMocks.captureException.mockClear();
    sentryMocks.setTag.mockClear();
    sentryMocks.setExtra.mockClear();
    sentryMocks.withScope.mockClear();
    for (const k of Object.keys(sentryMocks.tagBag)) delete sentryMocks.tagBag[k];
    for (const k of Object.keys(sentryMocks.extraBag)) delete sentryMocks.extraBag[k];
    consoleErrorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
  });

  afterEach(() => {
    consoleErrorSpy.mockRestore();
  });

  it("forwards the error to Sentry.captureException", () => {
    const err = new Error("kaboom");
    reportClientError({ error: err, boundary: "global" });
    expect(sentryMocks.captureException).toHaveBeenCalledTimes(1);
    expect(sentryMocks.captureException).toHaveBeenCalledWith(err);
  });

  it("tags global boundary as P1 (pages on-call)", () => {
    reportClientError({ error: new Error("x"), boundary: "global" });
    expect(sentryMocks.tagBag.error_boundary).toBe("global");
    expect(sentryMocks.tagBag.severity).toBe("P1");
  });

  it("tags root boundary as P1", () => {
    reportClientError({ error: new Error("x"), boundary: "root" });
    expect(sentryMocks.tagBag.error_boundary).toBe("root");
    expect(sentryMocks.tagBag.severity).toBe("P1");
  });

  it("tags portal boundary as P2 (Slack only)", () => {
    reportClientError({ error: new Error("x"), boundary: "portal" });
    expect(sentryMocks.tagBag.error_boundary).toBe("portal");
    expect(sentryMocks.tagBag.severity).toBe("P2");
  });

  it("tags platform boundary as P2", () => {
    reportClientError({ error: new Error("x"), boundary: "platform" });
    expect(sentryMocks.tagBag.error_boundary).toBe("platform");
    expect(sentryMocks.tagBag.severity).toBe("P2");
  });

  it("preserves error.digest as a Sentry tag (server↔client correlation)", () => {
    const err = Object.assign(new Error("x"), { digest: "abc123" });
    reportClientError({ error: err, boundary: "global" });
    expect(sentryMocks.tagBag.digest).toBe("abc123");
  });

  it("does NOT set a digest tag when error has no digest", () => {
    reportClientError({ error: new Error("x"), boundary: "global" });
    expect(sentryMocks.tagBag.digest).toBeUndefined();
  });

  it("forwards extras as Sentry scope.setExtra entries", () => {
    reportClientError({
      error: new Error("x"),
      boundary: "portal",
      extras: { route: "/dashboard", flag: true, count: 3 },
    });
    expect(sentryMocks.extraBag.route).toBe("/dashboard");
    expect(sentryMocks.extraBag.flag).toBe(true);
    expect(sentryMocks.extraBag.count).toBe(3);
  });

  it("skips null/undefined extras (no garbage in Sentry payload)", () => {
    reportClientError({
      error: new Error("x"),
      boundary: "portal",
      extras: { route: "/x", missing: undefined, blank: null, kept: "ok" },
    });
    expect(sentryMocks.extraBag.route).toBe("/x");
    expect(sentryMocks.extraBag.kept).toBe("ok");
    expect(sentryMocks.extraBag.missing).toBeUndefined();
    expect(sentryMocks.extraBag.blank).toBeUndefined();
  });

  it("echoes to console.error so local dev sees the crash without Sentry", () => {
    const err = new Error("dev-kaboom");
    reportClientError({ error: err, boundary: "root" });
    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining("[root-error-boundary]"),
      err,
    );
  });

  it("does not throw if Sentry.withScope crashes (observability fail-safe)", () => {
    sentryMocks.withScope.mockImplementationOnce(() => {
      throw new Error("sentry exploded");
    });
    expect(() =>
      reportClientError({ error: new Error("x"), boundary: "global" }),
    ).not.toThrow();
  });

  it("does not throw if Sentry.captureException crashes", () => {
    sentryMocks.captureException.mockImplementationOnce(() => {
      throw new Error("sentry exploded");
    });
    expect(() =>
      reportClientError({ error: new Error("x"), boundary: "platform" }),
    ).not.toThrow();
  });

  it("uses a fresh scope per invocation (no tag leakage across calls)", () => {
    reportClientError({ error: new Error("a"), boundary: "global" });
    reportClientError({ error: new Error("b"), boundary: "portal" });
    expect(sentryMocks.withScope).toHaveBeenCalledTimes(2);
  });
});
