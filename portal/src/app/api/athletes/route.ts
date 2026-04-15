import { NextResponse } from "next/server";
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

/**
 * GET /api/athletes
 *
 * Returns active athlete members of the coach's group (read from session cookie).
 * Used by training-plan/new to populate the athlete dropdown.
 */
export async function GET() {
  try {
    const cookieStore = cookies();
    const groupId = cookieStore.get("portal_group_id")?.value;

    if (!groupId) {
      return NextResponse.json(
        { ok: false, error: { code: "NO_GROUP_SESSION" } },
        { status: 403 },
      );
    }

    const supabase = createClient();
    const {
      data: { user },
      error: authErr,
    } = await supabase.auth.getUser();

    if (authErr || !user) {
      return NextResponse.json(
        { ok: false, error: { code: "UNAUTHORIZED" } },
        { status: 401 },
      );
    }

    const { data: members, error } = await supabase
      .from("coaching_members")
      .select(
        `
        user_id,
        profiles (
          full_name,
          username,
          avatar_url
        )
      `,
      )
      .eq("group_id", groupId)
      .eq("role", "athlete")
      .eq("status", "active")
      .order("user_id");

    if (error) {
      logger.error("GET /api/athletes — DB error", error);
      return NextResponse.json(
        { ok: false, error: { code: "DB_ERROR", message: error.message } },
        { status: 500 },
      );
    }

    const result = (members ?? []).map((m) => {
      const profile = Array.isArray(m.profiles) ? m.profiles[0] : m.profiles;
      return {
        user_id: m.user_id,
        display_name:
          (profile as { full_name?: string; username?: string } | null)
            ?.full_name ||
          (profile as { full_name?: string; username?: string } | null)
            ?.username ||
          "Atleta",
        avatar_url:
          (profile as { avatar_url?: string | null } | null)?.avatar_url ??
          null,
      };
    });

    return NextResponse.json({ ok: true, data: result });
  } catch (err) {
    logger.error("GET /api/athletes", err);
    return NextResponse.json(
      { ok: false, error: { code: "INTERNAL_ERROR" } },
      { status: 500 },
    );
  }
}
