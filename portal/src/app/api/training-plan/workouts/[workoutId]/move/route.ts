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
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } }
  );
}

const MoveSchema = z.object({
  target_date:    z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  target_week_id: z.string().uuid().optional(),
  reason:         z.string().max(200).optional(),
});

type Params = { params: { workoutId: string } };

/** POST /api/training-plan/workouts/[workoutId]/move */
export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = MoveSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { data: result, error } = await supabase.rpc("fn_move_workout", {
    p_release_id:    params.workoutId,
    p_target_date:   parsed.data.target_date,
    p_target_week_id: parsed.data.target_week_id ?? null,
    p_reason:        parsed.data.reason ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("release_not_found") ? "NOT_FOUND"
      : error.message.includes("cannot_move_terminal_status") ? "TERMINAL_STATUS"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  return NextResponse.json({ ok: true, data: { result } });
}, "POST /api/training-plan/workouts/[workoutId]/move");
