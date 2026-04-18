import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  createWithdrawal,
  executeWithdrawal,
  getWithdrawals,
  assertInvariantsHealthy,
  getFxSpreadRate,
} from "@/lib/custody";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import {
  getAuthoritativeFxQuote,
  FxQuoteError,
  FxQuoteMissingError,
  FxQuoteStaleError,
} from "@/lib/fx/quote";
import {
  assertSubsystemEnabled,
  FeatureDisabledError,
} from "@/lib/feature-flags";
import { z } from "zod";

/**
 * L01-02 — fx_rate removido do body.
 *
 * O rate é buscado server-side em `public.platform_fx_quotes` via
 * `getAuthoritativeFxQuote()`. Aceitar fx_rate do cliente permitia a um
 * admin_master malicioso inflar artificialmente o payout local (ex: BRL=10 em
 * vez de 5.25 → payout 2× em BRL). Schema `.strict()` rejeita campos
 * desconhecidos com 400 para defesa em profundidade.
 */
const withdrawSchema = z
  .object({
    amount_usd: z.number().min(1).max(1_000_000),
    target_currency: z.enum(["BRL", "EUR", "GBP"]).default("BRL"),
    provider_fee_usd: z.number().min(0).optional(),
  })
  .strict();

async function requireAdminMaster() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Unauthorized", status: 401 } as const;

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return { error: "No group", status: 400 } as const;

  const db = createServiceClient();
  const { data: membership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!membership || membership.role !== "admin_master") {
    return { error: "Forbidden", status: 403 } as const;
  }

  return { user, groupId } as const;
}

export async function GET() {
  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const withdrawals = await getWithdrawals(auth.groupId);
  return NextResponse.json({ withdrawals });
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`withdraw:${ip}`, { maxRequests: 5, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  // L06-06 — kill switch operacional. Permite ops desligar withdrawals
  // imediatamente via /platform/feature-flags ou SQL sem deploy.
  // Ver docs/runbooks/WITHDRAW_STUCK_RUNBOOK.md, GATEWAY_OUTAGE_RUNBOOK.md.
  try {
    await assertSubsystemEnabled(
      "custody.withdrawals.enabled",
      "Saques temporariamente desabilitados pelo time de ops.",
    );
  } catch (e) {
    if (e instanceof FeatureDisabledError) {
      return NextResponse.json(
        { error: e.hint, code: e.code, key: e.key },
        { status: 503, headers: { "Retry-After": "60" } },
      );
    }
    throw e;
  }

  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return NextResponse.json(
      { error: "System invariant violation detected. Operations suspended." },
      { status: 503 },
    );
  }

  const body = await req.json();
  const parsed = withdrawSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  // L01-02: fetch do rate é SEMPRE server-side. Falha fechada (503) se
  // não houver cotação ativa ou estiver stale — o operador precisa refrescar.
  let fxQuote;
  try {
    fxQuote = await getAuthoritativeFxQuote(parsed.data.target_currency);
  } catch (err) {
    if (err instanceof FxQuoteStaleError) {
      return NextResponse.json(
        {
          error: "FX quote stale",
          detail: "Cotação expirada; platform_admin deve refrescar em /platform/fx.",
          code: err.code,
        },
        { status: 503 },
      );
    }
    if (err instanceof FxQuoteMissingError) {
      return NextResponse.json(
        {
          error: "FX quote missing",
          detail: "Moeda sem cotação ativa; contate platform_admin.",
          code: err.code,
        },
        { status: 503 },
      );
    }
    if (err instanceof FxQuoteError) {
      return NextResponse.json(
        { error: "FX quote unavailable", code: err.code },
        { status: 503 },
      );
    }
    throw err;
  }

  const spreadPct = await getFxSpreadRate();

  try {
    const withdrawal = await createWithdrawal({
      groupId: auth.groupId,
      amountUsd: parsed.data.amount_usd,
      targetCurrency: parsed.data.target_currency,
      fxRate: fxQuote.rate,
      spreadPct,
      providerFeeUsd: parsed.data.provider_fee_usd,
    });

    if (!withdrawal) {
      return NextResponse.json({ error: "Custody feature not available" }, { status: 503 });
    }

    await executeWithdrawal(withdrawal.id);

    await auditLog({
      actorId: auth.user.id,
      groupId: auth.groupId,
      action: "custody.withdrawal.executed",
      targetId: withdrawal.id,
      metadata: {
        amount_usd: parsed.data.amount_usd,
        target_currency: parsed.data.target_currency,
        fx_rate: fxQuote.rate,
        fx_source: fxQuote.source,
        fx_age_seconds: fxQuote.ageSeconds,
        spread_pct: spreadPct,
        net_local: withdrawal.net_local_amount,
      },
    });

    return NextResponse.json({ withdrawal });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Withdrawal failed";
    return NextResponse.json({ error: msg }, { status: 422 });
  }
}
