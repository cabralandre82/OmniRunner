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

const CancelSchema = z.object({ reason: z.string().max(200).optional() });

type Params = { params: { workoutId: string } };

/** POST /api/training-plan/workouts/[workoutId]/cancel */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const cookieStore = cookies();
  const groupId = cookieStore.get("portal_group_id")?.value;

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => ({}));
  const parsed = CancelSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ ok: false, error: { code: "VALIDATION_ERROR" } }, { status: 422 });
  }

  const { data: result, error } = await supabase.rpc("fn_cancel_workout", {
    p_release_id: params.workoutId,
    p_reason: parsed.data.reason ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("release_not_found") ? "NOT_FOUND"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404 : 500;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  if (groupId) {
    await auditLog({
      actorId: user.id,
      groupId,
      action: "workout_release.cancelled",
      targetType: "plan_workout_release",
      targetId: params.workoutId,
      metadata: { result, reason: parsed.data.reason },
    });
  }

  return NextResponse.json({ ok: true, data: { result } });
}, "POST /api/training-plan/workouts/[workoutId]/cancel");
