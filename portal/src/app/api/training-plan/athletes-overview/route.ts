import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { withErrorHandler } from "@/lib/api-handler";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

/**
 * GET /api/training-plan/athletes-overview
 *
 * Returns all athletes in the current group enriched with their training status:
 * - Active plan (if any)
 * - Current week (week that covers today, or most recent)
 * - Workout counts per status
 * - Fatigue alert based on avg RPE of last 5 feedbacks
 */
export const GET = withErrorHandler(async (_req: NextRequest) => {
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

  // 1. Athletes in group
  const { data: members, error: membersErr } = await supabase
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("role", "athlete");

  if (membersErr) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: membersErr.message } }, { status: 500 });
  }

  if (!members?.length) {
    return NextResponse.json({ ok: true, data: [] });
  }

  const athleteIds = members.map((m) => m.user_id);

  // 2. Profiles
  const { data: profiles } = await supabase
    .from("profiles")
    .select("id, display_name, avatar_url")
    .in("id", athleteIds);

  const profileMap = new Map((profiles ?? []).map((p) => [p.id, p]));

  // 3. Active training plans (one per athlete — most recent)
  const { data: plans } = await supabase
    .from("training_plans")
    .select("id, name, athlete_user_id, status")
    .eq("group_id", groupId)
    .in("athlete_user_id", athleteIds)
    .in("status", ["active", "paused"])
    .order("created_at", { ascending: false });

  const planByAthlete = new Map<string, { id: string; name: string; status: string }>();
  for (const p of plans ?? []) {
    if (!planByAthlete.has(p.athlete_user_id)) {
      planByAthlete.set(p.athlete_user_id, { id: p.id, name: p.name, status: p.status });
    }
  }

  const planIds = Array.from(planByAthlete.values()).map((p) => p.id);

  // Maps keyed by plan_id, populated below
  const weekByPlan = new Map<string, {
    id: string; week_number: number; starts_on: string; ends_on: string; status: string;
  }>();
  const countsByPlan = new Map<string, { total: number; draft: number; released: number; completed: number }>();

  if (planIds.length > 0) {
    const today = new Date().toISOString().split("T")[0];

    // 4. Most relevant week per plan (covers today, or else most recent)
    const { data: weeks } = await supabase
      .from("training_plan_weeks")
      .select("id, plan_id, week_number, starts_on, ends_on, status")
      .in("plan_id", planIds)
      .order("starts_on", { ascending: false });

    for (const w of weeks ?? []) {
      const existing = weekByPlan.get(w.plan_id);
      if (!existing) {
        weekByPlan.set(w.plan_id, w);
        continue;
      }
      const coversToday   = w.starts_on <= today && w.ends_on >= today;
      const existingToday = existing.starts_on <= today && existing.ends_on >= today;
      if (coversToday && !existingToday) weekByPlan.set(w.plan_id, w);
    }

    const weekIds = Array.from(weekByPlan.values()).map((w) => w.id);

    if (weekIds.length > 0) {
      // 5. Workout counts per week
      const { data: releases } = await supabase
        .from("plan_workout_releases")
        .select("plan_week_id, release_status")
        .in("plan_week_id", weekIds)
        .not("release_status", "in", "(cancelled,replaced,archived)");

      const rawCounts = new Map<string, { total: number; draft: number; released: number; completed: number }>();
      for (const r of releases ?? []) {
        if (!rawCounts.has(r.plan_week_id)) {
          rawCounts.set(r.plan_week_id, { total: 0, draft: 0, released: 0, completed: 0 });
        }
        const c = rawCounts.get(r.plan_week_id)!;
        c.total++;
        if (["draft", "scheduled"].includes(r.release_status)) c.draft++;
        else if (["released", "in_progress"].includes(r.release_status)) c.released++;
        else if (r.release_status === "completed") c.completed++;
      }

      // Re-key by plan_id
    const weekToPlan = new Map<string, string>();
    weekByPlan.forEach((week, planId) => weekToPlan.set(week.id, planId));
    rawCounts.forEach((counts, weekId) => {
      const planId = weekToPlan.get(weekId);
      if (planId) countsByPlan.set(planId, counts);
    });
  }
  }

  // 6. Recent avg RPE per athlete (last 5 feedbacks with perceived_effort)
  const rpeByAthlete = new Map<string, number>();
  if (athleteIds.length > 0) {
    const { data: feedbacks } = await supabase
      .from("athlete_workout_feedback")
      .select("athlete_user_id, perceived_effort")
      .in("athlete_user_id", athleteIds)
      .not("perceived_effort", "is", null)
      .order("submitted_at", { ascending: false })
      .limit(athleteIds.length * 5);

    const buckets = new Map<string, number[]>();
    for (const f of feedbacks ?? []) {
      if (!buckets.has(f.athlete_user_id)) buckets.set(f.athlete_user_id, []);
      const list = buckets.get(f.athlete_user_id)!;
      if (list.length < 5) list.push(f.perceived_effort);
    }
    buckets.forEach((rpes, id) => {
      rpeByAthlete.set(id, rpes.reduce((a: number, b: number) => a + b, 0) / rpes.length);
    });
  }

  // Assemble result
  const result = athleteIds.map((athleteId) => {
    const profile = profileMap.get(athleteId);
    const plan = planByAthlete.get(athleteId) ?? null;
    const week = plan ? (weekByPlan.get(plan.id) ?? null) : null;
    const counts = plan ? (countsByPlan.get(plan.id) ?? null) : null;
    const avgRpe = rpeByAthlete.get(athleteId) ?? null;

    return {
      user_id:       athleteId,
      display_name:  profile?.display_name ?? "Atleta",
      avatar_url:    profile?.avatar_url ?? null,
      plan,
      current_week: week
        ? {
            id:           week.id,
            week_number:  week.week_number,
            starts_on:    week.starts_on,
            ends_on:      week.ends_on,
            status:       week.status,
            total:        counts?.total    ?? 0,
            draft:        counts?.draft    ?? 0,
            released:     counts?.released ?? 0,
            completed:    counts?.completed ?? 0,
          }
        : null,
      avg_rpe_last5: avgRpe,
      fatigue_alert: avgRpe !== null && avgRpe >= 8,
    };
  });

  // Sort: with plan first → by fatigue alert → by name
  result.sort((a, b) => {
    if (a.plan && !b.plan) return -1;
    if (!a.plan && b.plan) return 1;
    if (a.fatigue_alert && !b.fatigue_alert) return -1;
    if (!a.fatigue_alert && b.fatigue_alert) return 1;
    return a.display_name.localeCompare(b.display_name);
  });

  return NextResponse.json({ ok: true, data: result });
}, "GET /api/training-plan/athletes-overview");
