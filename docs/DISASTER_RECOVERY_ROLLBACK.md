# DISASTER RECOVERY & ROLLBACK SIMULATION

> Phase 7 — Principal SRE Analysis  
> Date: 2026-03-04  
> Scope: DB recovery, duplicate prevention, recompute scripts, migration reversibility, feature flag safety

---

## 7.1 DB Recovery — System Resume After Outage

### 7.1.1 Flutter App — Does It Auto-Recover?

**FINDING: PARTIAL AUTO-RECOVERY — No Supabase reconnection logic, but connectivity-based sync exists.**

The Flutter app initializes Supabase once in `main.dart` (lines 98-112):

```dart
await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  anonKey: AppConfig.supabaseAnonKey,
);
```

There is **no reconnection logic** — `supabase_flutter` SDK does not expose a reconnection API. If the DB goes down after initialization, individual requests fail silently with each screen handling errors independently.

**Recovery mechanisms that DO exist:**

1. **`AutoSyncManager`** (`core/sync/auto_sync_manager.dart`, lines 34-48): Listens to `Connectivity.onConnectivityChanged`. When connectivity transitions from `none` to available, calls `_syncRepo.syncPending()`. However, this detects **network** changes, not DB availability. If the network stays up but Supabase is down, this never triggers.

2. **`ConnectivityMonitor`** (`core/offline/connectivity_monitor.dart`, lines 23-26): Separate monitor that replays the `OfflineQueue` when connectivity restores. Same limitation — detects network, not DB.

3. **`OfflineQueue`** (`core/utils/offline_queue.dart`): Simple `SharedPreferences`-based queue that stores failed RPC calls as JSON. Drained on connectivity restore. Tasks are replayed but there's **no retry with backoff** — if the DB is still recovering and replay fails, the tasks are **lost** (drain removes them from the queue before executing).

**RISK: HIGH** — `OfflineQueue.drain()` (line 14-18) removes items before replaying. If replay fails, data is permanently lost.

### 7.1.2 Portal — Does It Auto-Recover?

**FINDING: YES — Next.js RSC auto-recovers on navigation.**

The portal uses Next.js App Router with Server Components. All pages use `export const dynamic = "force-dynamic"` (e.g., `custody/page.tsx` line 10, `clearing/page.tsx` line 8). Each navigation triggers a fresh server-side fetch.

After a DB outage:
- The user sees the error on the current page
- Any navigation to another page re-fetches from Supabase server-side
- If DB is back, the new page renders correctly

**GAP:** There is **no `error.tsx`** or **`global-error.tsx`** boundary in the portal (verified via glob search — 0 files found). If a server component throws, Next.js shows its default error page with no retry button. The user must manually navigate or refresh.

### 7.1.3 Edge Function Crons — Do They Pick Up Where They Left Off?

#### `lifecycle-cron` (`supabase/functions/lifecycle-cron/index.ts`)

**FINDING: YES — Stateless and catches up by design.**

- Queries all championships with `status='open'` AND `start_at <= now` (line 82-86) — any missed transitions are caught on next run
- Queries all challenges with `status='active'` AND `ends_at_ms <= now` (line 141-146) — expired challenges are settled regardless of when they expired
- Queries all pending challenges older than 7 days (line 191-196) — expiration is absolute, not relative to last run
- Has a **time budget** of 45s (`MAX_ELAPSED_MS`, line 24); if exceeded, remaining work is logged and deferred to next run (line 172-177)
- **Limitation:** `limit(50)` on challenges to settle (line 146). If >50 expire during outage, requires multiple runs

#### `auto-topup-cron` (`supabase/functions/auto-topup-cron/index.ts`)

**FINDING: YES — Catches all enabled groups.**

- Fetches ALL groups with `enabled=true` from `billing_auto_topup_settings` (line 76-79)
- Processes in batches of 50 with concurrency cap of 5 (lines 21-22)
- Has 50s time budget; skipped groups are logged (line 118-123)
- **No cursor/bookmark** — starts from scratch each run. After an outage, the next run processes all groups again. Groups skipped due to timeout may need multiple runs.

#### `strava-webhook` (`supabase/functions/strava-webhook/index.ts`)

**FINDING: YES — Queue-based architecture is outage-resilient.**

- Events are enqueued to `strava_event_queue` with `status='pending'` (line 99-108)
- Dedup via unique index on `(owner_id, object_id, aspect_type)` with `onConflict` (line 109)
- If DB is down during enqueue, Strava webhook returns 500 and **Strava retries** (standard webhook behavior)
- Processing is done by a separate queue processor, not this function
- **RISK:** If Strava retries exhaust before DB recovers, events are lost. Strava's retry window is ~24 hours.

#### `clearing-cron` (`supabase/functions/clearing-cron/index.ts`)

**FINDING: PARTIALLY — Race condition handled, but clearing week can be missed.**

- Creates clearing weeks idempotently (line 82-116) with retry on conflict
- Unmatched entries are found by anti-join (lines 122-144), so missed runs accumulate entries that are caught later
- Overdue cases are expired correctly (lines 364-389)
- **RISK:** The netting window is only 1 minute (line 325). If the cron was down, settlements created >1min ago won't be auto-settled.

### 7.1.4 Recovery Summary

| Component | Auto-Recovery | Catch-Up Mechanism | Gap |
|-----------|--------------|-------------------|-----|
| Flutter app | Partial | ConnectivityMonitor + AutoSync | Detects network, not DB; OfflineQueue drain loses items on failure |
| Portal (Next.js) | Yes | RSC refetch on navigation | No error.tsx boundary |
| lifecycle-cron | Yes | Stateless re-query by status/time | limit(50) may need multiple runs |
| auto-topup-cron | Yes | Full re-scan of all enabled groups | Timeout may skip some groups |
| strava-webhook | Yes | Queue + Strava retries | ~24h retry window from Strava |
| clearing-cron | Mostly | Anti-join catches up unmatched entries | 1-min netting window is fragile |

---

## 7.2 Duplicate Action Prevention After Recovery

### 7.2.1 Delivery Confirmation Double-Submit

**`fn_athlete_confirm_item` (referenced in `chaos_fixes.sql`):**

The delivery confirmation flow uses `WorkoutDeliveryService.confirmItem()` which calls an RPC. The Flutter screen (`athlete_delivery_screen.dart`, lines 69-103) guards against double-tap with a local `_confirmingIds` Set:

```dart
if (_confirmingIds.contains(itemId)) return;
setState(() => _confirmingIds.add(itemId));
```

**Server-side protection:** The `fn_athlete_confirm_item` RPC (per `chaos_fixes.sql` line 19-50) uses a conditional `UPDATE ... WHERE status = 'published'`. A second call with the same item where status is already `confirmed` returns no rows updated. **Safe against double-confirm.**

**`fn_mark_item_published`:** Uses the same conditional pattern: `UPDATE ... WHERE status = 'draft'`. Cannot double-publish.

**`fn_fulfill_purchase` (referenced in `webhook-mercadopago/index.ts`, line 275):**

The webhook comments confirm 3-layer idempotency (lines 12-17):
- **L1:** `billing_events` dedup via unique index on `(purchase_id, event_type, mp_payment_id)` in metadata
- **L2:** Conditional `UPDATE ... WHERE status = 'pending'` (line 235-246) — can't re-transition
- **L3:** `fn_fulfill_purchase` checks `status = 'paid'` with `FOR UPDATE` lock — can't double-fulfill

**VERDICT: SAFE** — All three RPCs handle duplicate calls correctly.

### 7.2.2 Payment Webhook Dedup

**`webhook-mercadopago` (`supabase/functions/webhook-mercadopago/index.ts`):**

- `insertEvent()` (lines 29-49) inserts into `billing_events` with unique constraint on `(purchase_id, event_type, metadata->>'mp_payment_id')` — see `chaos_fixes.sql` line 14-16
- If duplicate, returns `false` and the webhook returns `already_processed: true` (line 258-259)
- Payment status transitions use conditional `WHERE status = 'pending'` (line 235-246)

**FINDING: Dedup is based on `(purchase_id, event_type, mp_payment_id)`** — matches the requirement exactly.

**`webhook-payments` (Stripe):**

File `supabase/functions/webhook-payments/index.ts` exists (found in grep). The same `insertEvent()` pattern is used. Stripe sends `event.id` in payload which serves as dedup key.

**VERDICT: SAFE** — Both payment gateways have robust dedup.

---

## 7.3 Recompute Scripts

### 7.3.1 `reconcile-wallets-cron` (`supabase/functions/reconcile-wallets-cron/index.ts`)

**FINDING: IDEMPOTENT — Safe to re-run.**

- Calls `reconcile_all_wallets()` RPC (line 71-73) which compares every wallet's `balance_coins` against `SUM(coin_ledger.delta_coins)`
- Any drift is auto-corrected with an `admin_correction` ledger entry
- Logs an alert if drift is detected (lines 88-98)
- **Idempotent:** Running again after correction finds zero drift — no-op

### 7.3.2 `compute-leaderboard` (`supabase/functions/compute-leaderboard/index.ts`)

**FINDING: SAFE TO RE-RUN — Uses RPC with UPSERT semantics.**

- Calls `compute_leaderboard_global`, `compute_leaderboard_assessoria`, or `compute_leaderboard_championship` RPCs
- These RPCs use `ON CONFLICT DO UPDATE` (confirmed by grep on migrations: `20260221000032_leaderboard_v2.sql`)
- Period key format: `2026-W09` or `2026-03` — deterministic, same re-run produces same key
- `batch_assessoria` mode (line 235) processes all groups with cursor support and 50s deadline

**VERDICT: SAFE** — Fully idempotent via UPSERT.

### 7.3.3 `compute_coaching_kpis_daily`

**FINDING: Referenced in multiple migrations but defined in `full_schema.sql`.**

- Uses UPSERT via `ON CONFLICT (user_id, group_id, day) DO UPDATE`
- Running for the same day overwrites with recalculated values
- **Idempotent by design** — safe to re-run for any day

### 7.3.4 KPI/Leaderboard Computation Patterns

| Function | UPSERT/INSERT | Idempotent | Re-run Safe |
|----------|--------------|------------|-------------|
| `reconcile_all_wallets` | Corrective INSERT + UPDATE | Yes | Yes |
| `compute_leaderboard_*` | ON CONFLICT DO UPDATE | Yes | Yes |
| `compute_coaching_kpis_daily` | ON CONFLICT DO UPDATE | Yes | Yes |
| `recalculate_profile_progress` | UPSERT by user_id | Yes | Yes |
| `evaluate_badges_retroactive` | Conditional INSERT (dedup) | Yes | Yes |

---

## 7.4 Migration Reversibility

### 7.4.1 Do Any Migrations Have DOWN Sections?

**FINDING: NO** — Zero migrations contain `DOWN`, `ROLLBACK`, or reverse logic. All migrations are forward-only.

### 7.4.2 Destructive Migration Analysis

**Last 17 migrations classified:**

| # | Migration | Type | Reversibility |
|---|-----------|------|--------------|
| 1 | `20260221095517_baseline_remote_schema.sql` | Baseline schema | **IRREVERSIBLE** — Creates entire DB |
| 2 | `20260223140000_fix_coaching_members_rls_recursion.sql` | ALTER POLICY | Partially reversible — old policy text needed |
| 3 | `20260223160000_fix_group_members_rls_recursion.sql` | ALTER POLICY | Partially reversible |
| 4 | `20260223170000_fix_fn_create_assessoria_created_at_ms.sql` | CREATE OR REPLACE FUNCTION | Partially — old function body needed |
| 5 | `20260223180000_fix_championship_templates_rls.sql` | ALTER POLICY | Partially reversible |
| 6 | `20260223190000_coaching_join_requests.sql` | CREATE TABLE + RLS | Reversible (DROP TABLE) |
| 7 | `20260223200000_fn_remove_member.sql` | CREATE FUNCTION | Reversible (DROP FUNCTION) |
| 8 | `20260223210000_staff_read_athlete_data.sql` | CREATE POLICY | Reversible (DROP POLICY) |
| 9 | `20260223220000_fix_fn_request_join_email_col.sql` | CREATE OR REPLACE FUNCTION | Partially reversible |
| 10 | `20260224200000_fn_friends_activity_feed.sql` | CREATE FUNCTION | Reversible |
| 11 | `20260226100000_join_request_approval_required.sql` | ALTER TABLE ADD COLUMN | Partially — requires data migration |
| 12 | `20260226110000_platform_approval_assessorias.sql` | ALTER TABLE ADD COLUMN | Partially — same |
| 13 | `20260228120000_feature_flags.sql` | CREATE TABLE + seed data | Reversible (DROP TABLE) |
| 14 | `20260306000000_comprehensive_security_hardening.sql` | ALTER FUNCTION + REVOKE/GRANT | **PARTIALLY REVERSIBLE** — original permissions lost |
| 15 | `20260306100000_session_journal_entries.sql` | CREATE TABLE + RLS | Reversible (DROP TABLE) |
| 16 | `20260306200000_missing_indexes.sql` | CREATE INDEX IF NOT EXISTS | Reversible (DROP INDEX) |
| 17 | `20260307000000_chaos_fixes.sql` | CREATE OR REPLACE FUNCTION + CREATE INDEX | **PARTIALLY REVERSIBLE** — old function bodies not stored |
| 18 | `20260308000000_scale_indexes_and_rls.sql` | CREATE INDEX + RLS optimization | Mostly reversible (DROP INDEX) |

### 7.4.3 Destructive Operations Found

- **No DROP TABLE** in any non-baseline migration
- **No ALTER TYPE** (column type changes)
- **No data DELETEs** in migrations
- Several `CREATE OR REPLACE FUNCTION` which overwrite the previous function body with no record of the old version
- `REVOKE ALL` in security hardening migration (`20260306000000`) removes permissions that may not be trivially reconstructed

### 7.4.4 Rollback Runbook

**FINDING: NO ROLLBACK RUNBOOK EXISTS.**

There is no `docs/ROLLBACK_RUNBOOK.md` or equivalent. The only rollback path is:
1. Restore from Supabase database backup (point-in-time recovery)
2. Manually re-apply migrations up to the desired point

**RECOMMENDATION:** Create a rollback runbook with:
- Point-in-time recovery procedure for Supabase
- Per-migration rollback SQL (at least for the last 5 migrations)
- Function version control (store old function bodies)

---

## 7.5 Feature Flag Safety

### 7.5.1 `trainingpeaks_enabled` Toggle During Recovery

**Source:** `feature_flags.dart` (lines 55-61)

The `FeatureFlagService` is a client-side in-memory cache loaded from the `feature_flags` table on startup. The `isEnabled()` method:

```dart
bool isEnabled(String key) {
  final flag = _flags[key];
  if (flag == null || !flag.enabled) return false;
  if (flag.rolloutPct >= 100) return true;
  if (flag.rolloutPct <= 0) return false;
  return _userBucket(key) < flag.rolloutPct;
}
```

**If `trainingpeaks_enabled` is toggled ON during recovery:**
1. Clients already running won't see it until `refresh()` is called (no periodic polling)
2. The portal checks flags server-side via `isFeatureEnabled("trainingpeaks_enabled")` in `layout.tsx` (line 99) — effective immediately on next navigation
3. TrainingPeaks sync functions (`trainingpeaks-sync`, `trainingpeaks-oauth`) will start accepting requests
4. **RISK:** If TrainingPeaks OAuth tokens are stale from the outage period, the sync will fail gracefully (token refresh logic exists)

### 7.5.2 Other Feature Flags

All flags are stored in the `feature_flags` table (created in migration `20260228120000`):
- Schema: `key TEXT PRIMARY KEY, enabled BOOLEAN, rollout_pct INTEGER`
- No other flags found in the codebase besides `trainingpeaks_enabled`
- The code comment (line 50-54) explicitly warns about stale cache:

> KNOWN RISK (m13): If a flag is toggled mid-operation (e.g. disabling a
> feature while the user is in the middle of an action that depends on it),
> the in-memory cache will be stale until the next [refresh].

### 7.5.3 Can a Flag Toggle Cause Data Inconsistency?

**FINDING: LOW RISK for current flags.**

- `trainingpeaks_enabled` gates UI navigation and sync endpoints — not data-critical
- The comment warns that "destructive operations should re-check the flag server-side (RPC/Edge Function)"
- **Potential issue:** If a flag is toggled OFF while a Strava/TP sync is in progress, the sync continues (it's already running). The flag only gates new requests.
- **No atomic flag+data coupling** — flags are independent of data state

### 7.5.4 Feature Flag Recovery Recommendation

| Scenario | Impact | Mitigation |
|----------|--------|-----------|
| Flag toggled ON during outage | No effect until DB recovers | Safe |
| Flag toggled OFF during active operations | In-flight ops complete normally | Safe |
| Flag toggled ON, then OFF rapidly | Stale client cache may still show feature | Low risk |
| New flag added during outage | Not visible until `load()` succeeds | Safe |

---

## Summary — Critical Recovery Gaps

| ID | Gap | Severity | Affected Area |
|----|-----|----------|---------------|
| R1 | `OfflineQueue.drain()` removes items before replay — failed replays lose data | **CRITICAL** | Flutter app |
| R2 | No Supabase-level reconnection in Flutter (only network-level) | HIGH | Flutter app |
| R3 | No `error.tsx` / `global-error.tsx` in Portal — unhandled RSC errors show default Next.js page | HIGH | Portal |
| R4 | No rollback runbook or down migrations | HIGH | Operations |
| R5 | `CREATE OR REPLACE FUNCTION` overwrites with no version history | MEDIUM | DB migrations |
| R6 | Clearing netting window is only 1 minute — missed settlements after outage | MEDIUM | clearing-cron |
| R7 | `limit(50)` on lifecycle-cron challenge settlement — large backlogs need multiple runs | LOW | lifecycle-cron |
| R8 | Feature flag client cache never auto-refreshes (no periodic timer) | LOW | Flutter app |
