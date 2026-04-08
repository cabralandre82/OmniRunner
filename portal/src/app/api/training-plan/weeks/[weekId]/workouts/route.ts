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
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const CreateWorkoutSchema = z.object({
  athlete_id: z.string().uuid(),
  template_id: z.string().uuid(),
  scheduled_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  workout_type: z.enum([
    "continuous", "interval", "regenerative", "long_run", "strength",
    "technique", "test", "free", "race", "brick"
  ]).default("continuous"),
  workout_label: z.string().max(120).optional(),
  coach_notes: z.string().max(500).optional(),
  workout_order: z.number().int().min(1).default(1),
});

type Params = { params: { weekId: string } };

export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = CreateWorkoutSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { athlete_id, template_id, scheduled_date, workout_type, workout_label, coach_notes, workout_order } = parsed.data;

  const { data: releaseId, error } = await supabase.rpc("fn_create_plan_workout", {
    p_plan_week_id:   params.weekId,
    p_athlete_id:     athlete_id,
    p_template_id:    template_id,
    p_scheduled_date: scheduled_date,
    p_workout_type:   workout_type,
    p_workout_label:  workout_label ?? null,
    p_coach_notes:    coach_notes ?? null,
    p_workout_order:  workout_order,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("week_not_found") ? "WEEK_NOT_FOUND"
      : error.message.includes("athlete_not_member") ? "ATHLETE_NOT_MEMBER"
      : error.message.includes("date_outside_week") ? "DATE_OUTSIDE_WEEK"
      : error.message.includes("template_not_found") ? "TEMPLATE_NOT_FOUND"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "WEEK_NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  return NextResponse.json({ ok: true, data: { id: releaseId } }, { status: 201 });
}, "POST /api/training-plan/weeks/[weekId]/workouts");
