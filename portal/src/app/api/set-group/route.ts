import { NextRequest, NextResponse } from "next/server";

const COOKIE_OPTS = {
  path: "/",
  httpOnly: true,
  sameSite: "lax" as const,
  maxAge: 60 * 60 * 8,
};

export async function GET(req: NextRequest) {
  const groupId = req.nextUrl.searchParams.get("groupId");
  const role = req.nextUrl.searchParams.get("role");

  if (!groupId || !role) {
    return NextResponse.redirect(new URL("/select-group", req.url));
  }

  const res = NextResponse.redirect(new URL("/dashboard", req.url));
  res.cookies.set("portal_group_id", groupId, COOKIE_OPTS);
  res.cookies.set("portal_role", role, COOKIE_OPTS);
  return res;
}
