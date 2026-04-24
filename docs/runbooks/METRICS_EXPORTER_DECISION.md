# Metrics Exporter — Decision

**Status:** Ratified (2026-04-21)
**Owner:** platform + observability
**Related:** L06-09, L20-04 (Sentry adaptive sampler), L20-05
(severity tags), L20-13 (error budget policy), L20-08 (SLO
docs).

## Question being answered

> "`portal/src/lib/metrics.ts` defines a `LogMetricsCollector`
> that emits JSON lines via `logger.info`. There's no
> Prometheus / StatsD / Datadog exporter. Are we OK shipping
> 'metrics' as Vercel log lines forever?"

## Decision (the short version)

**Stay on the log-line collector for at least the next 12
months.** Do not add Prometheus / StatsD / Datadog now. The
operational value of these exporters at our current scale
(< 10k MAU, < 5M requests/month, single Vercel project) is
swamped by their cost and complexity, and the existing
log-based metrics + Sentry + Better Uptime stack already
covers what we need to act on.

## Why we already have enough signal

| Need                          | Today's tool                             | Gap? |
|-------------------------------|------------------------------------------|------|
| Latency p50/p95/p99 per route | `fn_rpc_latency_summary` (L18-10) + Vercel Analytics | No |
| Error rate per route          | Sentry transactions tagged P1..P4 (L20-05) + alert routing | No |
| Custody / clearing balance drift | `reconcile-wallets-cron` (L06-03) + `wallet_drift_events` table + Slack alert | No |
| Cron health (started/finished, SLA) | `cron_health_alerts` + `cron-health-monitor` (L06-04) + `cron-sla-monitor` (L12-04) | No |
| Webhook delivery rate         | `business-health` endpoint (L18-10) + Sentry | No |
| Liveness / readiness          | `/api/liveness`, `/api/readiness` (L06-12) | No |
| Cost-per-MAU                  | `COST_OBSERVABILITY.md` monthly process (L20-11) | No |
| Edge / Postgres extras        | Supabase native dashboards (built-in) | No |

The gaps the auditor was worried about ("metrics are just log
lines") are real **only if you assume Prometheus-style
counters are the right tool for the job**. At our scale every
"metric" we'd publish is also surfaced either as a Sentry
event (with built-in alerting) or as a row in a Postgres table
(query-able from Metabase / DBeaver in seconds). Adding a
second observability stack would mean two places to alert
from, two places to dashboard from, and two SLAs to maintain.

## Triggers that flip the decision to YES

When ANY of these become true, we escalate to a real metrics
exporter (likely Grafana Cloud OTLP, sticking with the
@opentelemetry/api-metrics shape so the migration is mostly a
swap of `MetricsCollector` implementation):

1. **Multi-tenant rollout.** When white-label tenants land,
   per-tenant metric isolation is non-trivial in log lines
   but native in Prometheus labels.
2. **MAU > 100k.** Vercel log line cost grows linearly in
   request volume and we'd hit the breakpoint where a
   metrics exporter is cheaper than log retention.
3. **A second deployment target.** If we run Edge in
   Cloudflare Workers OR add a sidecar service in addition to
   Vercel, having a single metrics endpoint becomes a real
   operational benefit.
4. **An engineer spends > 4 h/week building Metabase
   dashboards** by querying our Postgres tables directly. At
   that point a real time-series DB pays for itself.
5. **An incident postmortem identifies "we couldn't see it in
   the metric"** as a contributing factor more than once in a
   quarter.

## Interim hardening for `LogMetricsCollector`

We make a small, immediate improvement to the existing
collector to get more structure for free:

- Tag every emission with `metric_name`, `metric_kind`
  (`counter` | `histogram` | `gauge`), `unit`, plus the
  L20-05 `severity` tag, so a future grep through Vercel logs
  can already give us per-name timeseries via a one-shot
  parser. (See follow-up to wire this consistently in
  `metrics.ts`; currently optional.)
- Document the 12 metric names that finance/security/ops
  actually act on (they are emitted by `metrics.ts` callers
  today). The single source of truth lives in
  `docs/observability/METRIC_CATALOG.md` (planned alongside
  `docs/analytics/EVENT_CATALOG.md` for L08-09). Until that
  catalog ships, the README in `metrics.ts` lists them.

## Implementation status

- **Decision:** ratified (this doc).
- **Catalog:** companion `METRIC_CATALOG.md` planned as a
  follow-up (does not gate this finding closure).
- **Migration to OTLP exporter:** not scheduled — guarded by
  the triggers above.
