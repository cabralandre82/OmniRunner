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

const SaveTemplateSchema = z.object({
  week_id:       z.string().uuid(),
  template_name: z.string().min(1).max(80),
});

/**
 * GET /api/training-plan/week-templates
 *
 * Lists all week templates for the current group, ordered by template name.
 * Returns the week id, template name, workout count, and a day-grid preview.
 */
export const GET = withErrorHandler(async (_req: NextRequest) => {
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

  // Fetch template weeks with their workouts
  const { data: weeks, error } = await supabase
    .from("training_plan_weeks")
    .select(`
      id, week_number, starts_on, ends_on, label, template_name,
      plan:plan_id ( group_id ),
      workouts:plan_workout_releases (
        id, scheduled_date, workout_order, workout_type, workout_label,
        release_status, template:template_id ( name )
      )
    `)
    .eq("is_week_template", true);

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  // Filter to the current group only (RLS should handle this, but be explicit)
  const groupWeeks = (weeks ?? []).filter(
    // @ts-expect-error Supabase nested type
    (w) => w.plan?.group_id === groupId,
  );

  const result = groupWeeks.map((w) => {
    const workouts = (w.workouts ?? []).filter(
      (x: { release_status: string }) =>
        !["cancelled", "replaced", "archived"].includes(x.release_status),
    );
    // Build day-grid: which days-of-week (0=Mon…6=Sun) have workouts
    const days = new Set(
      workouts.map((x: { scheduled_date: string }) => {
        const d = new Date(x.scheduled_date + "T00:00:00");
        return ((d.getDay() + 6) % 7); // 0=Mon … 6=Sun
      }),
    );
    return {
      id:            w.id,
      template_name: w.template_name ?? w.label ?? `Semana ${w.week_number}`,
      workout_count: workouts.length,
      days_with_workouts: Array.from(days).sort((a, b) => (a as number) - (b as number)),
      workouts: workouts.map((x: { scheduled_date: string; workout_type: string; workout_label: string | null; template: { name: string }[] | { name: string } | null }) => ({
        scheduled_date: x.scheduled_date,
        workout_type:   x.workout_type,
        workout_label:  x.workout_label,
        template_name:  Array.isArray(x.template) ? (x.template[0]?.name ?? null) : (x.template?.name ?? null),
      })),
    };
  });

  result.sort((a, b) => a.template_name.localeCompare(b.template_name));

  return NextResponse.json({ ok: true, data: result });
}, "GET /api/training-plan/week-templates");

/**
 * POST /api/training-plan/week-templates
 *
 * Marks an existing week as a reusable template and gives it a name.
 * { week_id, template_name }
 */
export const POST = withErrorHandler(async (req: NextRequest) => {
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

  const body = await req.json().catch(() => null);
  const parsed = SaveTemplateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const { week_id, template_name } = parsed.data;

  // Verify the week belongs to this group
  const { data: week, error: weekErr } = await supabase
    .from("training_plan_weeks")
    .select("id, plan:plan_id ( group_id )")
    .eq("id", week_id)
    .single();

  if (weekErr || !week) {
    return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });
  }
  // @ts-expect-error Supabase nested type
  if (week.plan?.group_id !== groupId) {
    return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
  }

  const { error: updateErr } = await supabase
    .from("training_plan_weeks")
    .update({ is_week_template: true, template_name, updated_at: new Date().toISOString() })
    .eq("id", week_id);

  if (updateErr) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: updateErr.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: { week_id, template_name } });
}, "POST /api/training-plan/week-templates");

/**
 * DELETE /api/training-plan/week-templates?weekId=xxx
 *
 * Removes the template flag from a week (does NOT delete the week itself).
 */
export const DELETE = withErrorHandler(async (req: NextRequest) => {
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

  const weekId = new URL(req.url).searchParams.get("weekId");
  if (!weekId) {
    return NextResponse.json({ ok: false, error: { code: "MISSING_WEEK_ID" } }, { status: 422 });
  }

  const { data: week } = await supabase
    .from("training_plan_weeks")
    .select("id, plan:plan_id ( group_id )")
    .eq("id", weekId)
    .single();

  // @ts-expect-error Supabase nested type
  if (!week || week.plan?.group_id !== groupId) {
    return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
  }

  await supabase
    .from("training_plan_weeks")
    .update({ is_week_template: false, template_name: null, updated_at: new Date().toISOString() })
    .eq("id", weekId);

  return NextResponse.json({ ok: true });
}, "DELETE /api/training-plan/week-templates");
