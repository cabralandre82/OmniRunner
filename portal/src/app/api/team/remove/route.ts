import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  const role = cookies().get("portal_role")?.value;

  if (!groupId || role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();
  const memberId = body.member_id ?? "";

  if (!memberId) {
    return NextResponse.json(
      { error: "member_id is required" },
      { status: 400 },
    );
  }

  const db = createServiceClient();

  const { data: member } = await db
    .from("coaching_members")
    .select("id, user_id, role")
    .eq("id", memberId)
    .eq("group_id", groupId)
    .maybeSingle();

  if (!member) {
    return NextResponse.json({ error: "Membro não encontrado" }, { status: 404 });
  }

  if (member.user_id === session.user.id) {
    return NextResponse.json(
      { error: "Você não pode remover a si mesmo" },
      { status: 400 },
    );
  }

  if (member.role === "admin_master") {
    return NextResponse.json(
      { error: "Não é possível remover outro admin_master" },
      { status: 403 },
    );
  }

  const { error: deleteErr } = await db
    .from("coaching_members")
    .delete()
    .eq("id", memberId)
    .eq("group_id", groupId);

  if (deleteErr) {
    return NextResponse.json({ error: deleteErr.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
