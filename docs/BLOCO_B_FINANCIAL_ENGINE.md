# BLOCO B — Engine Financeiro

## Overview

Financial engine for coaching groups: plans, subscriptions, ledger, and portal dashboards.

## Database Tables

### `coaching_plans`

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | default gen_random_uuid() |
| group_id | uuid FK → coaching_groups | |
| name | text NOT NULL | |
| description | text | |
| monthly_price | numeric(10,2) NOT NULL | |
| billing_cycle | text NOT NULL | `monthly` or `quarterly` |
| max_workouts_per_week | int | nullable = unlimited |
| status | text NOT NULL | `active` / `inactive` |
| created_at | timestamptz | default now() |

### `coaching_subscriptions`

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | default gen_random_uuid() |
| group_id | uuid FK → coaching_groups | |
| athlete_user_id | uuid FK → auth.users | |
| plan_id | uuid FK → coaching_plans | |
| status | text NOT NULL | `active` / `late` / `paused` / `cancelled` |
| next_due_date | timestamptz | |
| last_payment_at | timestamptz | |
| started_at | timestamptz NOT NULL | |
| cancelled_at | timestamptz | |
| created_at | timestamptz | default now() |

**Unique constraint:** `(group_id, athlete_user_id)` — one subscription per athlete per group.

### `coaching_financial_ledger`

| Column | Type | Notes |
|---|---|---|
| id | uuid PK | default gen_random_uuid() |
| group_id | uuid FK → coaching_groups | |
| type | text NOT NULL | `credit` / `debit` |
| category | text NOT NULL | e.g. `subscription`, `manual`, `refund` |
| amount | numeric(10,2) NOT NULL | |
| description | text | |
| created_at | timestamptz | default now() |

## RLS Policies

All three tables use RLS with the following pattern:

- **SELECT**: staff members (admin_master, coach) of the group can read
- **INSERT/UPDATE**: admin_master and coach roles only
- **DELETE**: admin_master only (plans, ledger) or denied (subscriptions — use status change)

```sql
CREATE POLICY "staff_read_plans"
  ON coaching_plans FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM coaching_members cm
      WHERE cm.group_id = coaching_plans.group_id
        AND cm.user_id = auth.uid()
        AND cm.role IN ('admin_master', 'coach')
    )
  );
```

## RPCs

### `fn_update_subscription_status(p_subscription_id uuid, p_new_status text)`

- SECURITY DEFINER
- Validates new status is in allowed set
- Sets `cancelled_at` when status = `cancelled`
- Updates `next_due_date` based on billing cycle when reactivating

### `fn_create_ledger_entry(p_group_id uuid, p_type text, p_category text, p_amount numeric, p_description text)`

- SECURITY DEFINER
- Validates caller is staff of the group
- Inserts row into `coaching_financial_ledger`

## Portal Pages

| Route | Description |
|---|---|
| `/financial` | KPI dashboard: revenue, active subs, late subs, growth % |
| `/financial/subscriptions` | Table of subscriptions with status filter |
| `/financial/plans` | Table of plans with subscriber counts |
| `/api/export/financial` | CSV export of ledger entries |

## Flutter Layer

| File | Purpose |
|---|---|
| `domain/entities/coaching_plan_entity.dart` | Plan entity (Equatable) |
| `domain/entities/coaching_subscription_entity.dart` | Subscription entity (Equatable) |
| `domain/repositories/i_financial_repo.dart` | Abstract interface |
| `data/repositories_impl/supabase_financial_repo.dart` | Supabase implementation |
| `domain/usecases/financial/list_plans.dart` | List plans use case |
| `domain/usecases/financial/manage_subscription.dart` | CRUD subscriptions |
| `domain/usecases/financial/create_ledger_entry.dart` | Create ledger entry |

Registered in `service_locator.dart` as `IFinancialRepo` → `SupabaseFinancialRepo`.

## Business Rules

1. One active subscription per athlete per group
2. Status transitions: `active` ↔ `paused`, `active` → `late`, `*` → `cancelled`
3. Cancellation sets `cancelled_at` timestamp
4. Ledger is append-only; corrections use debit entries
5. Monthly revenue = SUM of credit entries in current calendar month
6. Growth % = (current month revenue − previous month) / previous month × 100

## Rollback SQL

```sql
DROP FUNCTION IF EXISTS fn_update_subscription_status;
DROP FUNCTION IF EXISTS fn_create_ledger_entry;
DROP TABLE IF EXISTS coaching_financial_ledger;
DROP TABLE IF EXISTS coaching_subscriptions;
DROP TABLE IF EXISTS coaching_plans;
```
