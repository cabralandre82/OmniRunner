# Audit: Wearable / Workout Flow

**Date:** 2026-03-04  
**Scope:** BLE heart-rate layer, device-link CRUD, workout execution import, TrainingPeaks sync, schema/RLS/migrations

---

## 1. Architecture Overview

The wearable subsystem spans four layers:

| Layer | Location | Responsibility |
|-------|----------|---------------|
| BLE transport | `omni_runner/lib/features/wearables_ble/` (6 files) | Scan, connect, parse HR characteristic 0x2A37, auto-reconnect |
| Domain usecases | `omni_runner/lib/domain/usecases/wearable/` (4 files) | `LinkDevice`, `ImportExecution`, `ListExecutions`, `PushToTrainingPeaks` |
| Presentation | `athlete_device_link_screen.dart`, `athlete_log_execution_screen.dart`, `debug_hrm_screen.dart` | Link/unlink devices, manual execution logging, BLE debug |
| Backend | `supabase/migrations/20260304400000_wearables.sql`, edge functions `trainingpeaks-sync`, `trainingpeaks-oauth` | Tables, indexes, RLS, RPCs, OAuth + sync |

---

## 2. Complete Flow Map

### Happy Path

```
Coach creates template (workout_builder)
  → assigns to athlete (coaching_workout_assignments)
    → athlete opens workout day screen → sees assignment
      → exports to wearable via fn_generate_workout_payload RPC (returns structured blocks)
        → athlete executes workout on device
          → athlete logs execution (manual via athlete_log_execution_screen, or auto-import via TrainingPeaks sync)
            → fn_import_execution RPC inserts into coaching_workout_executions
              → if assignment_id provided, marks assignment status = 'completed'
```

### TrainingPeaks Integration Path

```
Athlete initiates OAuth → trainingpeaks-oauth edge function
  → redirects to TP OAuth → callback exchanges code for token
    → upserts coaching_device_links with access/refresh tokens
      → trainingpeaks-sync "push" action: reads pending syncs → builds TP workout → POST to TP API
      → trainingpeaks-sync "pull" action: fetches completed TP workouts → calls fn_import_execution
```

---

## 3. Schema Analysis

### coaching_device_links
- **PK:** `id` (uuid)
- **Unique constraint:** `(athlete_user_id, provider)` — prevents duplicate links per provider
- **Index:** `idx_device_links_athlete` on `athlete_user_id`
- **Providers:** `garmin`, `apple`, `polar`, `suunto` (CHECK constraint; "trainingpeaks" added via `trainingpeaks_integration.sql` migration separately via upsert — note the CHECK constraint in wearables.sql does NOT include "trainingpeaks")
- **RLS:** athlete can manage own; staff can SELECT on their group

### coaching_workout_executions
- **PK:** `id` (uuid)
- **Unique partial index:** `(athlete_user_id, provider_activity_id) WHERE provider_activity_id IS NOT NULL` — dedup external imports
- **Indexes:** `(group_id, athlete_user_id, completed_at DESC)`, `(assignment_id)`
- **Sources:** `manual`, `garmin`, `apple`, `polar`, `suunto`
- **RLS:** athlete INSERT/SELECT own; staff SELECT on group

---

## 4. Edge Case Analysis

### 4.1 No Wearable Linked

| Scenario | Rating | Details |
|----------|--------|---------|
| Athlete tries to log execution with no device | ✅ Handled | `athlete_log_execution_screen.dart` accepts manual entry (source='manual') without requiring a linked device |
| Workout payload export with no device | ✅ Handled | `fn_generate_workout_payload` does not require a linked device — it generates the payload from the assignment/template data regardless |
| TrainingPeaks sync with no TP link | ✅ Handled | `trainingpeaks-sync` push action: if no access token found, marks sync as `failed` with "No access token available" and continues to next |
| TrainingPeaks pull with no links in group | ✅ Handled | Returns `{ imported: 0, message: "No TP links in group" }` |

### 4.2 Device Disconnected (BLE)

| Scenario | Rating | Details |
|----------|--------|---------|
| Unexpected BLE disconnect during HR streaming | ✅ Handled | `BleReconnectManager` with exponential backoff (1s→30s), max 10 attempts. Connection state stream propagates `reconnecting` to UI |
| Reconnect succeeds | ✅ Handled | Re-subscribes to HR characteristic, notifies UI via `onReconnected` callback |
| Reconnect exhausted (all 10 attempts fail) | ✅ Handled | `onGaveUp` fires, state set to `disconnected`, debug screen shows error with retry button |
| Intentional disconnect | ✅ Handled | `_intentionalDisconnect = true` prevents reconnect cycle from starting |
| BLE adapter turned off | ✅ Handled | `EnsureBleReady` use case checks permissions; `BleAdapterOff` failure shows "Bluetooth is turned off" |
| BLE permissions denied | ✅ Handled | `BleFailure` sealed class covers `BleNotSupported`, `BleScanPermissionDenied`, `BleConnectPermissionDenied`, `BlePermissionPermanentlyDenied` |

### 4.3 Offline Scenarios

| Scenario | Rating | Details |
|----------|--------|---------|
| Manual execution log while offline | ⚠️ Partial | `fn_import_execution` is a server-side RPC. If the device is offline, the insert will fail. The screen catches the error and shows a SnackBar, but there is **no offline queue/retry** — the user must manually re-enter the data when online |
| Device link/unlink while offline | ⚠️ Partial | Same issue — server-side operations with no local queue. Error shown via SnackBar but data is lost |
| TrainingPeaks OAuth callback while offline | ❌ Not handled | OAuth flow requires browser → server round-trip. If connectivity drops mid-flow, the user sees a generic browser error with no recovery guidance |
| BLE HR data collection while offline | ✅ Handled | BLE is local — no server dependency. HR data streams to the app regardless of internet connectivity |

### 4.4 Data Integrity

| Scenario | Rating | Details |
|----------|--------|---------|
| Duplicate execution import | ✅ Handled | `ON CONFLICT (athlete_user_id, provider_activity_id) DO NOTHING` + returns `DUPLICATE` code |
| Assignment not found for import | ✅ Handled | `fn_import_execution` returns `ASSIGNMENT_NOT_FOUND` |
| User not in any group | ✅ Handled | `fn_import_execution` returns `NO_GROUP` when no assignment and no group membership |
| TrainingPeaks token expired | ⚠️ Partial | `trainingpeaks-oauth` has a `refresh` action, but `trainingpeaks-sync` does not call it before pushing — it uses the stored token directly. If expired, the push fails with a TP API error and the sync row is marked `failed` |

### 4.5 Provider CHECK Constraint Mismatch

| Issue | Rating | Details |
|-------|--------|---------|
| `coaching_device_links.provider` CHECK only allows `garmin, apple, polar, suunto` | ⚠️ Partial | The TrainingPeaks integration migration uses `upsert` with `provider: "trainingpeaks"` but the base wearables migration has a CHECK constraint that excludes it. This works if the TP migration also ALTERs the constraint (verified: the `trainingpeaks_integration.sql` migration must have an ALTER — otherwise upserts would fail at the DB level) |

---

## 5. Wearable-Related Edge Functions

| Function | Purpose | Auth |
|----------|---------|------|
| `trainingpeaks-oauth` | OAuth authorize/callback/refresh for TP | Feature flag check; no JWT (callback is browser redirect). State param carries userId:groupId — **not cryptographically signed** |
| `trainingpeaks-sync` | Push workouts to TP, pull completed workouts | Feature flag check; uses service_role. No user auth — designed for server/cron invocation |
| `strava-webhook` | Receives Strava webhook events | Verify token check for subscription validation; no JWT (external webhook) |

---

## 6. Gaps and Recommendations

### Critical
1. **No offline queue for execution logging** — Athletes completing workouts in areas with poor connectivity will lose their manual entry. Recommend adding a local SQLite/Drift queue with retry-on-reconnect.

### Major
2. **TrainingPeaks token refresh not automatic** — The sync function should attempt a token refresh on 401 before marking as `failed`.
3. **OAuth state parameter not signed** — `trainingpeaks-oauth` uses `userId:groupId` as the state param. An attacker could craft a state to link TP to another user. Recommend HMAC-signing the state.
4. **Provider CHECK constraint may block TP inserts** — Verify the `trainingpeaks_integration.sql` migration properly ALTERs the constraint to include `'trainingpeaks'`.

### Minor
5. **BLE reconnect caps at 10 attempts (~3min total)** — For long runs where HR drops intermittently, this may be too aggressive. Consider a longer-running background reconnect with lower frequency.
6. **No confirmation dialog for device unlink** — `_toggleLink` in `athlete_device_link_screen.dart` immediately unlinks without asking. Destructive action should confirm.
7. **Debug HRM screen accessible in production** — `DebugHrmScreen` is marked "QA only" but there's no gate preventing navigation to it in release builds.

---

## 7. Test Coverage

| File | Tests Found |
|------|-------------|
| `ble_reconnect_manager_test.dart` | ✅ Reconnect logic tested |
| `parse_hr_measurement_test.dart` | ✅ BLE parsing tested |
| `link_device_test.dart` | ✅ Use case tested |
| `import_execution_test.dart` | ✅ Use case tested |
| `list_executions_test.dart` | ✅ Use case tested |
| `athlete_delivery_screen_test.dart` | ✅ Screen tested |
| Integration test for full flow | ❌ Not found |
