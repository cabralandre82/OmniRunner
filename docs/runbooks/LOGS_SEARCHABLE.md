# Logs Searchable — Operational Runbook

> **Audit ref:** L20-10
> **Owner:** SRE / Platform
> **Last reviewed:** 2026-04-23

This runbook documents how Omni Runner ships, indexes, and
queries production logs. It exists because Vercel Functions
default retention (3 days) is **insufficient** for compliance and
incident forensics, especially for financial events that often
surface only after 30+ days.

---

## 1. Source of logs

| Producer | Format | Default retention | Volume (est. /day) |
|---|---|---|---|
| Vercel portal (SSR + Edge) | JSON-stdout | 3 days | 5 GB |
| Supabase Edge Functions    | JSON-stdout | 7 days | 1 GB |
| Postgres (slow query log)  | text        | 1 day  | 200 MB |
| Sentry (errors only)       | structured  | 90 days | 100 MB |
| pg_cron job log            | row in audit_logs | indefinite | 10 MB |

The Vercel/Supabase defaults do **not** satisfy:

- **Marco Civil Art. 15** — connection logs 6 months.
- **LGPD Art. 38 §V** — security incidents traceability.
- **BCB Resolução 4658/2018** — financial trail 5 years.
- **Internal SRE** — postmortem evidence beyond 3 days.

---

## 2. Target architecture

```
┌─────────────────┐       ┌──────────────┐
│ Vercel + EF     │──drain──▶│ Axiom Cloud │  ← 30-day hot
└─────────────────┘       └──────┬───────┘
                                 │
                                 ▼
                          ┌──────────────┐
                          │ S3 Glacier   │  ← 1-year cold
                          └──────────────┘

┌─────────────────┐       ┌──────────────┐
│ Sentry          │──webhook──▶│ Axiom (errors)│
└─────────────────┘       └──────────────┘

┌─────────────────┐       ┌──────────────┐
│ Postgres slow   │──pg_cron──▶│ audit_logs  │
└─────────────────┘       └──────────────┘
```

- **Hot tier:** Axiom (or Datadog Logs equivalent). 30 days
  searchable, indexed by `request_id`, `user_id_hash`,
  `route`, `severity`.
- **Cold tier:** S3 Glacier, partitioned by `YYYY/MM/DD/source`.
  Restore SLA = 12h; cost ≈ USD 0.004/GB/month.
- **Financial events:** also written synchronously to
  `audit_logs` (Postgres) by application code; never lost even
  if log drain is down.

---

## 3. Vercel Log Drain configuration

```yaml
# .vercel/log-drains/axiom.yaml (managed via Vercel CLI)
name: omni-runner-prod-axiom
url: https://api.axiom.co/v1/datasets/omni-runner-prod/ingest
projectIds: [omni-runner-portal]
sources: [edge, function, lambda, build, static]
deliveryFormat: json
samplingRate: 1.0
secret: ${VERCEL_LOG_DRAIN_SECRET}
```

Provisioning steps:

1. `vercel teams switch <team>`
2. `vercel logs drains add --file .vercel/log-drains/axiom.yaml`
3. Verify in Axiom dashboard that ingestion rate matches Vercel
   request count.

---

## 4. Required log fields

All structured logs MUST contain (enforced by
`portal/src/lib/logger.ts` + CI guard `audit:logger-shape`):

- `timestamp`         — ISO 8601 with milliseconds.
- `severity`          — debug | info | warn | error | fatal.
- `request_id`        — UUID v4, propagated from gateway.
- `user_id_hash`      — SHA-256 of user_id (never raw).
- `route`             — normalized path (e.g. `/api/coaching/[id]/digest`).
- `duration_ms`       — request latency.
- `status`            — HTTP status.
- `category`          — security | financial | privacy | business.

Logs missing `request_id` are flagged in Axiom by alert
"missing-request-id" and a Slack message is sent to `#sre`.

---

## 5. Search examples

```axiom
# Find all financial errors in last 24h
omni-runner-prod
| where category == "financial" and severity in ["error", "fatal"]
| where _time > ago(24h)
| project _time, request_id, user_id_hash, route, message
| sort by _time desc

# Trace single request_id end-to-end
omni-runner-prod
| where request_id == "00000000-0000-0000-0000-000000000abc"
| sort by _time asc

# 99th percentile latency per route this week
omni-runner-prod
| where _time > ago(7d) and severity in ["info"]
| summarize p99=percentile(duration_ms, 99) by route
| sort by p99 desc
```

---

## 6. Failure modes

### 6.1 Axiom ingestion lag > 60s

- **Detect:** Axiom alert "ingest-lag-high".
- **Fix:** check Vercel log drain status; rotate secret if 401.

### 6.2 Cold storage S3 PUT failing

- **Detect:** Axiom export job failure metric.
- **Fix:** confirm IAM role; ensure bucket lifecycle policy
  not deleting objects before S3 PUT succeeds.

### 6.3 PII leak via log message

- **Detect:** Axiom monitor regex `(\d{11}|\d{3}\.\d{3}\.\d{3}-\d{2})`
  (CPF in plain text).
- **Fix:** redact via PR; rotate the affected log file in S3
  per `docs/runbooks/PII_LEAK_RUNBOOK.md`.

---

## 7. Cost guardrails

- Axiom plan tier "Team" (USD 600/month) covers up to 100 GB/day.
- S3 Glacier ≈ USD 50/month per 1 TB cold.
- Alarm if hot tier ingestion > 200 GB/day (signal of either
  unexpected traffic spike or accidental DEBUG logging in prod).

---

## 8. Cross-references

- `docs/observability/SLO.md` — SLO baseline (L20-02).
- L06-13 — propagated `request_id` from portal (referenced above).
- L04-13 — Sentry/log redaction policy.

---

## 9. Histórico

| Versão | Data | Mudança |
|---|---|---|
| 1.0 | 2026-04-23 | Documento inicial — fecha L20-10. |
