import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";
import {
  isPublicRoute,
  isAuthOnlyRoute,
  isAuthNoGroupRoute,
  resolveRouteAccess,
  isStaffRole,
  portalCookieOptions,
} from "@/lib/route-policy";
import {
  MEMBERSHIP_NONE,
  getCachedMembership,
  setCachedMembership,
} from "@/lib/route-policy-cache";
import { enforceWebhookIpAllowlist } from "@/lib/webhook-ip-allowlist";
import {
  applyApiVersion,
  applyDeprecation,
  v1SuccessorFor,
  LEGACY_FINANCIAL_PATHS,
} from "@/lib/api/versioning";
import {
  ensureCsrfCookie,
  shouldEnforceCsrf,
  verifyCsrf,
} from "@/lib/api/csrf";

/**
 * Portal middleware (L13-01..L13-07).
 *
 * Responsibilities, in order:
 *
 *   1. Generate / propagate `x-request-id` to the downstream request
 *      headers (L13-06) so RSCs can read it via `headers()`.
 *   2. Gate `/api/custody/webhook` behind an opt-in IP allow-list
 *      (L13-07) — defence-in-depth on top of the HMAC signature check
 *      that already lives in the route handler.
 *   3. Pass public routes through unauthenticated.
 *   4. Auth-only routes (`/platform`, `/api/platform/`) require a user
 *      and platform-admin role.
 *   5. `/select-group` (L13-04) requires a user but explicitly does
 *      NOT require a portal-group cookie — the page is the entry point
 *      to choosing one.
 *   6. Everything else: require user + portal_group cookie + staff
 *      membership; resolve the route's access verdict.
 *
 * Cookies set from this middleware go through `portalCookieOptions()`
 * which now flips `secure: true` in production (L13-05).
 *
 * Membership lookups go through the LRU cache in
 * `lib/route-policy-cache.ts` (60 s TTL, negative-cached) so a single
 * page-load with N RSCs costs at most one Postgres round-trip per
 * `(user, group)` instead of one per RSC (L13-03).
 *
 * Layered on top of all of the above (L14-02):
 *
 *   - every `/api/*` response gets `X-Api-Version: 1` so consumers
 *     can positively identify which contract served them, and
 *   - every legacy financial path (`/api/{custody,custody/withdraw,
 *     swap,distribute-coins,clearing}`) gets `Deprecation: true`,
 *     `Sunset: <DEFAULT_FINANCIAL_SUNSET>` and
 *     `Link: </api/v1/...>; rel="successor-version"` so callers
 *     know they have a fixed window to migrate to the v1 path.
 *
 * (L01-06) CSRF defence-in-depth on top of `sameSite: "strict"`:
 *   - Every authenticated response that doesn't already carry a
 *     `portal_csrf` cookie gets one minted via `ensureCsrfCookie`.
 *   - `(POST|PUT|PATCH|DELETE)` requests on the financial mutation
 *     surface (see `CSRF_PROTECTED_PREFIXES`) are gated on a valid
 *     `x-csrf-token` header that matches the cookie. Mismatch returns
 *     403 `CSRF_TOKEN_INVALID` *before* the route handler runs.
 *   - Webhook + OAuth callback paths are explicitly exempt
 *     (`CSRF_EXEMPT_PREFIXES`) — they're authenticated by HMAC /
 *     OAuth `state`, not by browser cookies.
 */

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // (L13-06) Compute / honour x-request-id once and propagate to BOTH
  // the downstream request headers and the response.
  const requestId =
    request.headers.get("x-request-id") ?? crypto.randomUUID();
  const extraRequestHeaders = { "x-request-id": requestId };

  // (L14-02) Pre-compute version-header policy once per request.
  // Path-dependent only, so we lift the work out of tagResponse:
  //
  //   - every /api/* response gets X-Api-Version
  //   - every legacy financial path additionally gets Sunset/
  //     Deprecation/Link
  //   - everything else gets neither (RSC pages, static assets, etc.)
  const isApiPath = pathname.startsWith("/api/") || pathname === "/api";
  let isLegacyFinancialPath = false;
  if (isApiPath && !pathname.startsWith("/api/v1/")) {
    for (const p of Array.from(LEGACY_FINANCIAL_PATHS)) {
      if (pathname === p || pathname.startsWith(`${p}/`)) {
        isLegacyFinancialPath = true;
        break;
      }
    }
  }
  const v1Successor = isLegacyFinancialPath ? v1SuccessorFor(pathname) : null;

  const tagResponse = (res: NextResponse) => {
    res.headers.set("x-request-id", requestId);
    if (isApiPath) {
      applyApiVersion(res);
      if (isLegacyFinancialPath) {
        applyDeprecation(res, {
          successor: v1Successor ?? undefined,
        });
      }
    }
    return res;
  };

  // (L01-06) CSRF enforcement runs AFTER the IP allow-list (so
  // webhook 403s aren't swallowed) but BEFORE auth — a CSRF check
  // that comes only after auth would still pay the Postgres round-
  // trip cost on attacker requests, which is wasteful at best and a
  // DoS amplifier at worst. The check is pure-function (cookie vs
  // header on the request) so doing it early is free.
  if (shouldEnforceCsrf(request.method, pathname)) {
    const verdict = verifyCsrf(request);
    if (!verdict.ok) {
      return tagResponse(
        NextResponse.json(
          {
            ok: false,
            error: {
              code: "CSRF_TOKEN_INVALID",
              message: verdict.message,
              request_id: requestId,
              details: { reason: verdict.code },
            },
          },
          { status: 403 },
        ),
      );
    }
  }

  // (L13-07) Webhook IP allow-list runs BEFORE any auth so that
  // mis-configured callers cannot tickle session refresh logic.
  if (pathname === "/api/custody/webhook") {
    const denied = enforceWebhookIpAllowlist(request);
    if (denied) return tagResponse(denied);
  }

  if (isPublicRoute(pathname)) {
    const { supabaseResponse } = await updateSession(
      request,
      extraRequestHeaders,
    );
    return tagResponse(supabaseResponse);
  }

  if (isAuthOnlyRoute(pathname)) {
    const { user, supabaseResponse, supabase } = await updateSession(
      request,
      extraRequestHeaders,
    );
    if (!user) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.searchParams.set("next", pathname);
      return tagResponse(NextResponse.redirect(url));
    }
    if (
      pathname.startsWith("/platform") ||
      pathname.startsWith("/api/platform/")
    ) {
      const { data: profile } = await supabase
        .from("profiles")
        .select("platform_role")
        .eq("id", user.id)
        .single();
      if (profile?.platform_role !== "admin") {
        if (pathname.startsWith("/api/")) {
          return tagResponse(
            NextResponse.json({ error: "Forbidden" }, { status: 403 }),
          );
        }
        const url = request.nextUrl.clone();
        url.pathname = "/";
        return tagResponse(NextResponse.redirect(url));
      }
    }
    ensureCsrfCookie(request, supabaseResponse);
    return tagResponse(supabaseResponse);
  }

  // (L13-04) /select-group needs a logged-in user but explicitly does
  // not require a portal-group cookie. Without this carve-out, the
  // group-resolution branch below would either redirect into itself
  // (multi-membership branch) or silently rely on the implicit
  // pathname check at line 138 of the legacy middleware.
  if (isAuthNoGroupRoute(pathname)) {
    const { user, supabaseResponse } = await updateSession(
      request,
      extraRequestHeaders,
    );
    if (!user) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.searchParams.set("next", pathname);
      return tagResponse(NextResponse.redirect(url));
    }
    ensureCsrfCookie(request, supabaseResponse);
    return tagResponse(supabaseResponse);
  }

  const { user, supabaseResponse, supabase } = await updateSession(
    request,
    extraRequestHeaders,
  );

  if (!user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return tagResponse(NextResponse.redirect(url));
  }

  let groupId = request.cookies.get("portal_group_id")?.value;
  let role = request.cookies.get("portal_role")?.value;

  if (groupId) {
    const cached = getCachedMembership(user.id, groupId);

    if (cached === MEMBERSHIP_NONE) {
      groupId = undefined;
      role = undefined;
      const clearOpts = portalCookieOptions({ maxAge: 0 });
      supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
      supabaseResponse.cookies.set("portal_role", "", clearOpts);
    } else if (cached) {
      role = cached.role;
      supabaseResponse.cookies.set(
        "portal_role",
        role,
        portalCookieOptions(),
      );
    } else {
      const { data: membership } = await supabase
        .from("coaching_members")
        .select("role")
        .eq("user_id", user.id)
        .eq("group_id", groupId)
        .in("role", ["admin_master", "coach", "assistant"])
        .maybeSingle();
      if (!membership) {
        setCachedMembership(user.id, groupId, MEMBERSHIP_NONE);
        groupId = undefined;
        role = undefined;
        const clearOpts = portalCookieOptions({ maxAge: 0 });
        supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
        supabaseResponse.cookies.set("portal_role", "", clearOpts);
      } else {
        role = membership.role as string;
        // Defensive: if the DB ever returns a value we don't recognise
        // (e.g. legacy `professor` slipping through a migration),
        // we treat it as "no membership" instead of trusting it.
        // This converts a silent privilege escalation into a hard 403.
        if (!isStaffRole(role)) {
          setCachedMembership(user.id, groupId, MEMBERSHIP_NONE);
          groupId = undefined;
          role = undefined;
          const clearOpts = portalCookieOptions({ maxAge: 0 });
          supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
          supabaseResponse.cookies.set("portal_role", "", clearOpts);
        } else {
          setCachedMembership(user.id, groupId, { role });
          supabaseResponse.cookies.set(
            "portal_role",
            role,
            portalCookieOptions(),
          );
        }
      }
    }
  }

  if (!groupId || !role) {
    const { data: memberships } = await supabase
      .from("coaching_members")
      .select("group_id, role, coaching_groups(name)")
      .eq("user_id", user.id)
      .in("role", ["admin_master", "coach", "assistant"]);

    if (!memberships || memberships.length === 0) {
      const url = request.nextUrl.clone();
      url.pathname = "/no-access";
      return tagResponse(NextResponse.redirect(url));
    }

    if (memberships.length === 1) {
      groupId = memberships[0].group_id as string;
      role = memberships[0].role as string;
      if (isStaffRole(role)) {
        setCachedMembership(user.id, groupId, { role });
      }
      const redirect = NextResponse.redirect(request.nextUrl);
      redirect.cookies.set(
        "portal_group_id",
        groupId,
        portalCookieOptions(),
      );
      redirect.cookies.set("portal_role", role, portalCookieOptions());
      return tagResponse(redirect);
    } else {
      // Multi-membership: defer to /select-group. The redundant
      // pathname-equality check that used to live here is no longer
      // needed because /select-group is now an explicit
      // AUTH_NO_GROUP_ROUTES match (L13-04) and never falls into
      // this branch in the first place.
      const url = request.nextUrl.clone();
      url.pathname = "/select-group";
      return tagResponse(NextResponse.redirect(url));
    }
  }

  // (L13-01) role-based protection delegated to a single,
  // ordering-aware resolver. Admin-coach routes (e.g. /settings/invite)
  // are checked BEFORE admin-only prefixes (e.g. /settings) so a coach
  // is allowed through /settings/invite even though /settings is in
  // ADMIN_ONLY_ROUTES.
  const verdict = resolveRouteAccess(pathname, role);
  if (verdict === "forbidden") {
    return tagResponse(
      NextResponse.json({ error: "Forbidden" }, { status: 403 }),
    );
  }

  ensureCsrfCookie(request, supabaseResponse);
  return tagResponse(supabaseResponse);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known|.*\\.(?:svg|png|jpg|jpeg|gif|webp|json)$).*)",
  ],
};
