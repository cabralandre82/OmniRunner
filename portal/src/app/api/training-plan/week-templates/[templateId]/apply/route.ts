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

type Params = { params: { templateId: string } };

const OverrideSchema = z.object({
  template_workout_id: z.string().uuid(),
  workout_label:       z.string().max(120).optional(),
  workout_type:        z.string().optional(),
  description:         z.string().max(2000).nullable().optional(),
  coach_notes:         z.string().max(500).nullable().optional(),
  blocks:              z.array(z.unknown()).optional(),
  remove:              z.boolean().optional(),
});

const ApplySchema = z.object({
  plan_week_id:    z.string().uuid(),
  athlete_id:      z.string().uuid(),
  week_start_date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  auto_release:    z.boolean().default(false),
  overrides:       z.array(OverrideSchema).default([]),
});

/**
 * POST /api/training-plan/week-templates/[templateId]/apply
 *
 * Applies a template to an athlete's plan week.
 * Each template workout becomes a plan_workout_release (draft or released).
 * Optional overrides allow per-workout customization before saving.
 */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
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
  const parsed = ApplySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 },
    );
  }

  const { plan_week_id, athlete_id, week_start_date, auto_release, overrides } = parsed.data;

  const { data: count, error } = await supabase.rpc("fn_apply_week_template", {
    p_template_id:     params.templateId,
    p_plan_week_id:    plan_week_id,
    p_athlete_id:      athlete_id,
    p_week_start_date: week_start_date,
    p_auto_release:    auto_release,
    p_overrides:       overrides,
  });

  if (error) {
    const code = error.message.includes("template_not_found") ? "TEMPLATE_NOT_FOUND"
      : error.message.includes("forbidden")          ? "FORBIDDEN"
      : error.message.includes("athlete_not_member") ? "ATHLETE_NOT_MEMBER"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "TEMPLATE_NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  await auditLog({
    actorId:    user.id,
    groupId,
    action:     "week_template.applied",
    targetType: "coaching_week_template",
    targetId:   params.templateId,
    metadata:   { plan_week_id, athlete_id, workouts_created: count, auto_release },
  });

  return NextResponse.json({ ok: true, data: { workouts_created: count } });
}, "POST /api/training-plan/week-templates/[templateId]/apply");
