# Capacity Planning Model

**Status:** Ratified (2026-04-21)
**Owner:** SRE + finance
**Related:** L20-12, L20-11 (cost observability),
L20-08 (SLOs), L18-09 (read replicas spec).

## Question being answered

> "When do we scale Supabase from `db.micro` to `db.small`?
> When do we add a read replica? When does Vercel Pro stop
> being enough? Today: 'when it breaks'. We need a forward-
> looking model."

## Decision

A **simple per-MAU resource model** with three breakpoints.
Reviewed quarterly. Re-validated against actual numbers at
each breakpoint.

## The model

```
DB load     = MAU × (req/MAU/mo) × (queries/req)
            ÷ (seconds_in_month × concurrent_query_capacity)

Edge load   = MAU × (req/MAU/mo) × (edge_pct)
            ÷ (seconds_in_month × edge_concurrency)

Storage     = MAU × (storage_per_MAU_GB)

CDN/egress  = MAU × (assets_per_session_KB)
            × (sessions/MAU/mo)
```

### Constants we track today

From `docs/observability/COST_OBSERVABILITY.md` (L20-11),
2026-Q1 numbers:

| Constant                          | Current value | Trend |
|-----------------------------------|---------------|-------|
| `req/MAU/mo`                      | 800           | stable |
| `queries/req` (avg)               | 4.2           | trending up (+0.3 / quarter — RSC fan-out) |
| `edge_pct`                        | 12%           | stable |
| `storage_per_MAU_GB`              | 0.05          | stable (GPS dominant) |
| `sessions/MAU/mo`                 | 14            | stable |
| `assets_per_session_KB`           | 320           | stable |
| `concurrent_query_capacity` (db.micro) | ~ 50      | hard limit |
| `concurrent_query_capacity` (db.small) | ~ 80      | hard limit |
| `concurrent_query_capacity` (db.medium) | ~ 200    | hard limit |

## Breakpoints

| MAU      | Supabase tier       | Read replica? | Vercel | Notes |
|----------|---------------------|---------------|--------|-------|
| 0–5k     | Free / Pro `db.nano` (current) | no | Pro | < USD 100/m total |
| 5k–25k   | Pro `db.small`       | no            | Pro    | First step. ~ USD 200/m. Triggered by p95 query latency > 50 ms OR concurrent queries > 30 sustained for 7 days. |
| 25k–100k | Pro `db.medium` + 1 read replica | yes (L18-09) | Pro | ~ USD 500/m. Triggered by 25k MAU OR ledger insert rate > 100/min. |
| 100k–500k | Team `db.large` + 2 read replicas + Edge fan-out | yes | Enterprise | ~ USD 2k/m. Triggered by 100k MAU OR p95 read latency > 100 ms during peak. |
| > 500k   | Bespoke (PostgreSQL on AWS RDS / dedicated infra) | yes | Enterprise | Re-architect. Likely sharded by `group_id`. |

## What triggers an upgrade BEFORE the MAU threshold

- p95 query latency on **`fn_rpc_latency_summary`** > 50 ms
  for any RPC for 7 consecutive days.
- Connection pool exhaustion event in
  `business-health.last_pool_saturation_at` more than once a
  week.
- `cron_run_state` rows with `status='failed' AND failure_reason='timeout'`
  > 3 / week.
- Any chaos-engineering exercise (L20-09) reveals headroom
  < 2x.

## What triggers a downgrade

We have never done this and don't plan to — the cost delta
between tiers is small enough that down-tiering risks more
than it saves. We DO right-size:

- Idle Edge Functions are auto-paused (Supabase default).
- Old `coin_ledger` partitions are archived to cold storage
  at 6 months (L19-01).

## Re-validation checklist (quarterly)

- [ ] Pull last quarter's `req/MAU/mo` from Vercel Analytics.
      Update the table if drift > 10%.
- [ ] Pull `queries/req` from `fn_rpc_latency_summary`.
      Update if drift > 5%.
- [ ] Run `business-health` peak hour and compare measured
      `concurrent_query_capacity` against the table — flag if
      we're > 70% of limit.
- [ ] Spot-check the breakpoint MAU values against actual
      growth (PostHog DAU/MAU funnel).

## Action plan when a breakpoint is hit

1. SRE files a Linear ticket "Upgrade to <next tier>" with
   the trigger metric attached.
2. Finance approves the cost delta against the
   `COST_OBSERVABILITY` budget; if outside ± 10% of
   forecast, escalate to leadership.
3. Upgrade scheduled for a Tuesday 02:00-03:00 BRT window
   (lowest traffic per `business-health`).
4. Pre-snapshot of all SLOs.
5. Apply the upgrade (Supabase upgrade is online; Vercel
   plan upgrade is online).
6. Watch dashboards for 1 h post-upgrade; compare to
   pre-snapshot.
7. Add a row to `docs/sre/UPGRADES_LOG.md` with the trigger,
   date, and observed impact.

## Why no auto-scaling

We considered Supabase Compute Add-ons (auto-scaling). Not
viable today:

- Supabase doesn't auto-scale tier (only burst CPU on the
  same tier).
- Auto-scaling Postgres in our pattern would mean a
  resharding event (no thanks).
- Vercel auto-scales Edge by default; our breakpoints there
  are paid-tier upgrades, not capacity per se.

So capacity planning is **deliberate, scheduled, and human-
reviewed**. Each upgrade is also a chance to refresh the
constants in this doc.
