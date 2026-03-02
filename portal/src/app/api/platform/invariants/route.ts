import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Not authenticated", status: 401 } as const;

  const { data: membership } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", user.id)
    .single();

  if (!membership) return { error: "Forbidden", status: 403 } as const;

  return { user } as const;
}

export async function GET() {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const db = createServiceClient();

  const { data: violations, error } = await db.rpc(
    "check_custody_invariants",
  );

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const healthy = !violations || violations.length === 0;

  return NextResponse.json({
    healthy,
    violations: violations ?? [],
    checked_at: new Date().toISOString(),
  });
}
