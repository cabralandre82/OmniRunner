# BLOCO A — Workout Builder

## Overview

The Workout Builder allows coaching staff (admin_master, coach) to create structured workout templates composed of ordered blocks, then assign those templates to athletes on specific dates. Athletes see their assigned workouts in a daily view within the app.

---

## Database Tables

### 1. `coaching_workout_templates`

| Column       | Type         | Notes                                      |
|--------------|--------------|---------------------------------------------|
| id           | uuid PK      | `gen_random_uuid()`                         |
| group_id     | uuid FK       | → `coaching_groups(id)` ON DELETE CASCADE   |
| name         | text NOT NULL | Length between 2 and 120 chars              |
| description  | text          | Optional                                    |
| created_by   | uuid FK       | → `auth.users(id)`                          |
| created_at   | timestamptz   | Default `now()`                             |
| updated_at   | timestamptz   | Default `now()`                             |

### 2. `coaching_workout_blocks`

| Column                    | Type         | Notes                                               |
|---------------------------|--------------|------------------------------------------------------|
| id                        | uuid PK      | `gen_random_uuid()`                                  |
| template_id               | uuid FK       | → `coaching_workout_templates(id)` ON DELETE CASCADE |
| order_index               | int NOT NULL  | Position within the template                         |
| block_type                | text NOT NULL | `warmup`, `interval`, `recovery`, `cooldown`, `steady` |
| duration_seconds          | int           | Optional                                             |
| distance_meters           | int           | Optional                                             |
| target_pace_seconds_per_km| int           | Optional                                             |
| target_hr_zone            | int           | 1–5 or NULL                                          |
| rpe_target                | int           | 1–10 or NULL                                         |
| notes                     | text          | Optional                                             |
| created_at                | timestamptz   | Default `now()`                                      |

### 3. `coaching_workout_assignments`

| Column           | Type         | Notes                                               |
|------------------|--------------|------------------------------------------------------|
| id               | uuid PK      | `gen_random_uuid()`                                  |
| group_id         | uuid FK       | → `coaching_groups(id)` ON DELETE CASCADE           |
| athlete_user_id  | uuid FK       | → `auth.users(id)`                                  |
| template_id      | uuid FK       | → `coaching_workout_templates(id)` ON DELETE CASCADE|
| scheduled_date   | date NOT NULL |                                                      |
| status           | text NOT NULL | `planned`, `completed`, `missed` (default: `planned`)|
| version          | int NOT NULL  | Default 1, incremented on re-assignment              |
| notes            | text          | Optional                                             |
| created_by       | uuid FK       | → `auth.users(id)`                                  |
| created_at       | timestamptz   | Default `now()`                                      |
| updated_at       | timestamptz   | Default `now()`                                      |

**UNIQUE constraint:** `(athlete_user_id, scheduled_date)` — prevents two assignments for the same athlete on the same date.

---

## RLS Policies

| Table                          | Policy                       | Operation  | Who                        |
|--------------------------------|------------------------------|------------|----------------------------|
| coaching_workout_templates     | staff_templates_select       | SELECT     | admin_master, coach        |
| coaching_workout_templates     | staff_templates_insert       | INSERT     | admin_master, coach        |
| coaching_workout_templates     | staff_templates_update       | UPDATE     | admin_master, coach        |
| coaching_workout_templates     | staff_templates_delete       | DELETE     | admin_master, coach        |
| coaching_workout_blocks        | staff_blocks_all             | ALL        | admin_master, coach (via template join) |
| coaching_workout_assignments   | staff_assignments_all        | ALL        | admin_master, coach        |
| coaching_workout_assignments   | athlete_assignments_select   | SELECT     | athlete (own rows only)    |

All policies check membership in `coaching_members` with the appropriate role.

---

## RPCs

### `fn_assign_workout(p_template_id uuid, p_athlete_user_id uuid, p_scheduled_date date, p_notes text)`

**Returns:** `jsonb` with `{ok, code, message/data}`

**Behavior:**
1. Looks up the template's `group_id`
2. Validates caller is staff (admin_master or coach) in that group
3. Validates athlete is a member with role `athlete`
4. Inserts assignment with `ON CONFLICT (athlete_user_id, scheduled_date) DO UPDATE` — increments `version`, updates `template_id` and `notes`

**Return codes:** `TEMPLATE_NOT_FOUND`, `NOT_STAFF`, `ATHLETE_NOT_MEMBER`, `ASSIGNED`

**Security:** `SECURITY DEFINER` with `search_path = public, pg_temp`. Revoked from `PUBLIC` and `anon`, granted to `authenticated` and `service_role`.

---

## App Screens (Flutter)

| Screen                          | File                                              | Description                              |
|---------------------------------|---------------------------------------------------|------------------------------------------|
| Staff Training List             | `staff_training_list_screen.dart`                 | List of workout templates                |
| Staff Training Create (Builder) | `staff_training_create_screen.dart`               | Create/edit template with ordered blocks |
| Staff Training Detail (Assign)  | `staff_training_detail_screen.dart`               | View template details + assign to athletes|
| Athlete Training List (Day View)| `athlete_training_list_screen.dart`               | Athlete's assigned workouts by date      |

---

## Portal Pages (Next.js)

| Page                    | Route                     | Description                                   |
|-------------------------|---------------------------|-----------------------------------------------|
| Templates de Treino     | `/workouts`               | List of workout templates with block counts   |
| Atribuições de Treino   | `/workouts/assignments`   | Assignments list with date filters + pagination|

Both pages are server components fetching from Supabase with try/catch error handling and empty states.

---

## Business Rules

1. **No duplicate assignments:** A UNIQUE constraint on `(athlete_user_id, scheduled_date)` prevents two assignments for the same athlete on the same date.
2. **Staff-only creation:** Only users with role `admin_master` or `coach` in the group can create templates and assign workouts (enforced by RLS and the RPC).
3. **Athlete read-only:** Athletes can only see their own assignments (RLS policy `athlete_assignments_select` checks `athlete_user_id = auth.uid()`).
4. **Ordered blocks:** Blocks within a template are ordered by `order_index`. The index is indexed for efficient retrieval.
5. **Idempotent re-assignment:** The `fn_assign_workout` RPC uses `ON CONFLICT DO UPDATE` — reassigning the same athlete on the same date updates the `template_id`, `notes`, and increments `version`.

---

## Migration

**File:** `supabase/migrations/20260304100000_workout_builder.sql`

Creates all 3 tables, 4 indexes, 7 RLS policies, and 1 RPC in a single transaction.

---

## Tests Needed

- [ ] RPC `fn_assign_workout` — happy path: assign returns `{ok: true, code: "ASSIGNED"}`
- [ ] RPC `fn_assign_workout` — re-assign same date: version increments
- [ ] RPC `fn_assign_workout` — non-staff caller: returns `NOT_STAFF`
- [ ] RPC `fn_assign_workout` — non-member athlete: returns `ATHLETE_NOT_MEMBER`
- [ ] RPC `fn_assign_workout` — invalid template: returns `TEMPLATE_NOT_FOUND`
- [ ] RLS: staff can SELECT/INSERT/UPDATE/DELETE templates in own group
- [ ] RLS: staff cannot access templates from another group
- [ ] RLS: athlete can SELECT own assignments only
- [ ] RLS: athlete cannot SELECT other athletes' assignments
- [ ] RLS: athlete cannot INSERT/UPDATE/DELETE assignments
- [ ] Portal `/workouts` — renders template list with block counts
- [ ] Portal `/workouts/assignments` — renders assignments with filters and pagination
- [ ] App: staff creates template with blocks → saved correctly
- [ ] App: staff assigns workout → athlete sees it in day view
- [ ] App: athlete marks workout completed → status updates

---

## Rollback SQL

```sql
DROP TABLE IF EXISTS public.coaching_workout_assignments CASCADE;
DROP TABLE IF EXISTS public.coaching_workout_blocks CASCADE;
DROP TABLE IF EXISTS public.coaching_workout_templates CASCADE;
DROP FUNCTION IF EXISTS public.fn_assign_workout(uuid, uuid, date, text);
```
