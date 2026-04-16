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

type Params = { params: { templateId: string } };

const UpdateTemplateSchema = z.object({
  name:        z.string().min(1).max(80).optional(),
  description: z.string().max(500).nullable().optional(),
});

async function getTemplateForGroup(supabase: ReturnType<typeof createClient>, templateId: string, groupId: string) {
  const { data, error } = await supabase
    .from("coaching_week_templates")
    .select("id, group_id, name, description")
    .eq("id", templateId)
    .single();
  if (error || !data) return null;
  if (data.group_id !== groupId) return null;
  return data;
}

/**
 * GET /api/training-plan/week-templates/[templateId]
 * Returns a single template with all its workouts.
 */
export const GET = withErrorHandler(async (_req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const { data: template, error } = await supabase
    .from("coaching_week_templates")
    .select(`
      id, name, description, created_at, updated_at,
      workouts:coaching_week_template_workouts (
        id, day_of_week, workout_order, workout_type, workout_label,
        description, coach_notes, blocks
      )
    `)
    .eq("id", params.templateId)
    .eq("group_id", groupId)
    .single();

  if (error || !template) {
    return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });
  }

  const workouts = (template.workouts ?? []).sort(
    (a: { day_of_week: number; workout_order: number }, b: { day_of_week: number; workout_order: number }) =>
      a.day_of_week !== b.day_of_week ? a.day_of_week - b.day_of_week : a.workout_order - b.workout_order,
  );

  return NextResponse.json({ ok: true, data: { ...template, workouts } });
}, "GET /api/training-plan/week-templates/[templateId]");

/**
 * PATCH /api/training-plan/week-templates/[templateId]
 * Updates template name/description.
 */
export const PATCH = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const tpl = await getTemplateForGroup(supabase, params.templateId, groupId);
  if (!tpl) return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });

  const body = await req.json().catch(() => null);
  const parsed = UpdateTemplateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const updates: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (parsed.data.name !== undefined)        updates.name        = parsed.data.name;
  if (parsed.data.description !== undefined) updates.description = parsed.data.description;

  const { data: updated, error } = await supabase
    .from("coaching_week_templates")
    .update(updates)
    .eq("id", params.templateId)
    .select("id, name, description, updated_at")
    .single();

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data: updated });
}, "PATCH /api/training-plan/week-templates/[templateId]");

/**
 * DELETE /api/training-plan/week-templates/[templateId]
 * Deletes a template and all its workouts (cascade).
 */
export const DELETE = withErrorHandler(async (_req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });

  const tpl = await getTemplateForGroup(supabase, params.templateId, groupId);
  if (!tpl) return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });

  const { error } = await supabase
    .from("coaching_week_templates")
    .delete()
    .eq("id", params.templateId);

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}, "DELETE /api/training-plan/week-templates/[templateId]");
