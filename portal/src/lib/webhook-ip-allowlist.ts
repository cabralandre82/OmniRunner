/**
 * Webhook IP allow-list (L13-07).
 *
 * Defence-in-depth for `/api/custody/webhook`. The route handler itself
 * already verifies HMAC signatures (Stripe / Mercado Pago); this module
 * adds an opt-in network-layer filter so only well-known gateway IP
 * ranges can even reach the handler.
 *
 * Configuration: set the env var `PAYMENT_GATEWAY_IPS_ALLOWLIST` to a
 * comma-separated list of literal IPv4 / IPv6 addresses or IPv4 CIDR
 * ranges. Examples:
 *
 *   PAYMENT_GATEWAY_IPS_ALLOWLIST="3.18.12.63,3.130.192.231"
 *   PAYMENT_GATEWAY_IPS_ALLOWLIST="54.241.31.99/24,209.225.49.0/24"
 *
 * Behaviour:
 *   - When the env var is unset OR empty, the allow-list is **disabled**
 *     (returns `null` for every request). A one-time warning is logged
 *     in production so operators are not surprised. We deliberately do
 *     NOT fail-closed here: the HMAC check at the handler is the real
 *     defence, and fail-closed on missing config would create an
 *     incident-shaped foot-gun whenever the env var disappears.
 *   - When the env var is set, requests whose source IP does not match
 *     any entry get a 403 with `Forbidden` body. Match is exact for
 *     literal IPs, CIDR-aware for `<v4>/<prefix>` entries.
 *   - We only parse / process the allow-list once per process; a tiny
 *     LRU around `parseAllowlist` is unnecessary because the result is
 *     a single readonly array.
 */

import { NextResponse, type NextRequest } from "next/server";

const ENV_VAR = "PAYMENT_GATEWAY_IPS_ALLOWLIST";

/**
 * Internal representation of one allow-list entry.
 *   - `kind: "ipv4"` — exact 32-bit match.
 *   - `kind: "ipv4-cidr"` — match against `network & mask`.
 *   - `kind: "ipv6"` — exact text match (lower-cased + collapsed).
 */
type AllowlistEntry =
  | { kind: "ipv4"; value: number }
  | { kind: "ipv4-cidr"; network: number; mask: number; bits: number }
  | { kind: "ipv6"; canonical: string };

let cachedRaw: string | undefined;
let cachedEntries: readonly AllowlistEntry[] | null = null;
let warnedEmpty = false;

export function _resetWebhookIpAllowlistForTests(): void {
  cachedRaw = undefined;
  cachedEntries = null;
  warnedEmpty = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Parsing
// ─────────────────────────────────────────────────────────────────────────────

function parseIpv4(text: string): number | null {
  const parts = text.split(".");
  if (parts.length !== 4) return null;
  let acc = 0;
  for (const p of parts) {
    if (!/^\d{1,3}$/.test(p)) return null;
    const n = Number(p);
    if (n < 0 || n > 255) return null;
    acc = (acc << 8) >>> 0;
    acc = (acc | n) >>> 0;
  }
  return acc >>> 0;
}

function canonicalIpv6(text: string): string | null {
  if (!text.includes(":")) return null;
  // Permissive normalisation: lower-case + strip surrounding brackets +
  // collapse multiple `::`. We do NOT attempt full RFC 5952 canonical
  // form; we just want exact-match equality between configured and
  // observed strings.
  const lower = text.toLowerCase().replace(/^\[|\]$/g, "");
  if (!/^[0-9a-f:]+$/.test(lower)) return null;
  return lower;
}

function parseEntry(rawEntry: string): AllowlistEntry | null {
  const trimmed = rawEntry.trim();
  if (!trimmed) return null;

  if (trimmed.includes("/")) {
    const [addr, prefixStr] = trimmed.split("/", 2);
    const ip = parseIpv4(addr);
    if (ip === null) return null;
    if (!/^\d{1,2}$/.test(prefixStr)) return null;
    const bits = Number(prefixStr);
    if (bits < 0 || bits > 32) return null;
    const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
    const network = (ip & mask) >>> 0;
    return { kind: "ipv4-cidr", network, mask, bits };
  }

  const v4 = parseIpv4(trimmed);
  if (v4 !== null) return { kind: "ipv4", value: v4 };

  const v6 = canonicalIpv6(trimmed);
  if (v6 !== null) return { kind: "ipv6", canonical: v6 };

  return null;
}

export function parseAllowlist(raw: string | undefined): readonly AllowlistEntry[] {
  if (!raw) return [];
  const out: AllowlistEntry[] = [];
  for (const piece of raw.split(",")) {
    const entry = parseEntry(piece);
    if (entry) out.push(entry);
  }
  return out;
}

function readEntries(): readonly AllowlistEntry[] {
  const raw = process.env[ENV_VAR];
  if (raw === cachedRaw && cachedEntries !== null) return cachedEntries;
  cachedRaw = raw;
  cachedEntries = parseAllowlist(raw);
  return cachedEntries;
}

// ─────────────────────────────────────────────────────────────────────────────
// Matching
// ─────────────────────────────────────────────────────────────────────────────

export function isAllowed(
  ip: string | null | undefined,
  entries: readonly AllowlistEntry[],
): boolean {
  if (!ip) return false;

  const v4 = parseIpv4(ip);
  if (v4 !== null) {
    for (const entry of entries) {
      if (entry.kind === "ipv4" && entry.value === v4) return true;
      if (
        entry.kind === "ipv4-cidr" &&
        ((v4 & entry.mask) >>> 0) === entry.network
      ) {
        return true;
      }
    }
    return false;
  }

  const v6 = canonicalIpv6(ip);
  if (v6 !== null) {
    for (const entry of entries) {
      if (entry.kind === "ipv6" && entry.canonical === v6) return true;
    }
    return false;
  }

  return false;
}

/**
 * Pull the source IP from a Next.js request. Order of preference:
 *   1. `request.ip` (populated by Vercel + Edge runtime).
 *   2. First entry of `x-forwarded-for` (set by the platform proxy).
 *   3. `x-real-ip` (set by some self-hosted reverse proxies).
 *
 * Anything trailing whitespace or port suffixes is trimmed.
 */
export function extractRequestIp(request: NextRequest): string | null {
  const reqIp = (request as unknown as { ip?: string | null }).ip;
  if (reqIp) return reqIp.trim();

  const xff = request.headers.get("x-forwarded-for");
  if (xff) {
    const first = xff.split(",")[0]?.trim();
    if (first) return stripPort(first);
  }

  const real = request.headers.get("x-real-ip");
  if (real) return stripPort(real.trim());

  return null;
}

function stripPort(addr: string): string {
  // Strip trailing `:port` from IPv4. Bracketed IPv6 (`[::1]:port`) gets
  // its brackets removed too. Bare IPv6 addresses contain colons, so we
  // leave them alone unless they are bracketed.
  if (addr.startsWith("[")) {
    const idx = addr.indexOf("]");
    return idx === -1 ? addr : addr.slice(1, idx);
  }
  if (addr.includes(":") && !addr.includes("::") && addr.split(":").length === 2) {
    return addr.split(":")[0];
  }
  return addr;
}

// ─────────────────────────────────────────────────────────────────────────────
// Middleware glue
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Enforce the allow-list against a Next.js request. Returns a 403
 * `NextResponse` if the request must be rejected, or `null` if it
 * should be passed through (either because the allow-list is disabled
 * or because the source IP matches).
 *
 * Logging is intentionally minimal: a single warning the first time we
 * observe an unset env var in production. Per-request denials are
 * counted by the upstream metrics layer (custody.webhook.* metrics).
 */
export function enforceWebhookIpAllowlist(
  request: NextRequest,
): NextResponse | null {
  const entries = readEntries();
  if (entries.length === 0) {
    if (!warnedEmpty && process.env.NODE_ENV === "production") {
      warnedEmpty = true;
      // eslint-disable-next-line no-console
      console.warn(
        `[webhook-ip-allowlist] ${ENV_VAR} not set; payment-gateway ` +
          "webhook is reachable from any IP. HMAC signature is the only " +
          "remaining defence.",
      );
    }
    return null;
  }

  const ip = extractRequestIp(request);
  if (isAllowed(ip, entries)) return null;

  return NextResponse.json({ error: "Forbidden" }, { status: 403 });
}
