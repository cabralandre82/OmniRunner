import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { withErrorHandler } from "@/lib/api-handler";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

/**
 * GET /api/training-plan/group-week-view?weekStart=YYYY-MM-DD
 *
 * Returns all athletes in the group with their workouts for the requested week.
 * Used by the "Visão Grupo" tab in the training plan section.
 *
 * If weekStart is omitted, defaults to the current Monday.
 *
 * Response shape:
 * {
 *   week_start: string,
 *   week_end: string,
 *   athletes: Array<{
 *     user_id, display_name, avatar_url, plan_id | null,
 *     workouts: Array<{ id, scheduled_date, workout_type, workout_label,
 *                       release_status, template_name | null }>
 *   }>
 * }
 */
export const GET = withErrorHandler(async (req: NextRequest) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });
  }

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  // Resolve week start
  const rawStart = new URL(req.url).searchParams.get("weekStart");
  let weekStart: string;
  if (rawStart && /^\d{4}-\d{2}-\d{2}$/.test(rawStart)) {
    weekStart = rawStart;
  } else {
    const today = new Date();
    const dow = today.getDay(); // 0=Sun
    const offsetToMon = (dow === 0 ? -6 : 1 - dow);
    const mon = new Date(today);
    mon.setDate(today.getDate() + offsetToMon);
    weekStart = mon.toISOString().split("T")[0];
  }
  const weekEnd = new Date(weekStart + "T00:00:00");
  weekEnd.setDate(weekEnd.getDate() + 6);
  const weekEndStr = weekEnd.toISOString().split("T")[0];

  // 1. Athletes
  const { data: members, error: membersErr } = await supabase
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("role", "athlete");

  if (membersErr) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: membersErr.message } }, { status: 500 });
  }
  if (!members?.length) {
    return NextResponse.json({ ok: true, data: { week_start: weekStart, week_end: weekEndStr, athletes: [] } });
  }

  const athleteIds = members.map((m) => m.user_id);

  // 2. Profiles
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, display_name, avatar_url")
    .in("id", athleteIds);
  const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

  // 3. Active plans
  const { data: plans } = await supabase
    .from("training_plans")
    .select("id, athlete_user_id")
    .eq("group_id", groupId)
    .in("athlete_user_id", athleteIds)
    .in("status", ["active", "paused"])
    .order("created_at", { ascending: false });

  const planByAthlete = new Map<string, string>();
  for (const p of plans ?? []) {
    if (!planByAthlete.has(p.athlete_user_id)) planByAthlete.set(p.athlete_user_id, p.id);
  }
  const planIds = Array.from(new Set(planByAthlete.values()));

  // 4. Weeks covering the requested range
  const weekIdByPlan = new Map<string, string>();
  if (planIds.length > 0) {
    const { data: weeks } = await supabase
      .from("training_plan_weeks")
      .select("id, plan_id")
      .in("plan_id", planIds)
      .lte("starts_on", weekEndStr)
      .gte("ends_on", weekStart);

    for (const w of weeks ?? []) {
      if (!weekIdByPlan.has(w.plan_id)) weekIdByPlan.set(w.plan_id, w.id);
    }
  }

  // 5. Workouts in those weeks, restricted to the date range
  const weekIds = Array.from(weekIdByPlan.values());
  const releasesByAthlete = new Map<string, {
    id: string; scheduled_date: string; workout_type: string;
    workout_label: string | null; release_status: string; template_name: string | null;
  }[]>();

  if (weekIds.length > 0) {
    const { data: releases } = await supabase
      .from("plan_workout_releases")
      .select(`
        id, athlete_user_id, scheduled_date, workout_type,
        workout_label, release_status,
        template:template_id ( name )
      `)
      .in("plan_week_id", weekIds)
      .gte("scheduled_date", weekStart)
      .lte("scheduled_date", weekEndStr)
      .not("release_status", "in", "(cancelled,replaced,archived)")
      .order("workout_order");

    for (const r of releases ?? []) {
      if (!releasesByAthlete.has(r.athlete_user_id)) releasesByAthlete.set(r.athlete_user_id, []);
      const tplName = Array.isArray(r.template)
        ? (r.template[0]?.name ?? null)
        : ((r.template as { name: string } | null)?.name ?? null);
      releasesByAthlete.get(r.athlete_user_id)!.push({
        id:             r.id,
        scheduled_date: r.scheduled_date,
        workout_type:   r.workout_type,
        workout_label:  r.workout_label,
        release_status: r.release_status,
        template_name:  tplName,
      });
    }
  }

  // 6. Assemble
  const athletes = athleteIds.map((athleteId) => {
    const profile = profileMap.get(athleteId);
    const planId  = planByAthlete.get(athleteId) ?? null;
    return {
      user_id:      athleteId,
      display_name: profile?.display_name ?? "Atleta",
      avatar_url:   profile?.avatar_url ?? null,
      plan_id:      planId,
      workouts:     releasesByAthlete.get(athleteId) ?? [],
    };
  });

  athletes.sort((a, b) => a.display_name.localeCompare(b.display_name));

  return NextResponse.json({
    ok: true,
    data: { week_start: weekStart, week_end: weekEndStr, athletes },
  });
}, "GET /api/training-plan/group-week-view");
