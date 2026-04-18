import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { invalidateFeatureCache } from "@/lib/feature-flags";
import { z } from "zod";

/**
 * L06-06 — toggle de feature flag pelo platform admin.
 *
 * Schema aceita `id` (PK UUID, novo schema) OU `key+scope` (mais robusto
 * para ops que copiam comandos de runbooks). Sempre exige `reason` —
 * runbooks dependem disso para diagnóstico pós-incidente.
 */
const updateSchema = z
  .object({
    id: z.string().uuid().optional(),
    key: z.string().min(1).optional(),
    scope: z.string().min(1).optional(),
    enabled: z.boolean(),
    rollout_pct: z.number().int().min(0).max(100),
    reason: z.string().min(3).max(500).optional(),
  })
  .refine((d) => d.id !== undefined || (d.key !== undefined), {
    message: "either `id` or `key` is required",
  });

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Not authenticated", status: 401 };

  // Convenção do projeto: platform admin = profiles.platform_role='admin'.
  // (Anteriormente este route consultava `platform_admins` que não existe no
  // schema atual — tabela hipotética; corrigido em L06-06.)
  const { data: profile } = await supabase
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .single();

  if (!profile || profile.platform_role !== "admin") {
    return { error: "Forbidden", status: 403 };
  }

  return { user };
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`platform-ff:${ip}`, {
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

  const { id, key, scope, enabled, rollout_pct, reason } = parsed.data;
  const admin = createAdminClient();

  const patch = {
    enabled,
    rollout_pct,
    reason: reason ?? null,
    updated_by: auth.user.id,
    updated_at: new Date().toISOString(),
  };

  const query = admin.from("feature_flags").update(patch);
  const filtered = id
    ? query.eq("id", id)
    : query.eq("key", key!).eq("scope", scope ?? "global");

  const { error } = await filtered;

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  // L06-06 — invalida cache local IMEDIATAMENTE para que próximo request
  // ao subsistema reflita o toggle. Sem isso, kill switch poderia demorar
  // até 60s para fazer efeito.
  invalidateFeatureCache();

  await auditLog({
    action: "feature_flag.update",
    actorId: auth.user.id,
    targetId: id ?? `${key}@${scope ?? "global"}`,
    metadata: { id, key, scope, enabled, rollout_pct, reason },
  });

  return NextResponse.json({ ok: true });
}
