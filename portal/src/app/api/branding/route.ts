import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { brandingSchema } from "@/lib/schemas";
import { logger } from "@/lib/logger";

export async function GET() {
  try {
    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group" }, { status: 400 });
    }

    const supabase = createClient();
    const { data } = await supabase
      .from("portal_branding")
      .select("logo_url, primary_color, sidebar_bg, sidebar_text, accent_color")
      .eq("group_id", groupId)
      .maybeSingle();

    return NextResponse.json({
      logo_url: data?.logo_url ?? null,
      primary_color: data?.primary_color ?? "#2563eb",
      sidebar_bg: data?.sidebar_bg ?? "#ffffff",
      sidebar_text: data?.sidebar_text ?? "#111827",
      accent_color: data?.accent_color ?? "#2563eb",
    });
  } catch (error) {
    logger.error("Failed to fetch branding", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = await rateLimit(`branding:${user.id}`, { maxRequests: 10, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return NextResponse.json({ error: "No group" }, { status: 400 });
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
    const parsed = brandingSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0].message },
        { status: 400 },
      );
    }

    const payload: Record<string, unknown> = {
      group_id: groupId,
      updated_at: new Date().toISOString(),
      ...parsed.data,
    };

    const { error } = await db
      .from("portal_branding")
      .upsert(payload, { onConflict: "group_id" });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    await auditLog({
      actorId: user.id,
      groupId,
      action: "settings.branding",
      metadata: payload,
    });

    return NextResponse.json({ ok: true });
  } catch (error) {
    logger.error("Failed to save branding", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
