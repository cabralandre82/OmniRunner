import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  createSwapOffer,
  acceptSwapOffer,
  getOpenSwapOffers,
  cancelSwapOffer,
  SwapError,
  DEFAULT_SWAP_TTL_DAYS,
  SWAP_PAYMENT_REF_MIN_LEN,
  SWAP_PAYMENT_REF_MAX_LEN,
  type SwapErrorCode,
} from "@/lib/swap";
import { logger } from "@/lib/logger";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import {
  assertSubsystemEnabled,
  FeatureDisabledError,
} from "@/lib/feature-flags";
import { z } from "zod";

const createSchema = z
  .object({
    action: z.literal("create"),
    amount_usd: z.number().min(100).max(500_000),
    // L05-02 — TTL canônico (1/7/30/90 dias). Default 7d se omitido.
    expires_in_days: z
      .union([z.literal(1), z.literal(7), z.literal(30), z.literal(90)])
      .optional(),
  })
  .strict();

const acceptSchema = z
  .object({
    action: z.literal("accept"),
    order_id: z.string().uuid(),
    // L02-07/ADR-008 — referência opcional ao pagamento off-platform.
    // Validação dupla (tamanho + control chars). Quando ausente, route
    // emite WARN log para revisão CFO.
    external_payment_ref: z
      .string()
      .min(SWAP_PAYMENT_REF_MIN_LEN)
      .max(SWAP_PAYMENT_REF_MAX_LEN)
      .regex(/^[^\x00-\x1f]+$/, "must not contain control characters")
      .optional(),
  })
  .strict();

const cancelSchema = z
  .object({
    action: z.literal("cancel"),
    order_id: z.string().uuid(),
  })
  .strict();

const bodySchema = z.union([createSchema, acceptSchema, cancelSchema]);

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

/**
 * L05-01 — Mapeamento SwapErrorCode → HTTP status + body estruturado.
 *
 * Permite clientes reagir semanticamente (mostrar "oferta já aceita",
 * acionar retry com backoff, etc) sem parsing de message.
 */
function swapErrorToResponse(err: SwapError): NextResponse {
  const body: {
    error: string;
    code: SwapErrorCode;
    sqlstate?: string;
    detail?: Record<string, unknown>;
  } = {
    error: err.message,
    code: err.code,
  };
  if (err.sqlstate) body.sqlstate = err.sqlstate;
  if (err.detail) body.detail = err.detail;

  switch (err.code) {
    case "not_found":
      return NextResponse.json(body, { status: 404 });
    case "not_open":
      return NextResponse.json(body, { status: 409 });
    case "not_owner":
      return NextResponse.json(body, { status: 403 });
    case "self_buy":
      return NextResponse.json(body, { status: 400 });
    case "insufficient_backing":
      return NextResponse.json(body, { status: 422 });
    case "expired":
      // L05-02 — 410 Gone: recurso existiu mas não está mais disponível.
      // Cliente deve atualizar lista (oferta saiu do marketplace).
      return NextResponse.json(body, { status: 410 });
    case "payment_ref_invalid":
      // L02-07/ADR-008 — formato de external_payment_ref inválido.
      return NextResponse.json(body, { status: 400 });
    case "lock_not_available":
      return NextResponse.json(body, {
        status: 503,
        headers: { "Retry-After": "2" },
      });
    default:
      return NextResponse.json(body, { status: 422 });
  }
}

export async function GET(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`swap:${ip}`, { maxRequests: 30, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const offers = await getOpenSwapOffers(auth.groupId);
  return NextResponse.json({ offers });
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`swap:${ip}`, { maxRequests: 10, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  // L06-06 — kill switch. POST cobre create/accept/cancel; quando desligado
  // bloqueia tudo (cancel inclusive — caso ops queira congelar o estado).
  // Para parar só create/accept mantendo cancel disponível, usar route
  // separada (backlog).
  try {
    await assertSubsystemEnabled(
      "swap.enabled",
      "Swap marketplace temporariamente suspenso pelo time de ops.",
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

  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const body = await req.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const data = parsed.data;

  try {
    if (data.action === "create") {
      const ttl = data.expires_in_days ?? DEFAULT_SWAP_TTL_DAYS;
      const order = await createSwapOffer(auth.groupId, data.amount_usd, ttl);

      if (!order) {
        return NextResponse.json({ error: "Swap feature not available" }, { status: 503 });
      }

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.created",
        targetId: order.id,
        metadata: {
          amount_usd: data.amount_usd,
          expires_in_days: ttl,
          expires_at: order.expires_at,
        },
      });

      return NextResponse.json({ order });
    }

    if (data.action === "accept") {
      try {
        await acceptSwapOffer(
          data.order_id,
          auth.groupId,
          data.external_payment_ref,
        );
      } catch (err) {
        if (err instanceof SwapError) {
          // L05-01: erro semântico — NÃO emitir auditLog de sucesso.
          // Logamos a tentativa para forense.
          await auditLog({
            actorId: auth.user.id,
            groupId: auth.groupId,
            action: "swap.offer.accept_failed",
            targetId: data.order_id,
            metadata: { code: err.code, sqlstate: err.sqlstate ?? null },
          });
          return swapErrorToResponse(err);
        }
        throw err;
      }

      // L02-07/ADR-008 — WARN observability quando ref ausente.
      // CFO usa essas linhas para amostragem de revisão semanal. Métrica
      // futura `swap_accept_without_ref_total` virá daqui.
      if (!data.external_payment_ref) {
        logger.warn("swap.accept_without_external_payment_ref", {
          order_id: data.order_id,
          buyer_group_id: auth.groupId,
          actor_id: auth.user.id,
          adr: "ADR-008",
        });
      }

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.accepted",
        targetId: data.order_id,
        metadata: {
          external_payment_ref: data.external_payment_ref ?? null,
          has_payment_ref: Boolean(data.external_payment_ref),
        },
      });

      return NextResponse.json({ ok: true });
    }

    if (data.action === "cancel") {
      let result;
      try {
        result = await cancelSwapOffer(data.order_id, auth.groupId);
      } catch (err) {
        if (err instanceof SwapError) {
          await auditLog({
            actorId: auth.user.id,
            groupId: auth.groupId,
            action: "swap.offer.cancel_failed",
            targetId: data.order_id,
            metadata: { code: err.code, sqlstate: err.sqlstate ?? null },
          });
          return swapErrorToResponse(err);
        }
        throw err;
      }

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.cancelled",
        targetId: data.order_id,
        metadata: {
          previous_status: result.previousStatus,
          new_status: result.newStatus,
        },
      });

      return NextResponse.json({
        ok: true,
        previous_status: result.previousStatus,
        new_status: result.newStatus,
      });
    }
  } catch (e: unknown) {
    console.error("[swap] operation failed:", e);
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 });
}
