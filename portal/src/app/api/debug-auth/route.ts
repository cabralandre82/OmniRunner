import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = createClient();

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({
      status: "no_user",
      error: userError?.message ?? "No session",
    });
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id, display_name, user_role, platform_role")
    .eq("id", user.id)
    .single();

  return NextResponse.json({
    auth_user_id: user.id,
    auth_email: user.email,
    auth_provider: user.app_metadata?.provider,
    profile_found: !!profile,
    profile_data: profile,
    profile_error: profileError?.message ?? null,
  });
}
