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

const CreateTemplateSchema = z.object({
  name:        z.string().min(1).max(80),
  description: z.string().max(500).optional().nullable(),
});

/**
 * GET /api/training-plan/week-templates
 *
 * Lists all week templates for the current group, with their workouts.
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

  const { data: templates, error } = await supabase
    .from("coaching_week_templates")
    .select(`
      id, name, description, created_at, updated_at,
      workouts:coaching_week_template_workouts (
        id, day_of_week, workout_order, workout_type, workout_label,
        description, coach_notes, blocks
      )
    `)
    .eq("group_id", groupId)
    .order("name");

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  const result = (templates ?? []).map((t) => {
    const workouts = (t.workouts ?? []).sort(
      (a: { day_of_week: number; workout_order: number }, b: { day_of_week: number; workout_order: number }) =>
        a.day_of_week !== b.day_of_week ? a.day_of_week - b.day_of_week : a.workout_order - b.workout_order,
    );
    const days = Array.from(new Set(workouts.map((w: { day_of_week: number }) => w.day_of_week))).sort((a, b) => a - b);
    return {
      id:           t.id,
      name:         t.name,
      description:  t.description ?? null,
      created_at:   t.created_at,
      workout_count: workouts.length,
      days_with_workouts: days,
      workouts,
    };
  });

  return NextResponse.json({ ok: true, data: result });
}, "GET /api/training-plan/week-templates");

/**
 * POST /api/training-plan/week-templates
 *
 * Creates a new (empty) week template. Workouts are added separately via
 * /week-templates/[templateId]/workouts.
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
  const parsed = CreateTemplateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const { data: template, error } = await supabase
    .from("coaching_week_templates")
    .insert({
      group_id:   groupId,
      name:       parsed.data.name,
      description: parsed.data.description ?? null,
      created_by: user.id,
    })
    .select("id, name, description, created_at")
    .single();

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: template }, { status: 201 });
}, "POST /api/training-plan/week-templates");
