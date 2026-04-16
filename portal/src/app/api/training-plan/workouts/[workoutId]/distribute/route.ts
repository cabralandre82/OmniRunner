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
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

const DistributeSchema = z.object({
  target_athlete_ids: z.array(z.string().uuid()).min(1).max(100),
  target_date:        z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  group_id:           z.string().uuid(),
});

type Params = { params: { workoutId: string } };

/**
 * POST /api/training-plan/workouts/[workoutId]/distribute
 *
 * Copies a single workout to N athletes on a specific date,
 * automatically finding or creating the target week for each athlete.
 * Each copy starts as "draft".
 *
 * Returns per-athlete results so the UI can show partial success.
 */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = DistributeSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const { target_athlete_ids, target_date, group_id } = parsed.data;

  const results: Array<{
    athlete_id: string;
    success: boolean;
    new_release_id?: string;
    error?: string;
  }> = [];

  for (const athleteId of target_athlete_ids) {
    try {
      const { data: newId, error } = await supabase.rpc("fn_distribute_workout", {
        p_source_id:         params.workoutId,
        p_target_athlete_id: athleteId,
        p_target_date:       target_date,
        p_group_id:          group_id,
      });

      if (error) {
        results.push({ athlete_id: athleteId, success: false, error: error.message });
      } else {
        results.push({ athlete_id: athleteId, success: true, new_release_id: newId });
      }
    } catch (e) {
      results.push({
        athlete_id: athleteId,
        success: false,
        error: e instanceof Error ? e.message : "Erro desconhecido",
      });
    }
  }

  const successCount = results.filter((r) => r.success).length;

  if (groupId) {
    await auditLog({
      actorId: user.id,
      groupId,
      action: "workout_release.distributed",
      targetType: "plan_workout_release",
      targetId: params.workoutId,
      metadata: { target_date, total_athletes: target_athlete_ids.length, success_count: successCount },
    });
  }

  return NextResponse.json({ ok: true, data: { results, success_count: successCount } });
}, "POST /api/training-plan/workouts/[workoutId]/distribute");
