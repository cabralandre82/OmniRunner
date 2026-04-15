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

type Params = { params: { groupId: string } };

/**
 * GET /api/groups/[groupId]/members
 *
 * Returns active athlete members in the group, used for batch assignment.
 */
export async function GET(_req: NextRequest, { params }: Params) {
  try {
    const cookieStore = cookies();
    const sessionGroupId = cookieStore.get("portal_group_id")?.value;

    if (sessionGroupId !== params.groupId) {
      return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
    }

    const supabase = createClient();
    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return NextResponse.json({ ok: false, error: { code: "UNAUTHORIZED" } }, { status: 401 });
    }

    const { data: callerMembership } = await supabase
      .from("coaching_members")
      .select("role")
      .eq("group_id", params.groupId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!callerMembership) {
      return NextResponse.json({ ok: false, error: { code: "FORBIDDEN" } }, { status: 403 });
    }

    const { data: members, error } = await supabase
      .from("coaching_members")
      .select(`
        user_id,
        display_name,
        role,
        profiles (
          display_name,
          avatar_url
        )
      `)
      .eq("group_id", params.groupId)
      .eq("role", "athlete")
      .eq("status", "active")
      .order("display_name");

    if (error) {
      return NextResponse.json(
        { ok: false, error: { code: "DB_ERROR", message: error.message } },
        { status: 500 },
      );
    }

    const result = (members ?? []).map((m) => {
      const profile = Array.isArray(m.profiles) ? m.profiles[0] : m.profiles;
      return {
        user_id: m.user_id,
        display_name: m.display_name
          || (profile as { display_name?: string } | null)?.display_name
          || "Atleta",
        avatar_url: (profile as { avatar_url?: string | null } | null)?.avatar_url ?? null,
      };
    });

    return NextResponse.json({ ok: true, data: result });
  } catch (err) {
    logger.error("GET /api/groups/[groupId]/members", err);
    return NextResponse.json({ ok: false, error: { code: "INTERNAL_ERROR" } }, { status: 500 });
  }
}
