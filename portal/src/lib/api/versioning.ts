/**
 * API path-versioning helpers (L14-02).
 *
 * Why path versioning at all?
 *
 *   The financial endpoints (`/api/custody`, `/api/swap`,
 *   `/api/distribute-coins`, `/api/clearing`, `/api/custody/withdraw`)
 *   are consumed by:
 *
 *     - the Flutter mobile app (older versions live in users' phones
 *       for months — we cannot patch them retroactively),
 *     - partner B2B integrations (we have no IDE-level control over
 *       their build),
 *     - internal scripts and BI dashboards.
 *
 *   The first time we change a request/response signature without
 *   versioning, every one of those consumers breaks silently.
 *
 *   Solution: serve the new contract at `/api/v1/<path>` and keep
 *   the legacy `/api/<path>` operational with explicit deprecation
 *   headers (`Sunset`, `Deprecation`) so clients know they have a
 *   fixed window to migrate.
 *
 * What this module does:
 *
 *   - `applyApiVersion(res, version)` — adds `X-Api-Version: <n>` to
 *     a response. Lets clients positively identify which contract
 *     served the response (useful when both `/api/swap` and
 *     `/api/v1/swap` reach the same handler).
 *
 *   - `applyDeprecation(res, opts)` — adds the IETF
 *     `Deprecation: true` + `Sunset: <RFC 7231 date>` headers, plus
 *     an optional `Link: <successor>; rel="successor-version"`
 *     pointing the client to the v1 path. After `Sunset`, clients
 *     should treat the legacy path as gone (we still serve it for
 *     a grace period; the date communicates intent, not enforcement).
 *
 *   - `wrapV1Handler(legacyHandler)` — produces a thin v1 handler
 *     that delegates to a legacy handler and tags the response with
 *     `X-Api-Version: 1`. This lets the legacy `/api/swap/route.ts`
 *     remain the single source of truth while `/api/v1/swap/route.ts`
 *     becomes a one-liner alias. When we eventually flip the world
 *     (delete legacy), the alias file moves into the canonical
 *     position and the wrapper goes away.
 *
 *   - `LEGACY_FINANCIAL_PATHS` — the set of legacy financial paths
 *     covered by the migration. Imported by middleware to know which
 *     responses need `Sunset` tagging.
 *
 *   - `DEFAULT_FINANCIAL_SUNSET` — the sunset date for the legacy
 *     financial endpoints. Bumping this constant in one place
 *     updates every header.
 *
 * Cross-references:
 *   - L13-06: `x-request-id` propagation already exists; we layer
 *     versioning headers on the same response objects.
 *   - L14-05: error envelopes carry `request_id`; the version
 *     header is orthogonal so consumers can correlate errors with
 *     contract versions.
 *   - L14-01: `/api/v1/*` paths are documented in the OpenAPI
 *     registry as the canonical contract; `/api/*` legacy paths
 *     are documented as deprecated.
 */

import type { NextResponse } from "next/server";

/**
 * Current major version of the public API contract. This is the
 * value emitted in `X-Api-Version` and embedded in `/api/v1/*`
 * paths.
 */
export const CURRENT_API_VERSION = 1 as const;

/**
 * Header names follow the IETF draft "RFC 8594" convention plus
 * the de-facto `Deprecation` header (RFC 9745, formerly internet
 * draft). All header names are lowercase per fetch / Headers API
 * normalization.
 */
export const HEADER_API_VERSION = "x-api-version";
export const HEADER_DEPRECATION = "deprecation";
export const HEADER_SUNSET = "sunset";
export const HEADER_LINK = "link";

/**
 * Sunset date for the legacy `/api/{custody,swap,clearing,
 * distribute-coins,custody/withdraw}` paths.
 *
 * Picked at 2027-01-01 (≈ 8 months from rollout) which gives:
 *   - the mobile app two minor releases worth of lead time,
 *   - any B2B partner enough runway to rebuild their integration,
 *   - a clean calendar boundary so it's memorable in roadmap docs.
 *
 * Bump this constant when ops decides to extend or shorten the
 * window — DO NOT hard-code dates anywhere else.
 */
export const DEFAULT_FINANCIAL_SUNSET = new Date(
  Date.UTC(2027, 0, 1, 0, 0, 0),
);

/**
 * Legacy financial paths that are getting `Sunset`/`Deprecation`
 * tagging. The middleware iterates over this set on every request
 * to decide whether to layer the legacy headers; using a Set keeps
 * the lookup O(1).
 *
 * NOTE: matched on prefix so subroutes (`/api/custody/withdraw`)
 * inherit the parent tag without needing a separate entry — we
 * still list each one explicitly for clarity in code search.
 */
export const LEGACY_FINANCIAL_PATHS: Set<string> = new Set([
  "/api/custody",
  "/api/custody/withdraw",
  "/api/swap",
  "/api/distribute-coins",
  "/api/clearing",
]);

/**
 * Format a Date as RFC 7231 IMF-fixdate string (e.g. "Sun, 06 Nov
 * 1994 08:49:37 GMT"), required by the `Sunset` header per RFC 8594.
 */
export function toHttpDate(d: Date): string {
  return d.toUTCString();
}

/**
 * Stamp `X-Api-Version` on a response. Idempotent — calling twice
 * with the same version overwrites with the same value.
 */
export function applyApiVersion<T extends NextResponse>(
  res: T,
  version: number = CURRENT_API_VERSION,
): T {
  res.headers.set(HEADER_API_VERSION, String(version));
  return res;
}

export interface DeprecationOptions {
  /** Sunset date. Defaults to `DEFAULT_FINANCIAL_SUNSET`. */
  sunset?: Date;
  /**
   * URL-relative path to the successor version, e.g. `/api/v1/swap`.
   * When provided, emitted as `Link: <successor>; rel="successor-version"`
   * per RFC 5988.
   */
  successor?: string;
  /**
   * Whether to emit the `Deprecation: true` header (default true).
   * Set false if you want only the Sunset/Link signals.
   */
  emitDeprecation?: boolean;
}

/**
 * Stamp `Deprecation`, `Sunset`, and (optionally) `Link:
 * rel="successor-version"` headers on a response. This is the
 * canonical signalling for "this path is going away; here's where
 * to go and when".
 */
export function applyDeprecation<T extends NextResponse>(
  res: T,
  opts: DeprecationOptions = {},
): T {
  const sunset = opts.sunset ?? DEFAULT_FINANCIAL_SUNSET;
  const emitDep = opts.emitDeprecation ?? true;

  if (emitDep) res.headers.set(HEADER_DEPRECATION, "true");
  res.headers.set(HEADER_SUNSET, toHttpDate(sunset));

  if (opts.successor) {
    // Append rather than overwrite — there may already be a Link
    // header set by other middleware.
    const existing = res.headers.get(HEADER_LINK);
    const entry = `<${opts.successor}>; rel="successor-version"`;
    res.headers.set(HEADER_LINK, existing ? `${existing}, ${entry}` : entry);
  }

  return res;
}

/**
 * Map a legacy financial path to its v1 successor.
 *
 *   /api/swap                      → /api/v1/swap
 *   /api/custody/withdraw          → /api/v1/custody/withdraw
 *   /api/clearing                  → /api/v1/clearing
 *
 * Returns null when the path is not in the legacy financial set
 * (used by middleware to skip non-applicable paths quickly).
 */
export function v1SuccessorFor(pathname: string): string | null {
  // Match on exact path OR "<path>/something" so subroutes inherit.
  // We iterate via Array.from(...) instead of `for..of (set)` to keep
  // compatibility with the project's tsconfig (no target / no
  // downlevelIteration). The set is small (5 entries) so the
  // allocation is irrelevant.
  for (const legacy of Array.from(LEGACY_FINANCIAL_PATHS)) {
    if (pathname === legacy || pathname.startsWith(`${legacy}/`)) {
      return pathname.replace(/^\/api\//, "/api/v1/");
    }
  }
  return null;
}

/**
 * Wrap a legacy handler to produce a v1-tagged handler. Used in
 * `/api/v1/<path>/route.ts` files so the legacy file stays the
 * single source of truth:
 *
 *   import { POST as legacyPost } from "@/app/api/swap/route";
 *   export const POST = wrapV1Handler(legacyPost);
 *
 * The wrapper:
 *   1. invokes the legacy handler with the original request,
 *   2. applies `X-Api-Version: 1` to the response,
 *   3. propagates any other headers / status / body unchanged.
 */
export function wrapV1Handler<Args extends unknown[]>(
  legacy: (...args: Args) => NextResponse | Promise<NextResponse>,
): (...args: Args) => Promise<NextResponse> {
  return async (...args: Args) => {
    const result = await legacy(...args);
    return applyApiVersion(result);
  };
}
