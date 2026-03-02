import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { gatewayPreferenceSchema } from "@/lib/schemas";

export async function GET() {
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

  const { data: customer } = await db
    .from("billing_customers")
    .select("preferred_gateway")
    .eq("group_id", groupId)
    .maybeSingle();

  return NextResponse.json({
    preferred_gateway: customer?.preferred_gateway ?? "mercadopago",
  });
}

export async function POST(request: Request) {
  const rl = rateLimit(`gateway-pref:${request.headers.get("x-forwarded-for") ?? "unknown"}`);
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
  const parsed = gatewayPreferenceSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const gateway = parsed.data.preferred_gateway;

  const { data: existing } = await db
    .from("billing_customers")
    .select("group_id")
    .eq("group_id", groupId)
    .maybeSingle();

  if (existing) {
    const { error } = await db
      .from("billing_customers")
      .update({ preferred_gateway: gateway, updated_at: new Date().toISOString() })
      .eq("group_id", groupId);

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
  } else {
    const { data: profile } = await db
      .from("profiles")
      .select("display_name, email")
      .eq("id", user.id)
      .maybeSingle();

    const { data: group } = await db
      .from("coaching_groups")
      .select("name")
      .eq("id", groupId)
      .maybeSingle();

    const { error } = await db.from("billing_customers").insert({
      group_id: groupId,
      legal_name: group?.name ?? profile?.display_name ?? "Assessoria",
      email: profile?.email ?? "admin@omnirunner.app",
      preferred_gateway: gateway,
    });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }
  }

  await auditLog({ actorId: user.id, groupId: groupId, action: "settings.gateway_preference", metadata: { preferred_gateway: gateway } });
  return NextResponse.json({ ok: true, preferred_gateway: gateway });
}
