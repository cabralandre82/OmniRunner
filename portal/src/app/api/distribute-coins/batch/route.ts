import { NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { distributeCoinsBatchSchema } from "@/lib/schemas";
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
  apiNoGroupSession,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withIdempotency } from "@/lib/api/idempotency";
import { withErrorHandler } from "@/lib/api-handler";

// L05-03 — POST /api/distribute-coins/batch
//
// Distribui coins para múltiplos atletas em UMA transação SQL via
// `distribute_coins_batch_atomic` (ver migration
// `20260421120000_l05_distribute_coins_batch.sql`). Substitui o pattern
// "loop client-side de N chamadas a /api/distribute-coins" que multiplica o
// risco de atomicidade já tratado em L02-01 e degrada UX para clubes com
// 200+ atletas.
//
// Compromisso de design:
//   • Caps duros: items <=200, total <=1_000_000, amount/item <=100_000.
//     Bloqueio é triplo: Zod (handler) → CHECK runtime na função SQL →
//     `emit_coins_atomic` (UNIQUE INDEX em coin_ledger.ref_id).
//   • Idempotência forte: `ref_id` (corpo OU header `x-idempotency-key`)
//     vira `<ref>__<idx>` em cada item. Replay inteiro é seguro;
//     replays parciais (mesmo header, items diferentes) batem em 409
//     IDEMPOTENCY_KEY_CONFLICT pelo wrapper genérico.
//   • Audit log emitido somente para distribuições novas (was_idempotent
//     flag por item) — replays não inflam o audit.
//
// Cross-refs: L02-01 (atomicidade), L17-01 (withErrorHandler), L18-02
// (idempotency wrapper), L14-04 (rate-limit por group), L06-06 (kill switch).
export const POST = withErrorHandler(
  _post,
  "api.distribute-coins.batch.post",
);

interface BatchItemResult {
  athlete_user_id: string;
  amount: number;
  new_balance: number | null;
  was_idempotent: boolean;
  ledger_id: string | null;
}

interface BatchRpcRow {
  total_amount: number;
  total_distributions: number;
  batch_was_idempotent: boolean;
  items: BatchItemResult[] | null;
}

async function _post(request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return apiUnauthorized(request);

  // L06-06 — share kill switch with the per-athlete endpoint. If ops
  // disable distribute_coins.enabled, the batch path must die too.
  try {
    await assertSubsystemEnabled(
      "distribute_coins.enabled",
      "Distribuição de coins temporariamente suspensa pelo time de ops.",
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

  // L14-04 — rate-limit POR GROUP. Limite mais apertado que o endpoint
  // single-athlete (5/min vs 20/min) porque cada chamada pode mover até
  // 200 atletas de uma vez; queremos evitar que o bug de um cliente
  // dispare um ramp-up de carga em emit_coins_atomic / custody.
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({
      prefix: "distribute.batch",
      groupId: cookieGroupId,
      userId: user.id,
      request,
    }),
    { maxRequests: 5, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(request, retryAfter);
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return apiNoGroupSession(request);

  const db = createServiceClient();

  // Authz duplica a checagem do RPC: queremos 403 limpo ANTES de gastar
  // CPU em parsing de payload de 200 itens. O RPC mantém sua própria
  // checagem como defesa em profundidade caso alguém chame direto.
  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!callerMembership || callerMembership.role !== "admin_master") {
    return apiForbidden(request);
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return apiValidationFailed(request, "Corpo JSON inválido");
  }
  const parsed = distributeCoinsBatchSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(
      request,
      parsed.error.issues[0].message,
      parsed.error.flatten(),
    );
  }
  const { items, ref_id: clientRefId } = parsed.data;

  const idempotencyKey = request.headers.get("x-idempotency-key");
  // Prefer-order: explicit body ref_id > header x-idempotency-key > derived.
  // The derived form (`portal_batch_<actor>_<ts>`) is for legacy callers that
  // don't send a key; it still flows through the RPC's per-item dedupe but
  // gives no replay protection above the wrapper.
  const batchRefId =
    clientRefId ?? idempotencyKey ?? `portal_batch_${user.id}_${Date.now()}`;

  // assertInvariantsHealthy é GLOBAL (não por group), então rodamos uma vez
  // por requisição em vez de uma vez por item.
  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return apiServiceUnavailable(
      request,
      "System invariant violation. Emission blocked.",
    );
  }

  const actorId = user.id;

  return withIdempotency({
    request,
    namespace: "coins.distribute.batch",
    actorId,
    requestBody: {
      items,
      group_id: groupId,
      ref_id: batchRefId,
    },
    handler: async () => {
      const { data: rpcData, error: rpcErr } = await withSpan(
        "rpc distribute_coins_batch_atomic",
        "db.rpc",
        async (setAttr) => {
          const result = await db.rpc("distribute_coins_batch_atomic" as any, {
            p_group_id: groupId,
            p_caller_user_id: actorId,
            p_items: items,
            p_batch_ref_id: batchRefId,
          });
          if (result.data) {
            const row = Array.isArray(result.data) ? result.data[0] : result.data;
            setAttr("omni.batch.size", items.length);
            setAttr("omni.batch.total_amount", row?.total_amount ?? 0);
            setAttr(
              "omni.batch.was_idempotent",
              Boolean(row?.batch_was_idempotent),
            );
          }
          if (result.error) {
            setAttr("db.error_code", result.error.code);
          }
          return result;
        },
        {
          "db.system": "postgresql",
          "db.operation": "rpc:distribute_coins_batch_atomic",
          "omni.group_id": groupId,
          "omni.batch.size": items.length,
          "omni.batch.ref_id": batchRefId,
        },
      );

      const errorBody = (code: string, message: string) => ({
        ok: false,
        error: {
          code,
          message,
          request_id: request.headers.get("x-request-id"),
        },
      });

      if (rpcErr) {
        const msg = rpcErr.message ?? "";
        if (rpcErr.code === "55P03" || msg.includes("lock_not_available")) {
          return {
            status: 503,
            body: errorBody(
              "LOCK_NOT_AVAILABLE",
              "Recurso em uso, tente novamente em instantes.",
            ),
            headers: { "Retry-After": "2" },
          };
        }
        if (msg.includes("CUSTODY_FAILED") || rpcErr.code === "P0002") {
          return {
            status: 422,
            body: errorBody(
              "CUSTODY_FAILED",
              "Lastro insuficiente na custódia da assessoria. Deposite mais lastro antes de emitir o lote.",
            ),
          };
        }
        if (
          msg.includes("INVENTORY_INSUFFICIENT") ||
          rpcErr.code === "P0003"
        ) {
          return {
            status: 422,
            body: errorBody(
              "INVENTORY_INSUFFICIENT",
              "Saldo insuficiente de OmniCoins para o lote inteiro. Nenhum atleta foi creditado.",
            ),
          };
        }
        if (
          msg.includes("FORBIDDEN") ||
          msg.includes("MISSING_CALLER")
        ) {
          return {
            status: 403,
            body: errorBody(
              "FORBIDDEN",
              "Apenas admin_master pode distribuir coins.",
            ),
          };
        }
        if (
          msg.includes("BATCH_TOO_LARGE") ||
          msg.includes("BATCH_TOTAL_EXCEEDED") ||
          msg.includes("INVALID_ITEMS") ||
          msg.includes("INVALID_ITEM") ||
          msg.includes("EMPTY_BATCH") ||
          msg.includes("MISSING_REF_ID") ||
          msg.includes("INVALID_AMOUNT") ||
          rpcErr.code === "P0001"
        ) {
          return {
            status: 400,
            body: errorBody(
              "VALIDATION_FAILED",
              "Lote inválido. Verifique itens, totais e ref_id.",
            ),
          };
        }
        logger.error("distribute_coins_batch_atomic failed", rpcErr, {
          groupId,
          batch_size: items.length,
          batchRefId,
        });
        return {
          status: 500,
          body: errorBody("INTERNAL_ERROR", "Erro ao distribuir lote de coins"),
        };
      }

      const row = (Array.isArray(rpcData) ? rpcData[0] : rpcData) as
        | BatchRpcRow
        | null
        | undefined;
      if (!row) {
        logger.error(
          "distribute_coins_batch_atomic empty response",
          new Error("empty"),
          { groupId, batch_size: items.length },
        );
        return {
          status: 500,
          body: errorBody("INTERNAL_ERROR", "Lote sem retorno do banco"),
        };
      }

      const itemResults = (row.items ?? []) as BatchItemResult[];

      // Audit per item, mas SOMENTE para distribuições novas. Replays
      // existentes ficam fora do log para não inflar a tabela em retries
      // de rede do cliente.
      const newItems = itemResults.filter((it) => !it.was_idempotent);
      if (newItems.length > 0) {
        // Single bulk audit entry sumariza o lote — detalhes por item
        // ficam no metadata para forensics. Evita N inserts auditLog.
        await auditLog({
          actorId,
          groupId,
          action: "coins.distribute.batch",
          targetType: "group",
          targetId: groupId,
          metadata: {
            batch_ref_id: batchRefId,
            total_amount: row.total_amount,
            total_distributions: row.total_distributions,
            new_distributions: newItems.length,
            replayed_distributions:
              row.total_distributions - newItems.length,
            items: newItems.map((it) => ({
              athlete_user_id: it.athlete_user_id,
              amount: it.amount,
            })),
          },
        });
      }

      const traceId = currentTraceId();
      const responseHeaders: Record<string, string> = {};
      if (traceId) responseHeaders["x-trace-id"] = traceId;

      return {
        status: 200,
        headers: responseHeaders,
        body: {
          ok: true,
          batch_ref_id: batchRefId,
          total_amount: row.total_amount,
          total_distributions: row.total_distributions,
          batch_was_idempotent: row.batch_was_idempotent,
          items: itemResults,
        },
      };
    },
  });
}
