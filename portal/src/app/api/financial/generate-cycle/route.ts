/**
 * POST /api/financial/generate-cycle
 *
 * L09-15 · Admin-callable path para forçar geração de invoices pendentes
 * do mês (sem esperar o cron `fn_subscription_generate_cycle`).
 *
 * Uso típico:
 *   - Demo: assessoria acabou de cadastrar atletas e quer ver a agenda.
 *   - Backfill: popular um período anterior.
 *   - Catch-up: o cron falhou num mês (p.ex. janela de manutenção).
 *
 * Auth:
 *   - 401 sem sessão.
 *   - 400 sem `portal_group_id` cookie.
 *   - 403 se o caller não é `admin_master` do grupo ativo.
 *     (Coach puro não gera — evita confusão de "quem gerou" quando a
 *     assessoria tem vários coaches. Coach pode operar via admin.)
 *
 * Body (JSON opcional):
 *   { period_month?: "YYYY-MM-01" }  // default: mês corrente
 *
 * Response:
 *   { ok: true, data: {
 *       ok, period_month, group_id,
 *       total_active_subs, inserted, skipped
 *   } }
 *
 * Idempotente: o conflito (subscription_id, period_month) é tratado
 * na RPC via ON CONFLICT DO NOTHING.
 */

import type { NextRequest } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { withErrorHandler } from "@/lib/api-handler";
import {
  apiOk,
  apiError,
  apiUnauthorized,
  apiForbidden,
} from "@/lib/api/errors";

export const POST = withErrorHandler(
  _post,
  "api.financial.generate-cycle.post",
);

async function _post(req: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return apiUnauthorized(req);

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) {
    return apiError(
      req,
      "NO_GROUP_SESSION",
      "No portal group selected",
      400,
    );
  }

  const { data: membership, error: membershipErr } = await supabase
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (membershipErr) {
    return apiError(
      req,
      "MEMBERSHIP_LOOKUP_FAILED",
      membershipErr.message,
      500,
    );
  }
  if (!membership || membership.role !== "admin_master") {
    return apiForbidden(req);
  }

  let body: { period_month?: unknown } = {};
  try {
    body = (await req.json()) ?? {};
  } catch {
    // Corpo opcional — JSON vazio/ausente é aceitável, default é mês corrente.
    body = {};
  }

  const periodMonth =
    typeof body.period_month === "string" && body.period_month.length > 0
      ? body.period_month
      : null;

  // Validação local barata antes do round-trip à RPC: "YYYY-MM-DD".
  if (periodMonth !== null && !/^\d{4}-\d{2}-\d{2}$/.test(periodMonth)) {
    return apiError(
      req,
      "INVALID_PERIOD_FORMAT",
      "period_month must be ISO date YYYY-MM-DD",
      400,
    );
  }

  const { data, error } = await supabase.rpc(
    "fn_subscription_admin_generate_cycle_scoped",
    {
      p_group_id: groupId,
      p_period_month: periodMonth,
    },
  );

  if (error) {
    // P0001 = invariant violado (formato/range de período, etc.) — retorno
    // 400 com mensagem semântica do Postgres.
    const pgCode = (error as { code?: string }).code;
    if (pgCode === "P0001") {
      return apiError(req, "INVALID_PERIOD", error.message, 400);
    }
    // 42501 = privilege error (não admin). Só acontece se o check local
    // acima for bypassado (ex.: membership stale).  Mapear pra 403.
    if (pgCode === "42501") {
      return apiForbidden(req, error.message);
    }
    return apiError(req, "RPC_ERROR", error.message, 500);
  }

  return apiOk(data);
}
