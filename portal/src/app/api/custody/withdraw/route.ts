import { NextRequest, NextResponse } from "next/server";
import { cookies } from "next/headers";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import {
  createWithdrawal,
  executeWithdrawal,
  getWithdrawals,
  assertInvariantsHealthy,
  getFxSpreadRate,
} from "@/lib/custody";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { z } from "zod";

const withdrawSchema = z.object({
  amount_usd: z.number().min(1).max(1_000_000),
  target_currency: z.enum(["BRL", "EUR", "GBP"]).default("BRL"),
  fx_rate: z.number().positive(),
  provider_fee_usd: z.number().min(0).optional(),
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

  const withdrawals = await getWithdrawals(auth.groupId);
  return NextResponse.json({ withdrawals });
}

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") ?? "unknown";
  const rl = rateLimit(`withdraw:${ip}`, { maxRequests: 5, windowMs: 60_000 });
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const auth = await requireAdminMaster();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const healthy = await assertInvariantsHealthy();
  if (!healthy) {
    return NextResponse.json(
      { error: "System invariant violation detected. Operations suspended." },
      { status: 503 },
    );
  }

  const body = await req.json();
  const parsed = withdrawSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid input", details: parsed.error.flatten() },
      { status: 400 },
    );
  }

  const spreadPct = await getFxSpreadRate();

  try {
    const withdrawal = await createWithdrawal({
      groupId: auth.groupId,
      amountUsd: parsed.data.amount_usd,
      targetCurrency: parsed.data.target_currency,
      fxRate: parsed.data.fx_rate,
      spreadPct,
      providerFeeUsd: parsed.data.provider_fee_usd,
    });

    await executeWithdrawal(withdrawal.id);

    await auditLog({
      actorId: auth.user.id,
      groupId: auth.groupId,
      action: "custody.withdrawal.executed",
      targetId: withdrawal.id,
      metadata: {
        amount_usd: parsed.data.amount_usd,
        target_currency: parsed.data.target_currency,
        fx_rate: parsed.data.fx_rate,
        spread_pct: spreadPct,
        net_local: withdrawal.net_local_amount,
      },
    });

    return NextResponse.json({ withdrawal });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Withdrawal failed";
    return NextResponse.json({ error: msg }, { status: 422 });
  }
}
