import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";
import { auditLog } from "@/lib/audit";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const ScheduleSchema = z.object({
  scheduled_release_at: z.string().datetime({ offset: true }),
});

type Params = { params: { workoutId: string } };

/** POST /api/training-plan/workouts/[workoutId]/schedule — agenda liberação automática */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = ScheduleSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const releaseAt = parsed.data.scheduled_release_at;
  if (new Date(releaseAt) <= new Date()) {
    return NextResponse.json(
      { ok: false, error: { code: "TIME_IN_PAST", message: "O horário de liberação deve ser no futuro" } },
      { status: 422 }
    );
  }

  const { data: result, error } = await supabase.rpc("fn_schedule_workout_release", {
    p_release_id:           params.workoutId,
    p_scheduled_release_at: releaseAt,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("release_not_found") ? "NOT_FOUND"
      : error.message.includes("already_released") ? "ALREADY_RELEASED"
      : error.message.includes("invalid_status") ? "INVALID_STATUS"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  if (groupId) {
    await auditLog({
      actorId: user.id,
      groupId,
      action: "workout_release.scheduled",
      targetType: "plan_workout_release",
      targetId: params.workoutId,
      metadata: { scheduled_release_at: releaseAt, result },
    });
  }

  return NextResponse.json({ ok: true, data: { result, scheduled_release_at: releaseAt } });
}, "POST /api/training-plan/workouts/[workoutId]/schedule");
