# AUDIT_LOCAL_DATA.md — Local Data Usage Audit

**Date:** 2026-03-04  
**Scope:** Flutter app local storage: Isar, SharedPreferences, FlutterSecureStorage  

---

## 1. Isar Database

### 1.1 Database Provider

**File:** `omni_runner/lib/data/datasources/isar_database_provider.dart`

- Single `Isar` instance, singleton pattern
- Initialized once at startup via `open()`
- Uses `path_provider` for app documents directory
- Named database: `omni_runner`

### 1.2 Registered Collections (27 schemas)

| # | Schema | Purpose | Should be local? |
|---|--------|---------|-----------------|
| 1 | `LocationPointRecordSchema` | GPS route points during active run | ✅ Yes — local recording |
| 2 | `WorkoutSessionRecordSchema` | Run session metadata | ✅ Yes — offline-first recording |
| 3 | `ChallengeRecordSchema` | Challenge data | ⚠️ Hybrid — cache of Supabase data |
| 4 | `ChallengeResultRecordSchema` | Challenge results | ⚠️ Hybrid — cache |
| 5 | `WalletRecordSchema` | OmniCoins balance | ⚠️ Hybrid — financial data cached |
| 6 | `LedgerRecordSchema` | Transaction history | ⚠️ Hybrid — financial data cached |
| 7 | `ProfileProgressRecordSchema` | XP, level, streaks | ⚠️ Hybrid — cache |
| 8 | `XpTransactionRecordSchema` | XP transactions | ⚠️ Hybrid — cache |
| 9 | `BadgeAwardRecordSchema` | Badge awards | ⚠️ Hybrid — cache |
| 10 | `MissionProgressRecordSchema` | Mission progress | ⚠️ Hybrid — cache |
| 11 | `SeasonRecordSchema` | Season definitions | ⚠️ Hybrid — cache |
| 12 | `SeasonProgressRecordSchema` | Season progress | ⚠️ Hybrid — cache |
| 13 | **`CoachingGroupRecordSchema`** | Assessoria group data | ⚠️ **Concern** — coaching data cached |
| 14 | **`CoachingMemberRecordSchema`** | Group member list | ⚠️ **Concern** — member data cached |
| 15 | `CoachingInviteRecordSchema` | Invite records | ⚠️ Hybrid — cache |
| 16 | `CoachingRankingRecordSchema` | Rankings | ⚠️ Hybrid — cache |
| 17 | `CoachingRankingEntryRecordSchema` | Ranking entries | ⚠️ Hybrid — cache |
| 18 | `AthleteBaselineRecordSchema` | Anti-cheat baselines | ⚠️ Hybrid — cache |
| 19 | `AthleteTrendRecordSchema` | Performance trends | ⚠️ Hybrid — cache |
| 20 | `CoachInsightRecordSchema` | Coach insights | ⚠️ Hybrid — cache |
| 21 | `FriendshipRecordSchema` | Friend connections | ⚠️ Hybrid — cache |
| 22 | `GroupRecordSchema` | Social groups | ⚠️ Hybrid — cache |
| 23 | `GroupMemberRecordSchema` | Social group members | ⚠️ Hybrid — cache |
| 24 | `GroupGoalRecordSchema` | Group goals | ⚠️ Hybrid — cache |
| 25 | `EventRecordSchema` | Events | ⚠️ Hybrid — cache |
| 26 | `EventParticipationRecordSchema` | Event participations | ⚠️ Hybrid — cache |
| 27 | `LeaderboardSnapshotRecordSchema` / `LeaderboardEntryRecordSchema` | Leaderboards | ⚠️ Hybrid — cache |

### 1.3 Isar Repository Implementations (16 repos)

Found via `isar.` usage across `data/repositories_impl/`:

| Repository | Operations |
|------------|------------|
| `isar_ledger_repo.dart` | Read/write wallet transactions |
| `isar_atomic_ledger_ops.dart` | Atomic ledger operations |
| `isar_xp_transaction_repo.dart` | XP transaction storage |
| `isar_badge_award_repo.dart` | Badge award storage |
| `isar_coaching_member_repo.dart` | Member cache |
| `isar_coaching_invite_repo.dart` | Invite cache |
| `isar_coaching_group_repo.dart` | Group cache |
| `isar_challenge_repo.dart` | Challenge cache |
| `isar_session_repo.dart` | Session storage |
| `isar_profile_progress_repo.dart` | Profile/XP cache |
| `isar_wallet_repo.dart` | Wallet cache |
| `isar_coach_insight_repo.dart` | Coach insights cache |
| `isar_athlete_trend_repo.dart` | Trend data cache |
| `isar_athlete_baseline_repo.dart` | Baseline cache |
| `isar_coaching_ranking_repo.dart` | Ranking cache |
| `isar_mission_progress_repo.dart` | Mission cache |
| `isar_points_repo.dart` | GPS points storage |

---

## 2. SharedPreferences Usage

**Files using SharedPreferences (9 files):**

| File | Keys | Purpose |
|------|------|---------|
| `offline_queue.dart` | `offline_queue` | Queue of tasks to retry when online |
| `deep_link_handler.dart` | Various | Deep link state persistence |
| `first_use_tips.dart` | `tip_*` keys | Track which tips user has dismissed |
| `coach_settings_repo.dart` | Coach preferences | Coach-specific settings |
| `mock_auth_datasource.dart` | Auth mock state | Testing only |
| `theme_notifier.dart` | Theme preference | Dark/light mode |
| `export_screen.dart` | `has_seen_garmin_import_guide` | First-use education flag |
| `ble_heart_rate_source.dart` | `ble_hr_last_device_id`, `ble_hr_last_device_name` | Last known BLE device |
| `i_coach_settings_repo.dart` | Interface definition | N/A |

**Assessment:** SharedPreferences usage is **appropriate** — only small key-value data (preferences, flags, device IDs). No sensitive or large data stored here.

---

## 3. Secure Storage Usage

**Files using FlutterSecureStorage (1 file):**

| File | Purpose |
|------|---------|
| `strava_secure_store.dart` | Strava OAuth tokens (access_token, refresh_token, expires_at, athlete_id, athlete_name) |

**Assessment:** ✅ **Correct** — only Strava OAuth credentials use FlutterSecureStorage. No other sensitive data (passwords, API keys) stored client-side.

---

## 4. Data That Should Come from Backend But Is Stored Locally

### 4.1 Coaching Data (Groups, Members)

**Finding:** Coaching groups and members are cached in Isar (`CoachingGroupRecordSchema`, `CoachingMemberRecordSchema`) AND fetched from Supabase.

**Evidence from `staff_dashboard_screen.dart`:**
```
// Lines 70-143: Queries Supabase directly, then syncs to Isar
final memberRows = await db.from('coaching_members').select(...)
...
await sl<ICoachingGroupRepo>().save(groupEntity);   // write to Isar
await sl<ICoachingMemberRepo>().save(membership);    // write to Isar
```

**Pattern:** Supabase is authoritative; Isar is used as offline cache. The `athlete_dashboard_screen.dart` also follows this:
```
// Lines 128-156: Try Supabase first, fallback to local Isar
try {
  final row = await db.from('coaching_members').select(...)
} catch (e) {
  final memberships = await sl<ICoachingMemberRepo>().getByUserId(uid);
}
```

**Assessment:** ⚠️ The pattern is intentional (offline-first) but creates a **stale data risk**:
- If a member is removed server-side, the local Isar cache still shows them
- There's no TTL or cache invalidation mechanism visible
- Group name changes won't reflect until next successful Supabase fetch

### 4.2 Financial Data (Wallet, Ledger)

**Finding:** Wallet balance and ledger history are cached in Isar (`WalletRecordSchema`, `LedgerRecordSchema`).

**Assessment:** ⚠️ Financial data cached locally could show stale balances. The `WalletBloc` appears to always fetch from Supabase first, but if offline, the user sees the cached (potentially outdated) balance.

### 4.3 Profile Progress

**Finding:** `ProfileProgressRecordSchema` caches XP, level, streaks locally.

**Evidence from `today_screen.dart`:**
```
// Lines 137-176: Supabase first, save to Isar, fallback to Isar
try {
  final row = await db.from('profile_progress').select(...)
  profile = ProfileProgressEntity(...)
  await sl<IProfileProgressRepo>().save(profile);  // cache to Isar
} catch (e) {
  profile = await sl<IProfileProgressRepo>().getByUserId(uid);  // fallback
}
```

**Assessment:** ✅ Acceptable — XP/level data is non-critical and the Supabase-first pattern ensures freshness when online.

---

## 5. Sync Patterns

### 5.1 Sync Service (`sync_repo.dart`)

**Architecture:** Offline-first with queued sync.

**Sync flow for completed workout sessions:**
1. Check connectivity (`_svc.hasConnection()`)
2. Check authentication (`_svc.userId`)
3. Find pending sessions in Isar (`isSynced == false, status == completed`)
4. For each session: Upload GPS points to Supabase Storage → Upsert session metadata to Postgres → Mark synced in Isar
5. Fire-and-forget: trigger server-side verification + auto-upload to Strava

**Failure handling:**
- `SyncNotConfigured` — Supabase not initialized
- `SyncNoConnection` — offline
- `SyncNotAuthenticated` — no user
- `SyncTimeout` — timeout detected
- `SyncServerError` — generic server error
- Returns first failure but continues syncing remaining sessions

### 5.2 Offline Queue (`offline_queue.dart`)

Simple SharedPreferences-based queue:
- `enqueue()` — JSON-encode task and append to string list
- `drain()` — return all tasks and clear queue
- `hasItems` — check if queue is non-empty

**Assessment:** ⚠️ Rudimentary — no retry limits, no exponential backoff, no task deduplication, no ordering guarantees beyond insertion order.

### 5.3 Auto-Sync Manager

**File:** `core/sync/auto_sync_manager.dart` (exists per grep results)

### 5.4 Connectivity Checks

**Files with connectivity handling (7 files):**

| File | Mechanism |
|------|-----------|
| `main.dart` | Connectivity initialization |
| `no_connection_banner.dart` | UI banner widget for offline state |
| `auto_sync_manager.dart` | Auto-sync on connectivity change |
| `challenge_ghost_provider.dart` | Connectivity check before fetch |
| `sync_repo.dart` | `_svc.hasConnection()` check |
| `data/datasources/sync_service.dart` | Connection check implementation |
| `features/watch_bridge/watch_bridge.dart` | Watch connectivity |

**`NoConnectionBanner` widget** is wrapped around the main `HomeScreen` body in both athlete and staff shells — providing a persistent offline indicator.

---

## 6. Risk Assessment

### High Risk
| Issue | Impact | Location |
|-------|--------|----------|
| No Isar cache invalidation/TTL | Stale data shown when back online | All Isar repos |
| Financial data cached without staleness marker | User may see outdated OmniCoins balance | `isar_wallet_repo.dart` |

### Medium Risk
| Issue | Impact | Location |
|-------|--------|----------|
| Coaching member removal not synced to Isar | Removed members may still appear in local cache | `isar_coaching_member_repo.dart` |
| Offline queue has no retry limit | Could accumulate unbounded tasks | `offline_queue.dart` |
| No encryption on Isar database | Local data accessible if device compromised | `isar_database_provider.dart` |

### Low Risk
| Issue | Impact | Location |
|-------|--------|----------|
| 27 Isar schemas = large local footprint | Storage usage on low-end devices | `isar_database_provider.dart` |
| SharedPreferences not cleared on logout | Tip state persists across accounts | `first_use_tips.dart` |

---

## 7. Recommendations

### Critical
1. **Add cache invalidation strategy** — TTL-based or version-based invalidation for Isar caches, especially for coaching data and wallet balances

### High
2. **Mark cached financial data as potentially stale** — show "Last updated: X" indicator when displaying cached wallet data
3. **Add retry limits to offline queue** — prevent unbounded task accumulation; add max retries and error logging

### Medium
4. **Clear Isar on logout** — ensure user data doesn't leak across accounts
5. **Add Isar encryption** for sensitive collections (wallet, coaching member data)
6. **Implement full sync** — periodic reconciliation between Isar cache and Supabase truth (e.g., on app foreground after >1 hour)

### Low
7. **Monitor Isar database size** — add telemetry to track local storage usage
8. **Clear SharedPreferences tip state on logout** — prevent cross-account tip bleed
