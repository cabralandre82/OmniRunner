import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = (await request.json()) as {
    athleteUserId?: string;
    note?: string;
  };
  const groupId = cookies().get("portal_group_id")?.value;
  const { athleteUserId, note } = body;

  if (!groupId || !athleteUserId || !note?.trim()) {
    return NextResponse.json(
      { error: "groupId, athleteUserId and note required" },
      { status: 400 }
    );
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

  const { error } = await supabase.from("coaching_athlete_notes").insert({
    group_id: groupId,
    athlete_user_id: athleteUserId,
    created_by: session.user.id,
    note: note.trim(),
  });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
