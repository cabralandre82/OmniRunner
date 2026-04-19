/**
 * Browser-side fetch wrapper that injects the CSRF header (L01-06).
 *
 * Why a wrapper instead of a global `fetch` patch?
 *
 *   - Patching the global hides the requirement at code-review time.
 *     Forcing call sites to import `csrfFetch` keeps the security
 *     posture greppable: `git grep -E '\bfetch\(' portal/src` should
 *     return zero matches inside browser components touching gated
 *     endpoints (financial mutations + platform admin POSTs).
 *   - Some call sites legitimately need plain `fetch` — public health
 *     pings, third-party APIs, etc. — and shouldn't pay the CSRF cost.
 *
 * Server-side usage is a no-op pass-through: when `document` is
 * undefined (RSC, route handler, edge), the helper falls back to
 * native `fetch` without trying to read a cookie. This keeps the
 * import safe in shared modules.
 */

import { CSRF_COOKIE_NAME, CSRF_HEADER_NAME } from "./csrf";

/**
 * Read a cookie value from `document.cookie` by name. Returns `null`
 * if not in a browser context or the cookie doesn't exist.
 *
 * The naive `split(";")` approach is correct because cookie names
 * can't contain `;` (RFC 6265 §4.1.1) and `decodeURIComponent` handles
 * any percent-encoding the browser applied at write time.
 */
export function readCookie(name: string): string | null {
  if (typeof document === "undefined") return null;
  const target = `${name}=`;
  const parts = document.cookie.split(";");
  for (const part of parts) {
    const trimmed = part.trim();
    if (trimmed.startsWith(target)) {
      try {
        return decodeURIComponent(trimmed.substring(target.length));
      } catch {
        return null;
      }
    }
  }
  return null;
}

/**
 * Drop-in replacement for `fetch` that automatically attaches the
 * `x-csrf-token` header (read from the `portal_csrf` cookie). All
 * other RequestInit fields pass through unchanged.
 *
 * If the cookie is missing (user hasn't been through the middleware
 * yet, or the cookie was cleared by sign-out), the request is sent
 * WITHOUT the header — the server-side enforcement will then return
 * 403 with a clear `CSRF_COOKIE_MISSING` code so the UI can surface a
 * "please reload to refresh your session" prompt rather than failing
 * silently.
 */
export async function csrfFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const headers = new Headers(init?.headers);
  if (!headers.has(CSRF_HEADER_NAME)) {
    const token = readCookie(CSRF_COOKIE_NAME);
    if (token) {
      headers.set(CSRF_HEADER_NAME, token);
    }
  }
  return fetch(input, { ...init, headers });
}
