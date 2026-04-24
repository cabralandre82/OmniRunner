# Mobile offline analytics queue (L08-12)

> **Status:** spec ratified · **Owner:** Mobile · **Last updated:** 2026-04-21

## Problem

`ProductEventTracker._insert` in
`omni_runner/lib/core/analytics/product_event_tracker.dart`
sends events to Supabase synchronously. When the device is
offline (subway, airplane, weak 3G), every call falls into
the `PostgrestException` branch, logs a warn, and silently
drops the event. Onboarding milestones are the most
sensitive losses — a user who finishes the onboarding
wizard while their phone is between WiFi and cellular **does
not get the `onboarding_completed` event recorded**, which
distorts the funnel.

## Decision

Persist every fire-and-forget event to a local Drift table
`pending_events` and flush in the background when the device
re-acquires connectivity. This is a strict superset of the
current behaviour: events that succeed inline are still
written immediately, and the queue is empty in the steady
state.

## Schema

A new Drift table:

```dart
class PendingEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get eventName => text().withLength(min: 1, max: 64)();
  TextColumn get propertiesJson => text()();
  IntColumn get createdAtMs => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastErrorCode => text().nullable()();
  IntColumn get oneShot => integer().withDefault(const Constant(0))();
  // 0 = multi-shot, 1 = one-shot (e.g. onboarding_completed).
}
```

A unique partial index `(event_name)` covers the
one-shot family so a runaway flush retry doesn't accidentally
double-count an `onboarding_completed`. The index lives in the
mobile-side Drift schema; the server-side dedup partial index
on `product_events` (`idx_product_events_user_event_once`)
remains the canonical source of truth.

## Behaviour

### Online path (unchanged)

`tracker.track(name, props)` → INSERT directly into Supabase.
On success, log debug. On `PostgrestException`, fall through
to the queue path below (we no longer drop).

### Offline path (new)

If `Connectivity().checkConnectivity() == ConnectivityResult.none`
OR the inline INSERT raises `SocketException` /
`PostgrestException` with code `503/network`:

1. Validate locally with `ProductEvents.validate(...)`.
2. INSERT into `pending_events` with `attempts = 0`.
3. Return without throwing.

### Flush worker

A `WorkManager` (Android) / `BGProcessingTask` (iOS) job named
`omni-product-events-flush`:

* Wakes up on `connectivity_changed` events plus a fallback
  every 30 minutes.
* Reads up to 100 oldest rows from `pending_events`.
* For each row:
  * Re-validates locally (defensive — schema may have
    tightened since enqueue).
  * Upserts into Supabase using the same SDK call path as
    the online path; honours the `one_shot` column to choose
    between `insert` and `insert + 23505 swallow`.
  * On success → `DELETE FROM pending_events WHERE id = ?`.
  * On retryable failure → increment `attempts`, set
    `last_error_code`, leave row in queue.
  * On non-retryable failure (validation tightening,
    permanent `403`) → DELETE the row; log a warn.
* Exponential back-off cap: a row that has `attempts >= 10`
  is moved to a separate `pending_events_dead` table and a
  Sentry breadcrumb is emitted. We DO NOT page the user — the
  worst case is a missed funnel event, not data loss with
  user-visible impact.

### Queue size cap

If `pending_events` exceeds **5000 rows** (sustained offline
for days), the tracker switches to **drop-newest** to bound
on-device storage. The cap is intentionally above the daily
expected volume per user (~50 events/day) so a one-week
offline period still fits.

## Cross-platform reuse

The same pattern applies to `notifications_received` (FCM
delivery receipts) and `crashlytics_breadcrumbs`. Once
`pending_events` ships, those two should be migrated to use a
shared `OfflineQueue<T>` Drift abstraction instead of
each owning their own table.

## Test plan

When the implementation lands, the change MUST include:

1. Unit test: enqueue → flush → DELETE happy path.
2. Unit test: enqueue while offline → reconnect simulation
   triggers WorkManager job → INSERT into Supabase.
3. Unit test: 23505 on a one-shot event during flush →
   row is DELETEd, no duplicate, no error log at warn level.
4. Integration test: 100 events enqueued offline, flushed in
   one batch, every row appears in `product_events` exactly
   once.
5. Stress test: queue exceeds 5000 → drop-newest behaviour
   verified.

## Out of scope

* Resending **failed** Supabase auth refresh — handled by
  the Supabase SDK itself with its own retry logic.
* Resending **business-critical** writes (workouts, payments)
  — those have their own offline-first stores in Drift
  (`workouts` already, `payments` deliberately NOT — see
  L05-19 / payments-offline policy).

## Cross-references

* `docs/audit/findings/L08-12-mobile-analytics-nao-enviados-quando-offline.md`
* `docs/analytics/EVENT_CATALOG.md` (L08-09)
* `omni_runner/lib/core/analytics/product_event_tracker.dart`
* `omni_runner/lib/data/datasources/drift_database.dart`
* L05-19 — offline-first sessions policy (related but separate)
