/**
 * Wallet drift severity classifier + Slack payload builder (L06-03).
 *
 * Mirror of `public.fn_classify_wallet_drift_severity` (SQL migration
 * `20260420110000_l06_wallet_drift_events.sql`). Keep the two implementations
 * byte-equivalent — there is a Deno test (`wallet_drift.test.ts`) and a SQL
 * self-test (the migration) asserting the same enum on the same vectors.
 *
 * Contract is intentionally pure / no I/O — exposed for unit tests and reused
 * by `reconcile-wallets-cron/index.ts`. The DB persistence side-effect goes
 * through `fn_record_wallet_drift_event` (called via supabase-js .rpc); the
 * Slack delivery side-effect goes through `postSlackAlert` below.
 */

export type WalletDriftSeverity = "ok" | "warn" | "critical";

export const DEFAULT_DRIFT_WARN_THRESHOLD = 10;

export interface WalletDriftClassification {
  severity: WalletDriftSeverity;
  /** true for severity ∈ {warn, critical} — caller should emit notification. */
  shouldAlert: boolean;
  /** P-tier from `docs/observability/ALERT_POLICY.md` (P1 = page; P2 = Slack). */
  pTier: "P1" | "P2" | "P4";
}

/**
 * Classify a reconcile-cron drift count into a severity tier.
 *
 *   driftedCount ≤ 0 (or NaN/non-finite) → ok    (no alert, P4)
 *   1 ≤ driftedCount ≤ warnThreshold      → warn  (Slack #incidents, P2)
 *   driftedCount > warnThreshold          → critical (page on-call, P1)
 *
 * `warnThreshold` defaults to 10 (matches DB function default). A negative
 * threshold is clamped to 0 so the caller cannot accidentally turn every
 * drift into a P1.
 */
export function classifyWalletDrift(
  driftedCount: number,
  warnThreshold: number = DEFAULT_DRIFT_WARN_THRESHOLD,
): WalletDriftClassification {
  if (!Number.isFinite(driftedCount) || driftedCount <= 0) {
    return { severity: "ok", shouldAlert: false, pTier: "P4" };
  }
  const threshold = Math.max(
    Number.isFinite(warnThreshold) ? Math.floor(warnThreshold) : DEFAULT_DRIFT_WARN_THRESHOLD,
    0,
  );
  if (Math.floor(driftedCount) <= threshold) {
    return { severity: "warn", shouldAlert: true, pTier: "P2" };
  }
  return { severity: "critical", shouldAlert: true, pTier: "P1" };
}

// ─── Slack alert payload ────────────────────────────────────────────────────

export interface DriftAlertContext {
  totalWallets: number;
  driftedCount: number;
  runId: string;
  runAt: string;
  environment: string;
  /** Optional URL to the runbook section. */
  runbookUrl?: string;
}

export interface SlackPayload {
  /** Plain-text fallback for clients that don't render blocks (mobile push). */
  text: string;
  blocks?: ReadonlyArray<unknown>;
}

/**
 * Build a Slack `chat.postMessage` payload for a wallet drift alert.
 *
 * Used for both `warn` (Slack only) and `critical` (Slack + escalation tag).
 * Returns null when `classification.shouldAlert === false` so the caller has
 * a single "should I post?" check.
 */
export function buildSlackDriftPayload(
  classification: WalletDriftClassification,
  ctx: DriftAlertContext,
): SlackPayload | null {
  if (!classification.shouldAlert) return null;

  const isCritical = classification.severity === "critical";
  const emoji = isCritical ? ":rotating_light:" : ":warning:";
  const headline = isCritical
    ? `${emoji} *${classification.pTier} — Wallet drift CRITICAL*`
    : `${emoji} *${classification.pTier} — Wallet drift detected*`;

  const lines: string[] = [
    headline,
    `Environment: \`${ctx.environment}\``,
    `Drifted wallets: *${ctx.driftedCount}* / ${ctx.totalWallets}`,
    `Run ID: \`${ctx.runId}\``,
    `Observed at: ${ctx.runAt}`,
  ];
  if (ctx.runbookUrl) {
    lines.push(`Runbook: ${ctx.runbookUrl}`);
  }
  if (isCritical) {
    lines.push(
      ":point_right: Auto-correction has already been applied. *Investigate the root mutator* (execute_burn_atomic / fn_increment_wallets_batch / etc.) before the next reconcile cycle.",
    );
  }

  const text = lines.join("\n");

  // Block kit version mirrors the text — Slack renders blocks if present and
  // falls back to text otherwise (push notifications, legacy clients).
  const blocks: ReadonlyArray<unknown> = [
    {
      type: "section",
      text: { type: "mrkdwn", text: lines.slice(0, 1).join("") },
    },
    {
      type: "section",
      fields: [
        { type: "mrkdwn", text: `*Environment*\n\`${ctx.environment}\`` },
        {
          type: "mrkdwn",
          text: `*Drifted*\n*${ctx.driftedCount}* / ${ctx.totalWallets}`,
        },
        { type: "mrkdwn", text: `*Run ID*\n\`${ctx.runId}\`` },
        { type: "mrkdwn", text: `*Observed*\n${ctx.runAt}` },
      ],
    },
  ];

  return { text, blocks };
}

// ─── Slack delivery ─────────────────────────────────────────────────────────

export interface SlackDeliveryResult {
  ok: boolean;
  status: number;
  /** Populated on failure (network error, non-2xx). Never on success. */
  error?: string;
}

/**
 * POST a Slack incoming-webhook payload, fully wrapped in try/catch so a
 * Slack outage NEVER blocks the cron from completing. Caller is expected to
 * forward the result to `fn_mark_wallet_drift_event_alerted` so the DB row
 * carries the delivery outcome.
 *
 * `fetchImpl` is injectable for unit testing.
 */
export async function postSlackAlert(
  webhookUrl: string,
  payload: SlackPayload,
  fetchImpl: typeof fetch = fetch,
  timeoutMs: number = 5_000,
): Promise<SlackDeliveryResult> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetchImpl(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    if (!res.ok) {
      return { ok: false, status: res.status, error: `HTTP ${res.status}` };
    }
    return { ok: true, status: res.status };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, status: 0, error: message };
  } finally {
    clearTimeout(timer);
  }
}
