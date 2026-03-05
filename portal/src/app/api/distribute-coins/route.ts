import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { distributeCoinsSchema } from "@/lib/schemas";
import { assertInvariantsHealthy } from "@/lib/custody";
import { logger } from "@/lib/logger";

export async function POST(request: Request) {
  try {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const rl = rateLimit(`distribute:${user.id}`, { maxRequests: 20, windowMs: 60_000 });
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

  const idempotencyKey = request.headers.get("x-idempotency-key");
  if (idempotencyKey) {
    const { data: existing } = await db
      .from("coin_ledger")
      .select("user_id, delta_coins")
      .eq("ref_id", idempotencyKey)
      .maybeSingle();

    if (existing) {
      return NextResponse.json({
        ok: true,
        athlete_user_id: existing.user_id,
        amount: existing.delta_coins,
        idempotent: true,
      });
    }
  }

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

  // Custody check (skip if custody system not deployed yet)
  try {
    const { error: custodyErr } = await db.rpc("custody_commit_coins", {
      p_group_id: groupId,
      p_coin_count: amount,
    });
    if (custodyErr && !custodyErr.message?.includes("could not find")) {
      return NextResponse.json(
        { error: "Lastro insuficiente na custódia da assessoria. Deposite mais lastro antes de emitir coins." },
        { status: 422 },
      );
    }
  } catch {
    // custody_commit_coins RPC may not exist yet
  }

  const { error: walletErr } = await db.rpc("increment_wallet_balance", {
    p_user_id: athlete_user_id,
    p_delta: amount,
  });

  if (walletErr) {
    return NextResponse.json(
      { error: "Erro ao creditar wallet do atleta" },
      { status: 500 },
    );
  }

  await db.from("coin_ledger").insert({
    user_id: athlete_user_id,
    delta_coins: amount,
    reason: "institution_token_issue",
    ref_id: idempotencyKey ?? `portal_${user.id}_${Date.now()}`,
    created_at_ms: Date.now(),
  });

  await auditLog({
    actorId: user.id,
    groupId,
    action: "coins.distribute",
    targetType: "athlete",
    targetId: athlete_user_id,
    metadata: { amount, athlete_name: member.display_name },
  });

  return NextResponse.json({
    ok: true,
    athlete_user_id,
    amount,
    athlete_name: member.display_name,
  });
  } catch (error) {
    logger.error("Failed to distribute coins", error);
    return NextResponse.json({ error: "Erro interno" }, { status: 500 });
  }
}
