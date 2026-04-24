/**
 * L01-10 — open-redirect defence for OAuth callbacks.
 *
 * Validates the `next` query parameter so we ONLY ever redirect to
 * an internal pathname. The `${origin}${next}` pattern in the legacy
 * callback already prevents a fully cross-origin redirect, but it
 * accepts any path including:
 *
 *   - `/platform/...`             — phishing into admin surfaces
 *   - `//evil.example.com/x`      — protocol-relative cross-origin
 *   - `/\\evil.example.com/x`     — Windows-style backslash escape
 *   - `next=javascript:alert(1)`  — JS scheme on relaxed parsers
 *
 * `safeNext()` is a pure function — given (raw, fallback) it returns
 * a vetted internal path. The whitelist is intentionally narrow:
 * only ASCII-alphanumeric + `-`, `_`, `/`, `?`, `&`, `=`, `%`, `.`,
 * and a leading `/`. Anything else falls back.
 */

const ALLOWED_NEXT = /^\/[A-Za-z0-9_\-./?&=%]*$/;

const FORBIDDEN_PREFIXES: readonly string[] = [
  "//",
  "/\\",
];

/**
 * Returns a safe internal pathname or `fallback`.
 *
 * @param raw       Untrusted input (e.g. `searchParams.get("next")`).
 * @param fallback  Default path on validation failure (must itself be safe).
 */
export function safeNext(
  raw: string | null | undefined,
  fallback = "/dashboard",
): string {
  if (typeof raw !== "string" || raw.length === 0) return fallback;
  if (raw.length > 256) return fallback;
  if (!raw.startsWith("/")) return fallback;
  for (const bad of FORBIDDEN_PREFIXES) {
    if (raw.startsWith(bad)) return fallback;
  }
  if (!ALLOWED_NEXT.test(raw)) return fallback;
  return raw;
}
