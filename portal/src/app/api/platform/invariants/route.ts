import { type NextRequest, NextResponse } from "next/server";
import { randomUUID } from "node:crypto";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { checkAndRecordWalletDrift } from "@/lib/wallet-invariants";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

async function requirePlatformAdmin() {
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) return { error: "Not authenticated", status: 401 } as const;

  const { data: membership } = await supabase
    .from("platform_admins")
    .select("role")
    .eq("user_id", user.id)
    .single();

  if (!membership) return { error: "Forbidden", status: 403 } as const;

  return { user } as const;
}

/**
 * GET /api/platform/invariants
 *
 * Composite health check returning two independent invariant surfaces:
 *
 *   - `custody`         : output of `check_custody_invariants()` —
 *                         per-group accounting/issuance invariants.
 *   - `wallet_drift`    : real-time `wallets.balance_coins` vs
 *                         `SUM(coin_ledger.delta_coins)` drift via
 *                         `fn_check_wallet_ledger_drift` (L08-07).
 *
 * Any non-empty `wallet_drift.rows` is funnelled into the L06-03 alert
 * pipeline (`wallet_drift_events` row + Slack/PagerDuty if webhooks
 * are wired) so ad-hoc admin checks reuse the same observability
 * surface as the daily reconcile cron.
 *
 * Audit: docs/audit/findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md
 *
 * L17-01 — endpoint financeiro crítico (invariantes de custódia +
 * wallet drift). Outermost wrapper garante 500 canônico + Sentry +
 * x-request-id em qualquer throw inesperado.
 */
export const GET = withErrorHandler(_get, "api.platform.invariants.get");

async function _get(_req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const requestId = randomUUID();
  const db = createServiceClient();

  const { data: violations, error } = await db.rpc(
    "check_custody_invariants",
  );

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  const custodyHealthy = !violations || violations.length === 0;

  // L08-07 — real-time wallet drift detection (admin endpoint, not the
  // hot /api/health path). Failures here MUST NOT mask custody results.
  let walletDrift: {
    healthy: boolean;
    count: number;
    severity: "ok" | "warn" | "critical";
    sample: Array<unknown>;
    scanned_max_users: number;
    recent_hours: number;
    drift_event_id: string | null;
    error?: string;
  };
  try {
    const dr = await checkAndRecordWalletDrift({
      runId: requestId,
      notes: { source: "platform_admin_realtime", actor: auth.user.id },
    });
    walletDrift = {
      healthy: dr.severity === "ok",
      count: dr.result.rows.length,
      severity: dr.severity,
      // Cap the sample we return over the wire so a pathological
      // drift event (thousands of rows) never blows up the response.
      sample: dr.result.rows.slice(0, 50),
      scanned_max_users: dr.totalWalletsScanned,
      recent_hours: dr.result.recentHours,
      drift_event_id: dr.eventId,
    };
    metrics.gauge(
      "invariants.wallet_drift_count",
      dr.result.rows.length,
    );
    metrics.gauge(
      "invariants.wallet_drift_healthy",
      dr.severity === "ok" ? 1 : 0,
    );
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error("platform.invariants.wallet_drift_failed", {
      request_id: requestId,
      error: msg,
    });
    metrics.increment("invariants.wallet_drift_check_error");
    walletDrift = {
      healthy: false,
      count: 0,
      severity: "ok",
      sample: [],
      scanned_max_users: 0,
      recent_hours: 0,
      drift_event_id: null,
      error: msg,
    };
  }

  return NextResponse.json({
    healthy: custodyHealthy && walletDrift.healthy && !walletDrift.error,
    request_id: requestId,
    violations: violations ?? [],
    wallet_drift: walletDrift,
    checked_at: new Date().toISOString(),
  });
}
