import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

const PUBLIC_ROUTES = new Set(["/login", "/no-access", "/api/auth/callback"]);

const PUBLIC_PREFIXES = ["/challenge/", "/invite/"];

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
    return NextResponse.next();
  }

  // Step 1: verify session
  const { user, supabaseResponse, supabase } = await updateSession(request);

  if (!user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  // Step 2: verify staff membership (check cookie cache first)
  let groupId = request.cookies.get("portal_group_id")?.value;
  let role = request.cookies.get("portal_role")?.value;

  if (!groupId || !role) {
    const { data: memberships } = await supabase
      .from("coaching_members")
      .select("group_id, role, coaching_groups(name)")
      .eq("user_id", user.id)
      .in("role", ["admin_master", "professor", "assistente"]);

    if (!memberships || memberships.length === 0) {
      const { data: profile } = await supabase
        .from("profiles")
        .select("platform_role")
        .eq("id", user.id)
        .single();

      if (profile?.platform_role === "admin") {
        if (!pathname.startsWith("/platform")) {
          const url = request.nextUrl.clone();
          url.pathname = "/platform/assessorias";
          return NextResponse.redirect(url);
        }
        return supabaseResponse;
      }

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
      // Multi-group — redirect to selector if not already there
      if (pathname !== "/select-group") {
        const url = request.nextUrl.clone();
        url.pathname = "/select-group";
        return NextResponse.redirect(url);
      }
      return supabaseResponse;
    }
  }

  // Platform admin routes — allow if platform_role = admin
  if (pathname.startsWith("/platform")) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("platform_role")
      .eq("id", user.id)
      .single();

    if (profile?.platform_role !== "admin") {
      const url = request.nextUrl.clone();
      url.pathname = "/no-access";
      return NextResponse.redirect(url);
    }
    return supabaseResponse;
  }

  // Step 3: role-based route protection
  if (ADMIN_ONLY_ROUTES.some((r) => pathname.startsWith(r))) {
    if (role !== "admin_master") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  if (ADMIN_PROFESSOR_ROUTES.some((r) => pathname.startsWith(r))) {
    if (role !== "admin_master" && role !== "professor") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }
  }

  return supabaseResponse;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|\\.well-known|.*\\.(?:svg|png|jpg|jpeg|gif|webp|json)$).*)",
  ],
};
