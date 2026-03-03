# TrainingPeaks Integration

## Architecture Overview

The TrainingPeaks integration connects OmniRunner's workout builder (`coaching_workout_templates`, `coaching_workout_blocks`, `coaching_workout_assignments`) to the TrainingPeaks API, enabling coaches to:

1. **Push** structured workouts from OmniRunner to athletes' TrainingPeaks calendars.
2. **Pull** completed workout data back from TrainingPeaks into OmniRunner execution records.

```
┌──────────────────┐          ┌──────────────────┐          ┌──────────────┐
│   OmniRunner     │          │   Supabase Edge   │          │ TrainingPeaks│
│   (App/Portal)   │          │   Functions       │          │   API        │
├──────────────────┤          ├──────────────────┤          ├──────────────┤
│ Coach assigns    │──RPC────▶│ fn_push_to_tp()  │          │              │
│ workout          │          │ creates pending  │          │              │
│                  │          │ sync record      │          │              │
│                  │          ├──────────────────┤          │              │
│                  │          │ trainingpeaks-   │──POST───▶│ /v1/workouts │
│                  │          │ sync (push)      │◀─200─────│              │
│                  │          ├──────────────────┤          │              │
│                  │          │ trainingpeaks-   │──GET────▶│ /v1/workouts │
│                  │◀─────────│ sync (pull)      │◀─────────│ /{from}/{to} │
│ Execution        │          │ fn_import_exec() │          │              │
│ recorded         │          └──────────────────┘          └──────────────┘
└──────────────────┘

OAuth Flow (one-time per athlete):

┌────────┐   1. authorize    ┌──────────────┐   2. redirect   ┌──────────────┐
│ Athlete│──────────────────▶│ tp-oauth     │───────────────▶│ TP OAuth     │
│ (App)  │                   │ Edge Fn      │                │ Consent Page │
│        │◀──────────────────│              │◀───────────────│              │
│        │   5. success HTML │              │  3. callback   │              │
└────────┘                   │              │  with code     └──────────────┘
                             │  4. exchange │
                             │  code→tokens │
                             │  store link  │
                             └──────────────┘
```

---

## Database Schema

### Migration: `20260304800000_trainingpeaks_integration.sql`

#### Updated CHECK Constraints

| Table | Constraint | Added Value |
|---|---|---|
| `coaching_device_links` | `provider_check` | `'trainingpeaks'` |
| `coaching_workout_executions` | `source_check` | `'trainingpeaks'` |

#### New Table: `coaching_tp_sync`

Tracks the sync lifecycle of each workout assignment pushed to TrainingPeaks.

| Column | Type | Description |
|---|---|---|
| `id` | `uuid` PK | Auto-generated |
| `group_id` | `uuid` FK | References `coaching_groups(id)` |
| `assignment_id` | `uuid` FK | References `coaching_workout_assignments(id)` |
| `athlete_user_id` | `uuid` FK | References `auth.users(id)` |
| `tp_workout_id` | `text` | TrainingPeaks workout ID after push |
| `sync_status` | `text` | `pending` → `pushed` → `completed` or `failed` / `cancelled` |
| `pushed_at` | `timestamptz` | When workout was sent to TP |
| `completed_at` | `timestamptz` | When completed data was pulled back |
| `error_message` | `text` | Error detail on failure |
| `created_at` | `timestamptz` | Record creation |
| `updated_at` | `timestamptz` | Last status change |

**Unique constraint:** `(assignment_id, athlete_user_id)` — prevents duplicate syncs.

**Indexes:**
- `idx_tp_sync_group_status` — group dashboard queries
- `idx_tp_sync_athlete` — athlete-scoped queries

#### RLS Policies

| Policy | Operation | Rule |
|---|---|---|
| `athlete_tp_sync_select` | SELECT | `athlete_user_id = auth.uid()` |
| `staff_tp_sync_all` | ALL | Caller is `admin_master` or `coach` in the group |

---

## RPCs

### `fn_push_to_trainingpeaks(p_assignment_id uuid) → jsonb`

Called by a coach/admin to queue a workout for TrainingPeaks sync.

**Flow:**
1. Validates caller is authenticated and has `admin_master` or `coach` role in the assignment's group.
2. Verifies the athlete has a `trainingpeaks` entry in `coaching_device_links`.
3. Creates (or resets) a `coaching_tp_sync` record with `sync_status = 'pending'`.

**Return codes:**
- `SYNC_QUEUED` — success, returns `{ sync_id }`
- `NOT_AUTHENTICATED` — no JWT
- `ASSIGNMENT_NOT_FOUND` — invalid assignment ID
- `FORBIDDEN` — caller is not staff
- `TP_NOT_LINKED` — athlete hasn't connected TrainingPeaks

### `fn_tp_sync_status(p_group_id uuid) → jsonb`

Returns sync status for all assignments in a group.

- **Staff** see all syncs with full detail (athlete_user_id, tp_workout_id, error_message).
- **Athletes** see only their own syncs with limited fields.

---

## Edge Functions

### `trainingpeaks-oauth`

Handles the OAuth 2.0 authorization code flow with TrainingPeaks.

| Action | Method | Description |
|---|---|---|
| `?action=authorize&state={userId}:{groupId}` | GET | Redirects to TP consent page |
| `?action=callback&code=...&state=...` | GET | Exchanges code for tokens, stores device link |
| `?action=refresh` | POST | Refreshes an expired access token |

**Token storage:** Tokens are stored in `coaching_device_links` with `provider = 'trainingpeaks'`. The `state` parameter encodes `userId:groupId` to associate the link correctly.

### `trainingpeaks-sync`

Handles the bidirectional workout sync with TrainingPeaks.

| Action | Method | Description |
|---|---|---|
| `push` | POST | Processes pending `coaching_tp_sync` records (up to 50 per invocation) |
| `pull` | POST | Imports completed workouts from TP for all linked athletes in a group |

---

## Workout Format Mapping

OmniRunner workout blocks are translated to TrainingPeaks structured workout format:

| OmniRunner `block_type` | TrainingPeaks `IntensityClass` |
|---|---|
| `warmup` | `WarmUp` |
| `interval` | `Interval` |
| `recovery` | `Recovery` |
| `cooldown` | `CoolDown` |
| `steady` | `SteadyState` |

**Step length** uses `duration_seconds` (preferred) or `distance_meters` as fallback.

**Targets** are mapped as:
- `target_hr_zone` → `{ Type: "HeartRateZone", Value: N }`
- `rpe_target` → `{ Type: "RPE", Value: N }`
- `target_pace_seconds_per_km` → `{ Type: "Pace", Value: N, Unit: "SecondsPerKilometer" }`

All workouts are pushed as `WorkoutType: "Run"` with `PrimaryIntensityTarget: HeartRate`.

---

## Sync Flow

```
1. Coach creates workout template (coaching_workout_templates + blocks)
2. Coach assigns workout to athlete (coaching_workout_assignments)
3. Coach clicks "Sync to TP" in app/portal
       │
       ▼
4. RPC fn_push_to_trainingpeaks() validates & creates coaching_tp_sync (status: pending)
       │
       ▼
5. Cron or manual trigger invokes trainingpeaks-sync { action: "push" }
       │
       ▼
6. Edge function reads pending syncs, builds TP workout payload,
   POSTs to TP API, updates sync_status → pushed / failed
       │
       ▼
7. Athlete completes workout on TrainingPeaks / watch
       │
       ▼
8. Cron or manual trigger invokes trainingpeaks-sync { action: "pull", group_id }
       │
       ▼
9. Edge function fetches completed workouts from TP (last 7 days),
   calls fn_import_execution() to create coaching_workout_executions
       │
       ▼
10. Sync record updated → completed. Execution visible in app.
```

---

## Error Handling

| Scenario | Handling |
|---|---|
| **Token expired** | `trainingpeaks-oauth?action=refresh` refreshes the access token. The push flow should call refresh before pushing if `expires_at` is past. |
| **TP API error (4xx/5xx)** | Sync record set to `failed` with `error_message` containing status code and truncated body (max 200 chars). Can be retried by resetting to `pending`. |
| **Athlete not linked** | `fn_push_to_trainingpeaks` returns `TP_NOT_LINKED` before creating any sync record. |
| **Duplicate execution import** | The `p_provider_activity_id` parameter (`tp_{Id}`) is passed to `fn_import_execution` for deduplication. |
| **Assignment deleted** | `coaching_tp_sync.assignment_id` has `ON DELETE CASCADE`, so the sync record is cleaned up automatically. |
| **Rate limiting** | Push processes max 50 pending syncs per invocation to stay within TP API rate limits. |

---

## Required Environment Variables

| Variable | Description |
|---|---|
| `TRAININGPEAKS_CLIENT_ID` | OAuth client ID from TrainingPeaks developer portal |
| `TRAININGPEAKS_CLIENT_SECRET` | OAuth client secret |
| `TRAININGPEAKS_REDIRECT_URI` | Callback URL pointing to `trainingpeaks-oauth?action=callback` |
| `SUPABASE_URL` | (already configured) |
| `SUPABASE_SERVICE_ROLE_KEY` | (already configured) |

Set these in Supabase project secrets:

```bash
supabase secrets set TRAININGPEAKS_CLIENT_ID=your_client_id
supabase secrets set TRAININGPEAKS_CLIENT_SECRET=your_client_secret
supabase secrets set TRAININGPEAKS_REDIRECT_URI=https://<project-ref>.supabase.co/functions/v1/trainingpeaks-oauth?action=callback
```

---

## Rollout Plan

1. **Apply migration** — `supabase db push` or `supabase migration up` to create the `coaching_tp_sync` table and update CHECK constraints.
2. **Set secrets** — Configure TP OAuth credentials in Supabase project secrets.
3. **Deploy edge functions** — `supabase functions deploy trainingpeaks-oauth` and `supabase functions deploy trainingpeaks-sync`.
4. **Smoke test OAuth** — Link a test account via `?action=authorize&state=testUserId:testGroupId`, verify the device link row is created.
5. **Smoke test push** — Create a test assignment, call `fn_push_to_trainingpeaks`, trigger `trainingpeaks-sync { action: "push" }`, verify workout appears in TP.
6. **Smoke test pull** — Complete a workout in TP, trigger `trainingpeaks-sync { action: "pull", group_id }`, verify execution record is created.
7. **Set up cron** — Add a pg_cron or external cron job to invoke push/pull periodically (e.g., every 15 minutes).
8. **Enable in app/portal** — Add UI controls for linking TP and syncing workouts behind a feature flag.
9. **Monitor** — Watch edge function logs for `trainingpeaks-oauth` and `trainingpeaks-sync` error rates.
