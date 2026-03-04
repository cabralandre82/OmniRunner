import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  createSwapOffer,
  acceptSwapOffer,
  getOpenSwapOffers,
  cancelSwapOffer,
} from "@/lib/swap";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const createSchema = z.object({
  action: z.literal("create"),
  amount_usd: z.number().min(100).max(500_000),
});

const acceptSchema = z.object({
  action: z.literal("accept"),
  order_id: z.string().uuid(),
});

const cancelSchema = z.object({
  action: z.literal("cancel"),
  order_id: z.string().uuid(),
});

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

export async function GET(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`swap:${ip}`, { maxRequests: 30, windowMs: 60_000 });
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
  const rl = rateLimit(`swap:${ip}`, { maxRequests: 10, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
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
      const order = await createSwapOffer(auth.groupId, data.amount_usd);

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.created",
        targetId: order.id,
        metadata: { amount_usd: data.amount_usd },
      });

      return NextResponse.json({ order });
    }

    if (data.action === "accept") {
      await acceptSwapOffer(data.order_id, auth.groupId);

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.accepted",
        targetId: data.order_id,
      });

      return NextResponse.json({ ok: true });
    }

    if (data.action === "cancel") {
      await cancelSwapOffer(data.order_id, auth.groupId);

      await auditLog({
        actorId: auth.user.id,
        groupId: auth.groupId,
        action: "swap.offer.cancelled",
        targetId: data.order_id,
      });

      return NextResponse.json({ ok: true });
    }
  } catch (e: unknown) {
    console.error("[swap] operation failed:", e);
    return NextResponse.json({ error: "Operação falhou. Tente novamente." }, { status: 422 });
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 });
}
