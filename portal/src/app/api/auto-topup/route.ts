import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { autoTopupSchema } from "@/lib/schemas";
import { withErrorHandler } from "@/lib/api-handler";
import type { NextRequest } from "next/server";

// L17-01 — outermost safety-net: throws inesperados (DB outage no insert,
// audit log crash) viram 500 INTERNAL_ERROR canônico em vez de stack
// trace cru. Antes desta refatoração existia um try/catch no top-level
// que devolvia "Erro interno" pt-BR (também flagrado em L07-01).
export const POST = withErrorHandler(_post, "api.auto-topup.post");

async function _post(request: NextRequest) {
  const rl = await rateLimit(`auto-topup:${request.headers.get("x-forwarded-for") ?? "unknown"}`);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group selected" }, { status: 400 });
  }

  const db = createServiceClient();

  // Verify admin_master
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || membership.role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();
  const parsed = autoTopupSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const { enabled, threshold_tokens, product_id, max_per_month } = parsed.data;

  // Upsert settings
  const updatePayload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (typeof enabled === "boolean") updatePayload.enabled = enabled;
  if (typeof threshold_tokens === "number") updatePayload.threshold_tokens = threshold_tokens;
  if (typeof product_id === "string") updatePayload.product_id = product_id;
  if (typeof max_per_month === "number") updatePayload.max_per_month = max_per_month;

  // Check if settings exist
  const { data: existing } = await db
    .from("billing_auto_topup_settings")
    .select("group_id")
    .eq("group_id", groupId)
    .maybeSingle();

  if (existing) {
    const { error } = await db
      .from("billing_auto_topup_settings")
      .update(updatePayload)
      .eq("group_id", groupId);

    if (error) {
      return NextResponse.json(
        { error: error.message ?? "Update failed" },
        { status: 400 },
      );
    }
  } else {
    if (!product_id) {
      return NextResponse.json(
        { error: "product_id is required for initial setup" },
        { status: 400 },
      );
    }

    const { error } = await db
      .from("billing_auto_topup_settings")
      .insert({
        group_id: groupId,
        enabled: enabled ?? false,
        threshold_tokens: threshold_tokens ?? 50,
        product_id,
        max_per_month: max_per_month ?? 3,
      });

    if (error) {
      return NextResponse.json(
        { error: error.message ?? "Insert failed" },
        { status: 400 },
      );
    }
  }

  await auditLog({
    actorId: user.id,
    groupId: groupId,
    action: "settings.auto_topup",
    metadata: { enabled, threshold_tokens, product_id, max_per_month },
  });

  return NextResponse.json({ ok: true });
}
