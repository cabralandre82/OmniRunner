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
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
  apiValidationFailed,
  apiRateLimited,
  apiServiceUnavailable,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
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

type WithdrawAuthError =
  | { error: "Unauthorized"; status: 401 }
  | { error: "No group"; status: 400 }
  | { error: "Forbidden"; status: 403 };

async function requireAdminMaster(): Promise<
  WithdrawAuthError | { user: { id: string }; groupId: string }
> {
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

function authErrorResponse(
  req: NextRequest | null,
  err: WithdrawAuthError,
): NextResponse {
  switch (err.status) {
    case 401:
      return apiUnauthorized(req);
    case 400:
      return apiError(req, "NO_GROUP_SESSION", "No portal group selected", 400);
    case 403:
      return apiForbidden(req);
  }
}

export async function GET(req: NextRequest) {
  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

  const withdrawals = await getWithdrawals(auth.groupId);
  return NextResponse.json({ withdrawals });
}

export async function POST(req: NextRequest) {
  // L14-04 — bucket por grupo (cookie) para que um grupo ativo não
  // bloqueie withdrawals de outros grupos atrás do mesmo NAT.
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({ prefix: "withdraw", groupId: cookieGroupId, request: req }),
    { maxRequests: 5, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(req, retryAfter);
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

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
      return apiError(req, e.code, e.hint ?? e.message, 503, {
        details: { key: e.key },
        headers: { "Retry-After": "60" },
      });
    }
    throw e;
  }

  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return apiServiceUnavailable(
      req,
      "System invariant violation detected. Operations suspended.",
    );
  }

  const body = await req.json();
  const parsed = withdrawSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(req, "Invalid input", parsed.error.flatten());
  }

  // L01-02: fetch do rate é SEMPRE server-side. Falha fechada (503) se
  // não houver cotação ativa ou estiver stale — o operador precisa refrescar.
  let fxQuote;
  try {
    fxQuote = await getAuthoritativeFxQuote(parsed.data.target_currency);
  } catch (err) {
    if (err instanceof FxQuoteStaleError) {
      return apiError(req, err.code, "FX quote stale", 503, {
        details: {
          hint: "Cotação expirada; platform_admin deve refrescar em /platform/fx.",
        },
      });
    }
    if (err instanceof FxQuoteMissingError) {
      return apiError(req, err.code, "FX quote missing", 503, {
        details: {
          hint: "Moeda sem cotação ativa; contate platform_admin.",
        },
      });
    }
    if (err instanceof FxQuoteError) {
      return apiError(req, err.code, "FX quote unavailable", 503);
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
      return apiServiceUnavailable(req, "Custody feature not available");
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
    return apiError(req, "WITHDRAWAL_FAILED", msg, 422);
  }
}
