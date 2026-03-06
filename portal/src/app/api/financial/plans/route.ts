import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

export async function POST(req: Request) {
  try {
    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group" }, { status: 400 });
    }

    const body = await req.json();
    const { id, name, description, monthly_price, billing_cycle, max_workouts_per_week, status } =
      body as {
        id?: string;
        name: string;
        description?: string;
        monthly_price: number;
        billing_cycle: string;
        max_workouts_per_week?: number | null;
        status?: string;
      };

    if (!name || name.trim().length < 2) {
      return NextResponse.json({ error: "Nome deve ter pelo menos 2 caracteres" }, { status: 400 });
    }
    if (monthly_price == null || monthly_price < 0) {
      return NextResponse.json({ error: "Preço inválido" }, { status: 400 });
    }

    const supabase = createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
    }

    if (id) {
      const { error } = await supabase
        .from("coaching_plans")
        .update({
          name: name.trim(),
          description: description?.trim() || null,
          monthly_price,
          billing_cycle: billing_cycle || "monthly",
          max_workouts_per_week: max_workouts_per_week ?? null,
          status: status || "active",
          updated_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("group_id", groupId);

      if (error) {
        return NextResponse.json({ error: error.message }, { status: 500 });
      }
      return NextResponse.json({ ok: true, id });
    }

    const { data: inserted, error: insertErr } = await supabase
      .from("coaching_plans")
      .insert({
        group_id: groupId,
        name: name.trim(),
        description: description?.trim() || null,
        monthly_price,
        billing_cycle: billing_cycle || "monthly",
        max_workouts_per_week: max_workouts_per_week ?? null,
        status: status || "active",
        created_by: user.id,
      })
      .select("id")
      .single();

    if (insertErr) {
      return NextResponse.json({ error: insertErr.message }, { status: 500 });
    }

    return NextResponse.json({ ok: true, id: inserted.id });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}

export async function DELETE(req: Request) {
  try {
    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group" }, { status: 400 });
    }

    const { id } = (await req.json()) as { id: string };
    if (!id) {
      return NextResponse.json({ error: "Missing id" }, { status: 400 });
    }

    const supabase = createClient();

    const { count } = await supabase
      .from("coaching_subscriptions")
      .select("id", { count: "exact", head: true })
      .eq("plan_id", id)
      .eq("status", "active");

    if (count && count > 0) {
      return NextResponse.json(
        { error: `Não é possível excluir: ${count} assinatura(s) ativa(s) vinculada(s)` },
        { status: 409 },
      );
    }

    const { error } = await supabase
      .from("coaching_plans")
      .delete()
      .eq("id", id)
      .eq("group_id", groupId);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
