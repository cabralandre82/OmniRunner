import { NextResponse, type NextRequest } from "next/server";
import { randomUUID } from "node:crypto";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { checkAndRecordWalletDrift } from "@/lib/wallet-invariants";
import { metrics } from "@/lib/metrics";
import { logger } from "@/lib/logger";
import { withErrorHandler } from "@/lib/api-handler";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

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
 * GET /api/platform/invariants/wallets
 *   ?max_users=5000&recent_hours=24&warn_threshold=10
 *
 * Dedicated real-time wallet ↔ ledger drift endpoint (L08-07).
 *
 * Differences vs. /api/platform/invariants:
 *   - Wallet-only — does NOT also call check_custody_invariants.
 *   - Tunable knobs via query params (clamped against the same DB-side
 *     bounds that fn_check_wallet_ledger_drift enforces).
 *   - Returns the FULL drift row set (not capped at 50) — intended for
 *     CSV-export from the on-call shell during incidents.
 *   - Always funnels non-empty results into the L06-03 alert pipeline.
 *
 * Audit: docs/audit/findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md
 * Runbook: docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md §3.x
 */

const QuerySchema = z
  .object({
    max_users: z.coerce.number().int().min(1).max(100_000).default(5000),
    recent_hours: z.coerce.number().int().min(0).max(720).default(24),
    warn_threshold: z.coerce.number().int().min(0).max(100_000).default(10),
  })
  .strict();

// L17-01 — endpoint financeiro crítico: dump completo do drift
// wallet ↔ ledger (usado em incidentes via on-call). Outermost wrapper
// garante 500 canônico + Sentry + x-request-id; o try/catch interno
// continua existindo para registrar `invariants.wallet_drift_check_error`
// e devolver `{ error: "INTERNAL", detail }` (já no formato consumido
// pelo runbook), mas qualquer throw acima dele agora também é coberto.
export const GET = withErrorHandler(_get, "api.platform.invariants.wallets.get");

async function _get(req: NextRequest) {
  const auth = await requirePlatformAdmin();
  if ("error" in auth) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const url = new URL(req.url);
  const queryRaw = Object.fromEntries(url.searchParams.entries());
  const parsed = QuerySchema.safeParse(queryRaw);
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: "BAD_REQUEST",
        detail: parsed.error.flatten(),
      },
      { status: 400 },
    );
  }

  const requestId = randomUUID();
  const t0 = Date.now();

  try {
    const dr = await checkAndRecordWalletDrift({
      runId: requestId,
      warnThreshold: parsed.data.warn_threshold,
      options: {
        maxUsers: parsed.data.max_users,
        recentHours: parsed.data.recent_hours,
      },
      notes: {
        source: "platform_admin_realtime_dedicated",
        actor: auth.user.id,
      },
    });

    const durationMs = Date.now() - t0;

    metrics.gauge("invariants.wallet_drift_count", dr.result.rows.length);
    metrics.gauge(
      "invariants.wallet_drift_healthy",
      dr.severity === "ok" ? 1 : 0,
    );
    metrics.timing("invariants.wallet_drift_check_ms", durationMs);

    logger.info("platform.invariants.wallet_drift_checked", {
      request_id: requestId,
      severity: dr.severity,
      drift_count: dr.result.rows.length,
      duration_ms: durationMs,
      drift_event_id: dr.eventId,
      max_users: parsed.data.max_users,
      recent_hours: parsed.data.recent_hours,
      actor_user_id: auth.user.id,
    });

    return NextResponse.json({
      healthy: dr.severity === "ok",
      severity: dr.severity,
      request_id: requestId,
      drift_event_id: dr.eventId,
      count: dr.result.rows.length,
      rows: dr.result.rows,
      params: {
        max_users: parsed.data.max_users,
        recent_hours: parsed.data.recent_hours,
        warn_threshold: parsed.data.warn_threshold,
      },
      checked_at: dr.result.checkedAt,
      duration_ms: durationMs,
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    metrics.increment("invariants.wallet_drift_check_error");
    logger.error("platform.invariants.wallet_drift_failed", {
      request_id: requestId,
      error: msg,
      actor_user_id: auth.user.id,
    });
    return NextResponse.json(
      { error: "INTERNAL", detail: msg, request_id: requestId },
      { status: 500 },
    );
  }
}
