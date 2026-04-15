import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { logger } from "@/lib/logger";
import { MANAGER_ROLES } from "@/lib/roles";

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
        .select("display_name, avatar_url")
        .eq("id", plan.athlete_user_id)
        .maybeSingle();
      if (profile) {
        athleteName = profile.display_name || null;
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

/**
 * PATCH /api/training-plan/[planId]
 *
 * Updates plan status (e.g. restore archived plan back to active).
 */
export async function PATCH(req: NextRequest, { params }: Params) {
  try {
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
    const { status } = body as { status?: string };
    const allowed = ["active", "paused", "completed", "archived"];
    if (!status || !allowed.includes(status)) {
      return NextResponse.json({ ok: false, error: { code: "INVALID_STATUS" } }, { status: 422 });
    }

    const { error } = await supabase
      .from("training_plans")
      .update({ status, updated_at: new Date().toISOString() })
      .eq("id", params.planId)
      .eq("group_id", groupId);

    if (error) {
      return NextResponse.json({ ok: false, error: { code: "DB_ERROR", message: error.message } }, { status: 500 });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    logger.error("PATCH /api/training-plan/[planId]", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}

/**
 * DELETE /api/training-plan/[planId]
 *
 * Soft-deletes the plan by setting status = 'archived'.
 * The plan disappears from all list views (which filter out archived).
 * Only managers of the owning group can archive.
 */
export async function DELETE(_req: NextRequest, { params }: Params) {
  try {
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

    const { data: membership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!membership || !MANAGER_ROLES.includes(membership.role as never)) {
      return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
    }

    const { error } = await supabase
      .from("training_plans")
      .update({ status: "archived", updated_at: new Date().toISOString() })
      .eq("id", params.planId)
      .eq("group_id", groupId);

    if (error) {
      return NextResponse.json(
        { ok: false, error: { code: "DB_ERROR", message: error.message } },
        { status: 500 },
      );
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    logger.error("DELETE /api/training-plan/[planId]", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}
