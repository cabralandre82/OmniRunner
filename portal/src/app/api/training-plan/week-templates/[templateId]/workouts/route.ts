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

type Params = { params: { templateId: string } };

const WORKOUT_TYPES = [
  "continuous", "interval", "regenerative", "long_run", "strength",
  "technique", "test", "free", "race", "brick",
] as const;

const BlockSchema = z.object({
  order_index:                z.number().int().min(0),
  block_type:                 z.enum(["warmup","interval","recovery","cooldown","steady","rest","repeat","repeat_end"]),
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

const WorkoutSchema = z.object({
  day_of_week:   z.number().int().min(0).max(6),
  workout_order: z.number().int().min(1).default(1),
  workout_type:  z.enum(WORKOUT_TYPES).default("continuous"),
  workout_label: z.string().min(1).max(120),
  description:   z.string().max(2000).nullable().optional(),
  coach_notes:   z.string().max(500).nullable().optional(),
  blocks:        z.array(BlockSchema).max(30).default([]),
});

async function assertStaffOwnership(
  supabase: ReturnType<typeof createClient>,
  templateId: string,
  groupId: string,
): Promise<boolean> {
  const { data } = await supabase
    .from("coaching_week_templates")
    .select("id, group_id")
    .eq("id", templateId)
    .single();
  return !!data && data.group_id === groupId;
}

/**
 * GET /api/training-plan/week-templates/[templateId]/workouts
 */
export const GET = withErrorHandler(async (_req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const owned = await assertStaffOwnership(supabase, params.templateId, groupId);
  if (!owned) return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });

  const { data: workouts, error } = await supabase
    .from("coaching_week_template_workouts")
    .select("id, day_of_week, workout_order, workout_type, workout_label, description, coach_notes, blocks")
    .eq("template_id", params.templateId)
    .order("day_of_week")
    .order("workout_order");

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: workouts ?? [] });
}, "GET /api/training-plan/week-templates/[templateId]/workouts");

/**
 * POST /api/training-plan/week-templates/[templateId]/workouts
 * Adds a workout to the template.
 */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const owned = await assertStaffOwnership(supabase, params.templateId, groupId);
  if (!owned) return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });

  const body = await req.json().catch(() => null);
  const parsed = WorkoutSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const { day_of_week, workout_order, workout_type, workout_label, description, coach_notes, blocks } = parsed.data;

  const { data: workout, error } = await supabase
    .from("coaching_week_template_workouts")
    .insert({
      template_id:   params.templateId,
      day_of_week,
      workout_order,
      workout_type,
      workout_label,
      description:   description ?? null,
      coach_notes:   coach_notes ?? null,
      blocks:        blocks.map((b, i) => ({ ...b, order_index: i })),
    })
    .select("id, day_of_week, workout_order, workout_type, workout_label, description, coach_notes, blocks")
    .single();

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  // Touch template updated_at
  await supabase
    .from("coaching_week_templates")
    .update({ updated_at: new Date().toISOString() })
    .eq("id", params.templateId);

  return NextResponse.json({ ok: true, data: workout }, { status: 201 });
}, "POST /api/training-plan/week-templates/[templateId]/workouts");
