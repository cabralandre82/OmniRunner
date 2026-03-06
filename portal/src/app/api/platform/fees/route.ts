import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const updateSchema = z.object({
  fee_type: z.enum(["clearing", "swap", "maintenance", "billing_split"]),
  rate_pct: z.number().min(0).max(100).optional(),
  rate_usd: z.number().min(0).max(10).optional(),
  is_active: z.boolean().optional(),
});

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

  const admin = createAdminClient();
  const { data: fees } = await admin
    .from("platform_fee_config")
    .select("*")
    .order("fee_type");

  return NextResponse.json({ fees: fees ?? [] });
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`platform-fees:${ip}`, {
    maxRequests: 20,
    windowMs: 60_000,
  });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const body = await req.json();
  const parsed = updateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const { fee_type, rate_pct, rate_usd, is_active } = parsed.data;
  const admin = createAdminClient();

  const updatePayload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
    updated_by: auth.user.id,
  };
  if (rate_pct !== undefined) updatePayload.rate_pct = rate_pct;
  if (rate_usd !== undefined) updatePayload.rate_usd = rate_usd;
  if (is_active !== undefined) updatePayload.is_active = is_active;

  const { error } = await admin
    .from("platform_fee_config")
    .update(updatePayload)
    .eq("fee_type", fee_type);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  await auditLog({
    action: "platform.fee.update",
    actorId: auth.user.id,
    metadata: { fee_type, rate_pct, rate_usd, is_active },
  });

  return NextResponse.json({ ok: true });
}
