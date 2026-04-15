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

const ReleaseBlockSchema = z.object({
  order_index:                z.number().int().min(0),
  block_type:                 z.enum(["warmup","interval","recovery","cooldown","steady","rest","repeat"]),
  duration_seconds:           z.number().int().min(1).nullable().optional(),
  distance_meters:            z.number().int().min(1).nullable().optional(),
  target_pace_min_sec_per_km: z.number().int().min(60).max(1800).nullable().optional(),
  target_pace_max_sec_per_km: z.number().int().min(60).max(1800).nullable().optional(),
  target_hr_zone:             z.number().int().min(1).max(5).nullable().optional(),
  target_hr_min:              z.number().int().min(40).max(220).nullable().optional(),
  target_hr_max:              z.number().int().min(40).max(220).nullable().optional(),
  rpe_target:                 z.number().int().min(1).max(10).nullable().optional(),
  repeat_count:               z.number().int().min(1).max(100).nullable().optional(),
  notes:                      z.string().max(200).nullable().optional(),
});

const UpdateSchema = z.object({
  workout_label: z.string().max(120).nullable().optional(),
  coach_notes:   z.string().max(1000).nullable().optional(),
  blocks:        z.array(ReleaseBlockSchema).max(30).optional(),
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

    if (parsed.data.blocks !== undefined) {
      // Fetch current snapshot to merge, then replace blocks
      const { data: current } = await supabase
        .from("plan_workout_releases")
        .select("content_snapshot")
        .eq("id", params.workoutId)
        .single();
      const snapshot = (current?.content_snapshot as Record<string, unknown>) ?? {};
      updatePayload.content_snapshot = {
        ...snapshot,
        blocks: parsed.data.blocks.map((b, i) => ({ ...b, order_index: i })),
        edited_at: new Date().toISOString(),
      };
      updatePayload.content_version = ((snapshot.content_version as number) ?? 1) + 1;
    }

    const { data: updated, error } = await supabase
      .from("plan_workout_releases")
      .update(updatePayload)
      .eq("id", params.workoutId)
      .select("id, workout_label, coach_notes, content_snapshot, content_version")
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
