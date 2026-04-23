import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  getCustodyAccount,
  getOrCreateCustodyAccount,
  createCustodyDeposit,
  confirmDeposit,
} from "@/lib/custody";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import {
  apiError,
  apiUnauthorized,
  apiForbidden,
  apiValidationFailed,
  apiRateLimited,
  apiServiceUnavailable,
} from "@/lib/api/errors";
import { rateLimitKey } from "@/lib/api/rate-limit-key";
import { withErrorHandler } from "@/lib/api-handler";
import { z } from "zod";

const depositSchema = z
  .object({
    amount_usd: z.number().min(10).max(1_000_000),
    gateway: z.enum(["stripe", "mercadopago"]),
  })
  .strict();

const confirmSchema = z
  .object({
    deposit_id: z.string().uuid(),
  })
  .strict();

/**
 * L01-04 — UUID v4 (RFC 4122) — formato canônico aceito.
 * Aceitamos qualquer UUID v4 OU outras chaves opacas com >= 16 chars
 * (alguns clientes usam ULID, etc).
 */
const IDEMPOTENCY_KEY_RE =
  /^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9_-]{16,128})$/i;

type CustodyAuthError =
  | { error: "Unauthorized"; status: 401 }
  | { error: "No group"; status: 400 }
  | { error: "Forbidden"; status: 403 };

async function requireAdminMaster(): Promise<
  CustodyAuthError | { user: { id: string }; groupId: string }
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
  err: CustodyAuthError,
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

// L17-01 — outermost safety-net: qualquer throw vira 500 INTERNAL_ERROR
// canônico (`{ ok:false, error:{ code, message, request_id } }`) com
// Sentry capture + request_id propagado em vez de stack trace cru.
export const GET = withErrorHandler(_get, "api.custody.get");
export const POST = withErrorHandler(_post, "api.custody.post");

async function _get(req: NextRequest) {
  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

  const account = await getCustodyAccount(auth.groupId);
  return NextResponse.json({ account });
}

async function _post(req: NextRequest) {
  // L14-04 — bucket por grupo (cookie) com fallback para hashed-IP.
  const cookieGroupId = cookies().get("portal_group_id")?.value ?? null;
  const rl = await rateLimit(
    rateLimitKey({ prefix: "custody", groupId: cookieGroupId, request: req }),
    { maxRequests: 10, windowMs: 60_000 },
  );
  if (!rl.allowed) {
    const retryAfter = Math.ceil((rl.resetAt - Date.now()) / 1000);
    return apiRateLimited(req, retryAfter);
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) return authErrorResponse(req, auth);

  const body = await req.json();

  // Determine action: deposit or confirm
  if (body.deposit_id) {
    const parsed = confirmSchema.safeParse(body);
    if (!parsed.success) {
      return apiValidationFailed(req, "Invalid input", parsed.error.flatten());
    }

    try {
      // L01-04 — propaga auth.groupId para confirm (cross-group block).
      // Se um admin_master do grupo A tentar confirmar deposit do grupo B,
      // a RPC retorna "Deposit not found, wrong group, or already processed"
      // (mensagem genérica para defender contra enumeration).
      await confirmDeposit(parsed.data.deposit_id, auth.groupId);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Confirm failed";
      return apiError(req, "CUSTODY_CONFIRM_FAILED", msg, 422);
    }

    await auditLog({
      actorId: auth.user.id,
      groupId: auth.groupId,
      action: "custody.deposit.confirmed",
      targetId: parsed.data.deposit_id,
    });

    return NextResponse.json({ ok: true });
  }

  // ─── Create deposit ────────────────────────────────────────────────────
  // L01-04 — exige x-idempotency-key. Sem header: 400. UUID v4 ou opaque
  // 16-128 chars (ULID, nanoid, etc). Mesma chave + mesmo group → mesmo
  // deposit (idempotent hit).
  const idempotencyKey = req.headers.get("x-idempotency-key")?.trim();
  if (!idempotencyKey) {
    return apiError(
      req,
      "IDEMPOTENCY_KEY_REQUIRED",
      "Missing x-idempotency-key header",
      400,
      {
        details: {
          hint: "Send a UUID v4 in the x-idempotency-key header to make this request safely retryable.",
        },
      },
    );
  }
  if (!IDEMPOTENCY_KEY_RE.test(idempotencyKey)) {
    return apiError(
      req,
      "IDEMPOTENCY_KEY_INVALID",
      "Invalid x-idempotency-key format",
      400,
      {
        details: {
          hint: "Expected UUID v4 or opaque 16-128 char [A-Za-z0-9_-] string.",
        },
      },
    );
  }

  const parsed = depositSchema.safeParse(body);
  if (!parsed.success) {
    return apiValidationFailed(req, "Invalid input", parsed.error.flatten());
  }

  await getOrCreateCustodyAccount(auth.groupId);

  // L17-01 + L05-09 — try/catch APENAS para o caso conhecido P0010
  // (DAILY_DEPOSIT_CAP_EXCEEDED). Outros throws sobem para `withErrorHandler`,
  // que devolve 500 INTERNAL_ERROR canônico (sem vazar `e.message` cru, que
  // historicamente continha texto de erro do Postgres / nome de tabela).
  // Audit + Sentry capturados pelo wrapper.
  let result;
  try {
    result = await createCustodyDeposit(
      auth.groupId,
      parsed.data.amount_usd,
      parsed.data.gateway,
      idempotencyKey,
    );
  } catch (e: unknown) {
    const err = e as { code?: string; message?: string; hint?: string };
    if (err?.code === "P0010" || /DAILY_DEPOSIT_CAP_EXCEEDED/.test(err?.message ?? "")) {
      return apiError(
        req,
        "DAILY_DEPOSIT_CAP_EXCEEDED",
        "Cap diário de depósitos atingido para este grupo",
        422,
        {
          details: {
            hint:
              err?.hint ??
              "Aumente o limite via PATCH /api/platform/custody/[groupId]/daily-cap (platform admin) ou aguarde a próxima janela. Runbook: CUSTODY_DAILY_CAP_RUNBOOK.",
          },
        },
      );
    }
    throw e;
  }

  if (!result) {
    return apiServiceUnavailable(
      req,
      "Funcionalidade de custódia não disponível ainda",
    );
  }

  const { deposit, wasIdempotent } = result;

  // Audit só registra na criação real — replays não inflam o log.
  if (!wasIdempotent) {
    await auditLog({
      actorId: auth.user.id,
      groupId: auth.groupId,
      action: "custody.deposit.created",
      targetId: deposit.id,
      metadata: {
        amount_usd: parsed.data.amount_usd,
        gateway: parsed.data.gateway,
        idempotency_key: idempotencyKey,
      },
    });
  }

  // L01-04 — header `Idempotent-Replayed: true` permite ao cliente
  // detectar (Stripe usa convenção similar com `Idempotency-Key`).
  return NextResponse.json(
    { deposit, idempotent: wasIdempotent },
    {
      headers: wasIdempotent
        ? { "Idempotent-Replayed": "true" }
        : undefined,
    },
  );
}
