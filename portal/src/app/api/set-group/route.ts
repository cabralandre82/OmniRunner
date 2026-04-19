import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { portalCookieOptions } from "@/lib/route-policy";

export async function GET(req: NextRequest) {
  const groupId = req.nextUrl.searchParams.get("groupId");

  if (!groupId) {
    return NextResponse.redirect(new URL("/select-group", req.url));
  }

  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.redirect(new URL("/login", req.url));
  }

  const { data: membership } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .in("role", ["admin_master", "coach", "assistant"])
    .maybeSingle();

  if (!membership) {
    return NextResponse.redirect(new URL("/no-access", req.url));
  }

  const res = NextResponse.redirect(new URL("/dashboard", req.url));
  const opts = portalCookieOptions();
  res.cookies.set("portal_group_id", groupId, opts);
  res.cookies.set("portal_role", membership.role, opts);
  return res;
}
