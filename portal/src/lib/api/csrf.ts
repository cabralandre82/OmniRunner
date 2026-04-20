/**
 * CSRF double-submit token (L01-06) + origin pinning (L17-06).
 *
 * Why double-submit + sameSite=strict + origin-pinning together?
 *
 *   `portalCookieOptions()` already sets `sameSite: "strict"` for
 *   `portal_group_id` / `portal_role` (L01-06 first layer), which kills
 *   the lax-cookie top-level navigation CSRF vector. This module adds
 *   the SECOND layer of defence: even if a future cookie change, a
 *   browser bug, or a misconfigured proxy weakens SameSite enforcement,
 *   any state-changing request to a CSRF-gated endpoint must still
 *   carry an `x-csrf-token` header that matches the `portal_csrf`
 *   cookie. The cookie is non-`httpOnly` (so client JS can read it)
 *   but is `sameSite: "strict"` itself (so it never crosses origins),
 *   and it's bound to the user's session lifetime — rotating on
 *   sign-out and on every fresh middleware-issued response that
 *   doesn't see one.
 *
 *   L17-06 closed the audit gap "csrfCheck not invoked from middleware"
 *   by adding a THIRD, complementary layer that protects EVERY
 *   `/api/*` mutating route by default (allow-list-by-exception):
 *   `verifyOrigin` requires that the `Origin` header (or, fallback,
 *   `Referer`) matches the request's own host. Modern browsers always
 *   send `Origin` on POST/PUT/PATCH/DELETE — including from `fetch()`
 *   and form submission — so this check requires zero client changes
 *   while making cross-origin POSTs from attacker pages structurally
 *   impossible. Servers and external schedulers (webhooks, OAuth
 *   callback, cron) don't send a browser Origin and live in
 *   `CSRF_EXEMPT_PREFIXES` where authentication is HMAC / OAuth
 *   `state` / bearer token instead.
 *
 *   The combination matches the OWASP "double-submit cookie" pattern
 *   (Cheat Sheet 2024, §3.2) — cheap, stateless, and proves the
 *   request originated from a same-origin script that ran with the
 *   user's session present.
 *
 * Threat model
 *
 *   - `same-origin XSS`: NOT addressed here — an attacker who can run
 *     JS in our origin can read any cookie (incl. `portal_csrf`) and
 *     forge any header. CSP `'unsafe-inline'` removal (Lente 20) is
 *     the right mitigation for that class.
 *   - `cross-site request forgery`: addressed. A malicious page on
 *     attacker.example cannot read our `portal_csrf` cookie (browser
 *     same-origin policy on `document.cookie` for cross-site script
 *     contexts) and cannot set the `x-csrf-token` header on a
 *     simple-form POST (CORS preflight required for custom headers,
 *     and our endpoints don't echo the malicious origin in
 *     `Access-Control-Allow-Origin`).
 *   - `subdomain takeover` / cookie-on-parent-domain: NOT addressed —
 *     the cookie is `path=/` only. If we ever serve attacker-controlled
 *     content on a sibling subdomain, defence-in-depth needs HSTS +
 *     subdomain hygiene (tracked separately).
 *
 * Lifecycle
 *
 *   1. Middleware (`portal/src/middleware.ts`) runs on every request
 *      that resolves a session. After auth succeeds, if the request
 *      doesn't have a `portal_csrf` cookie, the middleware sets one
 *      with a fresh 32-byte hex value (`generateCsrfToken()`).
 *   2. Client JS reads the cookie (`document.cookie`) and adds it as
 *      the `x-csrf-token` header on state-changing requests via
 *      `csrfFetch()` from `lib/api/csrf-fetch.ts`.
 *   3. Server-side `verifyCsrf(req)` is invoked by the middleware on
 *      gated paths (POST/PUT/PATCH/DELETE on financial routes); on
 *      mismatch it returns 403 CSRF_TOKEN_INVALID before the route
 *      handler ever runs.
 *
 * Constant-time comparison
 *
 *   We hash both values with SHA-256 and compare via
 *   `node:crypto.timingSafeEqual` to prevent the trivial timing
 *   side-channel that `===` on long strings exposes.
 */

import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import type { NextRequest, NextResponse } from "next/server";

/** Cookie name carrying the CSRF token. Non-`httpOnly` by design. */
export const CSRF_COOKIE_NAME = "portal_csrf";

/** Header name the client must echo on state-changing requests. */
export const CSRF_HEADER_NAME = "x-csrf-token";

/**
 * 32 bytes (256 bits) of entropy, hex-encoded → 64 chars. Enough that
 * brute-forcing within a session lifetime (8h business day) is
 * infeasible.
 */
const TOKEN_BYTES = 32;

/** Token format we accept on the wire — exactly 64 hex chars. */
const TOKEN_REGEX = /^[a-f0-9]{64}$/;

/** HTTP methods that bypass CSRF enforcement (RFC 9110 §9.2.1 safe methods). */
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * Path prefixes that bypass CSRF enforcement entirely. Each entry has
 * a justification — when adding more, document why it's safe to skip.
 */
export const CSRF_EXEMPT_PREFIXES: readonly string[] = [
  // External payment-gateway webhooks: authenticated by HMAC signature
  // verified inside the route handler (Asaas + Stripe). These callers
  // are servers, not browsers, so cookie-based CSRF doesn't apply.
  "/api/custody/webhook",
  "/api/billing/asaas",
  // OAuth callback: the "request" is initiated by the IdP redirect
  // and the security model is the OAuth `state` parameter, not a
  // browser-issued CSRF token.
  "/api/auth/callback",
  // Cron endpoints (L02-10): authenticated by `Authorization: Bearer
  // ${CRON_SECRET}` constant-time compare inside each route handler.
  // External schedulers (Vercel Cron, GitHub Actions, in-DB pg_cron
  // via pg_net) have no browser cookie store.
  "/api/cron",
  // CSP violation reports (L01-38, L10-05): browsers POST these
  // WITHOUT cookies, often with `Origin: null` (sandboxed contexts) or
  // `application/csp-report`/`application/reports+json` content-types.
  // The endpoint is rate-limited and capped at 8 KiB inside the route;
  // it cannot mutate state.
  "/api/csp-report",
  // Liveness/health probes hit by external uptime monitors (BetterUp,
  // Vercel pings, k8s probes). They do not mutate state and the
  // handlers reject anything but GET.
  "/api/liveness",
  "/api/health",
];

/**
 * Path prefixes that REQUIRE a CSRF token on non-safe methods.
 *
 * The list is closed (allow-list) rather than open (block-list) so a
 * developer adding a new financial route MUST opt in explicitly,
 * making the security posture obvious in code review. Today the set
 * mirrors the financial mutation surface called out by L01-06 plus
 * the new platform-admin custody endpoints from L02-06.
 */
export const CSRF_PROTECTED_PREFIXES: readonly string[] = [
  "/api/custody/withdraw",
  "/api/custody",
  "/api/swap",
  "/api/clearing",
  "/api/distribute-coins",
  "/api/platform/custody",
  "/api/platform/feature-flags",
  "/api/platform/fees",
  "/api/platform/refunds",
];

/** Generate a fresh CSRF token (64 hex chars). */
export function generateCsrfToken(): string {
  return randomBytes(TOKEN_BYTES).toString("hex");
}

/** Validate that a string looks like a CSRF token we'd issue. */
export function isWellFormedCsrfToken(value: unknown): value is string {
  return typeof value === "string" && TOKEN_REGEX.test(value);
}

/**
 * Decide whether a request needs CSRF verification. Pure function,
 * no I/O — kept separate from `verifyCsrf` so the routing decision
 * can be unit-tested without constructing full requests.
 */
export function shouldEnforceCsrf(method: string, pathname: string): boolean {
  const upper = method.toUpperCase();
  if (SAFE_METHODS.has(upper)) return false;
  for (const exempt of CSRF_EXEMPT_PREFIXES) {
    if (pathname === exempt || pathname.startsWith(`${exempt}/`)) {
      return false;
    }
  }
  for (const protectedPrefix of CSRF_PROTECTED_PREFIXES) {
    if (
      pathname === protectedPrefix ||
      pathname.startsWith(`${protectedPrefix}/`)
    ) {
      return true;
    }
  }
  return false;
}

/**
 * Decide whether origin pinning runs (L17-06).
 *
 * Default-deny posture: every `/api/*` non-safe request gets the
 * origin check unless its prefix is in `CSRF_EXEMPT_PREFIXES`. This
 * is broader than `shouldEnforceCsrf`: the token check runs only on
 * the financial allow-list (because we control those clients and
 * they call `csrfFetch`), but origin pinning is free for every
 * client (modern browsers always send `Origin` on POST/PUT/PATCH/
 * DELETE) so we apply it everywhere it can possibly help.
 *
 * Pure function — no I/O — so the routing decision can be unit
 * tested without constructing full requests.
 */
export function shouldEnforceOrigin(method: string, pathname: string): boolean {
  const upper = method.toUpperCase();
  if (SAFE_METHODS.has(upper)) return false;
  if (!pathname.startsWith("/api/") && pathname !== "/api") return false;
  for (const exempt of CSRF_EXEMPT_PREFIXES) {
    if (pathname === exempt || pathname.startsWith(`${exempt}/`)) {
      return false;
    }
  }
  return true;
}

export type OriginVerifyResult =
  | { ok: true; matched: "origin" | "referer" }
  | {
      ok: false;
      code:
        | "ORIGIN_HOST_MISSING"
        | "ORIGIN_HEADER_MISSING"
        | "ORIGIN_NULL"
        | "ORIGIN_MALFORMED"
        | "ORIGIN_HOST_MISMATCH";
      message: string;
      observedOrigin?: string;
      requestHost?: string;
    };

/**
 * Verify that the request's `Origin` (or, fallback, `Referer`) host
 * equals the request's own host (L17-06). This is the SCHEME-AGNOSTIC
 * "is this same-origin" gate.
 *
 *   - `Origin: null` (sandbox iframes, file://) is rejected with
 *     `ORIGIN_NULL` — legitimate browser POSTs from our portal never
 *     produce this, so accepting `null` would be a tighter client
 *     fingerprint than rejecting and a wider attack surface than
 *     rejecting; the trade-off lands on rejection.
 *   - Both `Origin` AND `Referer` missing is rejected — modern
 *     browsers always send at least one on a non-safe request, so
 *     the absence of both indicates either a server-to-server caller
 *     (which should live in `CSRF_EXEMPT_PREFIXES`) or a deliberate
 *     header-strip attempt.
 *   - The request's own host comes from the `Host` header on the
 *     incoming request — Next.js Edge runtime sets this from the
 *     authoritative URL after Vercel/proxy normalisation, so it's
 *     the same host an attacker's `Origin` would have to spoof to
 *     pass.
 *   - SCHEME is intentionally NOT compared — TLS termination at the
 *     edge means the request can arrive as `http://` internally even
 *     when it left the browser as `https://`, and the audit's threat
 *     model is "attacker page in a different origin", which is a
 *     host distinction not a scheme distinction. HSTS + the `secure`
 *     cookie flag own the scheme guarantee.
 */
export function verifyOrigin(request: NextRequest): OriginVerifyResult {
  const requestHost = request.headers.get("host");
  if (!requestHost) {
    return {
      ok: false,
      code: "ORIGIN_HOST_MISSING",
      message: "Host header missing on incoming request",
    };
  }

  const origin = request.headers.get("origin");
  if (origin !== null) {
    if (origin === "null" || origin.trim() === "") {
      return {
        ok: false,
        code: "ORIGIN_NULL",
        message: "Origin: null is not allowed for state-changing requests",
        observedOrigin: origin,
        requestHost,
      };
    }
    let originHost: string;
    try {
      originHost = new URL(origin).host;
    } catch {
      return {
        ok: false,
        code: "ORIGIN_MALFORMED",
        message: "Origin header is not a valid absolute URL",
        observedOrigin: origin,
        requestHost,
      };
    }
    if (originHost !== requestHost) {
      return {
        ok: false,
        code: "ORIGIN_HOST_MISMATCH",
        message: `Origin host '${originHost}' does not match request host '${requestHost}'`,
        observedOrigin: origin,
        requestHost,
      };
    }
    return { ok: true, matched: "origin" };
  }

  // Origin absent — fall back to Referer for legacy clients that
  // strip Origin (e.g. some corporate proxies). Same host equality
  // applies. NOTE: a request that arrives with NEITHER header set is
  // either a server-to-server caller (must be in
  // `CSRF_EXEMPT_PREFIXES`) or a stripped attacker request — both
  // are correctly rejected.
  const referer = request.headers.get("referer");
  if (!referer) {
    return {
      ok: false,
      code: "ORIGIN_HEADER_MISSING",
      message: "Neither Origin nor Referer header present on state-changing request",
      requestHost,
    };
  }
  let refererHost: string;
  try {
    refererHost = new URL(referer).host;
  } catch {
    return {
      ok: false,
      code: "ORIGIN_MALFORMED",
      message: "Referer header is not a valid absolute URL",
      observedOrigin: referer,
      requestHost,
    };
  }
  if (refererHost !== requestHost) {
    return {
      ok: false,
      code: "ORIGIN_HOST_MISMATCH",
      message: `Referer host '${refererHost}' does not match request host '${requestHost}'`,
      observedOrigin: referer,
      requestHost,
    };
  }
  return { ok: true, matched: "referer" };
}

export type CsrfVerifyResult =
  | { ok: true }
  | { ok: false; code: "CSRF_COOKIE_MISSING" | "CSRF_HEADER_MISSING" | "CSRF_TOKEN_MALFORMED" | "CSRF_TOKEN_MISMATCH"; message: string };

/**
 * Verify that the `x-csrf-token` header matches the `portal_csrf`
 * cookie on the same request. Constant-time comparison via SHA-256
 * digests of both sides; the bare strings are never compared.
 *
 * Both cookie and header MUST be well-formed (64 hex). A malformed
 * value returns `CSRF_TOKEN_MALFORMED` rather than `MISMATCH` so
 * postmortem can distinguish "client sent garbage" from "cookie
 * doesn't match header" (the latter is more interesting — implies
 * either a real attack or a stale cookie after sign-out).
 */
export function verifyCsrf(request: NextRequest): CsrfVerifyResult {
  const cookieValue = request.cookies.get(CSRF_COOKIE_NAME)?.value;
  if (!cookieValue) {
    return { ok: false, code: "CSRF_COOKIE_MISSING", message: "CSRF cookie not present" };
  }
  const headerValue = request.headers.get(CSRF_HEADER_NAME);
  if (!headerValue) {
    return { ok: false, code: "CSRF_HEADER_MISSING", message: "CSRF token header not present" };
  }
  if (!isWellFormedCsrfToken(cookieValue) || !isWellFormedCsrfToken(headerValue)) {
    return { ok: false, code: "CSRF_TOKEN_MALFORMED", message: "CSRF token format invalid" };
  }
  const cookieHash = createHash("sha256").update(cookieValue).digest();
  const headerHash = createHash("sha256").update(headerValue).digest();
  if (cookieHash.length !== headerHash.length) {
    // Defensive: SHA-256 always produces 32 bytes, so this is a guard
    // against future code changes accidentally using a different hash.
    return { ok: false, code: "CSRF_TOKEN_MISMATCH", message: "CSRF token mismatch" };
  }
  return timingSafeEqual(cookieHash, headerHash)
    ? { ok: true }
    : { ok: false, code: "CSRF_TOKEN_MISMATCH", message: "CSRF token mismatch" };
}

/**
 * Issue a fresh CSRF cookie on the response if the request doesn't
 * already carry one. Idempotent — calling on an already-tokened
 * request is a no-op. Returns the token value that's now active for
 * this session (either the existing cookie or the freshly minted
 * one), useful for tests and for downstream code that wants to mirror
 * the cookie elsewhere.
 *
 * Note: the cookie is `httpOnly: false` by design — `csrfFetch`
 * (client) reads it via `document.cookie` to set the header. This is
 * the standard double-submit pattern. The token is NOT a credential
 * by itself; it only proves the request came from a script that
 * shares the user's origin.
 */
export function ensureCsrfCookie(
  request: NextRequest,
  response: NextResponse,
  opts?: { secure?: boolean; maxAgeSec?: number },
): string {
  const existing = request.cookies.get(CSRF_COOKIE_NAME)?.value;
  if (existing && isWellFormedCsrfToken(existing)) {
    return existing;
  }
  const token = generateCsrfToken();
  response.cookies.set(CSRF_COOKIE_NAME, token, {
    path: "/",
    httpOnly: false,
    sameSite: "strict",
    secure: opts?.secure ?? process.env.NODE_ENV === "production",
    maxAge: opts?.maxAgeSec ?? 60 * 60 * 8,
  });
  return token;
}

/**
 * Clear the CSRF cookie. Called on sign-out so the next session gets
 * a fresh token instead of inheriting the previous user's value.
 */
export function clearCsrfCookie(response: NextResponse, opts?: { secure?: boolean }): void {
  response.cookies.set(CSRF_COOKIE_NAME, "", {
    path: "/",
    httpOnly: false,
    sameSite: "strict",
    secure: opts?.secure ?? process.env.NODE_ENV === "production",
    maxAge: 0,
  });
}
