import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function GET(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
  }

  const { data: membership } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", session.user.id)
    .maybeSingle();

  if (
    !membership ||
    !["admin_master", "coach", "assistant"].includes(
      (membership as { role: string }).role
    )
  ) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const { data } = await supabase
    .from("coaching_tags")
    .select("id, name")
    .eq("group_id", groupId)
    .order("name");

  return NextResponse.json(data ?? []);
}
