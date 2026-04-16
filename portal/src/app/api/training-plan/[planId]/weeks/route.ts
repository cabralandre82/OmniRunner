import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";
import { MANAGER_ROLES } from "@/lib/roles";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const CreateWeekSchema = z.object({
  starts_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Must be YYYY-MM-DD"),
  cycle_type: z.enum(["base", "build", "peak", "recovery", "test", "free", "taper", "transition"]).default("base"),
  label: z.string().max(80).optional(),
  coach_notes: z.string().max(500).optional(),
});

type Params = { params: { planId: string } };

export const GET = withErrorHandler(async (_req: NextRequest, { params }: Params) => {
  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const { data, error } = await supabase
    .from("training_plan_weeks")
    .select(`
      id, week_number, starts_on, ends_on, label, coach_notes, cycle_type, status,
      workouts:plan_workout_releases (
        id, scheduled_date, workout_order, release_status, workout_type,
        workout_label, coach_notes, content_version, content_snapshot, video_url,
        template:template_id (
          id, name, description,
          coaching_workout_blocks (
            order_index, block_type, duration_seconds, distance_meters,
            target_pace_min_sec_per_km, target_pace_max_sec_per_km,
            target_hr_zone, target_hr_min, target_hr_max,
            rpe_target, repeat_count, notes
          )
        ),
        completed:completed_workouts (
          id, actual_distance_m, actual_duration_s, actual_avg_hr,
          perceived_effort, finished_at
        ),
        feedback:athlete_workout_feedback (rating, mood, how_was_it)
      )
    `)
    .eq("plan_id", params.planId)
    .order("week_number");

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data });
}, "GET /api/training-plan/[planId]/weeks");

export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });
  }

  const body = await req.json().catch(() => null);
  const parsed = CreateWeekSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { starts_on, cycle_type, label, coach_notes } = parsed.data;

  const { data: weekId, error } = await supabase.rpc("fn_create_plan_week", {
    p_plan_id: params.planId,
    p_starts_on: starts_on,
    p_cycle_type: cycle_type,
    p_label: label ?? null,
    p_coach_notes: coach_notes ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("week_must_start_on_monday") ? "WEEK_MUST_START_ON_MONDAY"
      : error.message.includes("plan_not_found") ? "PLAN_NOT_FOUND"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "PLAN_NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  return NextResponse.json({ ok: true, data: { id: weekId } }, { status: 201 });
}, "POST /api/training-plan/[planId]/weeks");
