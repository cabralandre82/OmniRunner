import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { cookies } from "next/headers";

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
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

  const body = (await request.json()) as {
    title?: string;
    body?: string;
    pinned?: boolean;
  };

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
    return NextResponse.json({ error: "Sem permissão para editar avisos" }, { status: 403 });
  }

  const updates: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };
  if (body.title !== undefined) {
    const t = body.title?.trim();
    if (!t || t.length < 2 || t.length > 200) {
      return NextResponse.json(
        { error: "Título deve ter entre 2 e 200 caracteres" },
        { status: 400 }
      );
    }
    updates.title = t;
  }
  if (body.body !== undefined) {
    if (!body.body?.trim()) {
      return NextResponse.json(
        { error: "Corpo do aviso é obrigatório" },
        { status: 400 }
      );
    }
    updates.body = body.body.trim();
  }
  if (body.pinned !== undefined) {
    updates.pinned = !!body.pinned;
  }

  const { error } = await supabase
    .from("coaching_announcements")
    .update(updates)
    .eq("id", id)
    .eq("group_id", groupId);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
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
    return NextResponse.json({ error: "Sem permissão para excluir avisos" }, { status: 403 });
  }

  const { error } = await supabase
    .from("coaching_announcements")
    .delete()
    .eq("id", id)
    .eq("group_id", groupId);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
