import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";

function createClient() {
  const cookieStore = cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    { cookies: { getAll: () => cookieStore.getAll(), setAll: () => {} } },
  );
}

type Params = { params: { planId: string } };

/** GET /api/training-plan/[planId] — returns plan header with athlete info */
export async function GET(_req: NextRequest, { params }: Params) {
  try {
    const supabase = createClient();
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
    }

    const { data: plan, error } = await supabase
      .from("training_plans")
      .select("id, name, sport_type, status, starts_on, ends_on, athlete_user_id, group_id, description")
      .eq("id", params.planId)
      .single();

    if (error || !plan) {
      return NextResponse.json({ ok: false, error: { code: "NOT_FOUND" } }, { status: 404 });
    }

    let athleteName: string | null = null;
    let athleteAvatar: string | null = null;
    if (plan.athlete_user_id) {
      const { data: profile } = await supabase
        .from("profiles")
        .select("full_name, username, avatar_url")
        .eq("id", plan.athlete_user_id)
        .maybeSingle();
      if (profile) {
        athleteName = profile.full_name || profile.username || null;
        athleteAvatar = profile.avatar_url ?? null;
      }
    }

    return NextResponse.json({
      ok: true,
      data: {
        id: plan.id,
        name: plan.name,
        sport_type: plan.sport_type,
        status: plan.status,
        starts_on: plan.starts_on,
        ends_on: plan.ends_on,
        athlete_user_id: plan.athlete_user_id,
        athlete_name: athleteName,
        athlete_avatar: athleteAvatar,
        group_id: plan.group_id,
        description: plan.description,
      },
    });
  } catch (err) {
    logger.error("GET /api/training-plan/[planId]", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}
