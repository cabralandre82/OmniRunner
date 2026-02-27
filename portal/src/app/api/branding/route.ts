import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";

const HEX_RE = /^#[0-9a-fA-F]{6}$/;
const MAX_URL_LEN = 512;

function isValidColor(v: unknown): v is string {
  return typeof v === "string" && HEX_RE.test(v);
}

export async function GET() {
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
}

export async function POST(request: Request) {
  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`branding:${session.user.id}`, { maxRequests: 10, windowMs: 60_000 });
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
    .eq("user_id", session.user.id)
    .maybeSingle();

  if (!membership || membership.role !== "admin_master") {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();

  const payload: Record<string, unknown> = {
    group_id: groupId,
    updated_at: new Date().toISOString(),
  };

  if (body.logo_url !== undefined) {
    if (body.logo_url === null || body.logo_url === "") {
      payload.logo_url = null;
    } else if (typeof body.logo_url === "string" && body.logo_url.length <= MAX_URL_LEN) {
      payload.logo_url = body.logo_url;
    } else {
      return NextResponse.json({ error: "logo_url inválida" }, { status: 400 });
    }
  }

  if (body.primary_color !== undefined) {
    if (!isValidColor(body.primary_color)) {
      return NextResponse.json({ error: "primary_color deve ser hex (#RRGGBB)" }, { status: 400 });
    }
    payload.primary_color = body.primary_color;
  }

  if (body.sidebar_bg !== undefined) {
    if (!isValidColor(body.sidebar_bg)) {
      return NextResponse.json({ error: "sidebar_bg deve ser hex (#RRGGBB)" }, { status: 400 });
    }
    payload.sidebar_bg = body.sidebar_bg;
  }

  if (body.sidebar_text !== undefined) {
    if (!isValidColor(body.sidebar_text)) {
      return NextResponse.json({ error: "sidebar_text deve ser hex (#RRGGBB)" }, { status: 400 });
    }
    payload.sidebar_text = body.sidebar_text;
  }

  if (body.accent_color !== undefined) {
    if (!isValidColor(body.accent_color)) {
      return NextResponse.json({ error: "accent_color deve ser hex (#RRGGBB)" }, { status: 400 });
    }
    payload.accent_color = body.accent_color;
  }

  const { error } = await db
    .from("portal_branding")
    .upsert(payload, { onConflict: "group_id" });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await auditLog({
    actorId: session.user.id,
    groupId,
    action: "settings.branding",
    metadata: payload,
  });

  return NextResponse.json({ ok: true });
}
