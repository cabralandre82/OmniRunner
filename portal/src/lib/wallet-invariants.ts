import { createServiceClient } from "@/lib/supabase/service";

/**
 * L08-07 — Real-time wallet ↔ ledger drift detection helper.
 *
 * Companion to `reconcile-wallets-cron` (which only runs daily at
 * 04:30 UTC). The DB-side function `public.fn_check_wallet_ledger_drift`
 * performs a bounded scan and returns one row per wallet whose
 * `balance_coins` no longer equals `SUM(coin_ledger.delta_coins)`.
 *
 * The function is `SECURITY DEFINER` and `service_role`-only, so this
 * helper MUST run on the server side (route handlers / cron / admin
 * pages) using the service client.
 *
 * Audit refs:
 *   docs/audit/findings/L08-07-drift-potencial-entre-coin-ledger-e-wallets-fora.md
 *   docs/runbooks/WALLET_RECONCILIATION_RUNBOOK.md (operational follow-up)
 *   L06-03 — alert pipeline (`wallet_drift_events`); callers are
 *   expected to forward non-empty results into the same forensic table
 *   via `fn_record_wallet_drift_event` so ad-hoc detections fan into
 *   the same Slack/PagerDuty channel as cron-detected drifts.
 */

export interface WalletLedgerDriftRow {
  user_id: string;
  balance_coins: number;
  ledger_sum: number;
  /**
   * `ledger_sum - balance_coins`.
   * Positive → wallet under-credited (ledger says more coins should exist).
   * Negative → wallet over-credited (more coins exist than the ledger justifies).
   */
  drift: number;
  last_reconciled_at_ms: number | null;
  recent_activity: boolean;
}

export interface WalletLedgerDriftOptions {
  /** Upper bound on wallets sampled. DB clamps to [1, 100_000]; default 5000. */
  maxUsers?: number;
  /** Recency window for activity-priority sampling. DB clamps to [0, 720]; default 24. */
  recentHours?: number;
}

export interface WalletLedgerDriftResult {
  rows: WalletLedgerDriftRow[];
  scannedMaxUsers: number;
  recentHours: number;
  /** UTC ISO timestamp captured by the caller right after the RPC returned. */
  checkedAt: string;
}

const DEFAULT_MAX_USERS = 5000;
const DEFAULT_RECENT_HOURS = 24;

/**
 * Run the bounded wallet/ledger drift scan and return any drift rows.
 *
 * Returns an empty `rows` array (not null) when the system is healthy.
 * Throws on RPC error so the caller's monitoring sees the incident
 * rather than silently swallowing a "looks healthy" response.
 */
export async function checkWalletLedgerDrift(
  opts: WalletLedgerDriftOptions = {},
): Promise<WalletLedgerDriftResult> {
  const maxUsers = opts.maxUsers ?? DEFAULT_MAX_USERS;
  const recentHours = opts.recentHours ?? DEFAULT_RECENT_HOURS;

  const db = createServiceClient();
  const { data, error } = await db.rpc("fn_check_wallet_ledger_drift", {
    p_max_users: maxUsers,
    p_recent_hours: recentHours,
  });

  if (error) {
    throw new Error(`fn_check_wallet_ledger_drift failed: ${error.message}`);
  }

  const rows = (Array.isArray(data) ? data : []) as Array<{
    user_id: string;
    balance_coins: number;
    ledger_sum: number | string;
    drift: number | string;
    last_reconciled_at_ms: number | string | null;
    recent_activity: boolean;
  }>;

  return {
    rows: rows.map((r) => ({
      user_id: r.user_id,
      balance_coins: Number(r.balance_coins ?? 0),
      ledger_sum: Number(r.ledger_sum ?? 0),
      drift: Number(r.drift ?? 0),
      last_reconciled_at_ms:
        r.last_reconciled_at_ms == null ? null : Number(r.last_reconciled_at_ms),
      recent_activity: !!r.recent_activity,
    })),
    scannedMaxUsers: maxUsers,
    recentHours,
    checkedAt: new Date().toISOString(),
  };
}

/**
 * Convenience helper that runs the drift scan AND, on any non-empty
 * result, persists a `wallet_drift_events` row via the L06-03 pipeline
 * (so the same Slack/PagerDuty alerting that fires for the daily cron
 * detection ALSO fires for ad-hoc admin checks).
 *
 * Returns the drift result enriched with the persisted event id (if
 * any). Severity is computed by the same rules as the cron path
 * (`fn_classify_wallet_drift_severity`).
 *
 * Caller is the source of `runId` — typically a request_id propagated
 * from the API route — so the forensic record can be cross-referenced
 * with route logs.
 */
export async function checkAndRecordWalletDrift(params: {
  runId: string;
  warnThreshold?: number;
  options?: WalletLedgerDriftOptions;
  notes?: Record<string, unknown>;
}): Promise<{
  result: WalletLedgerDriftResult;
  severity: "ok" | "warn" | "critical";
  eventId: string | null;
  totalWalletsScanned: number;
}> {
  const result = await checkWalletLedgerDrift(params.options);
  const driftedCount = result.rows.length;
  const warnThreshold = params.warnThreshold ?? 10;

  const db = createServiceClient();
  const { data: severityData, error: severityErr } = await db.rpc(
    "fn_classify_wallet_drift_severity",
    {
      p_drifted_count: driftedCount,
      p_warn_threshold: warnThreshold,
    },
  );
  if (severityErr) {
    throw new Error(`fn_classify_wallet_drift_severity failed: ${severityErr.message}`);
  }
  const severity = (severityData ?? "ok") as "ok" | "warn" | "critical";

  let eventId: string | null = null;
  if (severity !== "ok") {
    const { data: eventIdData, error: recordErr } = await db.rpc(
      "fn_record_wallet_drift_event",
      {
        p_run_id: params.runId,
        p_total_wallets: result.scannedMaxUsers,
        p_drifted_count: driftedCount,
        p_severity: severity,
        p_notes: {
          source: "platform_admin_realtime",
          warn_threshold: warnThreshold,
          recent_hours: result.recentHours,
          checked_at: result.checkedAt,
          ...(params.notes ?? {}),
        },
      },
    );
    if (recordErr) {
      throw new Error(`fn_record_wallet_drift_event failed: ${recordErr.message}`);
    }
    eventId = (eventIdData as string | null) ?? null;
  }

  return {
    result,
    severity,
    eventId,
    totalWalletsScanned: result.scannedMaxUsers,
  };
}
