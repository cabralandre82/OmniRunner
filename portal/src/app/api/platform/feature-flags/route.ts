import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const updateSchema = z.object({
  id: z.string().uuid(),
  enabled: z.boolean(),
  rollout_pct: z.number().int().min(0).max(100),
});

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Not authenticated", status: 401 };

  const { data: membership } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", user.id)
    .single();

  if (!membership) return { error: "Forbidden", status: 403 };

  return { user };
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`platform-ff:${ip}`, {
    maxRequests: 20,
    windowMs: 60_000,
  });
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
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const { id, enabled, rollout_pct } = parsed.data;
  const admin = createAdminClient();

  const { error } = await admin
    .from("feature_flags")
    .update({ enabled, rollout_pct, updated_at: new Date().toISOString() })
    .eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await auditLog({
    action: "feature_flag.update",
    actorId: auth.user.id,
    targetId: id,
    metadata: { enabled, rollout_pct },
  });

  return NextResponse.json({ ok: true });
}
