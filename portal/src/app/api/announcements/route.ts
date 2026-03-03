import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Não autorizado" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "Grupo não selecionado" }, { status: 400 });
  }

  const payload = (await request.json()) as {
    title?: string;
    body?: string;
    pinned?: boolean;
  };
  const { title, body, pinned = false } = payload;

  if (!title?.trim() || title.trim().length < 2 || title.trim().length > 200) {
    return NextResponse.json(
      { error: "Título deve ter entre 2 e 200 caracteres" },
      { status: 400 }
    );
  }
  if (!body?.trim()) {
    return NextResponse.json(
      { error: "Corpo do aviso é obrigatório" },
      { status: 400 }
    );
  }

  const { data: membership } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", session.user.id)
    .maybeSingle();

  const role = (membership as { role: string } | null)?.role ?? "";
  if (
    !membership ||
    !["admin_master", "coach"].includes(role)
  ) {
    return NextResponse.json({ error: "Sem permissão para criar avisos" }, { status: 403 });
  }

  const { data, error } = await supabase
    .from("coaching_announcements")
    .insert({
      group_id: groupId,
      created_by: session.user.id,
      title: title.trim(),
      body: body.trim(),
      pinned: !!pinned,
    })
    .select("id")
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true, id: data.id });
}
