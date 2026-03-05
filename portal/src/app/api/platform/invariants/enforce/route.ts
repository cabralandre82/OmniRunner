import { NextRequest, NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/service";
import { auditLog } from "@/lib/audit";
import { logger } from "@/lib/logger";
import { metrics } from "@/lib/metrics";

/**
 * POST /api/platform/invariants/enforce
 *
 * Cron-safe endpoint that checks custody invariants and auto-blocks
 * accounts with violations. Callable by service role or external cron.
 */
export async function POST(req: NextRequest) {
  const authHeader = req.headers.get("authorization") ?? "";
  const cronSecret = process.env.CRON_SECRET;

  if (cronSecret && authHeader !== `Bearer ${cronSecret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
  const db = createServiceClient();
  const start = Date.now();

  const { data: violations, error } = await db.rpc("check_custody_invariants");

  if (error) {
    logger.error("Invariant check failed", error);
    metrics.increment("invariants.check.error");
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const violationList = (violations ?? []) as {
    group_id: string;
    total_deposited: number;
    total_committed: number;
    computed_available: number;
    violation: string;
  }[];

  let blocked = 0;
  let alreadyBlocked = 0;

  for (const v of violationList) {
    const { data: account } = await db
      .from("custody_accounts")
      .select("is_blocked")
      .eq("group_id", v.group_id)
      .maybeSingle();

    if (account?.is_blocked) {
      alreadyBlocked++;
      continue;
    }

    await db
      .from("custody_accounts")
      .update({
        is_blocked: true,
        blocked_reason: `Invariant violation: ${v.violation}`,
        updated_at: new Date().toISOString(),
      })
      .eq("group_id", v.group_id);

    await auditLog({
      actorId: "system",
      groupId: v.group_id,
      action: "custody.account.blocked",
      metadata: {
        reason: v.violation,
        total_deposited: v.total_deposited,
        total_committed: v.total_committed,
      },
    });

    blocked++;
    logger.warn("Account blocked due to invariant violation", {
      group_id: v.group_id,
      violation: v.violation,
    });
  }

  const latencyMs = Date.now() - start;
  metrics.timing("invariants.enforce.duration", latencyMs);
  metrics.gauge("invariants.violations", violationList.length);
  metrics.gauge("invariants.blocked", blocked);

  return NextResponse.json({
    healthy: violationList.length === 0,
    violations_found: violationList.length,
    accounts_blocked: blocked,
    already_blocked: alreadyBlocked,
    checked_at: new Date().toISOString(),
    latency_ms: latencyMs,
  });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    if (/PGRST|does not exist|custody_accounts/.test(msg)) {
      return NextResponse.json({ error: "Feature not available yet" }, { status: 503 });
    }
    throw err;
  }
}
