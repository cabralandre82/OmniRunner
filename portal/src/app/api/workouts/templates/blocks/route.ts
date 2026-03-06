import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(req: Request) {
  try {
    const url = new URL(req.url);
    const templateId = url.searchParams.get("template_id");
    if (!templateId) {
      return NextResponse.json({ blocks: [] });
    }

    const supabase = createClient();
    const { data } = await supabase
      .from("coaching_workout_blocks")
      .select(
        "id, order_index, block_type, duration_seconds, distance_meters, target_pace_min_sec_per_km, target_pace_max_sec_per_km, target_hr_zone, target_hr_min, target_hr_max, rpe_target, repeat_count, notes",
      )
      .eq("template_id", templateId)
      .order("order_index");

    return NextResponse.json({ blocks: data ?? [] });
  } catch (e) {
    return NextResponse.json({ blocks: [], error: String(e) }, { status: 500 });
  }
}
