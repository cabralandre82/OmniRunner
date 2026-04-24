import { describe, expect, it } from "vitest";
import { stripPii } from "./sentryPii";
import type { ErrorEvent } from "@sentry/core";

function fixture(over: Partial<ErrorEvent> = {}): ErrorEvent {
  return {
    type: undefined,
    user: { id: "user-uuid", email: "alice@example.com", ip_address: "1.2.3.4" },
    request: {
      url: "https://omni.run/api/x?email=alice@example.com&token=secret",
      headers: {
        "user-agent": "ua",
        "x-request-id": "req-1",
        Authorization: "Bearer xxx",
        Cookie: "sb-access-token=...",
        "x-forwarded-for": "1.2.3.4",
        Referer: "https://omni.run/login",
      },
      cookies: { "sb-access-token": "xxx" },
      query_string: "email=alice@example.com&token=secret",
      data: { password: "hunter2" },
    },
    contexts: {
      request: { client_ip: "1.2.3.4" } as Record<string, unknown>,
    },
    ...over,
  } as ErrorEvent;
}

describe("stripPii", () => {
  it("keeps user.id and drops user.email + ip_address", () => {
    const e = stripPii(fixture());
    expect(e!.user).toEqual({ id: "user-uuid" });
  });

  it("strips Authorization / Cookie / x-forwarded-for headers", () => {
    const e = stripPii(fixture());
    expect(e!.request!.headers).not.toHaveProperty("Authorization");
    expect(e!.request!.headers).not.toHaveProperty("Cookie");
    expect(e!.request!.headers).not.toHaveProperty("x-forwarded-for");
  });

  it("retains user-agent + x-request-id + Referer for triage", () => {
    const e = stripPii(fixture());
    const headers = e!.request!.headers as Record<string, string>;
    expect(headers["user-agent"]).toBe("ua");
    expect(headers["x-request-id"]).toBe("req-1");
    // Header keys are case-preserving in Sentry's contract; allow-list
    // is case-insensitive on read.
    expect(headers["Referer"]).toBe("https://omni.run/login");
  });

  it("drops cookies, query_string and request body data", () => {
    const e = stripPii(fixture());
    expect((e!.request as Record<string, unknown>).cookies).toBeUndefined();
    expect((e!.request as Record<string, unknown>).query_string).toBeUndefined();
    expect((e!.request as Record<string, unknown>).data).toBeUndefined();
  });

  it("drops contexts.request.client_ip", () => {
    const e = stripPii(fixture());
    const reqCtx = e!.contexts!.request as Record<string, unknown>;
    expect(reqCtx.client_ip).toBeUndefined();
  });

  it("is a no-op when event is null", () => {
    expect(stripPii(null as unknown as ErrorEvent)).toBeNull();
  });

  it("does not crash when user/request/contexts are absent", () => {
    const e = stripPii({ type: undefined } as ErrorEvent);
    expect(e).toBeTruthy();
  });
});
