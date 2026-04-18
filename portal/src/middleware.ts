import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";
import {
  isPublicRoute,
  isAuthOnlyRoute,
  resolveRouteAccess,
  isStaffRole,
} from "@/lib/route-policy";
import {
  MEMBERSHIP_NONE,
  getCachedMembership,
  setCachedMembership,
} from "@/lib/route-policy-cache";

/**
 * Portal middleware (L13-01 / L13-02 / L13-03).
 *
 * Route policy is delegated to `lib/route-policy.ts` so the precedence
 * rule "ADMIN_COACH_ROUTES win over ADMIN_ONLY_ROUTES on conflicting
 * prefixes" is verified by unit tests rather than re-implemented inline.
 *
 * Membership lookups go through the LRU cache in
 * `lib/route-policy-cache.ts` (60 s TTL, negative-cached) so a single
 * page-load with N RSCs costs at most one Postgres round-trip per
 * `(user, group)` instead of one per RSC.
 */

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (isPublicRoute(pathname)) {
    const { supabaseResponse } = await updateSession(request);
    return supabaseResponse;
  }

  if (isAuthOnlyRoute(pathname)) {
    const { user, supabaseResponse, supabase } = await updateSession(request);
    if (!user) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.searchParams.set("next", pathname);
      return NextResponse.redirect(url);
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
          return NextResponse.json({ error: "Forbidden" }, { status: 403 });
        }
        const url = request.nextUrl.clone();
        url.pathname = "/";
        return NextResponse.redirect(url);
      }
    }
    return supabaseResponse;
  }

  const { user, supabaseResponse, supabase } = await updateSession(request);

  if (!user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  let groupId = request.cookies.get("portal_group_id")?.value;
  let role = request.cookies.get("portal_role")?.value;

  if (groupId) {
    // L13-03: try the LRU cache first. Cache stores both positive and
    // negative results (MEMBERSHIP_NONE). Cache misses fall through to
    // the existing Postgres query, which then populates the cache.
    const cached = getCachedMembership(user.id, groupId);

    if (cached === MEMBERSHIP_NONE) {
      groupId = undefined;
      role = undefined;
      const clearOpts = { path: "/", maxAge: 0 };
      supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
      supabaseResponse.cookies.set("portal_role", "", clearOpts);
    } else if (cached) {
      role = cached.role;
      supabaseResponse.cookies.set("portal_role", role, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
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
        const clearOpts = { path: "/", maxAge: 0 };
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
          const clearOpts = { path: "/", maxAge: 0 };
          supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
          supabaseResponse.cookies.set("portal_role", "", clearOpts);
        } else {
          setCachedMembership(user.id, groupId, { role });
          supabaseResponse.cookies.set("portal_role", role, {
            path: "/",
            httpOnly: true,
            sameSite: "lax",
            maxAge: 60 * 60 * 8,
          });
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
      return NextResponse.redirect(url);
    }

    if (memberships.length === 1) {
      groupId = memberships[0].group_id as string;
      role = memberships[0].role as string;
      // Populate the cache with the resolved membership so the
      // immediately-following navigation does not re-query.
      if (isStaffRole(role)) {
        setCachedMembership(user.id, groupId, { role });
      }
      const redirect = NextResponse.redirect(request.nextUrl);
      redirect.cookies.set("portal_group_id", groupId, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
      redirect.cookies.set("portal_role", role, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
      return redirect;
    } else {
      if (pathname !== "/select-group") {
        const url = request.nextUrl.clone();
        url.pathname = "/select-group";
        return NextResponse.redirect(url);
      }
      return supabaseResponse;
    }
  }

  // L13-01: role-based protection delegated to a single, ordering-aware
  // resolver. Admin-coach routes (e.g. /settings/invite) are checked
  // BEFORE admin-only prefixes (e.g. /settings) so a coach is allowed
  // through /settings/invite even though /settings is in ADMIN_ONLY_ROUTES.
  const verdict = resolveRouteAccess(pathname, role);
  if (verdict === "forbidden") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const requestId = request.headers.get("x-request-id") ?? crypto.randomUUID();
  supabaseResponse.headers.set("x-request-id", requestId);

  return supabaseResponse;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known|.*\\.(?:svg|png|jpg|jpeg|gif|webp|json)$).*)",
  ],
};
