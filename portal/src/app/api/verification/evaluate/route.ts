import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { cookies } from "next/headers";
import { auditLog } from "@/lib/audit";
import { rateLimit } from "@/lib/rate-limit";
import { verificationEvaluateSchema } from "@/lib/schemas";

/**
 * POST /api/verification/evaluate
 *
 * Triggers eval_athlete_verification RPC for a specific athlete.
 * This is NOT an override — it runs the same automated rules.
 * Only admin_master and professor roles can trigger this.
 * The athlete must belong to the caller's assessoria group.
 */
export async function POST(request: Request) {
  const rl = rateLimit(`verify-eval:${request.headers.get("x-forwarded-for") ?? "unknown"}`);
  if (!rl.allowed) {
    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  const supabase = createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();

  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
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
    .eq("user_id", session.user.id)
    .maybeSingle();

  if (!callerMembership || !["admin_master", "coach"].includes(callerMembership.role)) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();
  const parsed = verificationEvaluateSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues[0].message },
      { status: 400 },
    );
  }
  const userId = parsed.data.user_id;

  // Verify the athlete belongs to this group
  const { data: member } = await db
    .from("coaching_members")
    .select("user_id")
    .eq("group_id", groupId)
    .eq("user_id", userId)
    .eq("role", "athlete")
    .maybeSingle();

  if (!member) {
    return NextResponse.json(
      { error: "Atleta não encontrado nesta assessoria" },
      { status: 404 },
    );
  }

  // Call the same RPC used by event-driven and cron flows
  const { error: evalErr } = await db
    .rpc("eval_athlete_verification", { p_user_id: userId })
    .single();

  if (evalErr) {
    return NextResponse.json(
      { error: "Avaliação falhou: " + evalErr.message },
      { status: 500 },
    );
  }

  await auditLog({
    actorId: session.user.id,
    groupId: groupId,
    action: "verification.reevaluate",
    targetType: "athlete",
    targetId: userId,
  });

  return NextResponse.json({ ok: true });
}
