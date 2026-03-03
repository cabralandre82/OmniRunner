# BLOCO D — Wearables (Device Links + Workout Executions)

## Overview

BLOCO D adds wearable device integration to the coaching platform. Athletes can link wearable devices (Garmin, Apple Watch, Polar, Suunto), export structured workouts to those devices, and import execution results back — either manually or synced from the wearable provider.

---

## Database Tables

### `coaching_device_links`

Stores the link between an athlete and a wearable provider within a coaching group.

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| group_id | uuid FK | coaching_groups |
| athlete_user_id | uuid FK | auth.users |
| provider | text | CHECK: garmin, apple, polar, suunto |
| access_token | text | Encrypted at app level |
| refresh_token | text | |
| provider_user_id | text | External user ID |
| expires_at | timestamptz | Token expiration |
| linked_at | timestamptz | Default now() |

**Unique:** `(athlete_user_id, provider)`

### `coaching_workout_executions`

Records the outcome of a workout — imported from a wearable or manually entered.

| Column | Type | Notes |
|--------|------|-------|
| id | uuid PK | |
| group_id | uuid FK | coaching_groups |
| assignment_id | uuid FK | coaching_workout_assignments, ON DELETE SET NULL |
| athlete_user_id | uuid FK | auth.users |
| actual_duration_seconds | int | |
| actual_distance_meters | int | |
| avg_pace_seconds_per_km | int | |
| avg_hr | int | |
| max_hr | int | |
| calories | int | |
| source | text | CHECK: manual, garmin, apple, polar, suunto |
| provider_activity_id | text | External ID for dedup |
| completed_at | timestamptz | Default now() |
| created_at | timestamptz | Default now() |

**Partial unique index:** `(athlete_user_id, provider_activity_id) WHERE provider_activity_id IS NOT NULL`

---

## Indexes

| Index | Columns |
|-------|---------|
| idx_device_links_athlete | (athlete_user_id) |
| idx_executions_group_athlete | (group_id, athlete_user_id, completed_at DESC) |
| idx_executions_assignment | (assignment_id) |

---

## RLS Policies

### coaching_device_links

| Policy | Operation | Rule |
|--------|-----------|------|
| athlete_self_all | ALL | athlete_user_id = auth.uid() |
| staff_device_links_select | SELECT | staff membership in group (admin_master, coach, assistant) |

### coaching_workout_executions

| Policy | Operation | Rule |
|--------|-----------|------|
| athlete_insert_self | INSERT | athlete_user_id = auth.uid() |
| athlete_select_self | SELECT | athlete_user_id = auth.uid() |
| staff_executions_select | SELECT | staff membership in group (admin_master, coach, assistant) |

---

## RPCs

### `fn_generate_workout_payload(p_assignment_id uuid) → jsonb`

Builds a structured JSON payload for exporting a workout to a wearable device.

- Validates caller is the assigned athlete OR staff of the group
- Returns template name, scheduled date, and ordered blocks
- SECURITY DEFINER with restricted search_path

### `fn_import_execution(...) → jsonb`

Imports a workout execution result.

- Resolves group_id from assignment or from coaching_members
- Inserts into coaching_workout_executions
- ON CONFLICT on provider_activity_id → DO NOTHING (dedup)
- If assignment_id provided, marks assignment status = 'completed'
- SECURITY DEFINER with restricted search_path

---

## App Screens

### Dispositivos (`AthleteDeviceLinkScreen`)

- Lists all 4 providers with connect/disconnect buttons
- Shows linked date for connected devices
- Loading, empty, and error states with retry

### Registrar Execução (`AthleteLogExecutionScreen`)

- Optional assignment selector (shows label if navigated from assignment)
- Required field: duration (minutes)
- Optional fields: distance (meters), avg pace (sec/km), avg HR (bpm)
- Source dropdown: Manual, Garmin, Apple, Polar, Suunto
- Success snackbar + pop on submit
- Error handling with snackbar

---

## Portal Pages

### Execuções de Treino (`/executions`)

- Table columns: Atleta, Treino, Duração, Distância, Pace, FC, Fonte, Data
- Date range filters (from/to)
- Joins to coaching_workout_assignments → coaching_workout_templates for template name
- Joins to profiles for athlete display name
- Empty state and error handling
- Accessible to: admin_master, coach, assistant

---

## Business Rules

1. **One device per provider per athlete** — enforced by UNIQUE constraint
2. **Dedup on provider imports** — partial unique index on (athlete, provider_activity_id) prevents duplicate imports
3. **Assignment auto-completion** — when an execution is linked to an assignment, the assignment status is updated to 'completed'
4. **Athlete-only write** — athletes can only insert executions for themselves (RLS)
5. **Staff read-only** — staff can see all executions and device links for their group
6. **Token storage** — access/refresh tokens are stored encrypted at the application level; the DB stores ciphertext

---

## Rollback SQL

```sql
-- Drop tables (cascades policies + indexes)
DROP TABLE IF EXISTS public.coaching_workout_executions CASCADE;
DROP TABLE IF EXISTS public.coaching_device_links CASCADE;

-- Drop RPCs
DROP FUNCTION IF EXISTS public.fn_generate_workout_payload(uuid);
DROP FUNCTION IF EXISTS public.fn_import_execution(uuid, int, int, int, int, int, int, text, text);
```
