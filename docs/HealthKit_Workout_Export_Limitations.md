# HealthKit / Health Connect — Workout Export Limitations

## Overview

This document covers known limitations, platform quirks, and architectural
decisions for the workout export feature (SPRINT W2.3).

---

## 1. `writeWorkoutData` Does NOT Return a Workout UUID

**Problem:** The `health` Flutter plugin's `writeWorkoutData()` method returns
only `bool` (success/failure). It does **not** return the UUID of the created
`HKWorkout` object.

**Impact:** The `finishWorkoutRoute()` API requires a `workoutUuid` to
associate a GPS route with a workout. Without the UUID, we cannot directly
link them.

**Workaround:** After writing the workout, we query the health store for
`WORKOUT` type data in the same time window and use the UUID of the last
matching result. This is a heuristic — it may fail if:
- The user has another app writing workouts simultaneously.
- The health store takes time to index the new record (race condition).
- HealthKit read permission for workouts was denied (iOS silently returns empty).

**Risk Level:** Low for typical use cases. The workout itself always saves
correctly; only the route attachment may fail.

---

## 2. iOS Read Permission Privacy

**Problem:** Apple HealthKit does not reveal whether the user denied **read**
access for a data type. Calls to `hasPermissions()` for read-only types
return `null` (indeterminate), not `false`.

**Impact:** We cannot definitively check if WORKOUT read permission was
granted before attempting to query the UUID. If denied, the query returns
empty data and the route is not attached.

**Mitigation:** The export still succeeds (workout is saved), only the route
attachment is skipped. The `WorkoutExportResult.message` documents the reason.

---

## 3. Route Batch Size

GPS routes can contain thousands of points. The `insertWorkoutRouteData()`
API processes them in batches of 100 to avoid platform memory pressure. If
a batch fails mid-way, the route builder is discarded to prevent leaks.

---

## 4. Activity Type Hardcoded to RUNNING

Currently, `HealthWorkoutActivityType.RUNNING` is hardcoded. Future
expansion (walking, cycling) requires:
- Adding a workout type selector to the UI.
- Mapping the selected type to `HealthWorkoutActivityType`.
- Updating `IHealthProvider.writeWorkout()` to accept the type.

---

## 5. Heart Rate Data NOT Written to the Workout

Apple HealthKit **automatically correlates** HR data from Apple Watch or
paired BLE monitors with the workout timeline. Manually writing HR samples
to HealthKit would create duplicates.

For BLE-sourced HR (from our app), the samples are persisted in Isar
(`avgBpm`, `maxBpm`) but **not** written to HealthKit. This is intentional:
- Avoids duplicate HR entries when an Apple Watch is also recording.
- Avoids overwriting higher-quality watch data with lower-quality BLE data.

If the user has no Apple Watch and uses only our BLE HR monitor, they will
see HR in Omni Runner but **not** in the Health app. This is a trade-off
that can be revisited with a user setting in the future.

---

## 6. Health Connect (Android) Differences

| Feature | HealthKit (iOS) | Health Connect (Android) |
|---------|----------------|------------------------|
| `writeWorkoutData` return | `bool` | `bool` |
| Route support | `HKWorkoutRoute` via builder API | `ExerciseRoute` (HC 1.1+) |
| Read permission check | Always returns `null` for reads | Returns `true`/`false` |
| Background delivery | Supported | Not supported |
| Minimum version | iOS 15.0 | Android 14 (API 34) or HC APK |

The `health` package abstracts most differences, but the route builder
API behavior may vary between platforms.

---

## 7. Fire-and-Forget Export

The export is triggered as a fire-and-forget operation (`unawaited`) when
the user stops a workout. This means:
- The user is **not** blocked waiting for the export to complete.
- If the export fails, it logs a warning but does not show a UI error.
- There is **no retry mechanism** for failed exports.

**Future improvement:** Add a "pending exports" queue in Isar that retries
on next app launch, similar to the existing sync mechanism.

---

## 8. Calorie Estimation Not Implemented

The `totalCalories` parameter is accepted but currently passed as `null`.
Calorie estimation requires:
- User weight (not yet collected in the app).
- MET values for running at different speeds.
- Integration with a calorie estimation formula.

This is deferred to a future sprint.

---

## 9. Platform Testing Requirements

| Scenario | Where to test |
|----------|--------------|
| Workout appears in Apple Health | Real iOS device |
| Route visible on workout map | Real iOS device (Health app → Workouts → map) |
| Health Connect exercise record | Real Android device with HC installed |
| Permission denied behavior | Real device (deny in Settings) |
| Simultaneous Apple Watch workout | Real iOS device with paired watch |

**Cannot be tested on:** iOS Simulator, Android Emulator (no Health Connect).

---

## Summary Table

| Limitation | Severity | Workaround | Future Fix |
|-----------|----------|------------|------------|
| No workout UUID from plugin | Medium | Query-back heuristic | PR to `health` package |
| iOS read perm indeterminate | Low | Best-effort query | Apple API limitation |
| Hardcoded RUNNING type | Low | None needed yet | Add type selector |
| No HR export to HealthKit | Low | Intentional design | Optional user setting |
| No calorie estimation | Low | `null` calories | Add weight + MET calc |
| No retry on export failure | Medium | Logged warning | Retry queue in Isar |
