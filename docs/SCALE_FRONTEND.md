# SCALE_FRONTEND — Frontend Scale Analysis (Flutter + Next.js Portal)

**Target:** 10,000 groups · 800K athletes · 30K staff · ~10K peak concurrent users  
**Date:** 2026-03-04  
**Scope:** `omni_runner/lib/` (Flutter) + `portal/src/` (Next.js)

---

## 1. Flutter App: Query Inventory (Top 30 Heaviest Screens)

Ranked by total Supabase queries fired on mount (initState / _load). "Q" = queries on mount, "A" = queries on user action, "Subs" = real-time subscriptions, "Poll" = polling/periodic refresh.

| # | Screen | File | Q | A | Subs | Poll | Notes |
|---|--------|------|---|---|------|------|-------|
| 1 | **StaffDashboardScreen** | `staff_dashboard_screen.dart` | **8** | 1 | 0 | 0 | Fetches coaching_members (2x), coaching_groups, clearing_cases, coaching_join_requests, wallet, group members sync loop, pending professor check. `select()` on coaching_groups loads ALL columns |
| 2 | **TodayScreen** | `today_screen.dart` | **7** | 2 | 0 | 0 | RPC recalculate_profile_progress + profile_progress + sessions + challenge_participants + challenges + championship_participants + championships. Re-fires on tab visibility change |
| 3 | **StaffPerformanceScreen** | `staff_performance_screen.dart` | **6** | 0 | 0 | 0 | 6 Supabase selects for aggregate metrics across members, sessions, challenges |
| 4 | **AthleteDashboardScreen** | `athlete_dashboard_screen.dart` | **4** | 0 | 0 | 0 | profiles (display_name), coaching_members + coaching_groups, coaching_join_requests, Strava status check |
| 5 | **MatchmakingScreen** | `matchmaking_screen.dart` | **4** | 1 | 0 | 0 | Fetches candidate pool, sessions, profiles, creates RPC call on match action |
| 6 | **LeaderboardsScreen** | `leaderboards_screen.dart` | **4** | 0 | 0 | 0 | Multiple leaderboard tables + profiles |
| 7 | **StreaksLeaderboardScreen** | `streaks_leaderboard_screen.dart` | **4** | 0 | 0 | 0 | profile_progress + profiles + season data |
| 8 | **SupportTicketScreen** | `support_ticket_screen.dart` | **4** | 2 | 0 | 0 | Ticket + messages, `select()` on messages loads all columns |
| 9 | **JoinAssessoriaScreen** | `join_assessoria_screen.dart` | **4** | 2 | 0 | 0 | Groups search, validation, join request |
| 10 | **StaffWeeklyReportScreen** | `staff_weekly_report_screen.dart` | **3** | 0 | 0 | 0 | 3 aggregate queries over sessions, members |
| 11 | **StaffChampionshipInvitesScreen** | `staff_championship_invites_screen.dart` | **3** | 2 | 0 | 0 | Invites + championships + groups |
| 12 | **StaffChallengeInvitesScreen** | `staff_challenge_invites_screen.dart` | **3** | 2 | 0 | 0 | Challenge invites + challenge details + profiles |
| 13 | **FriendProfileScreen** | `friend_profile_screen.dart` | **3** | 1 | 0 | 0 | Profile, sessions, friendship status |
| 14 | **SupportScreen** | `support_screen.dart` | **3** | 1 | 0 | 0 | Tickets list, group info |
| 15 | **StaffRetentionDashboardScreen** | `staff_retention_dashboard_screen.dart` | **2** | 0 | 0 | 0 | Members + session aggregates |
| 16 | **ChallengeDetailsScreen** | `challenge_details_screen.dart` | **2** | 3 | 0 | **timer** | Polls challenge status periodically during active state |
| 17 | **StaffChampionshipManageScreen** | `staff_championship_manage_screen.dart` | **2** | 3 | 0 | 0 | `select()` fetches all columns on championships |
| 18 | **StaffChampionshipTemplatesScreen** | `staff_championship_templates_screen.dart` | **2** | 2 | 0 | 0 | `select()` on championship_templates |
| 19 | **StaffCreditsScreen** | `staff_credits_screen.dart` | **2** | 0 | 0 | 0 | coaching_token_inventory + institution_credit_purchases, `select()` on both |
| 20 | **CoachingGroupDetailsScreen** | `coaching_group_details_screen.dart` | **2** | 2 | 0 | 0 | Group + members list, `select()` on group |
| 21 | **ProfileScreen** | `profile_screen.dart` | **2** | 2 | 0 | 0 | Profile + social columns |
| 22 | **MoreScreen** | `more_screen.dart` | **2** | 0 | 0 | 0 | Membership + group info |
| 23 | **InviteQrScreen** | `invite_qr_screen.dart` | **2** | 0 | 0 | 0 | Group details + invite code |
| 24 | **MyAssessoriaScreen** | `my_assessoria_screen.dart` | **2** | 1 | 0 | 0 | Assessoria details + members |
| 25 | **HistoryScreen** | `history_screen.dart` | **1** | 1 | 0 | 0 | Sessions list |
| 26 | **PersonalEvolutionScreen** | `personal_evolution_screen.dart` | **1** | 0 | 0 | 0 | Profile progress data |
| 27 | **ProgressHubScreen** | `progress_hub_screen.dart` | **1** | 0 | 0 | 0 | Composite progress view |
| 28 | **AthleteVerificationScreen** | `athlete_verification_screen.dart` | **1** | 1 | 0 | 0 | Verification status, `select()` loads all columns |
| 29 | **StaffDisputesScreen** | `staff_disputes_screen.dart` | **1** | 2 | 0 | 0 | Clearing cases list |
| 30 | **WalletScreen** | `wallet_screen.dart` | 0 (via bloc) | 1 | 0 | 0 | Bloc loads wallet + full ledger history |

**Total unique screens with direct Supabase calls:** ~35 (out of 100 screens)  
**Total query volume on cold app start (athlete path):** TodayScreen(7) + AthleteDashboard(4) + HomeScreen(0) = **~11 Supabase RPCs/queries**  
**Total query volume on cold app start (staff path):** StaffDashboard(8) = **~8 Supabase queries** (sequential, not parallelized)

---

## 2. Flutter App: Memory Pressure Points

### 2.1 Unbounded List Loading

| Screen / Repo | Table | Issue | Impact at 800K |
|---------------|-------|-------|-----------------|
| `TodayScreen._load()` | `sessions` (Isar) | `getByStatus(completed)` loads ALL completed sessions into memory, then filters `>= 1km` in Dart | An active athlete with 500+ sessions loads all into RAM before filtering |
| `StaffDashboardScreen._loadStatus()` | `coaching_members` | Loads ALL members of the group into memory to sync to Isar (line 126-143). For a group with 500 athletes, this is 500 rows loaded and individually `await save()` in a sequential loop | 500 sequential Isar writes blocks the UI thread |
| `WalletBloc` | `coin_ledger` (Isar) | Full ledger history loaded on mount. No pagination. Power users may accumulate thousands of entries | OOM risk for athletes with 1000+ ledger entries |
| `ChallengesListScreen` via `ChallengesBloc` | `challenges + participants` | All challenges loaded without pagination | Light risk — most users have < 50 challenges |
| `coaching_group_details_screen.dart` | `coaching_members` | `select()` loads all columns for all members | Groups with 500+ members pull large payloads |

### 2.2 Image Memory

| Widget | Issue |
|--------|-------|
| `CachedAvatar` (`cached_avatar.dart`) | Uses `cached_network_image` with no explicit cache size limit. In CRM list with 200+ athletes, all avatar images stay in memory cache |

### 2.3 Isar Local Storage

| Area | Concern |
|------|---------|
| Session route data | `WorkoutSessionEntity.route` stores full GPS point lists in Isar. A single 10km run can have 1000+ points. Loading all sessions includes route data |
| Ledger records | No TTL-based eviction. Records accumulate indefinitely |
| Sync loop | `StaffDashboard` syncs ALL group members to Isar on every mount. No delta sync |

---

## 3. Flutter App: Duplicate Query Detection

### 3.1 Profile/Membership Fetched Repeatedly

| Data | Fetched In | Duplicate? |
|------|-----------|------------|
| `coaching_members` for current user | `StaffDashboardScreen`, `AthleteDashboardScreen`, `MoreScreen`, `MyAssessoriaScreen`, `CoachingGroupDetailsScreen` | **YES** — same user membership queried 3-5 times per session without shared cache |
| `profiles.display_name` | `AthleteDashboardScreen`, `ProfileScreen`, `TodayScreen` (via profile_progress) | **YES** — display name loaded from different tables by different screens |
| Strava connection status | `TodayScreen`, `AthleteDashboardScreen`, `ChallengesListScreen` | **YES** — each screen independently checks Strava auth |
| `coaching_groups` (full row) | `StaffDashboardScreen`, `CoachingGroupDetailsScreen`, `MoreScreen`, `InviteQrScreen` | **YES** — group details re-fetched on each screen visit |

### 3.2 Missing Shared State

The app uses service locator (`sl<>`) but lacks a per-session cache for frequently-accessed data:
- No `GroupSessionCache` — group metadata re-fetched on every screen
- No `MembershipCache` — membership check re-queried repeatedly
- `CacheTtlConfig` exists (`cache_ttl_config.dart`) with 5-min default TTL but is only used for Isar staleness, not for in-memory dedup

**Estimated wasted queries per typical staff session:** ~8-12 duplicate queries

---

## 4. Portal: Query Inventory (Top 20 Heaviest Pages)

All portal pages are React Server Components (RSC) — queries run server-side. Ranked by query count.

| # | Page | File | Queries | Data Volume | Issues |
|---|------|------|---------|-------------|--------|
| 1 | **Portal Layout** | `(portal)/layout.tsx` | **6** | Low per-query | Runs on EVERY page load: auth.getUser, profiles, coaching_members, coaching_groups, portal_branding, custody_accounts. Not cached between navigations |
| 2 | **CRM Page** | `(portal)/crm/page.tsx` | **7** | Medium-High | coaching_members, profiles, coaching_member_status, coaching_athlete_tags, coaching_training_attendance, coaching_alerts, coaching_athlete_notes (all in parallel). Capped at 100 members via `.range(0, 99)` |
| 3 | **Dashboard** | `(portal)/dashboard/page.tsx` | **6** | High | coaching_token_inventory, coaching_members, billing_purchases, sessions (2-week window), athlete_verification, challenge_participants. Sessions query returns ALL sessions for ALL athletes in the 2-week window |
| 4 | **Engagement** | `(portal)/engagement/page.tsx` | **6** | **Very High** | coaching_members, sessions (2x for different windows), challenge_participants, coaching_kpis_daily, coaching_athlete_kpis_daily. KPIs query has `limit(1000)`. Sessions for 200 athletes × 2 weeks = potentially 5000+ rows |
| 5 | **Custody** | `(portal)/custody/page.tsx` | **6** | **High** | custody_accounts, custody_deposits, custody_withdrawals, **coin_ledger with limit(10000)**, clearing_settlements (2x) |
| 6 | **Athletes** | `(portal)/athletes/page.tsx` | **3** | **Very High** | coaching_members (unbounded), athlete_verification, sessions (ALL completed sessions for ALL athletes — no date filter, no limit) |
| 7 | **Clearing** | `(portal)/clearing/page.tsx` | **4** | Medium | clearing_settlements (2x, limit 100 each), **coaching_groups `select("id, name")` — fetches ALL groups across entire platform**, clearing_events |
| 8 | **Attendance** | `(portal)/attendance/page.tsx` | **4** | Medium | coaching_training_sessions, coaching_training_attendance, coaching_members (count). **Calls getAttendanceData() TWICE** (once filtered, once unfiltered) |
| 9 | **Executions** | `(portal)/executions/page.tsx` | **1** | Medium | coaching_workout_executions with joins. limit(200) |
| 10 | **Financial** | `(portal)/financial/page.tsx` | **3** | Low | coaching_financial_ledger (2x), coaching_subscriptions |
| 11 | **Support (platform)** | `platform/support/page.tsx` | **3** | Medium | support_tickets (limit 200), coaching_groups (batched by ID), support_messages (batched by ticket IDs) |
| 12 | **Workouts** | `(portal)/workouts/page.tsx` | ~2 | Low | Templates + assignments |
| 13 | **Credits** | `(portal)/credits/page.tsx` | ~2 | Low | Token inventory + purchases |
| 14 | **Badges** | `(portal)/badges/page.tsx` | ~2 | Low | Badge definitions |
| 15 | **Swap** | `(portal)/swap/page.tsx` | **3** | Medium | Open orders, group orders, coaching_groups (ALL groups) |
| 16 | **Audit** | `(portal)/audit/page.tsx` | ~3 | Medium | Audit logs + coin_ledger + coaching_groups (ALL) |
| 17 | **FX** | `(portal)/fx/page.tsx` | ~3 | Low | FX orders + settlements |
| 18 | **Settings** | `(portal)/settings/page.tsx` | ~2 | Low | Group settings + branding |
| 19 | **CRM Detail** | `(portal)/crm/[userId]/page.tsx` | ~4 | Low | Single athlete profile + notes + tags |
| 20 | **Risk** | `(portal)/risk/page.tsx` | ~2 | Medium | At-risk athlete KPIs, limit(100) |

---

## 5. Portal: Server Component Data Volume

### 5.1 Critical Data Volume Issues

| Page | Table | Issue | Impact at Scale |
|------|-------|-------|-----------------|
| **Custody** | `coin_ledger` | `limit(10000)` — loads up to 10K rows to sum `delta_coins` client-side | At 800K athletes, active groups could have 50K+ ledger rows. Should use `SUM()` aggregate via RPC |
| **Athletes** | `sessions` | **No limit, no date filter** — `.in("user_id", userIds).gte("status", 3)` loads every completed session for every athlete in the group | A group with 200 athletes × 100 sessions each = 20,000 rows loaded into Node.js memory. At 500 athletes, this becomes 50K+ rows |
| **Dashboard** | `sessions` | 2-week window, but loads all columns for all athletes' sessions into memory for client-side aggregation | Same pattern: groups with 200+ athletes generate 2000+ session rows |
| **Engagement** | `coaching_athlete_kpis_daily` | `limit(1000)` — 30 days × athletes. For a 100-athlete group: 3000 rows needed, only 1000 returned | **Silent data truncation** — engagement scores will be incorrect for groups with >33 athletes |
| **Clearing** | `coaching_groups` | `select("id, name")` with NO filter — loads ALL 10,000 groups to build name lookup map | Should filter to only referenced groups |
| **Swap / Audit** | `coaching_groups` | Same issue: `select("id, name")` fetches all groups for name resolution | N+1 alternative: should batch-fetch by referenced IDs |
| **Attendance** | `getAttendanceData()` | Called **twice**: once with session_id filter, once without. Doubles the query count unnecessarily | Could cache the first call and filter in-memory |

### 5.2 Missing Pagination

| Page | Issue |
|------|-------|
| Athletes | All athletes rendered in a single `<table>` with no virtual scrolling or pagination |
| CRM | Capped at 100 athletes via `.range(0, 99)`, but no "Load More" UI. Groups with 500 athletes silently lose 400 |
| Engagement | Inactive athletes list rendered entirely — could be 200+ items |

---

## 6. Real-time vs Polling Analysis

### 6.1 Current State: No Real-time Subscriptions

**Flutter:** Zero `.stream()` or `.on().subscribe()` calls found in presentation or data layers. All data freshness is achieved through:
- Manual pull-to-refresh (`RefreshIndicator`)
- Re-fetch on screen re-entry (`didUpdateWidget` with visibility flag)
- Bloc re-load on navigation return (`.then((_) => _loadStatus())`)

**Portal:** Zero real-time channels. All pages are SSR with `force-dynamic`. Data is fresh on page load but stale during the session.

### 6.2 Polling Patterns Found

| Location | Pattern | Interval |
|----------|---------|----------|
| `ChallengeDetailsScreen` | Timer-based polling for challenge status updates during active challenges | Not specified (likely every 10-30s) |
| `coach_settings_repo.dart` | `Timer.periodic` for settings sync | Configured interval |
| `feature_flags.dart` | Periodic flag refresh | Application-configured |
| `matchmaking_screen.dart` | Polls matchmaking queue status | During active matchmaking |

### 6.3 Scale Impact

At 10K concurrent users, the absence of real-time means:
- **Challenge state:** ~500 active challenges with 2 participants each polling every 15s = **~67 queries/second** just for challenge status
- **Staff dashboards:** 30K staff × occasional refresh = burst query patterns when staff check in morning
- **No fan-out benefit:** Every client independently polls the same data; Supabase Realtime could broadcast to all subscribers from a single DB trigger

### 6.4 Recommendations

| Area | Current | Recommendation |
|------|---------|----------------|
| Active challenges | Polling | Supabase Realtime channel per challenge (max ~500 concurrent) |
| Wallet balance | Pull-to-refresh | Realtime subscription for ledger changes |
| Staff join requests | Manual refresh | Realtime notification (low volume, high value) |
| Portal dashboard | Page reload | Not needed — SSR is acceptable for staff tool |

---

## 7. CDN/Caching Opportunities

### 7.1 Portal (Next.js)

| Resource | Current | Opportunity |
|----------|---------|-------------|
| Layout queries (6 queries) | `force-dynamic` on every page | Cache group metadata + branding for 5 minutes via `unstable_cache` or ISR |
| `coaching_groups` name lookup | Fetched from DB on every clearing/swap/audit page | Cache group names globally for 15 minutes. Only ~10K rows, changes rarely |
| Static assets (badges, avatars) | Served from Supabase Storage | Add CDN layer (Cloudflare/Vercel Edge) with `Cache-Control: public, max-age=3600` |
| Leaderboard data | Real-time computation | Pre-compute daily leaderboard snapshots via cron, serve cached JSON |

### 7.2 Flutter App

| Resource | Current | Opportunity |
|----------|---------|-------------|
| Avatar images | `cached_network_image` default | Good. Add max cache size (100MB) to prevent unbounded growth |
| Group metadata | Re-fetched per screen | Implement in-memory LRU cache with 15-min TTL (matches `CacheTtlConfig.coachingTtlMs`) |
| Profile progress | Fetched from Supabase then saved to Isar | Good offline pattern. Add Isar-first read with background refresh |
| Season/badge definitions | Static data | Cache aggressively in Isar, refresh only on app cold start |
| Park polygons | Hardcoded seed (`parks_seed.dart`) | Good — no network call needed |

---

## 8. Client-side Connection Limits

### 8.1 Supabase Connection Budget

| Client Type | Concurrent Connections | Connection Pooler Mode |
|-------------|----------------------|----------------------|
| Flutter (PostgREST via supabase-flutter) | HTTP-based, no persistent connection | Transaction mode (PgBouncer) |
| Portal RSC (server-side) | One connection per request | Transaction mode |
| Portal service client (admin) | Elevated privileges, same pool | Transaction mode |
| Realtime (if adopted) | 1 WebSocket per client | Separate Realtime service |

**At 10K concurrent users:**
- PostgREST layer handles HTTP; PgBouncer limits actual DB connections
- Default Supabase Pro plan: 60 direct connections + pooler
- 10K concurrent × 11 queries on app open = **burst of ~110K queries** if all open simultaneously
- Sustained: ~2K average online × 1 query/30s (polling) = **~67 queries/second steady state**

### 8.2 Connection Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Morning burst (staff opening dashboards) | **HIGH** | Stagger load with jitter delay (0-5s random on mount) |
| StaffDashboard: 8 sequential queries | **MEDIUM** | Parallelize with `Future.wait()` — currently sequential |
| TodayScreen: 7 queries on every tab switch | **MEDIUM** | Add debounce or TTL guard — skip if last load < 60s ago |
| Portal Layout: 6 queries on every navigation | **HIGH** | Cache layout data in cookies or server-side cache |

### 8.3 PostgREST Request Size

| Concern | Detail |
|---------|--------|
| `select()` without column list | 7 instances in Flutter screens load ALL columns. At scale, this wastes bandwidth — especially on mobile networks |
| `in("user_id", athleteIds)` with 500 IDs | URL length approaches limits. Supabase may need POST-based filtering for large ID lists |
| Sessions without route data | `TodayDataService.getRemoteSessions` correctly selects specific columns. But Isar `getByStatus()` loads full entities including route GPS data |

---

## 9. Recommendations (Prioritized)

### P0 — Critical (Fix Before Scale)

| # | Issue | Location | Fix | Effort |
|---|-------|----------|-----|--------|
| 1 | **Athletes page loads ALL sessions for ALL athletes unbounded** | `portal/.../athletes/page.tsx` line 70-73 | Add `.limit()` and date filter, or use aggregate RPC: `SELECT user_id, COUNT(*), SUM(total_distance_m) FROM sessions GROUP BY user_id` | 2h |
| 2 | **coin_ledger limit(10000) for aggregation** | `portal/.../custody/page.tsx` line 23 | Replace with `db.rpc('sum_coin_ledger_by_group', ...)` or use Postgres `SUM(delta_coins)` via PostgREST computed column | 2h |
| 3 | **coaching_groups fetched without filter (ALL 10K groups)** | `clearing/page.tsx` line 41, `swap/page.tsx` line 20, `audit/page.tsx` | Filter by referenced group IDs: collect creditor/debtor IDs first, then `.in("id", referencedIds)` | 3h |
| 4 | **coaching_athlete_kpis_daily limit(1000) silently truncates** | `engagement/page.tsx` line 85 | Increase limit to `athletes × 30` or paginate, or pre-aggregate in a materialized view | 3h |
| 5 | **StaffDashboard syncs ALL members sequentially** | `staff_dashboard_screen.dart` lines 126-143 | Batch Isar writes: `isar.writeTxn(() async { for (m in members) save(m); })`. Or skip sync if last sync < 5min | 2h |
| 6 | **Portal Layout runs 6 queries on every navigation** | `(portal)/layout.tsx` | Move group metadata + branding + custody status into a server-side cache with 5-min TTL. Layout data barely changes | 4h |

### P1 — High Priority (Before 100K Athletes)

| # | Issue | Location | Fix | Effort |
|---|-------|----------|-----|--------|
| 7 | **StaffDashboard: 8 sequential queries** | `staff_dashboard_screen.dart` | Parallelize with `Future.wait()`. Currently each `await` blocks the next | 1h |
| 8 | **TodayScreen re-fires 7 queries on every tab switch** | `today_screen.dart` line 120-123 | Add TTL guard: `if (DateTime.now().difference(_lastLoad) < Duration(minutes: 1)) return;` | 30min |
| 9 | **`select()` without columns (7 screens)** | See §2.1 above | Specify columns: `select('id, name, ...')` to reduce payload | 2h |
| 10 | **CRM page capped at 100 athletes silently** | `portal/.../crm/page.tsx` line 41 | Add pagination with offset/limit controls, or cursor-based pagination | 4h |
| 11 | **Duplicate membership queries across screens** | Multiple Flutter screens | Create `MembershipSessionCache` — a singleton that caches the current user's membership for the session | 3h |
| 12 | **Attendance page calls getAttendanceData() twice** | `attendance/page.tsx` lines 91-103 | Call once, derive filtered/unfiltered views from the same result | 30min |
| 13 | **Dashboard sessions query loads all rows into Node.js** | `dashboard/page.tsx` line 83-89 | Use aggregate RPC: `SELECT COUNT(*), SUM(total_distance_m) FROM sessions WHERE user_id = ANY($1) AND start_time_ms >= $2` | 2h |

### P2 — Medium Priority (Before 500K Athletes)

| # | Issue | Location | Fix | Effort |
|---|-------|----------|-----|--------|
| 14 | **No real-time for active challenges** | `ChallengeDetailsScreen` | Subscribe to `challenges:id=eq.{id}` Realtime channel instead of polling | 4h |
| 15 | **Isar session entities include GPS route data** | `ISessionRepo.getByStatus()` | Add `getByStatusLightweight()` that excludes route field. TodayScreen doesn't need routes for the recap card | 2h |
| 16 | **WalletBloc loads full ledger without pagination** | `WalletBloc` + `isar_wallet_repo.dart` | Add `limit(50)` + "Load More" pattern | 2h |
| 17 | **CachedAvatar has no cache size limit** | `cached_avatar.dart` | Set `maxNrOfCacheObjects: 500` on CacheManager | 30min |
| 18 | **Morning burst risk from 30K staff** | All staff screens | Add random jitter (0-3s) before first query batch on mount | 1h |
| 19 | **Portal athletes page: no virtual scrolling** | `athletes/page.tsx` | For 500+ rows, implement server-side pagination with `?page=` param | 3h |
| 20 | **Portal engagement: inactive list could be 200+ items** | `engagement/page.tsx` | Limit to top 20, add "Show All" link | 30min |

### P3 — Nice-to-Have (Optimization)

| # | Issue | Fix | Effort |
|---|-------|-----|--------|
| 21 | Global group name cache for Portal | Redis/Vercel KV cache for `coaching_groups(id, name)` with 15-min TTL | 4h |
| 22 | SSR caching for Portal dashboard aggregates | `unstable_cache()` with 2-min revalidation | 2h |
| 23 | In-memory Strava connection cache in Flutter | Cache `isConnected` result for 5 minutes — checked by 3 screens | 30min |
| 24 | Batch Isar reads instead of per-entity | Use Isar `filter().findAll()` instead of individual `getById()` calls | 2h |
| 25 | Add request coalescing for concurrent identical queries | If two screens request coaching_members simultaneously, share the flight | 4h |

---

## Appendix A: `select()` Without Column Specification (All Columns Loaded)

These Supabase calls use `.select()` with no arguments, loading every column from the table:

| File | Table | Line |
|------|-------|------|
| `staff_dashboard_screen.dart` | `coaching_groups` | 90 |
| `staff_championship_manage_screen.dart` | `championships` | 63 |
| `staff_championship_templates_screen.dart` | `championship_templates` | 71 |
| `staff_credits_screen.dart` | `coaching_token_inventory` | 51 |
| `staff_credits_screen.dart` | `institution_credit_purchases` | 63 |
| `athlete_verification_screen.dart` | `athlete_verification` | 85 |
| `support_ticket_screen.dart` | `support_messages` | 56 |
| `coaching_group_details_screen.dart` | `coaching_groups` | 50 |

**Fix:** Add explicit column lists. Example:
```dart
// Before
.select()
// After
.select('id, name, logo_url, coach_user_id, invite_code, invite_enabled')
```

---

## Appendix B: Portal Supabase Client Architecture

| Client | File | Auth Level | Used For |
|--------|------|-----------|----------|
| `createClient()` | `lib/supabase/server.ts` | User session (anon key + cookies) | RLS-enforced queries in portal pages |
| `createServiceClient()` | `lib/supabase/service.ts` | Service role key (bypasses RLS) | Cross-group queries (dashboard aggregates, admin views) |
| `createAdminClient()` | `lib/supabase/admin.ts` | Service role key | Platform-level pages (support, assessorias management) |

**Scale concern:** `createServiceClient()` bypasses RLS. Any query using it that lacks a `WHERE group_id = ?` filter will scan the entire table. This is the root cause of the "ALL coaching_groups loaded" issue in clearing/swap/audit pages.

---

## Appendix C: Query Timing Estimates at 800K Scale

| Query Pattern | Current (1K users) | Projected (800K) | Risk |
|---------------|--------------------|--------------------|------|
| `coaching_members WHERE group_id = X` | ~5ms | ~5ms (indexed) | LOW |
| `sessions WHERE user_id IN (200 ids)` | ~20ms | ~50ms (larger table) | MEDIUM |
| `sessions WHERE user_id IN (200 ids)` no date filter | ~20ms | **~500ms** (full scan per user) | **HIGH** |
| `coin_ledger WHERE issuer_group_id = X LIMIT 10000` | ~10ms | **~200ms** (10K row transfer) | **HIGH** |
| `coaching_groups SELECT id, name` (no filter) | ~5ms | **~300ms** (10K groups, 800KB transfer) | **HIGH** |
| `coaching_athlete_kpis_daily LIMIT 1000` | ~15ms | ~15ms (capped, but **wrong data**) | **CRITICAL** (silent truncation) |
| Layout queries (6 × ~5ms) | ~30ms | ~30ms | LOW per-query, **HIGH aggregate** (runs on every page) |

---

## Summary

**Most urgent fixes (top 3):**
1. Athletes page unbounded sessions query — will timeout at scale
2. Clearing/Swap/Audit fetching all 10K coaching_groups — unnecessary full table scan
3. Engagement page silently truncating KPI data — produces wrong results

**Architecture gaps:**
- No shared in-memory cache in Flutter (duplicate queries waste ~30% of bandwidth)
- No server-side cache in Portal (Layout alone runs 6 queries per page navigation)
- No real-time subscriptions (missed opportunity for challenges, wallet, join requests)
- No database-side aggregation (client-side SUM/COUNT over large result sets)

**Estimated total effort for P0+P1 fixes:** ~25 engineering hours
