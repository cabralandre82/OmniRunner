import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { platformAssessoriaActionSchema } from "@/lib/schemas";
import { withErrorHandler } from "@/lib/api-handler";

// L17-01 — endpoint financeiro/operacional crítico: aprova/suspende
// assessorias (`coaching_groups.approval_status`). Outermost wrapper
// garante 500 canônico + Sentry + x-request-id em qualquer throw.
export const POST = withErrorHandler(_post, "api.platform.assessorias.post");

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

async function _post(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`platform-assessorias:${ip}`, { maxRequests: 20, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json(
      { error: auth.error },
      { status: auth.status },
    );
  }

  const body = await req.json();
  const parsed = platformAssessoriaActionSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0]?.message ?? "Invalid input" },
      { status: 400 },
    );
  }
  const { action, group_id, reason } = parsed.data;

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

    await auditLog({ actorId: auth.user.id, action: "platform.approve_assessoria", targetType: "group", targetId: group_id });
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

    await auditLog({ actorId: auth.user.id, action: "platform.reject_assessoria", targetType: "group", targetId: group_id, metadata: { reason } });
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

    await auditLog({ actorId: auth.user.id, action: "platform.suspend_assessoria", targetType: "group", targetId: group_id, metadata: { reason } });
    return NextResponse.json({ status: "suspended", group_id });
  }

  return NextResponse.json({ error: "Invalid action" }, { status: 400 });
}
