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

const DuplicateWeekSchema = z.object({
  target_starts_on: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "Must be YYYY-MM-DD Monday"),
  target_plan_id: z.string().uuid().optional(),
});

type Params = { params: { weekId: string } };

export const POST = withErrorHandler(async (req: NextRequest, { params }: Params) => {
  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const body = await req.json().catch(() => null);
  const parsed = DuplicateWeekSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { ok: false, error: { code: "VALIDATION_ERROR", details: parsed.error.flatten() } },
      { status: 422 }
    );
  }

  const { data: newWeekId, error } = await supabase.rpc("fn_duplicate_week", {
    p_source_week_id:   params.weekId,
    p_target_starts_on: parsed.data.target_starts_on,
    p_target_plan_id:   parsed.data.target_plan_id ?? null,
  });

  if (error) {
    const code = error.message.includes("forbidden") ? "FORBIDDEN"
      : error.message.includes("source_week_not_found") ? "WEEK_NOT_FOUND"
      : error.message.includes("week_must_start_on_monday") ? "WEEK_MUST_START_ON_MONDAY"
      : "DB_ERROR";
    const status = code === "FORBIDDEN" ? 403 : code === "WEEK_NOT_FOUND" ? 404 : 422;
    return NextResponse.json({ ok: false, error: { code, message: error.message } }, { status });
  }

  return NextResponse.json({ ok: true, data: { id: newWeekId } }, { status: 201 });
}, "POST /api/training-plan/weeks/[weekId]/duplicate");
