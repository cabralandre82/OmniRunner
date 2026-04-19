import { describe, it, expect, beforeEach, vi } from "vitest";
import { NextRequest } from "next/server";
import {
  POST,
  parseCspReportPayload,
  __resetRateLimitForTests,
} from "./route";

vi.mock("@sentry/nextjs", () => ({
  captureMessage: vi.fn(),
}));
import * as Sentry from "@sentry/nextjs";

vi.mock("@/lib/logger", () => ({
  logger: {
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));
import { logger } from "@/lib/logger";

function makeRequest(body: string, contentType = "application/csp-report") {
  return new NextRequest("https://portal.test/api/csp-report", {
    method: "POST",
    headers: {
      "content-type": contentType,
      "user-agent": "vitest/csp",
    },
    body,
  });
}

beforeEach(() => {
  __resetRateLimitForTests();
  vi.clearAllMocks();
});

describe("POST /api/csp-report — L10-05", () => {
  it("always responds 204 (no leakage of internal state)", async () => {
    const res = await POST(
      makeRequest(
        JSON.stringify({
          "csp-report": {
            "document-uri": "https://portal.test/",
            "violated-directive": "script-src",
            "blocked-uri": "inline",
          },
        }),
      ),
    );
    expect(res.status).toBe(204);
  });

  it("responds 204 even when the body is not valid JSON", async () => {
    const res = await POST(makeRequest("not-json{"));
    expect(res.status).toBe(204);
  });

  it("responds 204 on an empty body", async () => {
    const res = await POST(makeRequest(""));
    expect(res.status).toBe(204);
  });

  it("rejects payloads larger than 8 KiB and emits an oversize warning", async () => {
    const huge = "x".repeat(8 * 1024 + 1);
    const res = await POST(makeRequest(huge));
    expect(res.status).toBe(204);
    expect(logger.warn).toHaveBeenCalledWith(
      "csp.report.oversize",
      expect.objectContaining({ bytes: 8 * 1024 + 1 }),
    );
  });

  it("rate-limits to 60 reports per process per 60 s window", async () => {
    const body = JSON.stringify({
      "csp-report": {
        "document-uri": "https://portal.test/",
        "violated-directive": "img-src",
        "blocked-uri": "https://evil.test/",
      },
    });
    for (let i = 0; i < 60; i++) {
      await POST(makeRequest(body));
    }
    const infoCallsBefore = (logger.info as unknown as { mock: { calls: unknown[] } }).mock.calls.length;
    // Burst past the cap — these should be silently dropped, not logged.
    await POST(makeRequest(body));
    await POST(makeRequest(body));
    const infoCallsAfter = (logger.info as unknown as { mock: { calls: unknown[] } }).mock.calls.length;
    expect(infoCallsAfter).toBe(infoCallsBefore);
  });
});

describe("CSP report severity routing", () => {
  it("classifies script-src violations as high severity → Sentry capture", async () => {
    await POST(
      makeRequest(
        JSON.stringify({
          "csp-report": {
            "document-uri": "https://portal.test/",
            "violated-directive": "script-src 'self' 'nonce-XYZ'",
            "effective-directive": "script-src",
            "blocked-uri": "inline",
            "source-file": "https://portal.test/page",
            "line-number": 42,
          },
        }),
      ),
    );
    expect(logger.warn).toHaveBeenCalledWith(
      "csp.violation.script_src",
      expect.objectContaining({
        violated_directive: expect.stringContaining("script-src"),
      }),
    );
    expect(Sentry.captureMessage).toHaveBeenCalledWith(
      "CSP violation: script-src",
      expect.objectContaining({
        level: "warning",
        tags: expect.objectContaining({
          csp_directive: expect.any(String),
          csp_blocked_uri: expect.any(String),
        }),
      }),
    );
  });

  it("classifies non-script violations as info-only (no Sentry capture)", async () => {
    await POST(
      makeRequest(
        JSON.stringify({
          "csp-report": {
            "document-uri": "https://portal.test/",
            "violated-directive": "img-src 'self' data:",
            "effective-directive": "img-src",
            "blocked-uri": "https://evil.test/spy.png",
          },
        }),
      ),
    );
    expect(logger.info).toHaveBeenCalledWith(
      "csp.violation",
      expect.objectContaining({
        effective_directive: "img-src",
      }),
    );
    expect(Sentry.captureMessage).not.toHaveBeenCalled();
  });

  it("treats script-src-elem and script-src-attr as high severity too", async () => {
    for (const directive of ["script-src-elem", "script-src-attr"]) {
      __resetRateLimitForTests();
      vi.clearAllMocks();
      await POST(
        makeRequest(
          JSON.stringify({
            "csp-report": {
              "document-uri": "https://portal.test/",
              "violated-directive": directive,
              "effective-directive": directive,
              "blocked-uri": "inline",
            },
          }),
        ),
      );
      expect(Sentry.captureMessage).toHaveBeenCalled();
    }
  });
});

describe("parseCspReportPayload — shape normalisation", () => {
  it("parses the legacy `report-uri` shape into a single normalised entry", () => {
    const out = parseCspReportPayload({
      "csp-report": {
        "document-uri": "https://portal.test/login",
        "violated-directive": "script-src 'self'",
        "effective-directive": "script-src",
        "blocked-uri": "inline",
        "source-file": "https://portal.test/page.js",
        "line-number": 17,
        "column-number": 3,
        "status-code": 200,
        disposition: "enforce",
      },
    });
    expect(out).toHaveLength(1);
    expect(out[0]).toEqual({
      document_uri: "https://portal.test/login",
      blocked_uri: "inline",
      violated_directive: "script-src 'self'",
      effective_directive: "script-src",
      original_policy: null,
      source_file: "https://portal.test/page.js",
      line_number: 17,
      column_number: 3,
      status_code: 200,
      disposition: "enforce",
      referrer: null,
    });
  });

  it("parses the modern `report-to` array shape (Chromium)", () => {
    const out = parseCspReportPayload([
      {
        type: "csp-violation",
        body: {
          documentURL: "https://portal.test/dashboard",
          effectiveDirective: "script-src",
          blockedURL: "https://evil.test/x.js",
          sourceFile: "https://portal.test/page.js",
          lineNumber: 99,
          columnNumber: 1,
          disposition: "enforce",
        },
      },
    ]);
    expect(out).toHaveLength(1);
    expect(out[0].document_uri).toBe("https://portal.test/dashboard");
    expect(out[0].effective_directive).toBe("script-src");
    expect(out[0].blocked_uri).toBe("https://evil.test/x.js");
    expect(out[0].line_number).toBe(99);
  });

  it("returns an empty array for unrecognised shapes", () => {
    expect(parseCspReportPayload({})).toEqual([]);
    expect(parseCspReportPayload(null)).toEqual([]);
    expect(parseCspReportPayload("string")).toEqual([]);
    expect(parseCspReportPayload(42)).toEqual([]);
  });

  it("treats missing inner body fields as null (no NaN / undefined)", () => {
    const out = parseCspReportPayload({
      "csp-report": {
        "document-uri": "https://portal.test/",
      },
    });
    expect(out[0].violated_directive).toBeNull();
    expect(out[0].line_number).toBeNull();
    expect(out[0].status_code).toBeNull();
  });

  it("handles batched modern reports (more than one violation per request)", () => {
    const out = parseCspReportPayload([
      {
        type: "csp-violation",
        body: {
          documentURL: "a",
          effectiveDirective: "script-src",
          blockedURL: "x",
        },
      },
      {
        type: "csp-violation",
        body: {
          documentURL: "b",
          effectiveDirective: "img-src",
          blockedURL: "y",
        },
      },
    ]);
    expect(out).toHaveLength(2);
    expect(out[0].document_uri).toBe("a");
    expect(out[1].document_uri).toBe("b");
  });
});
