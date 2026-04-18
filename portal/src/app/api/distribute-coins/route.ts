import { NextResponse } from "next/server";
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

// L02-01: todas as mutações (custódia + inventário + wallet + ledger) são
// executadas por um único RPC SECURITY DEFINER em transação única. Qualquer
// falha após a primeira mutação reverte o bloco inteiro. Idempotência é
// garantida por UNIQUE INDEX parcial em coin_ledger(ref_id).
// Ver: supabase/migrations/20260417120000_emit_coins_atomic.sql
export async function POST(request: Request) {
  try {
    const supabase = createClient();
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    // L06-06 — kill switch (ver runbook CUSTODY_INCIDENT_RUNBOOK.md).
    // Toggleable via /platform/feature-flags sem precisar redeploy.
    try {
      await assertSubsystemEnabled(
        "distribute_coins.enabled",
        "Distribuição de coins temporariamente suspensa pelo time de ops.",
      );
    } catch (e) {
      if (e instanceof FeatureDisabledError) {
        return NextResponse.json(
          { error: e.hint, code: e.code, key: e.key },
          { status: 503, headers: { "Retry-After": "30" } },
        );
      }
      throw e;
    }

    const rl = await rateLimit(`distribute:${user.id}`, { maxRequests: 20, windowMs: 60_000 });
    if (!rl.allowed) {
      return NextResponse.json({ error: "Too many requests" }, { status: 429 });
    }

    const groupId = cookies().get("portal_group_id")?.value;
    if (!groupId) {
      return NextResponse.json({ error: "No group selected" }, { status: 400 });
    }

    const db = createServiceClient();

    const { data: callerMembership } = await db
      .from("coaching_members")
      .select("role")
      .eq("group_id", groupId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (!callerMembership || callerMembership.role !== "admin_master") {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    const body = await request.json();
    const parsed = distributeCoinsSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.issues[0].message },
        { status: 400 },
      );
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
      return NextResponse.json(
        { error: "Atleta não encontrado nesta assessoria" },
        { status: 404 },
      );
    }

    const healthy = await assertInvariantsHealthy();
    if (!healthy) {
      return NextResponse.json(
        { error: "System invariant violation. Emission blocked." },
        { status: 503 },
      );
    }

    // L20-03 — wrap RPC in span so the DB call appears as a child of the
    // request transaction in Sentry. Attributes follow OTel semantic conv:
    // db.system + db.operation + omni.* domain identifiers.
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
      // L19-05 — 55P03 lock_not_available: emit_coins_atomic tem
      // SET lock_timeout = '2s' → se custódia/wallet/inventário do grupo
      // está sob contenção, falha rápido em vez de segurar conexão. Cliente
      // deve fazer backoff e retry.
      if (rpcErr.code === "55P03" || msg.includes("lock_not_available")) {
        return new NextResponse(
          JSON.stringify({ error: "Recurso em uso, tente novamente em instantes." }),
          { status: 503, headers: { "Content-Type": "application/json", "Retry-After": "2" } },
        );
      }
      // P0002 — CUSTODY_FAILED (lastro insuficiente ou falha no check de custódia)
      if (msg.includes("CUSTODY_FAILED") || rpcErr.code === "P0002") {
        return NextResponse.json(
          { error: "Lastro insuficiente na custódia da assessoria. Deposite mais lastro antes de emitir coins." },
          { status: 422 },
        );
      }
      // P0003 — INVENTORY_INSUFFICIENT (saldo de tokens da assessoria)
      if (msg.includes("INVENTORY_INSUFFICIENT") || rpcErr.code === "P0003") {
        return NextResponse.json(
          { error: "Saldo insuficiente de OmniCoins" },
          { status: 422 },
        );
      }
      // P0001 — INVALID_AMOUNT / MISSING_REF_ID (erro de contrato; não deveria ocorrer após validação acima)
      if (msg.includes("INVALID_AMOUNT") || msg.includes("MISSING_REF_ID") || rpcErr.code === "P0001") {
        return NextResponse.json(
          { error: "Parâmetros inválidos" },
          { status: 400 },
        );
      }
      logger.error("emit_coins_atomic failed", rpcErr, {
        athlete_user_id,
        amount,
        groupId,
        refId,
      });
      return NextResponse.json({ error: "Erro ao distribuir coins" }, { status: 500 });
    }

    // rpcData é array com uma linha: { ledger_id, new_balance, was_idempotent }
    const row = Array.isArray(rpcData) ? rpcData[0] : rpcData;
    const wasIdempotent = Boolean(row?.was_idempotent);

    if (!wasIdempotent) {
      await auditLog({
        actorId: user.id,
        groupId,
        action: "coins.distribute",
        targetType: "athlete",
        targetId: athlete_user_id,
        metadata: { amount, athlete_name: member.display_name, ref_id: refId },
      });
    }

    // L20-03 — echo trace_id to client so support/users can quote it when
    // reporting incidents ("trace_id 1234 took 15s") and we can pivot
    // straight to the Sentry trace tree.
    const traceId = currentTraceId();
    const responseHeaders: Record<string, string> = {};
    if (traceId) responseHeaders["x-trace-id"] = traceId;
    return NextResponse.json(
      {
        ok: true,
        athlete_user_id,
        amount,
        athlete_name: member.display_name,
        idempotent: wasIdempotent,
        new_balance: row?.new_balance ?? null,
      },
      { headers: responseHeaders },
    );
  } catch (error) {
    logger.error("Failed to distribute coins", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
