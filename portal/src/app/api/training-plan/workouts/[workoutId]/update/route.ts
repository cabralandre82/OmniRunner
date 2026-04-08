import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { z } from "zod";
import { auditLog } from "@/lib/audit";
import { logger } from "@/lib/logger";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

const UpdateSchema = z.object({
  workout_label: z.string().max(120).nullable().optional(),
  coach_notes:   z.string().max(1000).nullable().optional(),
});

type Params = { params: { workoutId: string } };

/** PATCH /api/training-plan/workouts/[workoutId]/update */
export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const cookieStore = cookies();
    const groupId = cookieStore.get("portal_group_id")?.value;

    const supabase = createClient();
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
    }

    const body = await req.json().catch(() => ({}));
    const parsed = UpdateSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
        { status: 422 },
      );
    }

    const updatePayload: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    };
    if (parsed.data.workout_label !== undefined) updatePayload.workout_label = parsed.data.workout_label;
    if (parsed.data.coach_notes   !== undefined) updatePayload.coach_notes   = parsed.data.coach_notes;

    const { data: updated, error } = await supabase
      .from("plan_workout_releases")
      .update(updatePayload)
      .eq("id", params.workoutId)
      .select("id, workout_label, coach_notes")
      .single();

    if (error) {
      const status = error.message.includes("not found") ? 404 : 500;
      return NextResponse.json(
        { ok: false, error: { code: "DB_ERROR", message: error.message } },
        { status },
      );
    }

    if (groupId) {
      await auditLog({
        actorId: user.id,
        groupId,
        action: "workout_release.updated",
        targetType: "plan_workout_release",
        targetId: params.workoutId,
        metadata: parsed.data,
      });
    }

    return NextResponse.json({ ok: true, data: updated });
  } catch (err) {
    logger.error("PATCH /api/training-plan/workouts/[workoutId]/update", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}
