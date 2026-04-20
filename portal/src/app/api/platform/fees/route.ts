import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { cached, invalidate, CacheTTL } from "@/lib/cache";
import { platformFeeTypeSchema } from "@/lib/platform-fee-types";
import { z } from "zod";
import { withErrorHandler } from "@/lib/api-handler";

// L17-01 — endpoint financeiro crítico: configura taxas (`rate_pct`,
// `rate_usd`) que alimentam toda a precificação on-line. Outermost
// wrapper garante 500 canônico + Sentry + x-request-id em qualquer
// throw inesperado (e.g. cache failure, admin client crash).
export const GET = withErrorHandler(_get, "api.platform.fees.get");
export const POST = withErrorHandler(_post, "api.platform.fees.post");

// L01-45 fix: `fee_type` enum is sourced from the canonical
// `PLATFORM_FEE_TYPES` constant (see `lib/platform-fee-types.ts`). NEVER
// inline the list here again — see the comment block in that file for the
// 2026-04-13 BRL-crisis post-mortem that motivated the consolidation.
const updateSchema = z.object({
  fee_type: platformFeeTypeSchema,
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

async function _get(_req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const fees = await cached("platform:fees:config", CacheTTL.CONFIG, async () => {
    const admin = createAdminClient();
    const { data } = await admin
      .from("platform_fee_config")
      .select("*")
      .order("fee_type");
    return data ?? [];
  });

  return NextResponse.json({ fees });
}

async function _post(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`platform-fees:${ip}`, {
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

  await invalidate("platform:fees:config");

  return NextResponse.json({ ok: true });
}
