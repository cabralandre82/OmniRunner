import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { teamRemoveSchema } from "@/lib/schemas";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`remove:${user.id}`, { maxRequests: 10, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const db = createServiceClient();

  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!callerMembership || callerMembership.role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();
  const parsed = teamRemoveSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const memberId = parsed.data.member_id;

  const { data: member } = await db
    .from("coaching_members")
    .select("id, user_id, role")
    .eq("id", memberId)
    .eq("group_id", groupId)
    .maybeSingle();

  if (!member) {
    return NextResponse.json({ error: "Membro não encontrado" }, { status: 404 });
  }

  if (member.user_id === user.id) {
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

  await auditLog({
    actorId: user.id,
    groupId: groupId,
    action: "team.remove",
    targetType: "member",
    targetId: memberId,
    metadata: { removed_user_id: member.user_id, removed_role: member.role },
  });

  return NextResponse.json({ ok: true });
}
