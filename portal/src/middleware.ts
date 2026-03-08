import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

const PUBLIC_ROUTES = new Set(["/login", "/no-access", "/api/auth/callback", "/api/health", "/api/custody/webhook", "/api/liveness"]);

const PUBLIC_PREFIXES = [
  "/challenge/",
  "/invite/",
];

const AUTH_ONLY_PREFIXES = [
  "/platform",
  "/api/platform/",
];

const ADMIN_ONLY_ROUTES = [
  "/credits/history",
  "/credits/request",
  "/billing",
  "/settings",
];

const ADMIN_PROFESSOR_ROUTES = ["/engagement/export", "/settings/invite"];

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const isPublic =
    PUBLIC_ROUTES.has(pathname) ||
    PUBLIC_PREFIXES.some((p) => pathname.startsWith(p));

  if (isPublic) {
    const { supabaseResponse } = await updateSession(request);
    return supabaseResponse;
  }

  const isAuthOnly = AUTH_ONLY_PREFIXES.some((p) => pathname.startsWith(p));

  if (isAuthOnly) {
    const { user, supabaseResponse, supabase } = await updateSession(request);
    if (!user) {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.searchParams.set("next", pathname);
      return NextResponse.redirect(url);
    }
    // Server-side platform admin gate: verify platform_role (admin_master equivalent for platform)
    if (pathname.startsWith("/platform") || pathname.startsWith("/api/platform/")) {
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

  // Step 1: verify session
  const { user, supabaseResponse, supabase } = await updateSession(request);

  if (!user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  // Step 2: verify staff membership (check cookie cache first, re-verify group membership)
  let groupId = request.cookies.get("portal_group_id")?.value;
  let role = request.cookies.get("portal_role")?.value;

  // Re-verify: user must belong to the group stored in cookie (prevents tampering)
  if (groupId) {
    const { data: membership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("user_id", user.id)
      .eq("group_id", groupId)
      .in("role", ["admin_master", "coach", "assistant"])
      .maybeSingle();
    if (!membership) {
      groupId = undefined;
      role = undefined;
      const clearOpts = { path: "/", maxAge: 0 };
      supabaseResponse.cookies.set("portal_group_id", "", clearOpts);
      supabaseResponse.cookies.set("portal_role", "", clearOpts);
    } else {
      role = membership.role as string;
      supabaseResponse.cookies.set("portal_role", role, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
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
      supabaseResponse.cookies.set("portal_group_id", groupId, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
      supabaseResponse.cookies.set("portal_role", role, {
        path: "/",
        httpOnly: true,
        sameSite: "lax",
        maxAge: 60 * 60 * 8,
      });
    } else {
      if (pathname !== "/select-group") {
        const url = request.nextUrl.clone();
        url.pathname = "/select-group";
        return NextResponse.redirect(url);
      }
      return supabaseResponse;
    }
  }

  // Step 3: role-based route protection
  if (ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r))) {
    if (role !== "admin_master") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  if (ADMIN_PROFESSOR_ROUTES.some((r) => pathname.startsWith(r))) {
    if (role !== "admin_master" && role !== "coach") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
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
