import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { distributeCoinsSchema } from "@/lib/schemas";
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
  apiNotFound,
  apiValidationFailed,
  apiRateLimited,
  apiServiceUnavailable,
  apiNoGroupSession,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withIdempotency } from "@/lib/api/idempotency";
import { withErrorHandler } from "@/lib/api-handler";

// L02-01: todas as mutações (custódia + inventário + wallet + ledger) são
// executadas por um único RPC SECURITY DEFINER em transação única. Qualquer
// falha após a primeira mutação reverte o bloco inteiro. Idempotência é
// garantida por UNIQUE INDEX parcial em coin_ledger(ref_id).
// Ver: supabase/migrations/20260417120000_emit_coins_atomic.sql
//
// L17-01 — outermost safety-net: throws inesperados (auth client crash,
// invariants check infra error, audit log DB outage) viram 500 INTERNAL_ERROR
// canônico via `withErrorHandler` em vez de stack trace cru. Erros de
// domínio do RPC (`CUSTODY_FAILED`, `INVENTORY_INSUFFICIENT`, etc.)
// continuam mapeados inline pelo handler para preservar status codes.
export const POST = withErrorHandler(_post, "api.distribute-coins.post");

async function _post(request: NextRequest) {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return apiUnauthorized(request);

  // L06-06 — kill switch (ver runbook CUSTODY_INCIDENT_RUNBOOK.md).
  // Toggleable via /platform/feature-flags sem precisar redeploy.
  try {
    await assertSubsystemEnabled(
      "distribute_coins.enabled",
      "Coin distribution is temporarily suspended by ops.",
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

  // L14-04 — keying por group preferido a user (proteção do
  // throughput da assessoria); fallback para user.id quando o cookie
  // ainda não foi resolvido.
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({
      prefix: "distribute",
      groupId: cookieGroupId,
      userId: user.id,
      request,
    }),
    { maxRequests: 20, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(request, retryAfter);
  }

  const groupId = cookies().get("portal_group_id")?.value;
  if (!groupId) return apiNoGroupSession(request);

  const db = createServiceClient();

  const { data: callerMembership } = await db
    .from("coaching_members")
    .select("role")
    .eq("group_id", groupId)
    .eq("user_id", user.id)
    .maybeSingle();

  if (!callerMembership || callerMembership.role !== "admin_master") {
    return apiForbidden(request);
  }

  const body = await request.json();
  const parsed = distributeCoinsSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(request, parsed.error.issues[0].message, parsed.error.flatten());
  }
  const { athlete_user_id, amount } = parsed.data;

  // ref_id obrigatório para idempotência. Se cliente não fornecer, geramos um.
  // Observação: L09-03 (CRO) sugere trocar Date.now() por UUID v4; fica para
  // correção separada para manter o escopo do L02-01 focado em atomicidade.
  const idempotencyKey = request.headers.get("x-idempotency-key");
  const refId = idempotencyKey ?? `portal_${user.id}_${Date.now()}`;

  const { data: member } = await db
    .from("coaching_members")
    .select("user_id, display_name")
    .eq("group_id", groupId)
    .eq("user_id", athlete_user_id)
    .in("role", ["athlete", "atleta"])
    .maybeSingle();

  if (!member) {
    return apiError(request, "ATHLETE_NOT_FOUND", "Athlete not found in this coaching group.", 404);
  }

  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return apiServiceUnavailable(
      request,
      "System invariant violation. Emission blocked.",
    );
  }

  // L18-02 — defense-in-depth idempotency. The underlying RPC
  // (emit_coins_atomic) already guarantees at-most-once mutation
  // via UNIQUE INDEX on `coin_ledger.ref_id`. The wrapper layered
  // here adds RESPONSE replay: a network blip on the response
  // path is now safe because the second call with the same key
  // returns the byte-identical first response (and skips re-running
  // even the cheap auditLog/RPC roundtrips).
  const actorId = user.id;
  const athleteName = member.display_name;
  const errorBody = (code: string, message: string) => ({
    ok: false,
    error: {
      code,
      message,
      request_id: request.headers.get("x-request-id"),
    },
  });

  return withIdempotency({
    request,
    namespace: "coins.distribute",
    actorId,
    requestBody: {
      athlete_user_id,
      amount,
      group_id: groupId,
      ref_id: refId,
    },
    handler: async () => {
      const { data: rpcData, error: rpcErr } = await withSpan(
        "rpc emit_coins_atomic",
        "db.rpc",
        async (setAttr) => {
          const result = await db.rpc("emit_coins_atomic", {
            p_group_id: groupId,
            p_athlete_user_id: athlete_user_id,
            p_amount: amount,
            p_ref_id: refId,
          });
          if (result.data) {
            const row = Array.isArray(result.data) ? result.data[0] : result.data;
            setAttr("db.row_count", Array.isArray(result.data) ? result.data.length : 1);
            setAttr("omni.was_idempotent", Boolean(row?.was_idempotent));
          }
          if (result.error) {
            setAttr("db.error_code", result.error.code);
          }
          return result;
        },
        {
          "db.system": "postgresql",
          "db.operation": "rpc:emit_coins_atomic",
          "omni.group_id": groupId,
          "omni.athlete_user_id": athlete_user_id,
          "omni.amount": amount,
          "omni.ref_id": refId,
        },
      );

      if (rpcErr) {
        const msg = rpcErr.message ?? "";
        if (rpcErr.code === "55P03" || msg.includes("lock_not_available")) {
          return {
            status: 503,
            body: errorBody("LOCK_NOT_AVAILABLE", "Resource is locked, please retry in a moment."),
            headers: { "Retry-After": "2" },
          };
        }
        if (msg.includes("CUSTODY_FAILED") || rpcErr.code === "P0002") {
          return {
            status: 422,
            body: errorBody("CUSTODY_FAILED", "Insufficient custody backing. Top up custody before distributing coins."),
          };
        }
        if (msg.includes("INVENTORY_INSUFFICIENT") || rpcErr.code === "P0003") {
          return {
            status: 422,
            body: errorBody("INVENTORY_INSUFFICIENT", "Insufficient OmniCoin balance."),
          };
        }
        if (msg.includes("INVALID_AMOUNT") || msg.includes("MISSING_REF_ID") || rpcErr.code === "P0001") {
          return {
            status: 400,
            body: errorBody("VALIDATION_FAILED", "Invalid parameters."),
          };
        }
        logger.error("emit_coins_atomic failed", rpcErr, {
          athlete_user_id,
          amount,
          groupId,
          refId,
        });
        return {
          status: 500,
          body: errorBody("INTERNAL_ERROR", "Coin distribution failed."),
        };
      }

      const row = Array.isArray(rpcData) ? rpcData[0] : rpcData;
      const wasIdempotent = Boolean(row?.was_idempotent);

      if (!wasIdempotent) {
        await auditLog({
          actorId,
          groupId,
          action: "coins.distribute",
          targetType: "athlete",
          targetId: athlete_user_id,
          metadata: { amount, athlete_name: athleteName, ref_id: refId },
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
          athlete_user_id,
          amount,
          athlete_name: athleteName,
          idempotent: wasIdempotent,
          new_balance: row?.new_balance ?? null,
        },
      };
    },
  });
}
