import { createServiceClient } from "@/lib/supabase/service";

/**
 * L06-04 — pg_cron health monitor (TS surface).
 *
 * Mirror of `public.fn_check_cron_health()` and
 * `public.fn_classify_cron_severity()` (SQL migration
 * `20260420130000_l06_cron_health_monitor.sql`).
 *
 * Two responsibilities:
 *
 *   1. `checkCronHealth()` — wraps the read-only RPC so admin
 *      pages / endpoints get one row per known cron job with the
 *      severity already computed by Postgres. The RPC is
 *      `STABLE` + `service_role` only, so this helper MUST run
 *      server-side (route handlers / cron jobs / admin pages).
 *
 *   2. `classifyCronSeverity()` — pure mirror of the SQL
 *      classifier so unit tests can assert "TS and SQL produce the
 *      same enum on the same vector". The integration test
 *      (`tools/test_l06_04_cron_health_monitor.ts`) closes the
 *      loop by feeding the SAME vectors into both.
 *
 * The classifier is intentionally pure / no I/O — the only side
 * effect is the RPC call inside `checkCronHealth`.
 *
 * Audit refs:
 *   docs/audit/findings/L06-04-pg-cron-jobs-sem-monitoramento-de-execucao.md
 *   docs/runbooks/CRON_HEALTH_RUNBOOK.md
 */

export type CronSeverity = "ok" | "warn" | "critical" | "unknown";

export type CronStatus =
  | "never_run"
  | "running"
  | "completed"
  | "failed"
  | "skipped"
  | "timeout"
  | "unknown";

export type CronSource = "pg_cron" | "cron_run_state" | "both";

export interface CronHealthRow {
  name: string;
  /** Standard 5-field cron expression (or null if the job is only known via cron_run_state). */
  schedule: string | null;
  source: CronSource;
  /** From `cron.job.active`, or null when the job is only known via cron_run_state. */
  active: boolean | null;
  last_status: CronStatus;
  started_at: string | null;
  finished_at: string | null;
  last_success_at: string | null;
  /** Output of `fn_parse_cron_interval_seconds`. Falls back to 86400 for unknown shapes. */
  expected_interval_seconds: number;
  /** EPOCH age of the most recent `completed` finish, or null when no success has ever been observed. */
  seconds_since_last_success: number | null;
  /** EPOCH age of `started_at` when last_status='running'. */
  running_for_seconds: number | null;
  run_count: number;
  skip_count: number;
  last_error: string | null;
  last_meta: Record<string, unknown>;
  severity: CronSeverity;
}

export interface CronHealthSummary {
  rows: CronHealthRow[];
  countsBySeverity: Record<CronSeverity, number>;
  /** True when no row has severity `warn` or `critical`. */
  healthy: boolean;
  /** UTC ISO timestamp captured immediately after the RPC returned. */
  checkedAt: string;
}

/**
 * Pure mirror of `public.fn_classify_cron_severity`. Inputs are EXACTLY
 * the same names/units as the SQL function so unit tests can copy
 * vectors verbatim.
 *
 *   `secondsSinceLastSuccess`   → bigint in SQL; null = never succeeded
 *   `expectedIntervalSeconds`   → integer in SQL; falls back to 86400
 *   `lastStatus`                → enum string; null = unknown
 *   `runningForSeconds`         → bigint in SQL; null when not running
 *
 * The `>` / `>=` boundaries match the SQL function 1:1 — drifting
 * either side would silently make TS / SQL disagree. There is a
 * Vitest assertion (`cron-health.test.ts`) covering each branch
 * with the SAME numeric vectors as the SQL self-test, so
 * a regression on either side is caught immediately.
 */
export function classifyCronSeverity(
  secondsSinceLastSuccess: number | null,
  expectedIntervalSeconds: number | null | undefined,
  lastStatus: string | null | undefined,
  runningForSeconds: number | null = null,
): CronSeverity {
  const status = (lastStatus ?? "").trim();

  // Mirror the SQL `GREATEST(COALESCE(p_expected_interval_seconds, 86400), 60)`.
  const expected = Math.max(
    Number.isFinite(expectedIntervalSeconds as number)
      ? Math.floor(expectedIntervalSeconds as number)
      : 86400,
    60,
  );

  // 1) Never executed at all.
  if (
    secondsSinceLastSuccess === null &&
    (status === "" || status === "never_run" || status === "unknown")
  ) {
    return "unknown";
  }

  // 2) running > 3x cycle → orphaned, page.
  if (
    status === "running" &&
    runningForSeconds !== null &&
    runningForSeconds > 3 * expected
  ) {
    return "critical";
  }

  // 3) failed AND stale > 1.5x cycle → failure persisted, page.
  if (
    status === "failed" &&
    secondsSinceLastSuccess !== null &&
    secondsSinceLastSuccess > 1.5 * expected
  ) {
    return "critical";
  }

  // 4) > 3 cycles since success → page.
  if (
    secondsSinceLastSuccess !== null &&
    secondsSinceLastSuccess > 3 * expected
  ) {
    return "critical";
  }

  // 5) Single recent failure → warn.
  if (status === "failed") {
    return "warn";
  }

  // 6) Modestly stale → warn.
  if (
    secondsSinceLastSuccess !== null &&
    secondsSinceLastSuccess > 1.5 * expected
  ) {
    return "warn";
  }

  // 7) running 1.5x..3x cycle → warn.
  if (
    status === "running" &&
    runningForSeconds !== null &&
    runningForSeconds > 1.5 * expected
  ) {
    return "warn";
  }

  return "ok";
}

interface RawCronHealthRow {
  name: string | null;
  schedule: string | null;
  source: string | null;
  active: boolean | null;
  last_status: string | null;
  started_at: string | null;
  finished_at: string | null;
  last_success_at: string | null;
  expected_interval_seconds: number | string | null;
  seconds_since_last_success: number | string | null;
  running_for_seconds: number | string | null;
  run_count: number | string | null;
  skip_count: number | string | null;
  last_error: string | null;
  last_meta: unknown;
  severity: string | null;
}

function toNumber(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function normaliseSeverity(s: string | null | undefined): CronSeverity {
  if (s === "ok" || s === "warn" || s === "critical" || s === "unknown") {
    return s;
  }
  return "unknown";
}

function normaliseStatus(s: string | null | undefined): CronStatus {
  switch (s) {
    case "never_run":
    case "running":
    case "completed":
    case "failed":
    case "skipped":
    case "timeout":
      return s;
    default:
      return "unknown";
  }
}

function normaliseSource(s: string | null | undefined): CronSource {
  if (s === "pg_cron" || s === "cron_run_state" || s === "both") return s;
  return "cron_run_state";
}

function normaliseRow(raw: RawCronHealthRow): CronHealthRow | null {
  if (!raw.name || raw.name.length === 0) return null;
  return {
    name: raw.name,
    schedule: raw.schedule ?? null,
    source: normaliseSource(raw.source),
    active: typeof raw.active === "boolean" ? raw.active : null,
    last_status: normaliseStatus(raw.last_status),
    started_at: raw.started_at ?? null,
    finished_at: raw.finished_at ?? null,
    last_success_at: raw.last_success_at ?? null,
    expected_interval_seconds: toNumber(raw.expected_interval_seconds) ?? 86400,
    seconds_since_last_success: toNumber(raw.seconds_since_last_success),
    running_for_seconds: toNumber(raw.running_for_seconds),
    run_count: toNumber(raw.run_count) ?? 0,
    skip_count: toNumber(raw.skip_count) ?? 0,
    last_error: raw.last_error ?? null,
    last_meta:
      raw.last_meta && typeof raw.last_meta === "object" && !Array.isArray(raw.last_meta)
        ? (raw.last_meta as Record<string, unknown>)
        : {},
    severity: normaliseSeverity(raw.severity),
  };
}

export interface CheckCronHealthOptions {
  /**
   * Optional pre-built supabase client. Tests inject a stubbed `.rpc()`
   * to avoid hitting Postgres; production callers should leave this
   * undefined and let the helper instantiate the service client.
   */
  client?: { rpc: (fn: string, args?: Record<string, unknown>) => Promise<{ data: unknown; error: { message: string } | null }> };
  /**
   * When set, drops rows below this severity from `rows`. Useful for
   * the alert-only view but defaults to keeping everything so the
   * admin endpoint can render the full grid.
   */
  minSeverity?: CronSeverity;
}

const SEVERITY_ORDER: Record<CronSeverity, number> = {
  critical: 0,
  warn: 1,
  unknown: 2,
  ok: 3,
};

/**
 * Run `fn_check_cron_health()` and return the parsed rows + a
 * pre-computed counts/healthy summary for the UI banner.
 *
 * Throws on RPC error so the caller's monitoring sees the incident
 * rather than silently swallowing a "looks healthy" response. The
 * admin endpoint catches this and surfaces it as a 500 with the
 * underlying message.
 */
export async function checkCronHealth(
  opts: CheckCronHealthOptions = {},
): Promise<CronHealthSummary> {
  const db = opts.client ?? createServiceClient();
  const checkedAt = new Date().toISOString();

  const { data, error } = await db.rpc("fn_check_cron_health");
  if (error) {
    throw new Error(`fn_check_cron_health failed: ${error.message}`);
  }

  const rawRows = (Array.isArray(data) ? data : []) as RawCronHealthRow[];
  let rows = rawRows
    .map(normaliseRow)
    .filter((r): r is CronHealthRow => r !== null);

  if (opts.minSeverity) {
    const cutoff = SEVERITY_ORDER[opts.minSeverity];
    rows = rows.filter((r) => SEVERITY_ORDER[r.severity] <= cutoff);
  }

  const countsBySeverity: Record<CronSeverity, number> = {
    ok: 0,
    warn: 0,
    critical: 0,
    unknown: 0,
  };
  for (const r of rows) {
    countsBySeverity[r.severity] += 1;
  }

  const healthy = countsBySeverity.warn === 0 && countsBySeverity.critical === 0;

  return { rows, countsBySeverity, healthy, checkedAt };
}
