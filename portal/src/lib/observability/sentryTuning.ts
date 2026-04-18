/**
 * Centralized Sentry sampling + tag enrichment policy.
 *
 * Single source of truth for `sentry.client.config.ts`, `sentry.server.config.ts`,
 * and `sentry.edge.config.ts`. Without this module, each runtime would drift
 * independently (e.g. someone updates the server sampler but forgets the edge,
 * resulting in inconsistent visibility across the deployment).
 *
 * Audit references:
 *   - L20-04 — `tracesSampler` adaptativo por rota (custody/swap=100%, health=0%, default=10%)
 *   - L20-05 — `severity` tag automático por rota (P1 finance/security vs P4 padrão),
 *              consumido pela alert policy do Sentry para roteamento por severidade
 *              (ver `docs/observability/ALERT_POLICY.md`).
 */

import type { SamplingContext } from "@sentry/core";

// ─────────────────────────────────────────────────────────────────────
// L20-05 — Route severity classification (drives alert routing)
// ─────────────────────────────────────────────────────────────────────

/**
 * Severity ladder used as Sentry `severity` tag. The alert policy rules are
 * documented in `docs/observability/ALERT_POLICY.md`. Summary:
 *   - P1: financial/security/auth — pager + #incidents Slack channel
 *   - P2: critical user paths (checkout, login) — Slack only, no pager
 *   - P3: regular API + UI — Sentry digest email (daily)
 *   - P4: noise / dev console — Sentry only, no notification
 */
export type SeverityTag = "P1" | "P2" | "P3" | "P4";

interface SeverityRule {
  /** Match if the request URL pathname starts with any of these prefixes. */
  prefixes: readonly string[];
  /** Match if the URL pathname equals one of these literals. */
  exact?: readonly string[];
  severity: SeverityTag;
}

/**
 * Severity rules are evaluated in order. First match wins. Catch-all default
 * is P3. Keep the list DENSE and AUDITABLE — every rule must have a clear
 * justification in `docs/observability/ALERT_POLICY.md`.
 */
const SEVERITY_RULES: readonly SeverityRule[] = [
  // ── P1 — Wake someone up ──────────────────────────────────────────
  {
    severity: "P1",
    prefixes: [
      "/api/custody/", // deposits, withdrawals, balances
      "/api/swap/", // BRL <> coin swap
      "/api/distribute-coins", // fan-out money to runners
      "/api/withdraw", // top-level withdraw (legacy alias)
      "/api/billing/", // Asaas billing webhook + reconciliation
      "/api/auth/", // session bootstrap (down → no logins possible)
    ],
    exact: ["/api/auth/callback"],
  },
  // ── P2 — Slack ping, no pager ─────────────────────────────────────
  {
    severity: "P2",
    prefixes: [
      "/api/coaching/", // group/membership ops — affects whole team
      "/api/sessions/", // session ingest — runner data loss risk
      "/api/runs/", // raw run upload — runner data loss risk
      "/api/platform/", // admin/platform operations
    ],
  },
  // ── P4 — Pure noise we never want to alert on ────────────────────
  {
    severity: "P4",
    exact: ["/api/health", "/api/liveness"],
    prefixes: ["/_next/", "/monitoring", "/favicon"],
  },
  // Default catch-all = P3 (handled below — `classifySeverity`).
] as const;

/**
 * Classify a URL pathname into a severity bucket. Used by both:
 *   - Sentry tag enrichment (this file)
 *   - logger.error severity tagging (see `lib/logger.ts` — TODO L20-05 phase 2)
 */
export function classifySeverity(pathname: string | undefined | null): SeverityTag {
  if (!pathname) return "P3";
  for (const rule of SEVERITY_RULES) {
    if (rule.exact?.includes(pathname)) return rule.severity;
    if (rule.prefixes.some((p) => pathname.startsWith(p))) return rule.severity;
  }
  return "P3";
}

// ─────────────────────────────────────────────────────────────────────
// L20-04 — Adaptive trace sampler
// ─────────────────────────────────────────────────────────────────────

/**
 * Adaptive trace sampling rates. Tuned to:
 *   - Burn 0% of Sentry quota on health probes (which run every 30s).
 *   - Capture 100% of money-touching traces (forensic value > cost).
 *   - Capture 10% of normal traffic (statistically meaningful for p99).
 *
 * Tweak only with cost-modeling. Doubling the default to 20% roughly
 * doubles the Sentry transaction quota burn for steady-state traffic.
 */
const SAMPLE_RATES = {
  /** Money-touching, security-sensitive — full visibility required. */
  P1: 1.0,
  /** Critical user paths — high but not full to avoid budget burn. */
  P2: 0.5,
  /** Normal API + UI traffic. */
  P3: 0.1,
  /** Pure noise (health, static, monitoring tunnel). */
  P4: 0.0,
} as const satisfies Record<SeverityTag, number>;

/**
 * Sentry `tracesSampler` callback. Returns the sample rate (0..1) for the
 * given context. Sentry's recommended pattern (vs. flat `tracesSampleRate`)
 * because it lets us keep budget low while still capturing money-flow traces.
 *
 * Edge cases:
 *   - `samplingContext.name` is the transaction name (route or operation).
 *     Sentry's Next.js integration sets it to the URL pathname for HTTP
 *     transactions and to the operation name for non-HTTP transactions
 *     (e.g. background tasks).
 *   - When undefined (rare — early bootstrap), we fall back to P3 default.
 *   - `parentSampled` honored: if upstream service decided to sample, we
 *     follow them so the trace is contiguous (avoids broken trace trees).
 */
export function tracesSampler(samplingContext: SamplingContext): number {
  if (samplingContext.parentSampled !== undefined) {
    return samplingContext.parentSampled ? 1.0 : 0.0;
  }
  const name = samplingContext.name ?? samplingContext.transactionContext?.name;
  const severity = classifySeverity(typeof name === "string" ? name : undefined);
  return SAMPLE_RATES[severity];
}

// ─────────────────────────────────────────────────────────────────────
// L20-05 — Tag enrichment (event processor)
// ─────────────────────────────────────────────────────────────────────

interface SentryEventLike {
  request?: { url?: string };
  transaction?: string;
  tags?: Record<string, string | number | boolean | bigint | symbol | null | undefined>;
}

/**
 * Mutates a Sentry event in-place to add a `severity` tag derived from the
 * route. Use as a `beforeSend` / `beforeSendTransaction` callback.
 *
 * Why mutate vs. return new: `beforeSend` is in the hot path of every error
 * report — allocating a new object per event would add measurable GC pressure
 * for high-throughput error scenarios.
 */
export function enrichWithSeverity<T extends SentryEventLike>(event: T): T {
  const url = event.request?.url ?? event.transaction;
  if (!url) return event;

  let pathname: string;
  try {
    pathname = url.startsWith("/") ? url : new URL(url).pathname;
  } catch {
    pathname = typeof url === "string" ? url : "";
  }

  event.tags = { ...(event.tags ?? {}), severity: classifySeverity(pathname) };
  return event;
}

/**
 * Returns the sample rate for a given pathname. Exported for unit tests +
 * for use in non-Sentry code paths (e.g. custom OTLP exporters in future
 * L20-03 OpenTelemetry rollout).
 */
export function sampleRateForPath(pathname: string): number {
  return SAMPLE_RATES[classifySeverity(pathname)];
}
