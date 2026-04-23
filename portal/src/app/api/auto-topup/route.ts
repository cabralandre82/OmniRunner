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
  const {
    enabled,
    threshold_tokens,
    product_id,
    max_per_month,
    daily_charge_cap_brl,
    daily_max_charges,
    daily_limit_timezone,
    daily_cap_change_reason,
  } = parsed.data;

  // Upsert settings (NÃO inclui campos daily_* — eles vão pelo RPC abaixo
  // para garantir audit trail L12-05).
  const updatePayload: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (typeof enabled === "boolean") updatePayload.enabled = enabled;
  if (typeof threshold_tokens === "number") updatePayload.threshold_tokens = threshold_tokens;
  if (typeof product_id === "string") updatePayload.product_id = product_id;
  if (typeof max_per_month === "number") updatePayload.max_per_month = max_per_month;

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

  // L12-05 — daily cap mudanças passam pelo RPC dedicado para gerar audit
  // row em billing_auto_topup_cap_changes. Reason é obrigatória (validada
  // no Zod superRefine). Idempotency derivada do (group_id + reason hash
  // + payload) para safe-retry sob network flake.
  let dailyCapApplied: {
    previous_cap_brl: number | null;
    new_cap_brl: number | null;
    previous_max_charges: number | null;
    new_max_charges: number | null;
    was_idempotent: boolean;
  } | null = null;

  const touchesDailyCap =
    daily_charge_cap_brl !== undefined
    || daily_max_charges !== undefined
    || daily_limit_timezone !== undefined;

  if (touchesDailyCap) {
    // Carrega valores atuais para preencher os params NOT-undefined que
    // a RPC exige (a RPC não tem partial-update; quem chama precisa passar
    // os 3 valores, mesmo que algum venha igual ao atual).
    const { data: current } = await db
      .from("billing_auto_topup_settings")
      .select("daily_charge_cap_brl, daily_max_charges, daily_limit_timezone")
      .eq("group_id", groupId)
      .maybeSingle();

    if (!current) {
      // Não deveria acontecer (acabamos de inserir/atualizar), mas é
      // defensivo: settings podem ter sido removidas em race extremo.
      return NextResponse.json(
        { error: "Settings not found after upsert" },
        { status: 500 },
      );
    }

    const idempotencyKey =
      request.headers.get("x-idempotency-key")
      || `form-${user.id}-${Date.now().toString(36)}`;

    const { data: capResult, error: capErr } = await db.rpc(
      "fn_set_auto_topup_daily_cap",
      {
        p_group_id: groupId,
        p_new_cap_brl:
          daily_charge_cap_brl ?? current.daily_charge_cap_brl,
        p_new_max_charges:
          daily_max_charges ?? current.daily_max_charges,
        p_actor_user_id: user.id,
        p_reason: daily_cap_change_reason!,
        p_timezone: daily_limit_timezone ?? null,
        p_idempotency_key: idempotencyKey,
      },
    );

    if (capErr) {
      const code = (capErr as { code?: string }).code;
      const status = code === "P0001" ? 400 : code === "P0002" ? 404 : 500;
      return NextResponse.json(
        {
          error: capErr.message ?? "Failed to set daily cap",
          code: code ?? "UNKNOWN",
          hint: (capErr as { hint?: string }).hint ?? null,
        },
        { status },
      );
    }

    if (Array.isArray(capResult) && capResult.length > 0) {
      const r = capResult[0];
      dailyCapApplied = {
        previous_cap_brl: r.out_previous_cap_brl ?? null,
        new_cap_brl: r.out_new_cap_brl ?? null,
        previous_max_charges: r.out_previous_max_charges ?? null,
        new_max_charges: r.out_new_max_charges ?? null,
        was_idempotent: r.out_was_idempotent ?? false,
      };
    }
  }

  await auditLog({
    actorId: user.id,
    groupId: groupId,
    action: "settings.auto_topup",
    metadata: {
      enabled,
      threshold_tokens,
      product_id,
      max_per_month,
      daily_cap_change: dailyCapApplied,
      daily_cap_change_reason: dailyCapApplied
        ? daily_cap_change_reason
        : undefined,
    },
  });

  return NextResponse.json({
    ok: true,
    daily_cap: dailyCapApplied,
  });
}
