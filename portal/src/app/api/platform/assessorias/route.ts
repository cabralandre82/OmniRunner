import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return { error: "Not authenticated", status: 401 };
  }

  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (profile?.platform_role !== "admin") {
    return { error: "Not a platform admin", status: 403 };
  }

  return { user };
}

export async function POST(req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { error: auth.error },
      { status: auth.status },
    );
  }

  const body = await req.json();
  const { action, group_id, reason } = body as {
    action: string;
    group_id: string;
    reason?: string;
  };

  if (!action || !group_id) {
    return NextResponse.json(
      { error: "Missing action or group_id" },
      { status: 400 },
    );
  }

  const admin = createAdminClient();

  if (action === "approve") {
    const { error } = await admin
      .from("coaching_groups")
      .update({
        approval_status: "approved",
        approval_reviewed_at: new Date().toISOString(),
        approval_reviewed_by: auth.user.id,
        approval_reject_reason: null,
      })
      .eq("id", group_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "approved", group_id });
  }

  if (action === "reject") {
    const { error } = await admin
      .from("coaching_groups")
      .update({
        approval_status: "rejected",
        approval_reviewed_at: new Date().toISOString(),
        approval_reviewed_by: auth.user.id,
        approval_reject_reason: reason ?? "",
      })
      .eq("id", group_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "rejected", group_id });
  }

  if (action === "suspend") {
    const { error } = await admin
      .from("coaching_groups")
      .update({
        approval_status: "suspended",
        approval_reviewed_at: new Date().toISOString(),
        approval_reviewed_by: auth.user.id,
        approval_reject_reason: reason ?? "",
      })
      .eq("id", group_id);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ status: "suspended", group_id });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
