import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";
import { auditLog } from "@/lib/audit";
import { MANAGER_ROLES } from "@/lib/roles";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const CreatePlanSchema = z.object({
  athlete_user_id: z.string().uuid().optional(),
  name: z.string().min(2).max(120),
  description: z.string().max(500).optional(),
  sport_type: z.enum(["running", "cycling", "triathlon", "swimming", "strength", "multi"]).default("running"),
  starts_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  ends_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export const GET = withErrorHandler(async (_req: NextRequest) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ ok: false, error: { code: "NO_GROUP", message: "Grupo não selecionado" } }, { status: 400 });
  }

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED", message: "Não autenticado" } }, { status: 401 });
  }

  const { data: member } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .single();

  if (!member || !MANAGER_ROLES.includes(member.role as never)) {
    return NextResponse.json({ ok: false, error: { code: "FORBIDDEN", message: "Sem permissão" } }, { status: 403 });
  }

  const { data, error } = await supabase
    .from("training_plans")
    .select(`
      id, name, description, sport_type, status, starts_on, ends_on,
      created_at, updated_at,
      athlete:athlete_user_id (id, raw_user_meta_data),
      weeks:training_plan_weeks (count)
    `)
    .eq("group_id", groupId)
    .neq("status", "archived")
    .order("created_at", { ascending: false })
    .range(0, 49);

  if (error) {
    return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
  }

  return NextResponse.json({ ok: true, data });
}, "GET /api/training-plan");

export const POST = withErrorHandler(async (req: NextRequest) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ ok: false, error: { code: "NO_GROUP", message: "Grupo não selecionado" } }, { status: 400 });
  }

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED", message: "Não autenticado" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = CreatePlanSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", message: "Dados inválidos", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { name, description, sport_type, starts_on, ends_on, athlete_user_id } = parsed.data;

  const { data: planId, error } = await supabase.rpc("fn_create_training_plan", {
    p_group_id: groupId,
    p_athlete_user_id: athlete_user_id ?? null,
    p_name: name,
    p_description: description ?? null,
    p_sport_type: sport_type,
    p_starts_on: starts_on ?? null,
    p_ends_on: ends_on ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("athlete_not_member") ? "ATHLETE_NOT_MEMBER"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "ATHLETE_NOT_MEMBER" ? 422 : 500;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  await auditLog({
    actorId: user.id,
    groupId,
    action: "training_plan.created",
    targetType: "training_plan",
    targetId: planId,
    metadata: { name, sport_type, athlete_user_id },
  });

  return NextResponse.json({ ok: true, data: { id: planId } }, { status: 201 });
}, "POST /api/training-plan");
