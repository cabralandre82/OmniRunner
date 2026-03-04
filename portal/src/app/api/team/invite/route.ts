import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { teamInviteSchema } from "@/lib/schemas";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`invite:${user.id}`, { maxRequests: 10, windowMs: 60_000 });
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
  const parsed = teamInviteSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const email = parsed.data.email.trim().toLowerCase();
  const memberRole = parsed.data.role;

  const { data: lookup, error: lookupErr } = await db
    .rpc("fn_get_user_id_by_email", { p_email: email })
    .maybeSingle();

  if (lookupErr) {
    return NextResponse.json(
      { error: "Erro ao buscar usuário" },
      { status: 500 },
    );
  }

  const targetUser = lookup as { id: string; display_name: string } | null;

  if (!targetUser) {
    return NextResponse.json(
      { error: "Usuário não encontrado. Ele precisa criar uma conta primeiro." },
      { status: 404 },
    );
  }

  const { data: existing } = await db
    .from("coaching_members")
    .select("id, role")
    .eq("group_id", groupId)
    .eq("user_id", targetUser.id)
    .maybeSingle();

  if (existing) {
    return NextResponse.json(
      {
        error: `Usuário já é membro desta assessoria (role: ${existing.role})`,
      },
      { status: 409 },
    );
  }

  const displayName = targetUser.display_name || email.split("@")[0];

  const { error: insertErr } = await db.from("coaching_members").insert({
    user_id: targetUser.id,
    group_id: groupId,
    display_name: displayName,
    role: memberRole,
    joined_at_ms: Date.now(),
  });

  if (insertErr) {
    return NextResponse.json(
      { error: insertErr.message },
      { status: 500 },
    );
  }

  await auditLog({
    actorId: user.id,
    groupId: groupId,
    action: "team.invite",
    targetType: "user",
    targetId: targetUser.id,
    metadata: { email, role: memberRole },
  });

  return NextResponse.json({ ok: true, user_id: targetUser.id, role: memberRole });
}
