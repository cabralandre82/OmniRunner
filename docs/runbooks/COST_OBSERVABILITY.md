# Cost observability runbook (L20-11)

> **Status:** ratified · **Owner:** Finance + Platform · **Cadence:** monthly + on-call · **Last updated:** 2026-04-21

## Why this exists

The platform spends across **seven external vendors** with very
different billing models:

| Vendor      | Bills on…                                | Risk if unwatched                                         |
|-------------|-------------------------------------------|-----------------------------------------------------------|
| Vercel      | function-invocations + bandwidth + build  | viral landing page → 10× bill                             |
| Supabase    | DB compute + storage + egress + functions | runaway query / log retention bloat                       |
| Sentry      | events-per-month                          | regression in `logger.error` floods quota                 |
| Upstash     | Redis commands                            | rate-limit bug → infinite loops                           |
| Firebase    | FCM messages, Crashlytics events          | broken push job retries forever                           |
| Resend      | emails sent                               | broken `flow_abandoned` retry → email storm              |
| Mapbox/Google Maps | tiles + geocoding                  | mobile cache miss → quota burn                            |

These costs do NOT appear in the same dashboard, are billed in
different currencies, and historically have been reviewed only
when the credit card was declined. This runbook codifies the
opposite stance: **costs are a first-class SLO**.

## Definitions

* **Monthly Cost (MC)** — sum of invoiced amounts across all
  vendors, in BRL, for a calendar month.
* **MAU** — distinct `user_id` rows in `audit_logs` with at least
  one event in the month.
* **Cost-per-MAU (CPM)** — `MC / MAU` for the month.
* **MoM CPM growth** — `(CPM_this_month - CPM_last_month) / CPM_last_month`.

## Data plumbing

### Step 1 — invoice ingestion (monthly, on day 5)

The **Finance** squad owns invoice download:

| Vendor    | Source                                          | Format | Owner          |
|-----------|--------------------------------------------------|--------|----------------|
| Vercel    | Billing → Invoices → CSV export                  | CSV    | Finance        |
| Supabase  | Settings → Billing → Invoices PDF + CSV          | CSV+PDF| Finance        |
| Sentry    | Settings → Subscription → CSV export             | CSV    | Finance        |
| Upstash   | Console → Billing → Invoices                     | PDF    | Finance        |
| Firebase  | Google Cloud Billing → Reports → CSV             | CSV    | Finance        |
| Resend    | Dashboard → Billing → Invoices                   | PDF    | Finance        |
| Mapbox    | Account → Billing → CSV                          | CSV    | Finance        |

Files land in `~/finance/cost-observability/<YYYY-MM>/`. The
folder is shared via the company OneDrive — no proprietary
ingest tool is needed at this scale.

### Step 2 — CPM spreadsheet (monthly, on day 6)

A single Google Sheet
**`omni-cost-observability-<YYYY>`** has one tab per month with
columns:

```
vendor | amount_local | currency | exchange_rate | amount_brl | line_items | notes
```

The bottom row has `MC = SUM(amount_brl)` and a sibling row pulls
`MAU` from a saved Supabase query (`SELECT COUNT(DISTINCT user_id)
FROM audit_logs WHERE event_time >= date_trunc('month', NOW())
AND event_time < date_trunc('month', NOW()) + interval '1 month';`).

`CPM = MC / MAU` is the headline number.

### Step 3 — alert (cron, monthly on day 7)

A scheduled task in our internal automations workspace runs on
the 7th of each month and:

1. Reads the current month and previous month tabs.
2. Computes `mom_growth = (CPM_curr - CPM_prev) / CPM_prev`.
3. **If `mom_growth > 0.20`** (>20% MoM growth in cost per MAU)
   sends a Slack alert to `#finance-alerts` and creates a Jira
   ticket assigned to the Platform on-call.
4. Posts the headline numbers to `#exec-weekly`
   regardless of growth.

The 20% threshold is intentionally loose — most months grow
sub-10%; anything 20%+ is either viral growth (good) or a runaway
process (bad), and both deserve a human review.

## Anomaly playbook

When the alert fires, the Platform on-call:

1. **Diff per-vendor amount_brl MoM** in the spreadsheet. The
   vendor with the biggest absolute jump is the suspect.
2. **Pull the line-item breakdown** from that vendor's invoice
   (every CSV / PDF in step 1 is filed by month).
3. **Cross-reference with code changes** — `git log
   --since='1 month ago'` for the relevant subsystem (DB,
   notifications, web).
4. **Triage** — open one of:
   * Rollback ticket if a regression in code caused the spike,
   * Capacity planning ticket if growth is organic,
   * Vendor change ticket if a pricing change is the cause.

### Common patterns

| Symptom                                                  | Most likely cause                                                | Action                                                                   |
|----------------------------------------------------------|-------------------------------------------------------------------|--------------------------------------------------------------------------|
| Sentry events 5×                                         | New `logger.error` call in a hot loop                            | grep recent merges for `logger.error`; rate-limit if intentional         |
| Resend emails 3×                                         | `notification_idempotency` regression (L12-09)                   | check `notifications_sent` table for duplicate keys                      |
| Vercel functions 2×                                      | New cron added without `audit:cron-idempotency` review           | inspect new cron schedules; consolidate                                  |
| Supabase egress 4×                                       | Free-text PII in audit_logs blowing the row size                 | check audit_logs.metadata growth                                         |
| Upstash commands 5×                                      | rate-limit fail-closed leaking into a tight retry loop           | inspect L01-21 telemetry counters                                        |
| Mapbox tiles 10×                                         | Mobile offline cache miss after build                            | confirm `tile_cache_version` bump                                        |

## Escalation

Cost incidents follow the standard SEV mapping:

* **SEV-3** — CPM growth 20-50% MoM. Resolved by Platform on-call
  in the next sprint. No customer impact.
* **SEV-2** — CPM growth 50-100% or absolute monthly cost > 2×
  forecast. Engineering Manager owns the rollback / mitigation
  plan within 48 h.
* **SEV-1** — projected runway impact (e.g. spike that, if
  sustained, would consume >1 month of runway). Founders are paged.

## Future work

The current process is "spreadsheet-driven" and intentionally so
— at our scale (single-digit-thousand MAU), automating ingest
would be more expensive than the savings it surfaces. When MAU
crosses 50k, evaluate:

1. Pull invoices via the vendor APIs (Vercel + Supabase + Sentry
   + Firebase have stable billing APIs).
2. Persist into `analytics.cost_observations` (OLAP staging,
   L08-06) with one row per (vendor, month).
3. Materialise a cost dashboard in the existing Metabase /
   superset instance.
4. Move alerting from Slack to PagerDuty (cost SEVs become real
   pages, not just nudges).

## Cross-references

* L20-12 — capacity planning (sibling: cost informs capacity)
* L06-09 — metrics exporter (today: log-only; future: cost
  metrics emitted as gauges)
* L20-11 — this finding
