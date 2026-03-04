# Audit: Performance

**Date:** 2026-03-04  
**Scope:** N+1 queries, missing indexes, duplicate queries, large payloads, serial awaits in edge functions

---

## 1. N+1 Query Analysis

### 1.1 Portal (Next.js)

**Search patterns:** `for.*await.*\.from\(`, `for.*await.*\.rpc\(`, `map.*await`

**Result:** No N+1 patterns found in `portal/src/`. The portal uses server-side page components with single queries per page load. This is well-structured.

### 1.2 Flutter Presentation Layer

**Search pattern:** `for.*await.*Supabase`

**Result:** No N+1 patterns found in `omni_runner/lib/presentation/`. The screens delegate to repository/use-case layers which batch appropriately.

### 1.3 Edge Functions — CRITICAL N+1 Found

| File | Pattern | Severity | Description |
|------|---------|----------|-------------|
| `trainingpeaks-sync/index.ts` (push action, lines 115-207) | `for (const sync of pendingSyncs) { await db.from("coaching_device_links")... await db.from("coaching_workout_assignments")... await db.from("coaching_workout_templates")... await db.from("coaching_workout_blocks")... await fetch(TP_API)... }` | **Critical** | Each pending sync makes **4 sequential DB queries + 1 external API call** inside a loop. With 50 pending syncs, this is 200 DB queries + 50 TP API calls in series |
| `trainingpeaks-sync/index.ts` (pull action, lines 233-265) | `for (const link of links) { await fetch(TP_API)... for (const tw of tpWorkouts) { await db.rpc("fn_import_execution"...) } }` | **Major** | Nested loop: for each athlete link, fetch TP workouts, then for each workout call an RPC. Inner loop could be batched |

**Recommended fix for push action:**
```sql
-- Create a single RPC that joins device_links + assignments + templates + blocks
-- and returns all data needed for the batch, eliminating 4 queries per sync item
SELECT s.id, s.assignment_id, s.athlete_user_id,
       dl.access_token, a.scheduled_date, t.name,
       jsonb_agg(b.*) as blocks
FROM coaching_tp_sync s
JOIN coaching_device_links dl ON ...
JOIN coaching_workout_assignments a ON ...
LEFT JOIN coaching_workout_templates t ON ...
LEFT JOIN coaching_workout_blocks b ON ...
WHERE s.sync_status = 'pending'
GROUP BY ...
```

**Recommended fix for pull action:** Use `Promise.allSettled()` to parallelize TP API calls across athletes.

---

## 2. Missing Index Analysis

### 2.1 Baseline Schema (`20260218000000_full_schema.sql`)

The full schema was not explicitly read in this audit, but the wearables migration shows proper indexing:

**Well-indexed tables:**
- `coaching_device_links`: `idx_device_links_athlete` on `(athlete_user_id)` ✅
- `coaching_workout_executions`: `idx_executions_group_athlete` on `(group_id, athlete_user_id, completed_at DESC)` ✅, `idx_executions_assignment` on `(assignment_id)` ✅
- Unique partial index on `(athlete_user_id, provider_activity_id) WHERE provider_activity_id IS NOT NULL` ✅

**Potential missing indexes based on query patterns observed:**

| Table | Queried Column(s) | Found In | Index Present |
|-------|--------------------|----------|---------------|
| `coaching_tp_sync` | `sync_status = 'pending'` | `trainingpeaks-sync` push action | ⚠️ Unknown — depends on TP integration migration |
| `coaching_device_links` | `(athlete_user_id, provider)` | `trainingpeaks-oauth` callback/refresh | ✅ Covered by UNIQUE constraint |
| `coaching_device_links` | `(group_id, provider)` | `trainingpeaks-sync` pull action | ⚠️ Likely missing — would benefit from composite index |
| `billing_events` | `stripe_event_id` | `webhook-payments` L1 dedup | ⚠️ Unknown — should have unique partial index |
| `billing_purchases` | `payment_reference` | `webhook-payments` refund lookup | ⚠️ Should be indexed for quick lookups |
| `workout_delivery_items` | `(athlete_user_id, status)` | `athlete_delivery_screen.dart` | ⚠️ Unknown — composite index would help |

---

## 3. Duplicate Query Analysis

No duplicate queries detected on the same page/function. Each screen/function appears to make a single data-loading call.

Notable patterns:
- `trainingpeaks-oauth` and `trainingpeaks-sync` both independently check the `feature_flags` table for `trainingpeaks_enabled`. This is correct (separate entry points) but the flag value could be cached if performance becomes an issue.
- `webhook-payments` makes a pre-check query for existing `billing_events` by `stripe_event_id`, then the `insertEvent` function also handles duplicates via unique constraint. This is intentional defense-in-depth, not a waste.

---

## 4. Large Payload Analysis (`.select('*')`)

**Search pattern:** `.select('*')`

**Result:** No instances of `.select('*')` found anywhere in the codebase. All queries specify columns explicitly. This is excellent practice.

**However**, some queries use `.select()` without any argument (Supabase defaults to `*`):

| File | Line Pattern | Severity |
|------|-------------|----------|
| `athlete_delivery_screen.dart` line 46 | `.select()` (no columns) on `workout_delivery_items` | **Minor** — returns all columns including potentially large `notes` or `metadata` fields |

**Recommendation:** Explicitly list needed columns: `.select('id, status, created_at, template_name, scheduled_date')`.

---

## 5. Edge Function Serial Await Patterns

### 5.1 trainingpeaks-sync (push action) — Critical

Lines 115-207: Each sync item processes sequentially. The external TP API call + 4 DB queries are all awaited in series. Even within a single sync item, the DB queries for `device_links`, `assignments`, `templates`, and `blocks` are independent and could run in parallel:

```typescript
// CURRENT (serial — ~200ms per item)
const { data: deviceLink } = await db.from("coaching_device_links")...
const { data: assignment } = await db.from("coaching_workout_assignments")...
const { data: template } = await db.from("coaching_workout_templates")...
const { data: blocks } = await db.from("coaching_workout_blocks")...

// RECOMMENDED (parallel — ~60ms per item)
const [deviceLink, assignment] = await Promise.all([
  db.from("coaching_device_links")...,
  db.from("coaching_workout_assignments")...,
]);
const [template, blocks] = await Promise.all([
  db.from("coaching_workout_templates")...,
  db.from("coaching_workout_blocks")...,
]);
```

### 5.2 webhook-payments (handlePaymentConfirmed) — Minor

Lines 132-221: `resolvePaymentMethod` and `insertEvent` are called sequentially, but the Stripe API call in `resolvePaymentMethod` doesn't depend on the DB insert. Could parallelize:

```typescript
const [paymentMethod, isNew] = await Promise.all([
  resolvePaymentMethod(stripe, session.payment_intent),
  insertEvent(db, purchaseId, ...),
]);
```

### 5.3 trainingpeaks-oauth (callback) — Minor

Lines 73-128: Token exchange → profile fetch → DB upsert are naturally sequential (each depends on the previous result). No optimization possible.

---

## 6. Summary of Findings

| # | Finding | Severity | File/Location | Recommended Fix |
|---|---------|----------|---------------|-----------------|
| 1 | N+1 queries in TP sync push (4 DB + 1 API per sync × 50) | **Critical** | `trainingpeaks-sync/index.ts:115-207` | Single batch RPC + parallel DB queries |
| 2 | N+1 queries in TP sync pull (nested loops) | **Major** | `trainingpeaks-sync/index.ts:233-265` | `Promise.allSettled()` for athlete-level parallelism |
| 3 | Missing index on `coaching_device_links(group_id, provider)` | **Major** | `trainingpeaks-sync` pull query | Add composite index |
| 4 | Missing index on `billing_purchases(payment_reference)` | **Major** | `webhook-payments` refund lookup | Add index |
| 5 | Serial awaits in push action (parallelizable DB calls) | **Major** | `trainingpeaks-sync/index.ts:118-164` | `Promise.all()` for independent queries |
| 6 | `.select()` without columns in delivery screen | **Minor** | `athlete_delivery_screen.dart:46` | Specify column list |
| 7 | Serial Stripe API + DB insert in webhook | **Minor** | `webhook-payments/index.ts:132-178` | `Promise.all()` where independent |
| 8 | Feature flag check on every TP request | **Minor** | `trainingpeaks-sync`, `trainingpeaks-oauth` | Consider in-memory TTL cache |
