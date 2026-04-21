import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { reverseCoinsSchema } from "@/lib/schemas";
import { assertInvariantsHealthy } from "@/lib/custody";
import {
  assertSubsystemEnabled,
  FeatureDisabledError,
} from "@/lib/feature-flags";
import { logger } from "@/lib/logger";
import { withSpan, currentTraceId } from "@/lib/observability/tracing";
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
  apiValidationFailed,
  apiRateLimited,
  apiServiceUnavailable,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withIdempotency } from "@/lib/api/idempotency";
import { withErrorHandler } from "@/lib/api-handler";

// L03-13 — POST /api/coins/reverse
//
// Endpoint canônico de reembolso/estorno para os três fluxos financeiros
// cobertos por funções atômicas na migration
// `20260421130000_l03_reverse_coin_flows.sql`:
//
//   • `kind: 'emission'` → reverse_coin_emission_atomic
//   • `kind: 'burn'`     → reverse_burn_atomic
//   • `kind: 'deposit'`  → reverse_custody_deposit_atomic
//
// Substitui os blocos SQL manuais em `docs/runbooks/CHARGEBACK_RUNBOOK.md`
// §3.2 por um caminho transacional, idempotente e auditado. Ver
// `docs/runbooks/REVERSE_COINS_RUNBOOK.md` para procedimentos de
// triagem e comunicação ao atleta/grupo.
//
// Compromisso de segurança:
//   • ONLY platform_admin (auth.uid() presente em profiles com
//     platform_role='admin') pode chamar. Reversões são operações de
//     alto risco financeiro; admin_master do grupo NÃO tem permissão
//     — o fluxo chargeback/estorno é intermediado pelo time de ops.
//   • CSRF default-deny via middleware (L17-06).
//   • Kill switch `coins.reverse.enabled` (L06-06). Toggleable pelo
//     painel /platform/feature-flags sem redeploy.
//   • `assertInvariantsHealthy` (L08-07) bloqueia se o sistema já está
//     em estado degradado — evita cascata (ops resolve a invariante
//     primeiro).
//   • Rate limit 10/min por actor (platform_admin UI é naturalmente
//     baixa latência/baixa frequência; 10/min permite remediar um
//     fraud ring em lote sem abrir a porta para abuso).
//   • Idempotency obrigatório: `idempotency_key` no body OU header
//     `x-idempotency-key`. Sem key → 400 MISSING_IDEMPOTENCY_KEY.
//
// Cross-refs: L17-01 (withErrorHandler), L18-02 (withIdempotency), L14-04
// (rate-limit), L08-07 (invariants), L06-06 (kill switch), L02-06
// (fail_withdrawal cobre o flavor "withdrawal reversal").
export const POST = withErrorHandler(_post, "api.coins.reverse.post");

async function _post(request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return apiUnauthorized(request);

  // Kill switch (L06-06).
  try {
    await assertSubsystemEnabled(
      "coins.reverse.enabled",
      "Reversão de coins temporariamente suspensa pelo time de ops.",
    );
  } catch (e) {
    if (e instanceof FeatureDisabledError) {
      return apiError(request, e.code, e.hint ?? e.message, 503, {
        details: { key: e.key },
        headers: { "Retry-After": "30" },
      });
    }
    throw e;
  }

  // Rate limit POR actor — platform_admin UI é baixa frequência; 10/min
  // permite remediar um fraud ring lentamente sem abrir abuso.
  const rl = await rateLimit(
    rateLimitKey({
      prefix: "coins.reverse",
      userId: user.id,
      request,
    }),
    { maxRequests: 10, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(request, retryAfter);
  }

  const db = createServiceClient();

  // AuthZ: SOMENTE platform_admin. admin_master do grupo NÃO pode
  // reverter — chargeback/estorno é intermediado por ops.
  const { data: profile } = await db
    .from("profiles")
    .select("platform_role")
    .eq("id", user.id)
    .maybeSingle();

  if (!profile || profile.platform_role !== "admin") {
    return apiForbidden(
      request,
      "Somente platform_admin pode reverter fluxos financeiros.",
    );
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return apiValidationFailed(request, "Corpo JSON inválido");
  }

  const parsed = reverseCoinsSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(
      request,
      parsed.error.issues[0].message,
      parsed.error.flatten(),
    );
  }

  const headerKey = request.headers.get("x-idempotency-key");
  const idempotencyKey = parsed.data.idempotency_key ?? headerKey;
  if (!idempotencyKey || idempotencyKey.length < 8) {
    return apiValidationFailed(
      request,
      "idempotency_key (body) ou x-idempotency-key (header) é obrigatório (>=8 chars).",
    );
  }

  // Invariants check global (L08-07). Se sistema já drifta, reversão
  // espera ops fechar o drift primeiro — senão acumulamos dívida.
  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return apiServiceUnavailable(
      request,
      "System invariant violation. Reversal blocked until drift is resolved.",
    );
  }

  const actorId = user.id;
  const { kind } = parsed.data;
  const reason = parsed.data.reason;

  return withIdempotency({
    request,
    namespace: `coins.reverse.${kind}`,
    actorId,
    requestBody: parsed.data,
    handler: async () => {
      const errorBody = (code: string, message: string) => ({
        ok: false,
        error: {
          code,
          message,
          request_id: request.headers.get("x-request-id"),
        },
      });

      const mapPgError = (
        rpcErr: { code?: string | null; message?: string | null } | null,
      ) => {
        const msg = rpcErr?.message ?? "";
        const code = rpcErr?.code ?? "";
        if (code === "55P03" || msg.includes("lock_not_available")) {
          return {
            status: 503,
            body: errorBody(
              "LOCK_NOT_AVAILABLE",
              "Recurso em uso, tente novamente em instantes.",
            ),
            headers: { "Retry-After": "2" },
          };
        }
        if (
          code === "P0001" ||
          msg.includes("INVALID_LEDGER_ID") ||
          msg.includes("INVALID_BURN_REF") ||
          msg.includes("INVALID_DEPOSIT_ID") ||
          msg.includes("ACTOR_REQUIRED") ||
          msg.includes("REASON_REQUIRED") ||
          msg.includes("MISSING_IDEMPOTENCY_KEY")
        ) {
          return {
            status: 400,
            body: errorBody(
              "VALIDATION_FAILED",
              "Parâmetros inválidos para reversão.",
            ),
          };
        }
        if (
          code === "P0002" ||
          msg.includes("LEDGER_NOT_FOUND") ||
          msg.includes("BURN_NOT_FOUND") ||
          msg.includes("DEPOSIT_NOT_FOUND") ||
          msg.includes("CUSTODY_ACCOUNT_NOT_FOUND")
        ) {
          return {
            status: 404,
            body: errorBody(
              "NOT_FOUND",
              "Alvo da reversão não encontrado.",
            ),
          };
        }
        if (msg.includes("INSUFFICIENT_BALANCE") || code === "P0003") {
          return {
            status: 422,
            body: errorBody(
              "INSUFFICIENT_BALANCE",
              "Atleta já gastou as coins emitidas. Use o fluxo debt-of-group (CHARGEBACK_RUNBOOK §3.3).",
            ),
          };
        }
        if (msg.includes("NOT_REVERSIBLE")) {
          return {
            status: 422,
            body: errorBody(
              "NOT_REVERSIBLE",
              "Burn já compensado entre custódias. Exige unwind manual interclube — ver REVERSE_COINS_RUNBOOK.",
            ),
          };
        }
        if (msg.includes("INVARIANT_VIOLATION")) {
          return {
            status: 422,
            body: errorBody(
              "INVARIANT_VIOLATION",
              "Refund quebraria invariante (lastro < committed). Reverta emissões financiadas por este depósito primeiro.",
            ),
          };
        }
        if (msg.includes("INVALID_TARGET_REASON") || code === "P0008") {
          return {
            status: 422,
            body: errorBody(
              "INVALID_TARGET_STATE",
              "Alvo não está em estado reversível (reason/status inválidos).",
            ),
          };
        }
        if (msg.includes("INVALID_STATE")) {
          return {
            status: 422,
            body: errorBody(
              "INVALID_TARGET_STATE",
              "Alvo não está em estado reversível.",
            ),
          };
        }
        if (msg.includes("CUSTODY_RECOMMIT_FAILED")) {
          return {
            status: 422,
            body: errorBody(
              "CUSTODY_RECOMMIT_FAILED",
              "Lastro atual insuficiente para re-commitar custódia. Deposite mais lastro antes de reverter.",
            ),
          };
        }
        logger.error("reverse_coins RPC failed", rpcErr as Error, {
          kind,
          actorId,
          idempotencyKey,
        });
        return {
          status: 500,
          body: errorBody("INTERNAL_ERROR", "Erro ao reverter fluxo de coins"),
        };
      };

      const traceId = currentTraceId();
      const responseHeaders: Record<string, string> = {};
      if (traceId) responseHeaders["x-trace-id"] = traceId;

      // ── EMISSION ──────────────────────────────────────────────────────
      if (parsed.data.kind === "emission") {
        const emissionInput = parsed.data;
        const { data, error } = await withSpan(
          "rpc reverse_coin_emission_atomic",
          "db.rpc",
          async (setAttr) => {
            const result = await db.rpc(
              "reverse_coin_emission_atomic" as any,
              {
                p_original_ledger_id: emissionInput.original_ledger_id,
                p_reason: reason,
                p_actor_user_id: actorId,
                p_idempotency_key: idempotencyKey,
              },
            );
            if (result.data) {
              const row = Array.isArray(result.data)
                ? result.data[0]
                : result.data;
              setAttr(
                "omni.reverse.was_idempotent",
                Boolean(row?.was_idempotent),
              );
            }
            if (result.error) setAttr("db.error_code", result.error.code);
            return result;
          },
          {
            "db.system": "postgresql",
            "db.operation": "rpc:reverse_coin_emission_atomic",
            "omni.reverse.kind": "emission",
            "omni.reverse.target": emissionInput.original_ledger_id,
          },
        );

        if (error) return mapPgError(error);

        const row = Array.isArray(data) ? data[0] : data;
        if (!row) {
          return {
            status: 500,
            body: errorBody(
              "INTERNAL_ERROR",
              "Reversal sem retorno do banco",
            ),
          };
        }

        if (!row.was_idempotent) {
          await auditLog({
            actorId,
            action: "coins.reverse.emission",
            targetType: "coin_ledger",
            targetId: emissionInput.original_ledger_id,
            metadata: {
              reversal_id: row.reversal_id,
              athlete_user_id: row.athlete_user_id,
              reversed_amount: row.reversed_amount,
              reason,
            },
          });
        }

        return {
          status: 200,
          headers: responseHeaders,
          body: {
            ok: true,
            kind: "emission",
            reversal_id: row.reversal_id,
            reversal_ledger_id: row.reversal_ledger_id,
            athlete_user_id: row.athlete_user_id,
            reversed_amount: row.reversed_amount,
            new_balance: row.new_balance,
            was_idempotent: row.was_idempotent,
          },
        };
      }

      // ── BURN ──────────────────────────────────────────────────────────
      if (parsed.data.kind === "burn") {
        const burnInput = parsed.data;
        const { data, error } = await withSpan(
          "rpc reverse_burn_atomic",
          "db.rpc",
          async (setAttr) => {
            const result = await db.rpc("reverse_burn_atomic" as any, {
              p_burn_ref_id: burnInput.burn_ref_id,
              p_reason: reason,
              p_actor_user_id: actorId,
              p_idempotency_key: idempotencyKey,
            });
            if (result.data) {
              const row = Array.isArray(result.data)
                ? result.data[0]
                : result.data;
              setAttr(
                "omni.reverse.was_idempotent",
                Boolean(row?.was_idempotent),
              );
            }
            if (result.error) setAttr("db.error_code", result.error.code);
            return result;
          },
          {
            "db.system": "postgresql",
            "db.operation": "rpc:reverse_burn_atomic",
            "omni.reverse.kind": "burn",
            "omni.reverse.target": burnInput.burn_ref_id,
          },
        );

        if (error) return mapPgError(error);

        const row = Array.isArray(data) ? data[0] : data;
        if (!row) {
          return {
            status: 500,
            body: errorBody(
              "INTERNAL_ERROR",
              "Reversal sem retorno do banco",
            ),
          };
        }

        if (!row.was_idempotent) {
          await auditLog({
            actorId,
            action: "coins.reverse.burn",
            targetType: "clearing_event",
            targetId: String(row.clearing_event_id),
            metadata: {
              reversal_id: row.reversal_id,
              burn_ref_id: burnInput.burn_ref_id,
              athlete_user_id: row.athlete_user_id,
              reversed_amount: row.reversed_amount,
              settlements_cancelled: row.settlements_cancelled,
              reason,
            },
          });
        }

        return {
          status: 200,
          headers: responseHeaders,
          body: {
            ok: true,
            kind: "burn",
            reversal_id: row.reversal_id,
            clearing_event_id: row.clearing_event_id,
            athlete_user_id: row.athlete_user_id,
            reversed_amount: row.reversed_amount,
            new_balance: row.new_balance,
            settlements_cancelled: row.settlements_cancelled,
            was_idempotent: row.was_idempotent,
          },
        };
      }

      // ── DEPOSIT ───────────────────────────────────────────────────────
      if (parsed.data.kind !== "deposit") {
        return {
          status: 400,
          body: errorBody("VALIDATION_FAILED", "unexpected reverse kind"),
        };
      }
      const depositInput = parsed.data;
      const { data, error } = await withSpan(
        "rpc reverse_custody_deposit_atomic",
        "db.rpc",
        async (setAttr) => {
          const result = await db.rpc(
            "reverse_custody_deposit_atomic" as any,
            {
              p_deposit_id: depositInput.deposit_id,
              p_reason: reason,
              p_actor_user_id: actorId,
              p_idempotency_key: idempotencyKey,
            },
          );
          if (result.data) {
            const row = Array.isArray(result.data)
              ? result.data[0]
              : result.data;
            setAttr(
              "omni.reverse.was_idempotent",
              Boolean(row?.was_idempotent),
            );
          }
          if (result.error) setAttr("db.error_code", result.error.code);
          return result;
        },
        {
          "db.system": "postgresql",
          "db.operation": "rpc:reverse_custody_deposit_atomic",
          "omni.reverse.kind": "deposit",
          "omni.reverse.target": depositInput.deposit_id,
        },
      );

      if (error) return mapPgError(error);

      const row = Array.isArray(data) ? data[0] : data;
      if (!row) {
        return {
          status: 500,
          body: errorBody(
            "INTERNAL_ERROR",
            "Reversal sem retorno do banco",
          ),
        };
      }

      if (!row.was_idempotent) {
        await auditLog({
          actorId,
          groupId: row.group_id,
          action: "coins.reverse.deposit",
          targetType: "custody_deposit",
          targetId: depositInput.deposit_id,
          metadata: {
            reversal_id: row.reversal_id,
            refunded_usd: row.refunded_usd,
            reason,
          },
        });
      }

      return {
        status: 200,
        headers: responseHeaders,
        body: {
          ok: true,
          kind: "deposit",
          reversal_id: row.reversal_id,
          deposit_id: row.deposit_id,
          group_id: row.group_id,
          refunded_usd: row.refunded_usd,
          was_idempotent: row.was_idempotent,
        },
      };
    },
  });
}
