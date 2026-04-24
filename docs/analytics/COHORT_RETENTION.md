# Cohort retention analytics (L08-10)

> **Status:** spec ratified · **Owner:** Data + Product · **Last updated:** 2026-04-21

## What we measure

For each weekly **signup cohort**, we measure the share of the
cohort that came back at D1, D7, D30, D60, D90 and D180.
"Came back" is defined as **at least one `audit_logs` row with
`event_domain ∈ ('app','workout','assessoria','marketplace')`
on that day**. We deliberately exclude `auth` and `billing`
events from the recurrence definition because:

* `auth.session_renewed` would inflate retention with passive
  background refreshes,
* `billing.payment.received` lags by days/weeks and is captured
  in a separate paying-cohort funnel (see § Paying cohort).

## Materialised view contract

The view lives at `analytics.mv_cohort_retention` (OLAP staging
schema introduced in L08-06). Its shape:

| Column                 | Type      | Note                                                          |
|------------------------|-----------|---------------------------------------------------------------|
| `cohort_week`          | `date`    | Monday of the week the user signed up (`auth.users.created_at`).|
| `role`                 | `text`    | `athlete` / `coach` / `admin_master` (segmentation pivot).    |
| `cohort_size`          | `int`     | Number of distinct `user_id` in the cohort.                  |
| `retained_d1`          | `int`     | Distinct returning users on day 1.                            |
| `retained_d7`          | `int`     | Same, day 7.                                                  |
| `retained_d30`         | `int`     | Same, day 30.                                                 |
| `retained_d60`         | `int`     | Same, day 60.                                                 |
| `retained_d90`         | `int`     | Same, day 90.                                                 |
| `retained_d180`        | `int`     | Same, day 180.                                                |
| `pct_d1` … `pct_d180`  | `numeric` | `retained_dN / cohort_size` rounded to 4 decimals.            |

Refresh cadence: **weekly, every Sunday 04:00 UTC**, via the
`refresh_mv_cohort_retention` cron job in
`supabase/migrations/<TBD>_l08_10_cohort_retention.sql`. The
`REFRESH MATERIALIZED VIEW CONCURRENTLY` form is used so the
view stays queryable while the refresh runs.

## Why a materialised view

The naive cohort query is a self-join on `audit_logs` over
millions of rows; running it interactively on every dashboard
load costs > 4 seconds and burns substantial Supabase compute.
A weekly refresh:

* matches the product team's actual review cadence (Mondays),
* lets us write the dashboard query as a single `SELECT` over
  the view (sub-100 ms),
* keeps `audit_logs` partitions cold during the day.

## Access surface

The dashboard reads via a `SECURITY DEFINER` RPC
`fn_cohort_retention(p_role text DEFAULT NULL, p_max_weeks int
DEFAULT 26)` that:

* requires `platform_admins` membership,
* returns the last `p_max_weeks` cohorts,
* optionally filters to one `role`.

We do NOT expose `analytics.mv_cohort_retention` to the
authenticated role directly because the OLAP staging schema is
service-role-only (L08-06).

## Paying cohort (sibling)

A separate view `analytics.mv_paying_cohort_retention` keys the
same metrics off the **first paid event** instead of signup.
Definition of "paid":

```
first_paid_at = min(created_at)
                where event_domain = 'billing'
                  and action = 'payment.captured'
                  and amount_cents > 0
```

Rationale: paying users have meaningfully different retention
curves; mixing them with free users smears the headline number.

## Implementation milestones

The migration is split into four steps, each in its own commit:

1. **20260421860000_l08_10_cohort_retention_v1.sql** — create
   `analytics.mv_cohort_retention` (signup cohorts only,
   D1/D7/D30 only); refresh on demand; CI guard
   `audit:cohort-retention-shape`.
2. **20260421870000_l08_10_cohort_retention_v2.sql** — add
   D60/D90/D180; add the `refresh_mv_cohort_retention` cron job
   (weekly Sunday 04:00 UTC).
3. **20260421880000_l08_10_paying_cohort.sql** — add
   `analytics.mv_paying_cohort_retention`.
4. **20260421890000_l08_10_cohort_rpc.sql** — add the
   `fn_cohort_retention` + `fn_paying_cohort_retention` RPCs.

Step 1 is the one this finding gates. Steps 2-4 land in the
next data-team sprint; until they ship, the dashboard is
"D1/D7/D30 by signup cohort" only.

## Cross-references

* `docs/audit/findings/L08-10-sem-cohort-analysis-estruturada.md`
* L08-06 — OLAP staging schema
* L08-09 — event catalog (the source data)
* `docs/runbooks/CRON_TIMEZONE_POLICY.md` — UTC schedule rules
