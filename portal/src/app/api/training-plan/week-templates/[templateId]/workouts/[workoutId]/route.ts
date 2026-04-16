import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

type Params = { params: { templateId: string; workoutId: string } };

const WORKOUT_TYPES = [
  "continuous", "interval", "regenerative", "long_run", "strength",
  "technique", "test", "free", "race", "brick",
] as const;

const BlockSchema = z.object({
  order_index:                z.number().int().min(0),
  block_type:                 z.enum(["warmup","interval","recovery","cooldown","steady","rest","repeat"]),
  duration_seconds:           z.number().int().min(1).nullable().optional(),
  distance_meters:            z.number().int().min(1).nullable().optional(),
  target_pace_min_sec_per_km: z.number().int().nullable().optional(),
  target_pace_max_sec_per_km: z.number().int().nullable().optional(),
  target_hr_zone:             z.number().int().min(1).max(5).nullable().optional(),
  target_hr_min:              z.number().int().nullable().optional(),
  target_hr_max:              z.number().int().nullable().optional(),
  rpe_target:                 z.number().int().min(1).max(10).nullable().optional(),
  repeat_count:               z.number().int().min(1).max(100).nullable().optional(),
  notes:                      z.string().max(200).nullable().optional(),
});

const UpdateWorkoutSchema = z.object({
  day_of_week:   z.number().int().min(0).max(6).optional(),
  workout_order: z.number().int().min(1).optional(),
  workout_type:  z.enum(WORKOUT_TYPES).optional(),
  workout_label: z.string().min(1).max(120).optional(),
  description:   z.string().max(2000).nullable().optional(),
  coach_notes:   z.string().max(500).nullable().optional(),
  blocks:        z.array(BlockSchema).max(30).optional(),
});

/**
 * PATCH /api/training-plan/week-templates/[templateId]/workouts/[workoutId]
 */
export const PATCH = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  // Verify ownership via template → group
  const { data: tpl } = await supabase
    .from("coaching_week_templates")
    .select("group_id")
    .eq("id", params.templateId)
    .single();
  if (!tpl || tpl.group_id !== groupId) {
    return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });
  }

  const body = await req.json().catch(() => null);
  const parsed = UpdateWorkoutSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const updates: Record<string, unknown> = {};
  if (parsed.data.day_of_week   !== undefined) updates.day_of_week   = parsed.data.day_of_week;
  if (parsed.data.workout_order !== undefined) updates.workout_order = parsed.data.workout_order;
  if (parsed.data.workout_type  !== undefined) updates.workout_type  = parsed.data.workout_type;
  if (parsed.data.workout_label !== undefined) updates.workout_label = parsed.data.workout_label;
  if (parsed.data.description   !== undefined) updates.description   = parsed.data.description;
  if (parsed.data.coach_notes   !== undefined) updates.coach_notes   = parsed.data.coach_notes;
  if (parsed.data.blocks        !== undefined) {
    updates.blocks = parsed.data.blocks.map((b, i) => ({ ...b, order_index: i }));
  }

  if (Object.keys(updates).length === 0) {
    return NextResponse.json({ ok: false, error: { code: "NO_CHANGES" } }, { status: 422 });
  }

  const { data: workout, error } = await supabase
    .from("coaching_week_template_workouts")
    .update(updates)
    .eq("id", params.workoutId)
    .eq("template_id", params.templateId)
    .select("id, day_of_week, workout_order, workout_type, workout_label, description, coach_notes, blocks")
    .single();

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  await supabase
    .from("coaching_week_templates")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", params.templateId);

  return NextResponse.json({ ok: true, data: workout });
}, "PATCH /api/training-plan/week-templates/[templateId]/workouts/[workoutId]");

/**
 * DELETE /api/training-plan/week-templates/[templateId]/workouts/[workoutId]
 */
export const DELETE = withErrorHandler(async (_req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const { data: tpl } = await supabase
    .from("coaching_week_templates")
    .select("group_id")
    .eq("id", params.templateId)
    .single();
  if (!tpl || tpl.group_id !== groupId) {
    return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });
  }

  const { error } = await supabase
    .from("coaching_week_template_workouts")
    .delete()
    .eq("id", params.workoutId)
    .eq("template_id", params.templateId);

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  await supabase
    .from("coaching_week_templates")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", params.templateId);

  return NextResponse.json({ ok: true });
}, "DELETE /api/training-plan/week-templates/[templateId]/workouts/[workoutId]");
