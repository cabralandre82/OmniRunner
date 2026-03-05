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

const depositSchema = z.object({
  amount_usd: z.number().min(10).max(1_000_000),
  gateway: z.enum(["stripe", "mercadopago"]),
});

const confirmSchema = z.object({
  deposit_id: z.string().uuid(),
});

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
  const rl = rateLimit(`custody:${ip}`, { maxRequests: 10, windowMs: 60_000 });
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
      await confirmDeposit(parsed.data.deposit_id);
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

  // Create deposit
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
    );

    if (!result) {
      return NextResponse.json(
        { error: "Funcionalidade de custódia não disponível ainda" },
        { status: 503 },
      );
    }

    const { deposit } = result;

    await auditLog({
      actorId: auth.user.id,
      groupId: auth.groupId,
      action: "custody.deposit.created",
      targetId: deposit.id,
      metadata: {
        amount_usd: parsed.data.amount_usd,
        gateway: parsed.data.gateway,
      },
    });

    // In production, initiate gateway checkout here and return checkout URL
    // For now, return the deposit for manual/webhook confirmation
    return NextResponse.json({ deposit });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : "Deposit failed";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
