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
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
  apiValidationFailed,
  apiRateLimited,
  apiServiceUnavailable,
  apiInternalError,
  resolveRequestId,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withErrorHandler } from "@/lib/api-handler";
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

type SwapAuthError =
  | { error: "Unauthorized"; status: 401 }
  | { error: "No group"; status: 400 }
  | { error: "Forbidden"; status: 403 };

async function requireAdminMaster(): Promise<
  SwapAuthError | { user: { id: string }; groupId: string }
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
  req: NextRequest,
  err: SwapAuthError,
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

/**
 * L05-01 — Mapeamento SwapErrorCode → HTTP status + body estruturado.
 * L14-05 — Wrap em envelope canônico `{ ok, error: { code, message,
 * request_id, details } }` mantendo `code` (e `sqlstate`/`detail` em
 * `details`) para clientes que reagem semanticamente.
 */
function swapErrorToResponse(req: NextRequest, err: SwapError): NextResponse {
  const details: Record<string, unknown> = {};
  if (err.sqlstate) details.sqlstate = err.sqlstate;
  if (err.detail) Object.assign(details, err.detail);
  const detailsArg = Object.keys(details).length > 0 ? details : undefined;
  const requestId = resolveRequestId(req);

  const status: number = (() => {
    switch (err.code) {
      case "not_found":
        return 404;
      case "not_open":
        return 409;
      case "not_owner":
        return 403;
      case "self_buy":
      case "payment_ref_invalid":
        return 400;
      case "insufficient_backing":
        return 422;
      case "expired":
        // L05-02 — 410 Gone: recurso existiu mas não está mais disponível.
        return 410;
      case "lock_not_available":
        return 503;
      default:
        return 422;
    }
  })();

  const headers =
    err.code === "lock_not_available" ? { "Retry-After": "2" } : undefined;

  return apiError(requestId, err.code as SwapErrorCode, err.message, status, {
    details: detailsArg,
    headers,
  });
}

// L14-04 — Rate-limit keys são derivadas com `rateLimitKey()` (group →
// user → hashed-IP). O legado keyed-by-IP (`swap:${ip}`) misturava
// milhares de grupos atrás de NAT móvel num único bucket.

// L17-01 — outermost safety-net: qualquer throw cai no envelope canônico
// `{ ok:false, error:{ code:"INTERNAL_ERROR", … } }` em vez de vazar stack
// trace. Erros de domínio (`SwapError`) continuam sendo capturados inline
// pelos try/catch logo abaixo para manter o mapping rico de status code.
export const GET = withErrorHandler(_get, "api.swap.get");
export const POST = withErrorHandler(_post, "api.swap.post");

async function _get(req: NextRequest) {
  // GET é pré-auth, mas tentamos derivar groupId do cookie para já
  // bucketar por grupo quando o user tiver sessão. Sem cookie: cai
  // para hashed-IP, que ainda assim é melhor que IP plaintext.
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({ prefix: "swap", groupId: cookieGroupId, request: req }),
    { maxRequests: 30, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(req, retryAfter);
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

  const offers = await getOpenSwapOffers(auth.groupId);
  return NextResponse.json({ offers });
}

async function _post(req: NextRequest) {
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({ prefix: "swap", groupId: cookieGroupId, request: req }),
    { maxRequests: 10, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(req, retryAfter);
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
      return apiError(req, e.code, e.hint ?? e.message, 503, {
        details: { key: e.key },
        headers: { "Retry-After": "60" },
      });
    }
    throw e;
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

  const body = await req.json();
  const parsed = bodySchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(req, "Invalid input", parsed.error.flatten());
  }

  const data = parsed.data;

  // Erros de I/O / runtime inesperados sobem para `withErrorHandler`,
  // que devolve 500 canônico + Sentry + request_id. Erros de domínio
  // semânticos (`SwapError`) ainda são capturados inline para mapear
  // 4xx/5xx específicos (ver `swapErrorToResponse`).
  if (data.action === "create") {
    const ttl = data.expires_in_days ?? DEFAULT_SWAP_TTL_DAYS;
    const order = await createSwapOffer(auth.groupId, data.amount_usd, ttl);

    if (!order) {
      return apiServiceUnavailable(req, "Swap feature not available");
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
        return swapErrorToResponse(req, err);
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
        return swapErrorToResponse(req, err);
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

  return apiValidationFailed(req, "Unknown action");
}
