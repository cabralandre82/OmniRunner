/**
 * Tests for L14-04 — rate-limit identity / key derivation.
 */

import { describe, it, expect } from "vitest";
import { NextRequest } from "next/server";
import {
  hashIp,
  extractRequestIp,
  resolveIdentity,
  rateLimitKey,
} from "./rate-limit-key";

function makeRequest(opts: {
  ip?: string;
  forwardedFor?: string;
  realIp?: string;
} = {}): NextRequest {
  const headers = new Headers();
  if (opts.forwardedFor) headers.set("x-forwarded-for", opts.forwardedFor);
  if (opts.realIp) headers.set("x-real-ip", opts.realIp);
  const req = new NextRequest("https://example.com/api/x", { headers });
  if (opts.ip !== undefined) {
    Object.defineProperty(req, "ip", { value: opts.ip, configurable: true });
  }
  return req;
}

describe("hashIp", () => {
  it("returns a 16-char hex slug", () => {
    const slug = hashIp("203.0.113.5");
    expect(slug).toMatch(/^[0-9a-f]{16}$/);
  });

  it("is deterministic for the same input", () => {
    expect(hashIp("8.8.8.8")).toBe(hashIp("8.8.8.8"));
  });

  it("produces different slugs for different IPs", () => {
    expect(hashIp("8.8.8.8")).not.toBe(hashIp("8.8.4.4"));
  });
});

describe("extractRequestIp", () => {
  it("returns null when no source has an IP", () => {
    expect(extractRequestIp(makeRequest())).toBeNull();
    expect(extractRequestIp(null)).toBeNull();
    expect(extractRequestIp(undefined)).toBeNull();
  });

  it("prefers request.ip", () => {
    const req = makeRequest({
      ip: "1.1.1.1",
      forwardedFor: "2.2.2.2",
      realIp: "3.3.3.3",
    });
    expect(extractRequestIp(req)).toBe("1.1.1.1");
  });

  it("falls back to first XFF hop", () => {
    const req = makeRequest({ forwardedFor: "5.5.5.5, 6.6.6.6" });
    expect(extractRequestIp(req)).toBe("5.5.5.5");
  });

  it("falls back to x-real-ip", () => {
    expect(extractRequestIp(makeRequest({ realIp: "9.9.9.9" }))).toBe(
      "9.9.9.9",
    );
  });

  it("strips IPv4:port suffixes", () => {
    expect(
      extractRequestIp(makeRequest({ forwardedFor: "8.8.8.8:55012" })),
    ).toBe("8.8.8.8");
  });

  it("strips brackets from bracketed IPv6", () => {
    expect(extractRequestIp(makeRequest({ forwardedFor: "[::1]:8080" }))).toBe(
      "::1",
    );
  });
});

describe("resolveIdentity precedence", () => {
  it("group_id wins over everything else", () => {
    const id = resolveIdentity({
      prefix: "x",
      groupId: "G",
      userId: "U",
      ip: "1.1.1.1",
    });
    expect(id).toEqual({ kind: "group", value: "G" });
  });

  it("user_id wins when group is absent", () => {
    const id = resolveIdentity({
      prefix: "x",
      userId: "U",
      ip: "1.1.1.1",
    });
    expect(id).toEqual({ kind: "user", value: "U" });
  });

  it("falls back to hashed IP when group + user absent", () => {
    const id = resolveIdentity({ prefix: "x", ip: "203.0.113.5" });
    expect(id.kind).toBe("ip");
    expect(id.value).toBe(hashIp("203.0.113.5"));
  });

  it("uses anon bucket when nothing is available", () => {
    const id = resolveIdentity({ prefix: "x" });
    expect(id).toEqual({ kind: "anon", value: "unknown" });
  });

  it("treats null/empty group/user as absent", () => {
    expect(
      resolveIdentity({
        prefix: "x",
        groupId: null,
        userId: "",
        ip: "1.2.3.4",
      }).kind,
    ).toBe("ip");
  });

  it("uses request.ip when explicit ip is absent", () => {
    const req = makeRequest({ ip: "4.4.4.4" });
    const id = resolveIdentity({ prefix: "x", request: req });
    expect(id.kind).toBe("ip");
    expect(id.value).toBe(hashIp("4.4.4.4"));
  });
});

describe("rateLimitKey", () => {
  it("formats group keys as <prefix>:g:<id>", () => {
    expect(rateLimitKey({ prefix: "swap", groupId: "abc" })).toBe(
      "swap:g:abc",
    );
  });

  it("formats user keys as <prefix>:u:<id>", () => {
    expect(rateLimitKey({ prefix: "custody", userId: "uid-1" })).toBe(
      "custody:u:uid-1",
    );
  });

  it("formats ip keys as <prefix>:ip:<sha1-16>", () => {
    const key = rateLimitKey({ prefix: "swap", ip: "8.8.8.8" });
    expect(key).toMatch(/^swap:ip:[0-9a-f]{16}$/);
  });

  it("formats anon keys as <prefix>:anon:unknown", () => {
    expect(rateLimitKey({ prefix: "swap" })).toBe("swap:anon:unknown");
  });

  it("namespaces prevent collision across identity kinds (legacy bug)", () => {
    // Before the fix, `swap:abc` could mean either a group_id or a
    // raw IP. The namespace separator (`:g:` vs `:ip:`) makes the
    // collision impossible.
    const groupKey = rateLimitKey({ prefix: "swap", groupId: "abc" });
    const ipKey = rateLimitKey({ prefix: "swap", ip: "abc" });
    expect(groupKey).not.toBe(ipKey);
  });

  it("never includes the raw IP in the key (PII hygiene)", () => {
    const key = rateLimitKey({ prefix: "swap", ip: "203.0.113.5" });
    expect(key).not.toContain("203.0.113.5");
  });
});
