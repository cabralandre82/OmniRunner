import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { withErrorHandler } from "@/lib/api-handler";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

/**
 * GET /api/training-plan/templates?groupId=xxx
 *
 * Returns workout templates available for the group, enriched with
 * block count and estimated distance, sorted by name.
 */
export const GET = withErrorHandler(async (req: NextRequest) => {
  const { searchParams } = new URL(req.url);
  const requestedGroupId = searchParams.get("groupId");

  const cookieStore = cookies();
  const sessionGroupId = cookieStore.get("portal_group_id")?.value;

  const groupId = requestedGroupId ?? sessionGroupId;
  if (!groupId) {
    return NextResponse.json({ ok: false, error: { code: "NO_GROUP" } }, { status: 400 });
  }

  const supabase = createClient();
  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
  }

  const { data: templates, error } = await supabase
    .from("coaching_workout_templates")
    .select(`
      id,
      name,
      description,
      sport_type,
      workout_type,
      coaching_workout_blocks (
        id,
        distance_meters,
        duration_seconds
      )
    `)
    .eq("group_id", groupId)
    .eq("is_active", true)
    .order("name");

  if (error) {
    return NextResponse.json(
      { ok: false, error: { code: "DB_ERROR", message: error.message } },
      { status: 500 },
    );
  }

  const enriched = (templates ?? []).map((t) => {
    const blocks = Array.isArray(t.coaching_workout_blocks)
      ? t.coaching_workout_blocks
      : [];
    const totalDistanceM = blocks.reduce(
      (sum: number, b: { distance_meters: number | null }) => sum + (b.distance_meters ?? 0),
      0,
    );
    return {
      id: t.id,
      name: t.name,
      description: t.description,
      sport_type: t.sport_type,
      workout_type: t.workout_type,
      estimated_distance_m: totalDistanceM > 0 ? totalDistanceM : null,
      block_count: blocks.length,
    };
  });

  return NextResponse.json({ ok: true, data: enriched });
}, "GET /api/training-plan/templates");
