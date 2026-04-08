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
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const BulkReleaseSchema = z.object({ reason: z.string().max(200).optional() });

type Params = { params: { weekId: string } };

/** POST /api/training-plan/weeks/[weekId]/release — libera todos os treinos da semana */
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

  const body = await req.json().catch(() => ({}));
  const parsed = BulkReleaseSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: { code: "VALIDATION_ERROR" } }, { status: 422 });
  }

  const { data: count, error } = await supabase.rpc("fn_bulk_release_week", {
    p_plan_week_id: params.weekId,
    p_reason: parsed.data.reason ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("week_not_found") ? "WEEK_NOT_FOUND"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "WEEK_NOT_FOUND" ? 404 : 500;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  await auditLog({
    actorId: user.id,
    groupId,
    action: "training_plan_week.bulk_released",
    targetType: "training_plan_week",
    targetId: params.weekId,
    metadata: { released_count: count, reason: parsed.data.reason },
  });

  return NextResponse.json({ ok: true, data: { released_count: count } });
}, "POST /api/training-plan/weeks/[weekId]/release");
