import { createServiceClient } from "@/lib/supabase/service";

/**
 * L12-04 — pg_cron SLA monitor (TS surface).
 *
 * Mirror of `public.fn_compute_cron_sla_stats(p_window_hours)` and
 * `public.fn_classify_cron_sla()` (SQL migration
 * `20260420140000_l12_cron_sla_monitoring.sql`).
 *
 * Two responsibilities:
 *
 *   1. `computeCronSlaStats({ windowHours })` — wraps the read-only
 *      RPC so admin pages / endpoints get one row per known cron job
 *      with the SLA verdict already computed by Postgres. The RPC is
 *      `STABLE` + `service_role` only, so this helper MUST run
 *      server-side (route handlers / cron jobs / admin pages).
 *
 *   2. `classifyCronSla()` — pure mirror of the SQL classifier so
 *      unit tests can assert "TS and SQL produce the same enum on
 *      the same vector". The integration test
 *      (`tools/test_l12_04_cron_sla_monitor.ts`) closes the loop by
 *      feeding the SAME vectors into both.
 *
 * The classifier is intentionally pure / no I/O — the only side
 * effect is the RPC call inside `computeCronSlaStats`.
 *
 * SLA semantics
 * ─────────────
 *   • `target_seconds` — typical / "feels normal" runtime. Drift
 *     above target across multiple runs in the window is a leading
 *     indicator (warn-eligible).
 *   • `breach_seconds` — single-run alert threshold. A SINGLE run
 *     above breach is enough to warn; > 2x breach pages.
 *   • `enabled` — when false the classifier returns 'ok' regardless
 *     of how badly the job is performing (used for planned
 *     maintenance windows so on-call isn't paged unnecessarily).
 *
 * Audit refs:
 *   docs/audit/findings/L12-04-pg-cron-nao-monitora-sla-de-execucao.md
 *   docs/runbooks/CRON_HEALTH_RUNBOOK.md
 */

export type CronSlaSeverity = "ok" | "warn" | "critical" | "unknown";

export type CronSlaThresholdSource = "configured" | "derived";

export interface CronSlaRow {
  name: string;
  /** Standard 5-field cron expression, or null if the job is only known via history/thresholds. */
  schedule: string | null;
  /** Output of `fn_parse_cron_interval_seconds`. Falls back to 86400. */
  expectedIntervalSeconds: number;
  thresholdSource: CronSlaThresholdSource;
  /** Typical runtime (seconds). Drift above target ⇒ warn (when paired with breach_count ≥ 2). */
  targetSeconds: number;
  /** Single-run alert threshold (seconds). last_run/p95 > breach ⇒ warn; > 2x ⇒ critical. */
  breachSeconds: number;
  enabled: boolean;
  runCount: number;
  failedCount: number;
  /** Mean duration over the window. Null when run_count = 0. */
  avgDurationSeconds: number | null;
  p50DurationSeconds: number | null;
  p95DurationSeconds: number | null;
  p99DurationSeconds: number | null;
  maxDurationSeconds: number | null;
  /** Duration of the most recent run in the window. Null when run_count = 0. */
  lastDurationSeconds: number | null;
  /** Timestamp (ISO) of the most recent finished_at in the window. */
  lastFinishedAt: string | null;
  /** How many runs in the window exceeded breach_seconds. */
  breachCount: number;
  severity: CronSlaSeverity;
}

export interface CronSlaSummary {
  rows: CronSlaRow[];
  countsBySeverity: Record<CronSlaSeverity, number>;
  /** True when no row has severity `warn` or `critical`. */
  healthy: boolean;
  /** UTC ISO timestamp captured immediately after the RPC returned. */
  checkedAt: string;
  /** Echo of the window the RPC was asked to consider. */
  windowHours: number;
}

/**
 * Pure mirror of `public.fn_classify_cron_sla`. Inputs are EXACTLY
 * the same names/units as the SQL function so unit tests can copy
 * vectors verbatim.
 *
 *   `runCount`        → bigint in SQL; 0 = no runs in window
 *   `avgDuration`     → numeric in SQL; null when run_count = 0
 *   `p95Duration`     → numeric in SQL; null when run_count = 0
 *   `lastDuration`    → numeric in SQL; null when run_count = 0
 *   `targetSeconds`   → numeric in SQL; sustained-drift threshold
 *   `breachSeconds`   → numeric in SQL; per-run alert threshold
 *   `breachCount`     → bigint in SQL; runs > breach in window
 *   `enabled`         → boolean in SQL; false = silenced
 *
 * The `>` boundaries match the SQL function 1:1. There is a Vitest
 * assertion (`cron-sla.test.ts`) covering each branch with the
 * SAME numeric vectors as the SQL self-test, so a regression on
 * either side is caught immediately.
 */
export function classifyCronSla(
  runCount: number | null | undefined,
  avgDuration: number | null | undefined,
  p95Duration: number | null | undefined,
  lastDuration: number | null | undefined,
  targetSeconds: number | null | undefined,
  breachSeconds: number | null | undefined,
  breachCount: number | null | undefined,
  enabled: boolean = true,
): CronSlaSeverity {
  // 0) explicitly disabled → silenced.
  if (enabled === false) return "ok";

  const runs = numberOrZero(runCount);

  // 1) zero runs in window → no signal.
  if (runs === 0) return "unknown";

  const breach = numberOrNull(breachSeconds);
  const last = numberOrNull(lastDuration);
  const p95 = numberOrNull(p95Duration);

  // 2) Most recent run > 2x breach OR p95 > 2x breach → page.
  if (
    breach !== null &&
    ((last !== null && last > 2 * breach) ||
      (p95 !== null && p95 > 2 * breach))
  ) {
    return "critical";
  }

  // 3) Most recent run > breach OR p95 > breach → warn.
  if (
    breach !== null &&
    ((last !== null && last > breach) ||
      (p95 !== null && p95 > breach))
  ) {
    return "warn";
  }

  const target = numberOrNull(targetSeconds);
  const avg = numberOrNull(avgDuration);
  const breachEvents = numberOrZero(breachCount);

  // 4) Sustained drift: avg > target AND >= 2 breach events in window.
  if (
    target !== null &&
    avg !== null &&
    avg > target &&
    breachEvents >= 2
  ) {
    return "warn";
  }

  return "ok";
}

function numberOrNull(v: number | null | undefined): number | null {
  if (v === null || v === undefined) return null;
  return Number.isFinite(v) ? v : null;
}

function numberOrZero(v: number | null | undefined): number {
  if (v === null || v === undefined) return 0;
  return Number.isFinite(v) ? v : 0;
}

interface RawCronSlaRow {
  name: string | null;
  schedule: string | null;
  expected_interval_seconds: number | string | null;
  source_thresholds: string | null;
  target_seconds: number | string | null;
  breach_seconds: number | string | null;
  enabled: boolean | null;
  run_count: number | string | null;
  failed_count: number | string | null;
  avg_duration_seconds: number | string | null;
  p50_duration_seconds: number | string | null;
  p95_duration_seconds: number | string | null;
  p99_duration_seconds: number | string | null;
  max_duration_seconds: number | string | null;
  last_duration_seconds: number | string | null;
  last_finished_at: string | null;
  breach_count: number | string | null;
  severity: string | null;
}

function toNumber(value: number | string | null | undefined): number | null {
  if (value === null || value === undefined) return null;
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function normaliseSeverity(s: string | null | undefined): CronSlaSeverity {
  if (s === "ok" || s === "warn" || s === "critical" || s === "unknown") return s;
  return "unknown";
}

function normaliseThresholdSource(
  s: string | null | undefined,
): CronSlaThresholdSource {
  return s === "configured" ? "configured" : "derived";
}

function normaliseRow(raw: RawCronSlaRow): CronSlaRow | null {
  if (!raw.name || raw.name.length === 0) return null;
  return {
    name: raw.name,
    schedule: raw.schedule ?? null,
    expectedIntervalSeconds: toNumber(raw.expected_interval_seconds) ?? 86400,
    thresholdSource: normaliseThresholdSource(raw.source_thresholds),
    targetSeconds: toNumber(raw.target_seconds) ?? 0,
    breachSeconds: toNumber(raw.breach_seconds) ?? 0,
    enabled: typeof raw.enabled === "boolean" ? raw.enabled : true,
    runCount: toNumber(raw.run_count) ?? 0,
    failedCount: toNumber(raw.failed_count) ?? 0,
    avgDurationSeconds: toNumber(raw.avg_duration_seconds),
    p50DurationSeconds: toNumber(raw.p50_duration_seconds),
    p95DurationSeconds: toNumber(raw.p95_duration_seconds),
    p99DurationSeconds: toNumber(raw.p99_duration_seconds),
    maxDurationSeconds: toNumber(raw.max_duration_seconds),
    lastDurationSeconds: toNumber(raw.last_duration_seconds),
    lastFinishedAt: raw.last_finished_at ?? null,
    breachCount: toNumber(raw.breach_count) ?? 0,
    severity: normaliseSeverity(raw.severity),
  };
}

export interface ComputeCronSlaStatsOptions {
  /**
   * Optional pre-built supabase client. Tests inject a stubbed `.rpc()`
   * to avoid hitting Postgres; production callers should leave this
   * undefined and let the helper instantiate the service client.
   */
  client?: {
    rpc: (
      fn: string,
      args?: Record<string, unknown>,
    ) => Promise<{ data: unknown; error: { message: string } | null }>;
  };
  /**
   * History window the RPC will scan, in hours. Validated server-side
   * by `fn_compute_cron_sla_stats` (1..720). Defaults to 24h, which
   * matches the cadence the alert pipeline uses internally.
   */
  windowHours?: number;
  /**
   * When set, drops rows below this severity from `rows`. Useful for
   * the alert-only view but defaults to keeping everything so the
   * admin endpoint can render the full grid.
   */
  minSeverity?: CronSlaSeverity;
}

const SEVERITY_ORDER: Record<CronSlaSeverity, number> = {
  critical: 0,
  warn: 1,
  unknown: 2,
  ok: 3,
};

const DEFAULT_WINDOW_HOURS = 24;
const MAX_WINDOW_HOURS = 24 * 30;

/**
 * Run `fn_compute_cron_sla_stats(p_window_hours)` and return parsed
 * rows + a counts/healthy summary for the UI banner.
 *
 * Throws on RPC error so the caller's monitoring sees the incident
 * rather than silently swallowing a "looks healthy" response. The
 * admin endpoint catches this and surfaces it as a 500 with the
 * underlying message.
 */
export async function computeCronSlaStats(
  opts: ComputeCronSlaStatsOptions = {},
): Promise<CronSlaSummary> {
  const windowHours = clampWindowHours(opts.windowHours);
  const db = opts.client ?? createServiceClient();
  const checkedAt = new Date().toISOString();

  const { data, error } = await db.rpc("fn_compute_cron_sla_stats", {
    p_window_hours: windowHours,
  });
  if (error) {
    throw new Error(`fn_compute_cron_sla_stats failed: ${error.message}`);
  }

  const rawRows = (Array.isArray(data) ? data : []) as RawCronSlaRow[];
  let rows = rawRows
    .map(normaliseRow)
    .filter((r): r is CronSlaRow => r !== null);

  if (opts.minSeverity) {
    const cutoff = SEVERITY_ORDER[opts.minSeverity];
    rows = rows.filter((r) => SEVERITY_ORDER[r.severity] <= cutoff);
  }

  const countsBySeverity: Record<CronSlaSeverity, number> = {
    ok: 0,
    warn: 0,
    critical: 0,
    unknown: 0,
  };
  for (const r of rows) {
    countsBySeverity[r.severity] += 1;
  }

  const healthy =
    countsBySeverity.warn === 0 && countsBySeverity.critical === 0;

  return { rows, countsBySeverity, healthy, checkedAt, windowHours };
}

function clampWindowHours(v: number | null | undefined): number {
  if (v === null || v === undefined) return DEFAULT_WINDOW_HOURS;
  if (!Number.isFinite(v)) return DEFAULT_WINDOW_HOURS;
  const n = Math.floor(v);
  if (n < 1) return 1;
  if (n > MAX_WINDOW_HOURS) return MAX_WINDOW_HOURS;
  return n;
}
