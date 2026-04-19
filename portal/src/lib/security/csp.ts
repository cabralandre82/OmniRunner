/**
 * Content-Security-Policy builder (L01-38, L10-05).
 *
 * Centralises the CSP string construction so both the request-time
 * middleware and the unit-test surface read from a single source of
 * truth. Pure-function on purpose — every input flows through the
 * argument list, no module-level state, no I/O. That makes the CSP
 * easy to snapshot-test ("the production CSP today is exactly X")
 * and easy to mutate per-route (e.g. the doc viewer at `/api/docs`
 * may need to allow blob: workers in the future without leaking that
 * permission to the rest of the app).
 *
 * Design choices worth preserving:
 *
 *   • `'nonce-<...>' 'strict-dynamic'` is the modern CSP-3 pattern.
 *     Once one trusted (nonce-tagged) script runs, it can dynamically
 *     inject other scripts without re-tagging — but third-party
 *     `<script>` tags injected by a successful XSS still get blocked
 *     because the attacker has no nonce. This is *strictly stronger*
 *     than `'self'` allow-listing because it doesn't need to know in
 *     advance which Next.js chunks will be loaded.
 *
 *   • Production never carries `'unsafe-inline'` or `'unsafe-eval'`
 *     in `script-src`. Removing them was the entire point of L01-38.
 *     Development still needs `'unsafe-eval'` because Next.js Fast
 *     Refresh and React DevTools both rely on it. We expose that
 *     branch through the `isDev` argument so the test surface can
 *     prove production never falls back to dev semantics.
 *
 *   • `style-src 'unsafe-inline'` is *kept* (production included).
 *     Tailwind's runtime layer, shadcn/ui's animation primitives and
 *     `next/font` all emit inline `<style>`. Migrating those to
 *     hashed/nonce'd styles is doable but would multiply the surface
 *     of this PR by 10× without a proportional security gain — XSS
 *     via inline `<style>` is a far weaker exfiltration primitive
 *     than via inline `<script>` (no DOM mutation, no fetch, no
 *     keystroke capture). Documented explicitly so a future audit
 *     pass doesn't have to re-derive the trade-off.
 *
 *   • `connect-src` retains `https://*.sentry.io` defensively, even
 *     though `next.config.mjs` ships `tunnelRoute: "/monitoring"`
 *     which proxies Sentry events through the same origin. If the
 *     tunnel route is ever turned off (or fails over) the SDK falls
 *     back to direct ingest and `connect-src` must allow it.
 *
 *   • `report-uri` + `report-to` (L10-05) point to `/api/csp-report`,
 *     a same-origin endpoint that forwards violations to Sentry. We
 *     emit BOTH header forms because Firefox/Safari only honour the
 *     legacy `report-uri` and Chromium-family browsers prefer the
 *     newer `report-to` group. Browsers are allowed to send to both;
 *     the endpoint dedups via `(document_uri, blocked_uri,
 *     violated_directive)`.
 */

const REPORT_GROUP = "csp-endpoint";

/**
 * Build the `Content-Security-Policy` header value.
 *
 * @param opts.nonce            Per-request nonce (base64, 128+ bits).
 *                              Must be the same value injected as
 *                              `<script nonce="…">` and exposed via
 *                              the `x-nonce` request header to RSCs.
 * @param opts.isDev            `process.env.NODE_ENV !== "production"`.
 *                              Toggles `'unsafe-eval'` (Next.js HMR /
 *                              React Refresh) and the WebSocket origin
 *                              that Next dev server uses.
 * @param opts.reportEndpoint   Path or absolute URL the browser should
 *                              POST violation reports to. Pass
 *                              `null` to omit the report directives
 *                              entirely (useful for tests that want
 *                              to assert the rest of the policy).
 * @param opts.reportOnly       When `true`, returns the policy in
 *                              report-only mode (browser logs but
 *                              does NOT enforce). Defaults to `false`.
 *                              Surfaced as a separate function for
 *                              clarity, see `buildReportOnlyCsp`.
 * @param opts.extraConnectSrc  Optional additional `connect-src`
 *                              hosts (e.g. a staging domain). Empty
 *                              by default; production callers should
 *                              not need this.
 */
export interface BuildCspOptions {
  nonce: string;
  isDev: boolean;
  reportEndpoint?: string | null;
  reportOnly?: boolean;
  extraConnectSrc?: readonly string[];
}

export function buildCsp(opts: BuildCspOptions): string {
  const {
    nonce,
    isDev,
    reportEndpoint = "/api/csp-report",
    extraConnectSrc = [],
  } = opts;

  if (!nonce || typeof nonce !== "string") {
    throw new Error("buildCsp: nonce is required (got empty string)");
  }
  // Defence-in-depth — a nonce that contains spaces or quotes would
  // close the directive prematurely and silently disable the policy.
  if (/[\s"'<>]/.test(nonce)) {
    throw new Error("buildCsp: nonce contains forbidden characters");
  }

  const scriptSrc = [
    "'self'",
    `'nonce-${nonce}'`,
    "'strict-dynamic'",
    isDev ? "'unsafe-eval'" : null,
  ]
    .filter(Boolean)
    .join(" ");

  const connectSrc = [
    "'self'",
    "https://*.supabase.co",
    "wss://*.supabase.co",
    "https://*.sentry.io",
    isDev ? "ws://localhost:*" : null,
    isDev ? "http://localhost:*" : null,
    ...extraConnectSrc,
  ]
    .filter(Boolean)
    .join(" ");

  const directives: Array<[string, string]> = [
    ["default-src", "'self'"],
    ["script-src", scriptSrc],
    ["style-src", "'self' 'unsafe-inline'"],
    ["img-src", "'self' data: blob: https://*.supabase.co"],
    ["font-src", "'self'"],
    ["connect-src", connectSrc],
    ["worker-src", "'self' blob:"],
    ["frame-ancestors", "'none'"],
    ["base-uri", "'self'"],
    ["form-action", "'self'"],
    ["object-src", "'none'"],
    ["upgrade-insecure-requests", ""],
  ];

  if (reportEndpoint) {
    directives.push(["report-uri", reportEndpoint]);
    directives.push(["report-to", REPORT_GROUP]);
  }

  return directives
    .map(([k, v]) => (v ? `${k} ${v}` : k))
    .join("; ");
}

/**
 * Build the `Report-To` header that pairs with the `report-to`
 * directive emitted by `buildCsp`. Returns `null` when reporting is
 * disabled so the caller can skip setting the header altogether.
 */
export function buildReportToHeader(
  reportEndpoint: string | null,
): string | null {
  if (!reportEndpoint) return null;
  return JSON.stringify({
    group: REPORT_GROUP,
    max_age: 10_886_400,
    endpoints: [{ url: reportEndpoint }],
    include_subdomains: true,
  });
}

/**
 * Generate a per-request CSP nonce. 16 bytes (128 bits) of CSPRNG
 * output, base64-encoded — comfortably above the 96-bit recommendation
 * in the CSP-3 spec. We base64-encode (not base64url) because the
 * value lives in HTTP headers and `<script nonce="...">` attributes,
 * neither of which need URL-safe encoding.
 *
 * We pull entropy from `globalThis.crypto.getRandomValues`, which is
 * the only API guaranteed to exist in BOTH the Next.js Edge runtime
 * (where `node:crypto` does not exist) and modern Node (≥ 19, where
 * Web Crypto is promoted to a global). For Node 18 in ESM/test mode
 * the test setup polyfills the same surface from `node:crypto`'s
 * `webcrypto` — see `src/test/setup.ts`. We deliberately do NOT fall
 * back to `Math.random()` — failing loud is correct behaviour: a CSP
 * without entropy is a CSP that any attacker can predict and bypass.
 */
export function generateNonce(): string {
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}
