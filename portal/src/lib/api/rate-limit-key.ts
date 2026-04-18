/**
 * Rate-limit key derivation (L14-04).
 *
 * The previous pattern keyed every limiter on the source IP:
 *
 *   const ip = req.headers.get("x-forwarded-for") ?? "unknown";
 *   await rateLimit(`swap:${ip}`, { ... });
 *
 * That breaks for two reasons:
 *
 *   1. **CGN / mobile NAT** — thousands of legitimate users share a
 *      single egress IP. One active group exhausts the quota and
 *      blocks every other group on the same NAT pool. This was the
 *      original L14-04 motivation.
 *
 *   2. **Spoofable** — `x-forwarded-for` is honoured even when not
 *      sourced from a trusted proxy. An attacker can rotate identities
 *      cheaply and never trip the limit.
 *
 * The fix is to key on a stable, server-controlled identity in this
 * order of preference:
 *
 *   group_id  →  user_id  →  hashed-ip
 *
 * Group is preferred over user because the financial limiters
 * (swap, custody, withdraw) are protecting a *group's* throughput,
 * not a single user. When neither is available (truly anonymous
 * endpoint) we fall back to a SHA-1-prefixed IP so that an attacker
 * cannot craft a header that collides with a logged-in user's key.
 *
 * `kind` is encoded into the key (`swap:g:<id>`, `swap:u:<id>`,
 * `swap:ip:<hash>`) so:
 *
 *   - distinct identities cannot collide across the namespace
 *     (`group_id == user_id` value would have collided in the legacy
 *     key)
 *   - dashboards can group counters by identity kind
 */

import { createHash } from "crypto";
import type { NextRequest } from "next/server";

export type RateLimitIdentityKind = "group" | "user" | "ip" | "anon";

export interface RateLimitIdentity {
  kind: RateLimitIdentityKind;
  /** Already-encoded identity string (never raw IP — it's hashed). */
  value: string;
}

export interface RateLimitKeyInput {
  /** Per-route prefix (`swap`, `custody`, etc). */
  prefix: string;
  /** Group id from the resolved session, if available. */
  groupId?: string | null;
  /** User id from the resolved session, if available. */
  userId?: string | null;
  /** Source request, used for IP extraction when group/user are absent. */
  request?: NextRequest | null;
  /** Optional override IP (used by edge functions / tests). */
  ip?: string | null;
}

/**
 * Hash a raw IP into a 16-char hex slug. We do NOT key on the raw IP
 * for two reasons: it leaks PII into the rate-limit store, and an
 * attacker who can read keys (Redis breach, log injection) could not
 * easily craft a colliding `x-forwarded-for` header without knowing
 * the hash function. A truncated SHA-1 is plenty for namespacing —
 * we are not authenticating, just bucketing.
 */
export function hashIp(ip: string): string {
  return createHash("sha1").update(ip).digest("hex").slice(0, 16);
}

/**
 * Pull a usable IP from the request. Returns `null` when nothing is
 * available (which causes the key to fall back to the `anon` bucket).
 *
 * Order: explicit `request.ip` → first hop of `x-forwarded-for` →
 * `x-real-ip`. Port suffixes are stripped for IPv4; bracketed IPv6
 * has its brackets removed.
 */
export function extractRequestIp(
  request: NextRequest | null | undefined,
): string | null {
  if (!request) return null;

  const reqIp = (request as unknown as { ip?: string | null }).ip;
  if (reqIp) return reqIp.trim() || null;

  const xff = request.headers.get("x-forwarded-for");
  if (xff) {
    const first = xff.split(",")[0]?.trim();
    if (first) return stripPort(first) || null;
  }

  const real = request.headers.get("x-real-ip");
  if (real) return stripPort(real.trim()) || null;

  return null;
}

function stripPort(addr: string): string {
  if (addr.startsWith("[")) {
    const idx = addr.indexOf("]");
    return idx === -1 ? addr : addr.slice(1, idx);
  }
  if (addr.includes(":") && !addr.includes("::") && addr.split(":").length === 2) {
    return addr.split(":")[0];
  }
  return addr;
}

/**
 * Resolve the identity (kind + value) that will be used to key the
 * limiter. Pure function — no side effects, deterministic for a given
 * input. Tested directly so call-sites can build keys consistently.
 */
export function resolveIdentity(input: RateLimitKeyInput): RateLimitIdentity {
  if (input.groupId) return { kind: "group", value: input.groupId };
  if (input.userId) return { kind: "user", value: input.userId };

  const ip = input.ip ?? extractRequestIp(input.request);
  if (ip) return { kind: "ip", value: hashIp(ip) };

  return { kind: "anon", value: "unknown" };
}

const KIND_TO_NAMESPACE: Record<RateLimitIdentityKind, string> = {
  group: "g",
  user: "u",
  ip: "ip",
  anon: "anon",
};

/**
 * Build the final string key passed to `rateLimit()`.
 *
 * Examples:
 *   rateLimitKey({ prefix: "swap", groupId: "abc" })   → "swap:g:abc"
 *   rateLimitKey({ prefix: "custody", userId: "u-1" }) → "custody:u:u-1"
 *   rateLimitKey({ prefix: "swap", request })          → "swap:ip:<sha1>"
 *   rateLimitKey({ prefix: "swap" })                   → "swap:anon:unknown"
 */
export function rateLimitKey(input: RateLimitKeyInput): string {
  const id = resolveIdentity(input);
  const ns = KIND_TO_NAMESPACE[id.kind];
  return `${input.prefix}:${ns}:${id.value}`;
}
