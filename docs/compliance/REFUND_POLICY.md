# Refund & chargeback policy — Omni Runner

> **Finding:** [`L09-07`](../audit/findings/L09-07-politica-de-reembolso-chargeback-sem-prazo-sla.md)
> **Legal references:**
> - CDC Art. 49 — 7-day cooling-off for remote sales.
> - CMN/BCB Circular 3.682/2013 — payment-arrangement accountability.
> **CI guard:** `npm run audit:refund-sla`
> **Owner:** Finance / Platform.
> **Review cadence:** annual, or on change of payment processor.

---

## 1. SLA commitments

| Stage                                               | SLA               |
|-----------------------------------------------------|-------------------|
| Acknowledge refund request (status: `requested`)    | **24h**           |
| Platform review decision (`approved` or `rejected`) | **48 business h** |
| Execute at processor (status: `processed`)          | **48 business h** after `approved` |
| User-visible money-back on card                     | Provider-dependent (Stripe: 5-10 business days) |
| Notify requester of decision                        | Same moment as decision transition |

"48 business hours" approximation used by the SLA trigger:

- **Mon–Thu request**: target = `requested_at + 48h` calendar.
- **Fri/Sat/Sun request**: target = `requested_at + 72h` calendar
  (the extra 24h absorbs the weekend without requiring an explicit
  holiday calendar table — Brazilian national holidays are tracked
  as manual exceptions; see §4).

This heuristic matches the wall-clock experience of a requester who
files on Saturday at 3pm and expects review by Tuesday 3pm.
Precision beyond this (e.g., excluding `feriados nacionais` +
"ponto facultativo") is deferred to follow-up `L09-07-holiday-calendar`.

## 2. CDC Art. 49 commitment

Users purchasing via the portal or mobile app are exercising a
**remote-sale** transaction. Under CDC Art. 49, they have **7 days**
from delivery (i.e., credit activation) to request a full refund
without justification ("direito de arrependimento").

- If a refund request arrives ≤ 7 days after `delivered_at` of the
  related `billing_purchases` row, the platform **must** approve.
- Between 8-30 days, we approve on a case-by-case basis consistent
  with consumer-reasonable-expectation standard.
- After 30 days, refunds require either a defect, a duplicate
  charge, or a contractual reason — not a whim.

The `reason` column on `billing_refund_requests` captures the
category; reporting on the distribution is a follow-up
`L09-07-reason-taxonomy`.

## 3. Chargeback handling

When Stripe or Asaas notifies a chargeback via webhook:

1. We **do not** immediately credit the user — the chargeback is
   already moving funds away from us at the network level.
2. A system-initiated `billing_refund_requests` row is created with
   `status='approved'` and `reason='chargeback: <network-reason>'`.
3. Platform reviews the evidence bundle (receipts, session logs)
   within 48 business hours and chooses either:
   - **Accept** → mark `processed`; update `billing_purchases` to
     `chargeback_accepted`; debit the credits from inventory.
   - **Dispute** → stage the evidence via Stripe Dispute Evidence
     API; keep `processed_at` NULL until the network decides.
4. Until the dispute is resolved, credits already consumed by the
   user **remain** — we do not claw back coaching time already
   delivered. Post-resolution, we reconcile in the custody ledger
   with `reason='chargeback_net'`.

## 4. Holiday calendar (manual exceptions)

National holidays and "ponto facultativo" announced by ABBC cause
the 48h heuristic to under-count. During those weeks:

- Platform team **manually** extends the SLA by the lost day(s).
- Each extension is recorded by setting
  `sla_breach_reason = 'holiday: <name>'` via a platform-only UI
  (follow-up `L09-07-holiday-ui`). Until the UI ships, platform
  can update directly via service-role SQL.

Planned 2026 exceptions are listed here and applied in advance:

- **2026-11-02** Finados — add 24h to any window spanning.
- **2026-11-15** Proclamação da República — add 24h.

## 5. Internal monitoring

Dashboard: `/platform/billing/refunds` (follow-up)
should surface `v_billing_refund_requests_breached` and alert when
the count exceeds 0 for ≥ 6h.

SQL one-liner for on-call:

```sql
SELECT id, status, requested_at, sla_target_at, overdue_by
  FROM public.v_billing_refund_requests_breached;
```

Nightly job:

```sql
SELECT public.fn_billing_refund_sla_mark_breached();
```

…will be scheduled via `pg_cron` in a follow-up migration — it is
deliberately not scheduled in `20260421430000_l09_07_refund_sla.sql`
so that staging / preview envs don't stamp breach timestamps on
seeded test data.

## 6. Decision log

- **2026-04-21** — SLA set at **48 business hours** (heuristic
  described in §1). Chosen over 24h because our refund flow
  includes manual platform review for non-chargeback cases; 24h is
  unrealistic given timezone spread. Chosen over 5 business days
  because CDC Art. 49 users expect same-week resolution. The 48h
  target aligns with Stripe's recommended SLA for merchants under
  R$ 100k monthly volume.

## 7. Cross-links

- [`L09-07 finding`](../audit/findings/L09-07-politica-de-reembolso-chargeback-sem-prazo-sla.md)
- [`Migration`](../../supabase/migrations/20260421430000_l09_07_refund_sla.sql)
- [`Edge Function`](../../supabase/functions/process-refund/index.ts)
  — the executor that transitions `approved` → `processed`.
- [`billing_refund_requests`](../../supabase/migrations/20260221000015_billing_refund_requests.sql)
- [`L09-08 ADR`](../audit/findings/L09-08-provider-fee-usd-2-12-onus-ao-cliente-ou-a-plataforma.md)
  — provider-fee ownership interacts with partial-refund math.
