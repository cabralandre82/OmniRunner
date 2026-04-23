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
const mockCaptureException = vi.fn();
const mockCaptureMessage = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  getActiveSpan: () => mockGetActiveSpan(),
  spanToJSON: (s: unknown) => mockSpanToJSON(s),
  captureException: (...args: unknown[]) => mockCaptureException(...args),
  captureMessage: (...args: unknown[]) => mockCaptureMessage(...args),
}));

const { logger } = await import("./logger");

describe("logger", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    mockGetActiveSpan.mockReturnValue(undefined);
    mockSpanToJSON.mockReturnValue({ data: {}, start_timestamp: 0 });
    mockCaptureException.mockReset();
    mockCaptureMessage.mockReset();
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

  // ─── L17-05 — logger.error must always report to Sentry ──────────
  describe("L17-05 Sentry capture invariants", () => {
    it("reports Error instances via captureException", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      const err = new Error("boom");
      logger.error("failed", err, { userId: "u1" });

      expect(mockCaptureException).toHaveBeenCalledTimes(1);
      expect(mockCaptureMessage).not.toHaveBeenCalled();
      expect(mockCaptureException).toHaveBeenCalledWith(err, {
        extra: { msg: "failed", userId: "u1" },
      });
    });

    it("captures a message even when error is undefined (bug L17-05)", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      logger.error("config_missing", undefined, { gateway: "stripe" });

      expect(mockCaptureException).not.toHaveBeenCalled();
      expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
      expect(mockCaptureMessage).toHaveBeenCalledWith("config_missing", {
        level: "error",
        extra: { gateway: "stripe" },
      });
    });

    it("captures a message even when error is null", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      logger.error("ping", null);

      expect(mockCaptureException).not.toHaveBeenCalled();
      expect(mockCaptureMessage).toHaveBeenCalledWith("ping", {
        level: "error",
        extra: {},
      });
    });

    it("captures a message when error is a plain string", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      logger.error("rate limited", "too many requests", { ip: "1.2.3.4" });

      expect(mockCaptureMessage).toHaveBeenCalledWith("rate limited", {
        level: "error",
        extra: { ip: "1.2.3.4", error: "too many requests" },
      });
    });

    it("captures a message when error is a plain object", () => {
      vi.spyOn(console, "error").mockImplementation(() => {});
      logger.error("upstream failure", { code: 503, body: "timeout" });

      expect(mockCaptureMessage).toHaveBeenCalledTimes(1);
      const call = mockCaptureMessage.mock.calls[0];
      expect(call[0]).toBe("upstream failure");
      expect(call[1].level).toBe("error");
      expect(call[1].extra.error).toEqual({ code: 503, body: "timeout" });
    });

    it("omits the error field from console JSON when error is undefined", () => {
      const spy = vi.spyOn(console, "error").mockImplementation(() => {});
      logger.error("config_missing", undefined, { gateway: "stripe" });

      const parsed = JSON.parse(spy.mock.calls[0][0]);
      expect(parsed.error).toBeUndefined();
      expect(parsed.stack).toBeUndefined();
      expect(parsed.gateway).toBe("stripe");
      expect(parsed.level).toBe("error");
      expect(parsed.msg).toBe("config_missing");
    });
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
