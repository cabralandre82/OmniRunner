import { describe, it, expect, vi, beforeEach } from "vitest";

// L20-03 — mock Sentry so we can flip getActiveSpan/spanToJSON per-test
// and verify trace_id auto-injection in log lines.
const mockGetActiveSpan = vi.fn(() => undefined as unknown);
const mockSpanToJSON = vi.fn(
  () =>
    ({ data: {}, start_timestamp: 0 }) as {
      trace_id?: string;
      span_id?: string;
      data: Record<string, unknown>;
      start_timestamp: number;
    },
);
vi.mock("@sentry/nextjs", () => ({
  getActiveSpan: () => mockGetActiveSpan(),
  spanToJSON: (s: unknown) => mockSpanToJSON(s),
  captureException: vi.fn(),
  captureMessage: vi.fn(),
}));

const { logger } = await import("./logger");

describe("logger", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    mockGetActiveSpan.mockReturnValue(undefined);
    mockSpanToJSON.mockReturnValue({ data: {}, start_timestamp: 0 });
  });

  it("logs info as structured JSON", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    logger.info("test message", { userId: "123" });

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("info");
    expect(parsed.msg).toBe("test message");
    expect(parsed.userId).toBe("123");
    expect(parsed.ts).toBeDefined();
  });

  it("logs warnings", () => {
    const spy = vi.spyOn(console, "warn").mockImplementation(() => {});
    logger.warn("something off");

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("warn");
  });

  it("logs errors with error details", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const err = new Error("boom");
    logger.error("failed", err, { action: "test" });

    expect(spy).toHaveBeenCalledOnce();
    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.level).toBe("error");
    expect(parsed.error).toBe("boom");
    expect(parsed.stack).toContain("Error: boom");
    expect(parsed.action).toBe("test");
  });

  it("handles non-Error objects in error field", () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    logger.error("failed", "string error");

    const parsed = JSON.parse(spy.mock.calls[0][0]);
    expect(parsed.error).toBe("string error");
  });

  // ─── L20-03 — trace_id auto-injection ────────────────────────────
  describe("L20-03 trace correlation", () => {
    it("auto-injects trace_id + span_id when a Sentry span is active", () => {
      mockGetActiveSpan.mockReturnValue({});
      mockSpanToJSON.mockReturnValue({
        trace_id: "abcdef0123456789abcdef0123456789",
        span_id: "0123456789abcdef",
        data: {},
        start_timestamp: 0,
      });
      const spy = vi.spyOn(console, "log").mockImplementation(() => {});

      logger.info("hello", { foo: "bar" });

      const parsed = JSON.parse(spy.mock.calls[0][0]);
      expect(parsed.trace_id).toBe("abcdef0123456789abcdef0123456789");
      expect(parsed.span_id).toBe("0123456789abcdef");
      expect(parsed.foo).toBe("bar");
    });

    it("omits trace_id when no span is active", () => {
      const spy = vi.spyOn(console, "log").mockImplementation(() => {});

      logger.info("hello", { foo: "bar" });

      const parsed = JSON.parse(spy.mock.calls[0][0]);
      expect(parsed.trace_id).toBeUndefined();
      expect(parsed.span_id).toBeUndefined();
      expect(parsed.foo).toBe("bar");
    });

    it("survives Sentry throwing during getActiveSpan (no init scenario)", () => {
      mockGetActiveSpan.mockImplementation(() => {
        throw new Error("Sentry not initialized");
      });
      const spy = vi.spyOn(console, "log").mockImplementation(() => {});

      expect(() => logger.info("hello")).not.toThrow();
      const parsed = JSON.parse(spy.mock.calls[0][0]);
      expect(parsed.msg).toBe("hello");
      expect(parsed.trace_id).toBeUndefined();
    });

    it("preserves caller meta keys when trace context is also added", () => {
      mockGetActiveSpan.mockReturnValue({});
      mockSpanToJSON.mockReturnValue({
        trace_id: "trace-abc",
        span_id: "span-xyz",
        data: {},
        start_timestamp: 0,
      });
      const spy = vi.spyOn(console, "error").mockImplementation(() => {});

      logger.error("failed", new Error("boom"), { userId: "u-1" });

      const parsed = JSON.parse(spy.mock.calls[0][0]);
      expect(parsed.trace_id).toBe("trace-abc");
      expect(parsed.span_id).toBe("span-xyz");
      expect(parsed.userId).toBe("u-1");
      expect(parsed.error).toBe("boom");
    });
  });
});
