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

const BulkAssignSchema = z.object({
  source_week_id:     z.string().uuid(),
  target_athlete_ids: z.array(z.string().uuid()).min(1).max(100),
  target_start_date:  z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  group_id:           z.string().uuid(),
  auto_release:       z.boolean().default(false),
});

/**
 * POST /api/training-plan/bulk-assign
 *
 * Copies all workouts from source_week to each target athlete, preserving
 * the day-of-week offset relative to target_start_date.
 *
 * Returns per-athlete results so the UI can show partial success.
 */
export async function POST(req: NextRequest) {
  try {
    const cookieStore = cookies();
    const supabase = createClient();
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
    }

    const body = await req.json().catch(() => null);
    const parsed = BulkAssignSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
        { status: 422 },
      );
    }

    const { source_week_id, target_athlete_ids, target_start_date, group_id, auto_release } = parsed.data;

    // Fetch source week + its workouts
    const { data: sourceWeek, error: weekErr } = await supabase
      .from("training_plan_weeks")
      .select(`
        id, starts_on, ends_on, plan_id,
        plan_workout_releases (
          id, scheduled_date, workout_order, workout_type, workout_label,
          coach_notes, template_id, release_status
        )
      `)
      .eq("id", source_week_id)
      .single();

    if (weekErr || !sourceWeek) {
      return NextResponse.json(
        { ok: false, error: { code: "WEEK_NOT_FOUND" } },
        { status: 404 },
      );
    }

    // Ensure caller owns this plan (via group_id check)
    const { data: plan } = await supabase
      .from("training_plans")
      .select("id, group_id")
      .eq("id", sourceWeek.plan_id)
      .eq("group_id", group_id)
      .single();

    if (!plan) {
      return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
    }

    type SourceWorkout = {
      scheduled_date: string;
      workout_order: number;
      workout_type: string;
      workout_label: string | null;
      coach_notes: string | null;
      template_id: string | null;
      release_status: string | null;
    };
    const sourceWorkouts: SourceWorkout[] =
      (sourceWeek.plan_workout_releases as SourceWorkout[]) ?? [];

    const activeSources = sourceWorkouts.filter(
      (w) => !["cancelled", "replaced", "archived"].includes(w.release_status ?? ""),
    );

    if (activeSources.length === 0) {
      return NextResponse.json({ ok: false, error: { code: "EMPTY_WEEK" } }, { status: 422 });
    }

    const sourceStart = new Date(sourceWeek.starts_on + "T00:00:00");
    const targetStart = new Date(target_start_date + "T00:00:00");

    const shiftDate = (originalDate: string): string => {
      const orig = new Date(originalDate + "T00:00:00");
      const offsetDays = Math.round(
        (orig.getTime() - sourceStart.getTime()) / (1000 * 60 * 60 * 24),
      );
      const shifted = new Date(targetStart);
      shifted.setDate(shifted.getDate() + offsetDays);
      return shifted.toISOString().split("T")[0];
    };

    // Used by fn_bulk_assign_week RPC but kept available for fallback manual copy
    void shiftDate;

    const results: Array<{
      athlete_id: string;
      success: boolean;
      new_week_id?: string;
      error?: string;
    }> = [];

    for (const athleteId of target_athlete_ids) {
      try {
        const { data: newWeekId, error: newWeekErr } = await supabase.rpc(
          "fn_bulk_assign_week",
          {
            p_source_week_id:    source_week_id,
            p_target_athlete_id: athleteId,
            p_target_start_date: target_start_date,
            p_group_id:          group_id,
            p_actor_id:          user.id,
            p_auto_release:      auto_release,
          },
        );

        if (newWeekErr) {
          results.push({ athlete_id: athleteId, success: false, error: newWeekErr.message });
        } else {
          results.push({ athlete_id: athleteId, success: true, new_week_id: newWeekId });
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

    const cookieGroupId = cookieStore.get("portal_group_id")?.value;
    if (cookieGroupId) {
      await auditLog({
        actorId: user.id,
        groupId: cookieGroupId,
        action: "training_plan.bulk_assign",
        targetType: "training_plan_week",
        targetId: source_week_id,
        metadata: {
          target_start_date,
          total_athletes: target_athlete_ids.length,
          success_count: successCount,
        },
      });
    }

    return NextResponse.json({ ok: true, data: { results, success_count: successCount } });
  } catch (err) {
    logger.error("POST /api/training-plan/bulk-assign", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}
