import { describe, it, expect, vi, beforeEach } from "vitest";

const mockSpan = {
  setAttribute: vi.fn(),
  setStatus: vi.fn(),
};

const mockGetActiveSpan = vi.fn();
const mockStartSpan = vi.fn();
const mockSpanToJSON = vi.fn();
const mockSpanToTraceHeader = vi.fn();
const mockSpanToBaggageHeader = vi.fn();
const mockContinueTrace = vi.fn();

vi.mock("@sentry/nextjs", () => ({
  startSpan: (opts: unknown, cb: (s: unknown) => unknown) => mockStartSpan(opts, cb),
  getActiveSpan: () => mockGetActiveSpan(),
  spanToJSON: (s: unknown) => mockSpanToJSON(s),
  spanToTraceHeader: (s: unknown) => mockSpanToTraceHeader(s),
  spanToBaggageHeader: (s: unknown) => mockSpanToBaggageHeader(s),
  continueTrace: (h: unknown, cb: () => unknown) => mockContinueTrace(h, cb),
}));

import {
  withSpan,
  currentTraceId,
  currentSpanId,
  traceparent,
  continueTraceFromRequest,
} from "./tracing";

describe("L20-03 — tracing helpers", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockSpan.setAttribute.mockReset();
    mockSpan.setStatus.mockReset();
    mockStartSpan.mockImplementation(async (_opts, cb) => cb(mockSpan));
  });

  // ─── withSpan ─────────────────────────────────────────────────────
  describe("withSpan", () => {
    it("invokes Sentry.startSpan with name + op + attrs", async () => {
      await withSpan(
        "fetch user profile",
        "db.select",
        async () => "ok",
        { "db.system": "postgresql", "db.statement": "select * from users" },
      );
      expect(mockStartSpan).toHaveBeenCalledTimes(1);
      const opts = mockStartSpan.mock.calls[0][0];
      expect(opts.name).toBe("fetch user profile");
      expect(opts.op).toBe("db.select");
      expect(opts.attributes).toEqual({
        "db.system": "postgresql",
        "db.statement": "select * from users",
      });
    });

    it("filters undefined/null attribute values", async () => {
      await withSpan("op", "db.rpc", async () => "ok", {
        "db.system": "postgresql",
        "db.user": undefined,
        "db.name": null,
        "db.rows": 0,
      });
      const opts = mockStartSpan.mock.calls[0][0];
      expect(opts.attributes).toEqual({ "db.system": "postgresql", "db.rows": 0 });
    });

    it("returns the result of the callback", async () => {
      const result = await withSpan("op", "db.rpc", async () => 42);
      expect(result).toBe(42);
    });

    it("passes setAttr that calls span.setAttribute (skipping null/undef)", async () => {
      await withSpan("op", "db.rpc", async (setAttr) => {
        setAttr("k1", "v1");
        setAttr("k2", undefined);
        setAttr("k3", null);
        setAttr("k4", 42);
      });
      expect(mockSpan.setAttribute).toHaveBeenCalledTimes(2);
      expect(mockSpan.setAttribute).toHaveBeenCalledWith("k1", "v1");
      expect(mockSpan.setAttribute).toHaveBeenCalledWith("k4", 42);
    });

    it("on throw: marks span status=error AND re-throws", async () => {
      const boom = new Error("DB exploded");
      await expect(
        withSpan("op", "db.rpc", async () => {
          throw boom;
        }),
      ).rejects.toBe(boom);
      expect(mockSpan.setStatus).toHaveBeenCalledWith({ code: 2, message: "DB exploded" });
    });

    it("on throw with non-Error: still marks status=error", async () => {
      await expect(
        withSpan("op", "db.rpc", async () => {
          throw "string error";
        }),
      ).rejects.toBe("string error");
      expect(mockSpan.setStatus).toHaveBeenCalledWith({ code: 2, message: "string error" });
    });
  });

  // ─── currentTraceId / currentSpanId ───────────────────────────────
  describe("currentTraceId / currentSpanId", () => {
    it("returns null when no active span", () => {
      mockGetActiveSpan.mockReturnValue(undefined);
      expect(currentTraceId()).toBeNull();
      expect(currentSpanId()).toBeNull();
    });

    it("returns trace_id from spanToJSON", () => {
      mockGetActiveSpan.mockReturnValue(mockSpan);
      mockSpanToJSON.mockReturnValue({
        trace_id: "abcdef0123456789abcdef0123456789",
        span_id: "0123456789abcdef",
        data: {},
        start_timestamp: 0,
      });
      expect(currentTraceId()).toBe("abcdef0123456789abcdef0123456789");
      expect(currentSpanId()).toBe("0123456789abcdef");
    });

    it("returns null if Sentry throws (no init, etc)", () => {
      mockGetActiveSpan.mockImplementation(() => {
        throw new Error("Sentry not initialized");
      });
      expect(currentTraceId()).toBeNull();
      expect(currentSpanId()).toBeNull();
    });

    it("returns null when spanToJSON has no trace_id", () => {
      mockGetActiveSpan.mockReturnValue(mockSpan);
      mockSpanToJSON.mockReturnValue({ data: {}, start_timestamp: 0 });
      expect(currentTraceId()).toBeNull();
    });
  });

  // ─── traceparent ──────────────────────────────────────────────────
  describe("traceparent", () => {
    it("returns empty object when no active span", () => {
      mockGetActiveSpan.mockReturnValue(undefined);
      expect(traceparent()).toEqual({});
    });

    it("emits sentry-trace + baggage headers when span is active", () => {
      mockGetActiveSpan.mockReturnValue(mockSpan);
      mockSpanToTraceHeader.mockReturnValue("abc-def-1");
      mockSpanToBaggageHeader.mockReturnValue("sentry-environment=staging");
      expect(traceparent()).toEqual({
        "sentry-trace": "abc-def-1",
        baggage: "sentry-environment=staging",
      });
    });

    it("omits header keys when their values are empty/undefined", () => {
      mockGetActiveSpan.mockReturnValue(mockSpan);
      mockSpanToTraceHeader.mockReturnValue(undefined);
      mockSpanToBaggageHeader.mockReturnValue("sentry-environment=prod");
      expect(traceparent()).toEqual({ baggage: "sentry-environment=prod" });
    });

    it("returns empty when Sentry throws", () => {
      mockGetActiveSpan.mockImplementation(() => {
        throw new Error("nope");
      });
      expect(traceparent()).toEqual({});
    });
  });

  // ─── continueTraceFromRequest ─────────────────────────────────────
  describe("continueTraceFromRequest", () => {
    it("reads sentry-trace + baggage from Headers-like object", () => {
      const headers = new Headers({
        "sentry-trace": "abc-def-1",
        baggage: "sentry-environment=prod",
      });
      mockContinueTrace.mockImplementation((_h, cb) => cb());
      const result = continueTraceFromRequest(headers, () => "ok");
      expect(mockContinueTrace).toHaveBeenCalledWith(
        { sentryTrace: "abc-def-1", baggage: "sentry-environment=prod" },
        expect.any(Function),
      );
      expect(result).toBe("ok");
    });

    it("reads from plain object headers (Edge runtime IncomingHttpHeaders shape)", () => {
      mockContinueTrace.mockImplementation((_h, cb) => cb());
      continueTraceFromRequest(
        { "sentry-trace": "x-y-1", baggage: ["foo=bar"] },
        () => "ok",
      );
      expect(mockContinueTrace).toHaveBeenCalledWith(
        { sentryTrace: "x-y-1", baggage: "foo=bar" },
        expect.any(Function),
      );
    });

    it("passes undefined when headers absent", () => {
      mockContinueTrace.mockImplementation((_h, cb) => cb());
      continueTraceFromRequest(new Headers(), () => "ok");
      expect(mockContinueTrace).toHaveBeenCalledWith(
        { sentryTrace: undefined, baggage: undefined },
        expect.any(Function),
      );
    });
  });
});
