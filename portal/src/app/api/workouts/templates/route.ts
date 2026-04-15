import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";

interface BlockPayload {
  id: string;
  order_index: number;
  block_type: string;
  duration_seconds: number | null;
  distance_meters: number | null;
  target_pace_min_sec_per_km: number | null;
  target_pace_max_sec_per_km: number | null;
  target_hr_zone: number | null;
  target_hr_min: number | null;
  target_hr_max: number | null;
  rpe_target: number | null;
  repeat_count: number | null;
  notes: string | null;
}

export async function POST(req: Request) {
  try {
    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group" }, { status: 400 });
    }

    const body = await req.json();
    const { id, name, description, blocks } = body as {
      id?: string;
      name: string;
      description?: string;
      blocks: BlockPayload[];
    };

    if (!name || name.trim().length < 2) {
      return NextResponse.json(
        { error: "Nome deve ter pelo menos 2 caracteres" },
        { status: 400 },
      );
    }

    const supabase = createClient();

    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
    }

    let templateId = id;

    if (templateId) {
      const { error: updateErr } = await supabase
        .from("coaching_workout_templates")
        .update({
          name: name.trim(),
          description: description?.trim() || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", templateId)
        .eq("group_id", groupId);

      if (updateErr) {
        return NextResponse.json({ error: updateErr.message }, { status: 500 });
      }
    } else {
      const { data: inserted, error: insertErr } = await supabase
        .from("coaching_workout_templates")
        .insert({
          group_id: groupId,
          name: name.trim(),
          description: description?.trim() || null,
          created_by: user.id,
          is_active: true,
        })
        .select("id")
        .single();

      if (insertErr) {
        return NextResponse.json({ error: insertErr.message }, { status: 500 });
      }
      templateId = inserted.id;
    }

    await supabase
      .from("coaching_workout_blocks")
      .delete()
      .eq("template_id", templateId);

    if (blocks && blocks.length > 0) {
      const rows = blocks.map((b, idx) => ({
        id: b.id,
        template_id: templateId,
        order_index: idx,
        block_type: b.block_type,
        duration_seconds: b.duration_seconds,
        distance_meters: b.distance_meters,
        target_pace_min_sec_per_km: b.target_pace_min_sec_per_km,
        target_pace_max_sec_per_km: b.target_pace_max_sec_per_km,
        target_hr_zone: b.target_hr_zone,
        target_hr_min: b.target_hr_min,
        target_hr_max: b.target_hr_max,
        rpe_target: b.rpe_target,
        repeat_count: b.repeat_count,
        notes: b.notes,
      }));

      const { error: blocksErr } = await supabase
        .from("coaching_workout_blocks")
        .insert(rows);

      if (blocksErr) {
        return NextResponse.json(
          { error: blocksErr.message },
          { status: 500 },
        );
      }
    }

    return NextResponse.json({ ok: true, id: templateId });
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

    const { error: blocksErr } = await supabase
      .from("coaching_workout_blocks")
      .delete()
      .eq("template_id", id);

    if (blocksErr) {
      return NextResponse.json({ error: blocksErr.message }, { status: 500 });
    }

    const { error: templateErr } = await supabase
      .from("coaching_workout_templates")
      .delete()
      .eq("id", id)
      .eq("group_id", groupId);

    if (templateErr) {
      return NextResponse.json(
        { error: templateErr.message },
        { status: 500 },
      );
    }

    return NextResponse.json({ ok: true });
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
