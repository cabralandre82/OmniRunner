import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";

const STAFF_ROLES = ["professor", "assistente"];

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
  const email = (body.email ?? "").trim().toLowerCase();
  const memberRole = body.role ?? "";

  if (!email || !email.includes("@")) {
    return NextResponse.json({ error: "E-mail inválido" }, { status: 400 });
  }

  if (!STAFF_ROLES.includes(memberRole)) {
    return NextResponse.json(
      { error: `Role deve ser: ${STAFF_ROLES.join(", ")}` },
      { status: 400 },
    );
  }

  const db = createServiceClient();

  const { data: users, error: lookupErr } = await db.auth.admin.listUsers();
  if (lookupErr) {
    return NextResponse.json(
      { error: "Erro ao buscar usuários" },
      { status: 500 },
    );
  }

  const targetUser = users.users.find(
    (u) => u.email?.toLowerCase() === email,
  );

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

  const displayName =
    targetUser.user_metadata?.full_name ??
    targetUser.user_metadata?.name ??
    email.split("@")[0];

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

  return NextResponse.json({ ok: true, user_id: targetUser.id, role: memberRole });
}
