# BLOCO E — Analytics Avançado

Migration: `supabase/migrations/20260304500000_analytics_advanced.sql`

Pre-requisites:
- BLOCO A applied (`coaching_workout_assignments`)
- BLOCO B applied (`coaching_financial_ledger`, `coaching_subscriptions`, `coaching_plans`)
- BLOCO D applied (`coaching_workout_executions`)
- OS-05 applied (`coaching_kpis_daily` with attendance columns, `compute_coaching_kpis_daily`, `compute_coaching_alerts_daily`)

---

## New Columns on `coaching_kpis_daily`

| Column | Type | Default | Description |
|---|---|---|---|
| `adherence_percent_7d` | `numeric(5,2)` | `NULL` | % of workout assignments completed in last 7 days |
| `workout_load_week` | `int` | `0` | Total execution duration (seconds) in last 7 days |
| `performance_trend` | `numeric(5,2)` | `NULL` | Week-over-week pace change (positive = faster) |
| `revenue_month` | `numeric(12,2)` | `NULL` | Sum of revenue ledger entries for current month |
| `active_subscriptions` | `int` | `0` | Count of subscriptions with `status = 'active'` |
| `late_subscriptions` | `int` | `0` | Count of subscriptions with `status = 'late'` |

---

## How Each Metric Is Computed

All metrics are computed inside `compute_coaching_kpis_daily(p_day)` using LEFT JOIN LATERAL blocks, preserving the existing set-based pattern.

### adherence_percent_7d

Queries `coaching_workout_assignments` for the group where `scheduled_date` falls within `[p_day - 6, p_day]`. Computes:

```
completed_7d / total_7d * 100
```

Returns `NULL` if there are no assignments in the window.

### workout_load_week

Queries `coaching_workout_executions` for the group where `completed_at` falls within the 7-day window `[v_7d_start_ts, v_day_start_ts + 1 day)`. Sums `actual_duration_seconds`. Returns `0` when no executions exist.

### performance_trend

Compares average `avg_pace_seconds_per_km` from this week vs. last week using `coaching_workout_executions`:

```
(pace_last_week - pace_this_week) / pace_last_week * 100
```

- **Positive** value = athletes are running faster (improvement).
- **Negative** value = athletes are running slower (regression).
- Returns `NULL` if no last-week data or `pace_last_week = 0`.

### revenue_month

Queries `coaching_financial_ledger` where `type = 'revenue'` and `date` is within the current calendar month `[date_trunc('month', p_day), p_day]`. Returns `0` when no revenue entries exist.

### active_subscriptions / late_subscriptions

Counts rows in `coaching_subscriptions` for the group filtered by `status = 'active'` and `status = 'late'` respectively. Returns `0` when no subscriptions exist.

---

## New Alert: FINANCIAL_LATE

Added to `compute_coaching_alerts_daily(p_day)`.

For each athlete whose `coaching_subscriptions.status = 'late'`, inserts an alert:

| Field | Value |
|---|---|
| `alert_type` | `financial_late` |
| `title` | `{display_name} com assinatura em atraso` |
| `message` | `Atleta está com a assinatura em atraso desde {next_due_date}` |
| `severity` | `warning` |

Uses `ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING` for idempotency.

---

## Rollback

```sql
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS adherence_percent_7d;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS workout_load_week;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS performance_trend;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS revenue_month;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS active_subscriptions;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS late_subscriptions;

-- Re-apply previous compute functions from OS-05:
-- psql $DATABASE_URL -f supabase/migrations/20260303800000_kpi_attendance_integration.sql
```
