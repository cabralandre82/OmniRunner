/**
 * Tests for L13-07 — webhook IP allow-list.
 */

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { NextRequest } from "next/server";
import {
  parseAllowlist,
  isAllowed,
  extractRequestIp,
  enforceWebhookIpAllowlist,
  _resetWebhookIpAllowlistForTests,
} from "./webhook-ip-allowlist";

const ENV_VAR = "PAYMENT_GATEWAY_IPS_ALLOWLIST";
const NODE_ENV_VAR = "NODE_ENV";

function makeRequest(opts: {
  ip?: string;
  forwardedFor?: string;
  realIp?: string;
} = {}): NextRequest {
  const headers = new Headers();
  if (opts.forwardedFor) headers.set("x-forwarded-for", opts.forwardedFor);
  if (opts.realIp) headers.set("x-real-ip", opts.realIp);

  const req = new NextRequest("https://example.com/api/custody/webhook", {
    headers,
  });

  if (opts.ip !== undefined) {
    Object.defineProperty(req, "ip", {
      value: opts.ip,
      configurable: true,
    });
  }
  return req;
}

const originalEnv = { ...process.env };

beforeEach(() => {
  _resetWebhookIpAllowlistForTests();
});

afterEach(() => {
  process.env = { ...originalEnv };
  _resetWebhookIpAllowlistForTests();
});

describe("parseAllowlist", () => {
  it("returns empty array for undefined / empty input", () => {
    expect(parseAllowlist(undefined)).toEqual([]);
    expect(parseAllowlist("")).toEqual([]);
    expect(parseAllowlist("   ")).toEqual([]);
  });

  it("parses literal IPv4 addresses", () => {
    const entries = parseAllowlist("3.18.12.63, 54.241.31.99");
    expect(entries).toHaveLength(2);
    expect(entries.every((e) => e.kind === "ipv4")).toBe(true);
  });

  it("parses IPv4 CIDR ranges", () => {
    const entries = parseAllowlist("10.0.0.0/24, 172.16.0.0/12");
    expect(entries).toHaveLength(2);
    expect(entries[0]).toMatchObject({ kind: "ipv4-cidr", bits: 24 });
    expect(entries[1]).toMatchObject({ kind: "ipv4-cidr", bits: 12 });
  });

  it("parses IPv6 addresses (case-insensitive)", () => {
    const entries = parseAllowlist("2001:DB8::1, ::1");
    expect(entries).toHaveLength(2);
    expect(entries[0]).toMatchObject({ kind: "ipv6", canonical: "2001:db8::1" });
    expect(entries[1]).toMatchObject({ kind: "ipv6", canonical: "::1" });
  });

  it("silently drops malformed entries", () => {
    const entries = parseAllowlist("notanip, 999.999.999.999, 10.0.0.0/40, ");
    expect(entries).toEqual([]);
  });

  it("computes the correct CIDR network mask", () => {
    const [entry] = parseAllowlist("192.168.1.42/24");
    expect(entry).toMatchObject({ kind: "ipv4-cidr", bits: 24 });
    if (entry.kind === "ipv4-cidr") {
      // 192.168.1.0
      expect(entry.network).toBe(((192 << 24) | (168 << 16) | (1 << 8)) >>> 0);
      expect(entry.mask).toBe(0xffffff00);
    }
  });
});

describe("isAllowed", () => {
  it("returns false when IP is null/undefined", () => {
    const entries = parseAllowlist("10.0.0.1");
    expect(isAllowed(null, entries)).toBe(false);
    expect(isAllowed(undefined, entries)).toBe(false);
    expect(isAllowed("", entries)).toBe(false);
  });

  it("matches an exact literal IPv4 entry", () => {
    const entries = parseAllowlist("3.18.12.63");
    expect(isAllowed("3.18.12.63", entries)).toBe(true);
    expect(isAllowed("3.18.12.64", entries)).toBe(false);
  });

  it("matches inside a CIDR range", () => {
    const entries = parseAllowlist("10.0.0.0/24");
    expect(isAllowed("10.0.0.1", entries)).toBe(true);
    expect(isAllowed("10.0.0.255", entries)).toBe(true);
    expect(isAllowed("10.0.1.0", entries)).toBe(false);
  });

  it("handles /0 and /32 edge cases", () => {
    const allEntries = parseAllowlist("0.0.0.0/0");
    expect(isAllowed("8.8.8.8", allEntries)).toBe(true);
    expect(isAllowed("1.2.3.4", allEntries)).toBe(true);

    const singleEntry = parseAllowlist("1.2.3.4/32");
    expect(isAllowed("1.2.3.4", singleEntry)).toBe(true);
    expect(isAllowed("1.2.3.5", singleEntry)).toBe(false);
  });

  it("matches IPv6 by canonical lower-case form", () => {
    const entries = parseAllowlist("2001:DB8::1");
    expect(isAllowed("2001:db8::1", entries)).toBe(true);
    expect(isAllowed("2001:DB8::1", entries)).toBe(true);
    expect(isAllowed("2001:db8::2", entries)).toBe(false);
  });

  it("never matches when allow-list contains only v4 and request is v6", () => {
    const entries = parseAllowlist("10.0.0.0/8");
    expect(isAllowed("::1", entries)).toBe(false);
  });
});

describe("extractRequestIp", () => {
  it("prefers request.ip when present", () => {
    const req = makeRequest({
      ip: "1.1.1.1",
      forwardedFor: "2.2.2.2",
      realIp: "3.3.3.3",
    });
    expect(extractRequestIp(req)).toBe("1.1.1.1");
  });

  it("falls back to first hop of x-forwarded-for", () => {
    const req = makeRequest({ forwardedFor: "4.4.4.4, 5.5.5.5, 6.6.6.6" });
    expect(extractRequestIp(req)).toBe("4.4.4.4");
  });

  it("falls back to x-real-ip when XFF is absent", () => {
    const req = makeRequest({ realIp: "7.7.7.7" });
    expect(extractRequestIp(req)).toBe("7.7.7.7");
  });

  it("strips IPv4:port suffixes", () => {
    const req = makeRequest({ forwardedFor: "8.8.8.8:55012" });
    expect(extractRequestIp(req)).toBe("8.8.8.8");
  });

  it("strips IPv6 brackets when port is present", () => {
    const req = makeRequest({ forwardedFor: "[::1]:55012" });
    expect(extractRequestIp(req)).toBe("::1");
  });

  it("returns null when no IP header is present", () => {
    const req = makeRequest();
    expect(extractRequestIp(req)).toBeNull();
  });
});

describe("enforceWebhookIpAllowlist", () => {
  it("passes through (returns null) when env var is unset", () => {
    delete process.env[ENV_VAR];
    process.env[NODE_ENV_VAR] = "test";
    const req = makeRequest({ ip: "8.8.8.8" });
    expect(enforceWebhookIpAllowlist(req)).toBeNull();
  });

  it("passes through (returns null) when env var is empty", () => {
    process.env[ENV_VAR] = "";
    const req = makeRequest({ ip: "8.8.8.8" });
    expect(enforceWebhookIpAllowlist(req)).toBeNull();
  });

  it("returns 403 when source IP is not allow-listed", async () => {
    process.env[ENV_VAR] = "10.0.0.0/24";
    const req = makeRequest({ ip: "8.8.8.8" });
    const res = enforceWebhookIpAllowlist(req);
    expect(res).not.toBeNull();
    expect(res!.status).toBe(403);
    expect(await res!.json()).toEqual({ error: "Forbidden" });
  });

  it("returns null (allow) when source IP matches a CIDR entry", () => {
    process.env[ENV_VAR] = "10.0.0.0/24";
    const req = makeRequest({ ip: "10.0.0.42" });
    expect(enforceWebhookIpAllowlist(req)).toBeNull();
  });

  it("returns null (allow) when source IP matches a literal entry via XFF", () => {
    process.env[ENV_VAR] = "1.2.3.4, 5.6.7.8";
    const req = makeRequest({ forwardedFor: "5.6.7.8, 9.9.9.9" });
    expect(enforceWebhookIpAllowlist(req)).toBeNull();
  });

  it("rejects when no IP can be extracted at all", () => {
    process.env[ENV_VAR] = "1.2.3.4";
    const req = makeRequest();
    const res = enforceWebhookIpAllowlist(req);
    expect(res).not.toBeNull();
    expect(res!.status).toBe(403);
  });
});
