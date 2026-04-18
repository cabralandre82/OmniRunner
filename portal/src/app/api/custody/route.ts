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

  const account = await getCustodyAccount(auth.groupId);
  return NextResponse.json({ account });
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = await rateLimit(`custody:${ip}`, { maxRequests: 10, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const body = await req.json();

  // Determine action: deposit or confirm
  if (body.deposit_id) {
    const parsed = confirmSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        { error: "Invalid input", details: parsed.error.flatten() },
        { status: 400 },
      );
    }

    try {
      // L01-04 — propaga auth.groupId para confirm (cross-group block).
      // Se um admin_master do grupo A tentar confirmar deposit do grupo B,
      // a RPC retorna "Deposit not found, wrong group, or already processed"
      // (mensagem genérica para defender contra enumeration).
      await confirmDeposit(parsed.data.deposit_id, auth.groupId);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Confirm failed";
      return NextResponse.json({ error: msg }, { status: 422 });
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
    return NextResponse.json(
      {
        error: "Missing x-idempotency-key header",
        hint: "Send a UUID v4 in the x-idempotency-key header to make this request safely retryable.",
        code: "IDEMPOTENCY_KEY_REQUIRED",
      },
      { status: 400 },
    );
  }
  if (!IDEMPOTENCY_KEY_RE.test(idempotencyKey)) {
    return NextResponse.json(
      {
        error: "Invalid x-idempotency-key format",
        hint: "Expected UUID v4 or opaque 16-128 char [A-Za-z0-9_-] string.",
        code: "IDEMPOTENCY_KEY_INVALID",
      },
      { status: 400 },
    );
  }

  const parsed = depositSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  await getOrCreateCustodyAccount(auth.groupId);

  try {
    const result = await createCustodyDeposit(
      auth.groupId,
      parsed.data.amount_usd,
      parsed.data.gateway,
      idempotencyKey,
    );

    if (!result) {
      return NextResponse.json(
        { error: "Funcionalidade de custódia não disponível ainda" },
        { status: 503 },
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
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : "Deposit failed";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
