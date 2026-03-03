# BLOCO C — Integração Esportivo ↔ Financeiro

## Overview

BLOCO C bridges the **Workout Builder** (BLOCO A) and the **Financial Engine** (BLOCO B) by making `fn_assign_workout` subscription-aware. Before a coach can assign a workout to an athlete, the system now validates the athlete's subscription status and enforces plan-based weekly limits.

Migration: `supabase/migrations/20260304300000_workout_financial_integration.sql`

---

## What changed in `fn_assign_workout`

The original function (BLOCO A, `20260304100000_workout_builder.sql`) only validated:
1. Template exists
2. Caller is staff (`admin_master` or `coach`)
3. Target user is an `athlete` member of the group

BLOCO C adds two new validation stages **after** the membership checks and **before** the INSERT:

### Stage 1 — Subscription status check

Queries `coaching_subscriptions` for the athlete in the group:

| `status` | Result |
|---|---|
| `late` | **Blocked** — returns `SUBSCRIPTION_LATE` |
| `cancelled` | **Blocked** — returns `SUBSCRIPTION_INACTIVE` |
| `paused` | **Blocked** — returns `SUBSCRIPTION_INACTIVE` |
| `active` | Proceeds to Stage 2 (weekly limit check) |
| _(no row)_ | **Allowed** — group may not use the financial module |

### Stage 2 — Weekly limit check (only when `active`)

If the athlete's subscription references a `coaching_plans` row with `max_workouts_per_week IS NOT NULL`:

1. Compute `v_week_start = date_trunc('week', p_scheduled_date)::date`
2. Count existing assignments in `[v_week_start, v_week_start + 7)`
3. If `count >= max_workouts_per_week` → **Blocked** — returns `WEEKLY_LIMIT_REACHED`

---

## Business Rules

| Rule | Description |
|---|---|
| **Late blocks assignment** | An athlete with `subscription.status = 'late'` cannot receive new workout assignments. The coach sees a clear error message and must regularize the subscription first. |
| **Inactive blocks assignment** | `cancelled` or `paused` subscriptions also block assignments. The athlete must have an active subscription or no subscription at all. |
| **Weekly cap enforcement** | Plans can optionally define `max_workouts_per_week`. When set, the system counts assignments in the ISO week of the scheduled date and rejects if the cap is reached. |
| **No subscription = allowed** | Groups that don't use the financial module (no `coaching_subscriptions` rows) are unaffected. Assignments work exactly as before. |
| **Upsert preserved** | The idempotent upsert on `(athlete_user_id, scheduled_date)` is unchanged. Re-assigning the same date replaces the template and increments `version`. |

---

## Error Codes

| Code | HTTP-equivalent | When |
|---|---|---|
| `TEMPLATE_NOT_FOUND` | 404 | Template UUID doesn't exist |
| `NOT_STAFF` | 403 | Caller is not `admin_master`/`coach` in the group |
| `ATHLETE_NOT_MEMBER` | 404 | Target user is not an `athlete` in the group |
| `SUBSCRIPTION_LATE` | 402 | Athlete's subscription status is `late` |
| `SUBSCRIPTION_INACTIVE` | 402 | Athlete's subscription status is `cancelled` or `paused` |
| `WEEKLY_LIMIT_REACHED` | 429 | Plan's `max_workouts_per_week` cap reached for the target week |
| `ASSIGNED` | 200 | Success (insert or upsert) |

---

## Future: FINANCIAL_LATE alert (BLOCO E)

A future BLOCO E migration will extend `compute_coaching_alerts_daily` to emit a `FINANCIAL_LATE` alert when it detects athletes with `coaching_subscriptions.status = 'late'`. This will surface on the Portal risk dashboard alongside existing alert types (`inactive_7d`, `missed_trainings_14d`, etc.).

---

## Rollback

To revert BLOCO C and restore the original `fn_assign_workout` without subscription checks:

```bash
psql $DATABASE_URL -f supabase/migrations/20260304100000_workout_builder.sql
```

This re-applies the BLOCO A migration which contains the original `CREATE OR REPLACE FUNCTION fn_assign_workout` without subscription validation. Since the function signature is identical (`uuid, uuid, date, text`), the replacement is clean — no need to drop first.

Alternatively, manually re-create the function body from BLOCO A's migration section 4.1.

---

## Dependencies

| Depends on | Migration | What it provides |
|---|---|---|
| BLOCO A | `20260304100000_workout_builder.sql` | `coaching_workout_templates`, `coaching_workout_assignments`, original `fn_assign_workout` |
| BLOCO B | `20260304200000_financial_engine.sql` | `coaching_plans` (with `max_workouts_per_week`), `coaching_subscriptions` (with `status`) |
