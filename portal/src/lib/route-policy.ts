/**
 * Route-policy — single source of truth for the portal middleware
 * (L13-01 / L13-02 / L13-03).
 *
 * Why a separate module?
 *
 *   - **L13-01** (ordering bug): the middleware used to evaluate
 *     `ADMIN_ONLY_ROUTES` and `ADMIN_PROFESSOR_ROUTES` in two
 *     independent `if` blocks. Because `/settings` (admin-only) is a
 *     prefix of `/settings/invite` (admin OR coach), a `coach` hitting
 *     `/settings/invite` would be 403'd by the first block. Encoding
 *     the precedence rule in a single function with a deterministic
 *     match-most-specific-first algorithm makes the bug structurally
 *     impossible to reintroduce.
 *
 *   - **L13-02** (semantic debt): the constant
 *     `ADMIN_PROFESSOR_ROUTES` still used the legacy Portuguese term
 *     `professor` even though the DB role was renamed to `coach` in
 *     migration `20260304050000_fix_coaching_role_mismatch.sql`.
 *     Renamed to `ADMIN_COACH_ROUTES` and the role gate now reads
 *     `coach` directly.
 *
 *   - **L13-03** (perf debt): the middleware queried Postgres on every
 *     request. The cache lives in `route-policy-cache.ts` (separate
 *     module so it can be reset for tests).
 *
 * # API contract
 *
 *   `resolveRouteAccess(pathname, role)` returns one of:
 *
 *     - `"allow"`        — the request may proceed
 *     - `"forbidden"`    — return HTTP 403 (or redirect for HTML)
 *     - `"unprotected"`  — this module has nothing to say about the
 *                          path; the middleware decides (used for
 *                          public/auth-only routes).
 *
 * The function NEVER returns `"forbidden"` for a `"unprotected"`
 * pathname — the only way to be forbidden is to match a protected
 * prefix while not having the required role.
 */

// ─────────────────────────────────────────────────────────────────────────────
// Constants — exported for the existing middleware.ts consumers and for tests.
// Keep these arrays sorted longest-prefix-first to make the visual
// inspection of precedence trivial.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Routes accessible to admin_master AND coach.
 *
 * IMPORTANT: order matters when used by `resolveRouteAccess` —
 * longer/more-specific prefixes must come BEFORE shorter ones, even if
 * the more general one ends up in `ADMIN_ONLY_ROUTES`. The implementation
 * enforces this by checking this list **first**.
 */
export const ADMIN_COACH_ROUTES: readonly string[] = [
  "/engagement/export",
  "/settings/invite",
];

/**
 * Routes restricted to admin_master only. Notice `/settings` is a
 * prefix of `/settings/invite` (which is in ADMIN_COACH_ROUTES); the
 * resolver must match ADMIN_COACH_ROUTES first to handle that case
 * correctly. See L13-01.
 */
export const ADMIN_ONLY_ROUTES: readonly string[] = [
  "/credits/history",
  "/credits/request",
  "/billing",
  "/settings",
];

/**
 * Routes that are publicly reachable (no session required).
 */
export const PUBLIC_ROUTES: ReadonlySet<string> = new Set([
  "/login",
  "/no-access",
  "/api/auth/callback",
  "/api/health",
  "/api/custody/webhook",
  "/api/liveness",
]);

/**
 * Public path prefixes (deep links shareable without authentication).
 */
export const PUBLIC_PREFIXES: readonly string[] = ["/challenge/", "/invite/"];

/**
 * Path prefixes that require a session but no group membership
 * (platform admin pages).
 */
export const AUTH_ONLY_PREFIXES: readonly string[] = [
  "/platform",
  "/api/platform/",
];

// ─────────────────────────────────────────────────────────────────────────────
// Roles
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Roles that the portal recognises post-`fix_coaching_role_mismatch`
 * migration. `professor` is intentionally absent — if the DB still
 * returns it, that's a regression that should fail loudly rather than
 * being silently coerced to `coach`.
 */
export type StaffRole = "admin_master" | "coach" | "assistant";

const STAFF_ROLES: ReadonlySet<string> = new Set([
  "admin_master",
  "coach",
  "assistant",
]);

export function isStaffRole(value: unknown): value is StaffRole {
  return typeof value === "string" && STAFF_ROLES.has(value);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public route classifiers (kept for backward-compat with route-policy.test.ts
// and any RSC that needs to ask "is this public?").
// ─────────────────────────────────────────────────────────────────────────────

export function isPublicRoute(pathname: string): boolean {
  return (
    PUBLIC_ROUTES.has(pathname) ||
    PUBLIC_PREFIXES.some((p) => pathname.startsWith(p))
  );
}

export function isAuthOnlyRoute(pathname: string): boolean {
  return AUTH_ONLY_PREFIXES.some((p) => pathname.startsWith(p));
}

// ─────────────────────────────────────────────────────────────────────────────
// Role-gated access
// ─────────────────────────────────────────────────────────────────────────────

export type AccessVerdict = "allow" | "forbidden" | "unprotected";

/**
 * Decide whether a staff role may access a path that has already been
 * past the public/auth-only filters. The match algorithm is:
 *
 *   1. If `pathname` matches a prefix in `ADMIN_COACH_ROUTES`, the
 *      request is allowed iff `role ∈ {admin_master, coach}`.
 *
 *   2. Otherwise, if `pathname` matches a prefix in `ADMIN_ONLY_ROUTES`,
 *      the request is allowed iff `role === admin_master`.
 *
 *   3. Otherwise, the path is `"unprotected"` by this policy (the
 *      middleware will allow it after standard session checks).
 *
 * The two-step ordering (1 before 2) is what fixes L13-01: a `coach`
 * hitting `/settings/invite` matches step 1 (allow) and never reaches
 * step 2 (which would have forbidden them due to the `/settings`
 * prefix).
 *
 * `assistant` is not granted access to either ADMIN_COACH_ROUTES or
 * ADMIN_ONLY_ROUTES today; if a future role mapping is added, change
 * the conditions below — the match algorithm itself is policy-free.
 */
export function resolveRouteAccess(
  pathname: string,
  role: string | null | undefined,
): AccessVerdict {
  if (ADMIN_COACH_ROUTES.some((r) => pathname.startsWith(r))) {
    return role === "admin_master" || role === "coach"
      ? "allow"
      : "forbidden";
  }
  if (ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r))) {
    return role === "admin_master" ? "allow" : "forbidden";
  }
  return "unprotected";
}
