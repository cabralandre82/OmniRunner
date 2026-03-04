# DISASTER SIMULATION: Edge Functions Completely Down

**Scenario:** Supabase Edge Functions (Deno Deploy) are completely unavailable. All `.functions.invoke()` calls fail with network error / 5xx. DB (PostgREST) and Auth (GoTrue) are still operational.

**Date:** 2026-03-04  
**Analyst:** Principal SRE (automated analysis)

---

## 1. Inventory: Edge Function Calls vs Direct DB Calls

### 1.1 All Edge Function Invocations in Flutter App

Scanned `omni_runner/lib/` for `.functions.invoke(` — **30+ distinct call sites** across **18 files**:

| Edge Function | File(s) | Feature |
|---|---|---|
| `settle-challenge` | `challenge_details_screen.dart:94` | Auto-settle expired challenges |
| `challenge-get` | `challenge_join_screen.dart:52` | Fetch challenge for join flow |
| `challenge-join` | `challenge_join_screen.dart:130` | Join a challenge |
| `challenge-accept-group-invite` | `staff_challenge_invites_screen.dart:138` | Accept group challenge invite |
| `champ-list` | `staff_championship_templates_screen.dart:87`, `athlete_championships_screen.dart:54` | List championships |
| `champ-create` | `staff_championship_templates_screen.dart:1199` | Create championship |
| `champ-open` | `staff_championship_manage_screen.dart:170` | Open championship |
| `champ-cancel` | `staff_championship_manage_screen.dart:241` | Cancel championship |
| `champ-invite` | `staff_championship_manage_screen.dart:319` | Invite to championship |
| `champ-participant-list` | `staff_championship_manage_screen.dart:116`, `athlete_championship_ranking_screen.dart:64` | List championship participants |
| `champ-enroll` | `athlete_championships_screen.dart:123` | Enroll in championship |
| `champ-update-progress` | `athlete_championship_ranking_screen.dart:48` | Update championship progress |
| `champ-lifecycle` | `athlete_championships_screen.dart:48`, `athlete_championship_ranking_screen.dart:57` | Championship lifecycle |
| `champ-accept-invite` | `staff_championship_invites_screen.dart:118` | Accept championship invite |
| `clearing-confirm-sent` | `staff_disputes_screen.dart:102` | Clearing: confirm sent |
| `clearing-confirm-received` | `staff_disputes_screen.dart:124` | Clearing: confirm received |
| `clearing-open-dispute` | `staff_disputes_screen.dart:170` | Clearing: open dispute |
| `token-create-intent` | `remote_token_intent_repo.dart:30` | Create token intent (QR) |
| `token-consume-intent` | `remote_token_intent_repo.dart:69` | Consume token intent (QR scan) |
| `delete-account` | `profile_data_service.dart:55` | Delete user account |
| `complete-social-profile` | `remote_auth_datasource.dart:81` | Complete profile after social login |
| `validate-social-login` | `remote_auth_datasource.dart:335` | Validate social login |
| `generate-wrapped` | `wrapped_screen.dart:68` | Generate yearly wrapped |
| `generate-running-dna` | `running_dna_screen.dart:48` | Generate running DNA |
| `set-user-role` | `onboarding_role_screen.dart:111` | Set user role on onboarding |
| `matchmake` | `matchmaking_screen.dart:227,286,346` | Challenge matchmaking |
| `league-list` | `league_screen.dart:51` | League listings |
| `send-push` (via notify rules) | `notification_rules_service.dart:164` | Push notifications |
| `submit-analytics` | `analytics_sync_service.dart:159` | Analytics event submission |

### 1.2 Direct DB Calls (PostgREST / RPC) in Flutter App

The app makes **extensive** direct DB calls via `.from()` (~65+ files) and `.rpc()` (~30+ call sites). Key categories:

**PostgREST `.from()` — direct table reads/writes:**
- `today_data_service.dart` — profile_progress, sessions, challenges, championships, journal entries
- `staff_dashboard_screen.dart` — coaching_members, coaching_groups, clearing_cases, join_requests
- `challenge_details_screen.dart` — clearing_case_items, clearing_cases
- `coaching_group_details_screen.dart` — member management
- `support_screen.dart` / `support_ticket_screen.dart` — tickets
- Profile, settings, announcements, CRM, training sessions, attendance, etc.

**RPC `.rpc()` — server-side functions in Postgres:**
- `fn_remove_member` — member removal
- `fn_friends_activity_feed` — social feed
- `fn_athlete_confirm_item` — workout confirmation
- `fn_assign_workout` — workout assignment
- `fn_generate_workout_payload` — wearable workout data
- `fn_import_execution` — workout execution import
- `fn_create_assessoria` — create coaching group
- `fn_search_coaching_groups` — search groups
- `fn_request_join` / `fn_approve_join_request` / `fn_reject_join_request` — join flow
- `recalculate_profile_progress` — profile recalc
- `evaluate_badges_retroactive` — badge evaluation
- `backfill_strava_sessions` / `backfill_park_activities` — Strava data backfill
- `fn_mark_attendance` / `fn_issue_checkin_token` — attendance
- `fn_mark_announcement_read` — announcements
- `fn_create_ledger_entry` — ledger operations
- And 15+ more

---

## 2. Feature-by-Feature Impact Analysis

### 2.1 Challenge Operations — ALL via Edge Functions

| Operation | Mechanism | Edge Down Impact |
|---|---|---|
| View challenge details | BLoC + Isar/Supabase `.from()` | **WORKS** (direct DB) |
| Join challenge | `challenge-join` EF | **BLOCKED** |
| Accept group invite | `challenge-accept-group-invite` EF | **BLOCKED** |
| Auto-settle expired | `settle-challenge` EF | **BROKEN** — challenges stay active past window |
| Matchmaking | `matchmake` EF | **BLOCKED** |
| Cancel challenge | BLoC event → direct DB | **WORKS** |

**Error handling for join (challenge_join_screen.dart:51–131):** Wrapped in try/catch, shows error via `setState`. User sees error message. **Handled but blocked.**

**Auto-settle (challenge_details_screen.dart:94–104):** `.catchError` logs warning. Challenge remains in "active" status even though window expired. User sees "Calculando resultado..." (line 251) **indefinitely** — this is a **permanent misleading UI state** until edges come back.

**Severity: HIGH.** Users cannot create, join, or settle challenges. Active challenges with expired windows show permanent "calculating..." state.

### 2.2 Championship Operations — ALL via Edge Functions

| Operation | Mechanism | Edge Down Impact |
|---|---|---|
| List championships | `champ-list` EF | **BLOCKED** |
| Create championship | `champ-create` EF | **BLOCKED** |
| Open/cancel championship | `champ-open` / `champ-cancel` EF | **BLOCKED** |
| Invite to championship | `champ-invite` EF | **BLOCKED** |
| Enroll in championship | `champ-enroll` EF | **BLOCKED** |
| View ranking | `champ-participant-list` EF | **BLOCKED** |
| Update progress | `champ-update-progress` EF | **BLOCKED** |

All championship screens (`staff_championship_templates_screen.dart`, `athlete_championships_screen.dart`, `athlete_championship_ranking_screen.dart`, `staff_championship_manage_screen.dart`) use try/catch and show error states (e.g., `AppErrorState` with retry button).

**Severity: HIGH.** The entire championship feature is completely down.

### 2.3 Billing / Token Operations — via Edge Functions

| Operation | Mechanism | Edge Down Impact |
|---|---|---|
| Create token intent (QR) | `token-create-intent` EF | **BLOCKED** |
| Consume token intent (scan) | `token-consume-intent` EF | **BLOCKED** |
| Create checkout | `create-checkout-mercadopago` EF | **BLOCKED** |

**`remote_token_intent_repo.dart` (lines 30, 69):** Both create and consume are wrapped in try/catch. Errors propagate to the calling screen.

**Severity: HIGH.** Staff cannot distribute OmniCoins via QR codes. Assessorias cannot purchase new credits.

### 2.4 Clearing / Disputes — via Edge Functions

| Operation | Mechanism | Edge Down Impact |
|---|---|---|
| Confirm sent | `clearing-confirm-sent` EF | **BLOCKED** |
| Confirm received | `clearing-confirm-received` EF | **BLOCKED** |
| Open dispute | `clearing-open-dispute` EF | **BLOCKED** |
| View clearing cases | Direct DB `.from('clearing_cases')` | **WORKS** |

**`staff_disputes_screen.dart`:** Each clearing action is in try/catch (lines 101, 123, 169). Shows SnackBar error. **Handled.**

**Severity: MEDIUM.** Staff can view disputes but cannot act on them. Cross-assessoria settlements stall.

### 2.5 Push Notifications — via Edge Functions

**`notification_rules_service.dart:164`:** Calls `.functions.invoke(_fn, body: body)`. The send-push edge function delivers push notifications.

- If edges are down, push notifications silently fail
- Streak-at-risk notifications (triggered from TodayScreen line 278) won't send
- Challenge invite notifications won't send

**Severity: MEDIUM.** Notifications degrade silently — users just don't receive them.

### 2.6 Strava Sync — NOT via Edge Functions (mostly)

Strava operations use a mix:
- **Strava webhook processing**: `strava-webhook/index.ts` edge function — called by Strava, not by the app
- **Strava connect**: `strava_connect_controller.dart` uses `.rpc('backfill_strava_sessions')` — **direct DB RPC**
- **Strava OAuth**: `trainingpeaks-oauth` EF — used for TrainingPeaks, not Strava core
- **Strava register webhook**: `strava-register-webhook` EF — one-time setup

**Impact:** Existing Strava sync via webhook will fail. But manual backfill from the app (Strava connect flow) uses direct `.rpc()` and **continues to work**. New Strava activities won't auto-import during the outage.

**Severity: MEDIUM.** Auto-sync stops but manual sync works.

### 2.7 Account Operations — via Edge Functions

| Operation | Mechanism | Edge Down Impact |
|---|---|---|
| Delete account | `delete-account` EF | **BLOCKED** |
| Set user role (onboarding) | `set-user-role` EF | **BLOCKED** |
| Complete social profile | `complete-social-profile` EF | **BLOCKED** |
| Validate social login | `validate-social-login` EF | **BLOCKED** |

**Severity: HIGH for onboarding.** New users completing social login flow will be stuck. Existing users are unaffected for daily use.

### 2.8 Analytics Submission — via Edge Functions

**`analytics_sync_service.dart:159`:** Submits batched product events via edge function.

**Impact:** Analytics events accumulate locally and fail to submit. Not user-facing.

**Severity: LOW.**

### 2.9 Wrapped / Running DNA — via Edge Functions

| Feature | Mechanism | Edge Down Impact |
|---|---|---|
| Yearly Wrapped | `generate-wrapped` EF | **BLOCKED** |
| Running DNA | `generate-running-dna` EF | **BLOCKED** |

Both screens (`wrapped_screen.dart:68`, `running_dna_screen.dart:48`) have try/catch and show error states.

**Severity: LOW.** Non-critical features.

### 2.10 League — via Edge Functions

**`league_screen.dart:51`:** Calls `league-list` edge function.

**Impact:** League screen fails to load. Error handling not inspected but likely shows error/empty.

**Severity: MEDIUM.** League is a secondary feature.

---

## 3. Portal Edge Dependency

### 3.1 Does the Portal Call Edge Functions?

**Grep result:** No `.functions.invoke()` calls found in `portal/src/`.

The portal uses exclusively:
- `createClient()` / `createServiceClient()` for PostgREST queries
- `supabase.from(...)` and `supabase.rpc(...)` — direct DB
- `supabase.auth.getUser()` — GoTrue

**Verdict:** The portal has **ZERO dependency on edge functions**. When edges are down, the portal is **100% operational** (assuming DB is up).

### 3.2 Portal Functionality in Edge-Down Mode

| Portal Feature | Mechanism | Status |
|---|---|---|
| Layout / auth | GoTrue + PostgREST | **WORKS** |
| Athletes list | PostgREST | **WORKS** |
| Custody | PostgREST + RPC | **WORKS** |
| CRM | PostgREST | **WORKS** |
| Attendance | PostgREST | **WORKS** |
| Audit | PostgREST | **WORKS** |
| Clearing | PostgREST | **WORKS** |
| Support tickets | PostgREST | **WORKS** |
| All dashboards | PostgREST | **WORKS** |

---

## 4. Degraded Mode Capability

### 4.1 Flutter App — Read-Only Mode

When edge functions are down but DB is up, the app can:

**FULLY FUNCTIONAL (direct DB):**
- View Today screen (profile, runs, streaks)
- View Staff Dashboard (members, disputes count, join requests)
- View/edit profile
- View wallet balance and history
- View challenge details (read-only)
- View support tickets and create new ones
- View announcements
- View coaching group details and members
- Manage workout assignments
- View workout executions
- View leaderboards
- View friends and activity feed
- View attendance
- Manual Strava backfill
- View settings
- Search and join assessorias (via RPC)

**BLOCKED (edge functions only):**
- Join / create / settle challenges
- All championship operations (list, create, enroll, ranking)
- Create/scan QR token intents (OmniCoin distribution)
- Purchase credits (checkout)
- Clearing actions (confirm, dispute)
- Matchmaking
- Account deletion
- Push notifications
- New user onboarding (role set, profile completion)
- Analytics submission
- Wrapped / Running DNA generation
- League listings

### 4.2 Quantitative Breakdown

- **~65 files** use direct PostgREST/RPC → **continue working**
- **~18 files** use edge function invocations → **blocked**
- Approximately **70% of app features work** in edge-down mode
- **All write operations** that go through edge functions are blocked
- **Most read operations** continue working (they use direct DB)

### 4.3 User Experience in Edge-Down Mode

**Athlete daily use:**
- ✅ Open app, see today screen, streak, last run
- ✅ View wallet balance
- ✅ View challenge details (but can't join new ones)
- ✅ View workout assignments
- ❌ Cannot join/create challenges
- ❌ Cannot participate in championships
- ❌ Cannot scan QR for OmniCoins
- ❌ Won't receive push notifications

**Staff daily use:**
- ✅ View dashboard with member count, disputes
- ✅ View and manage group members
- ✅ Assign workouts
- ✅ View support tickets
- ❌ Cannot distribute OmniCoins via QR
- ❌ Cannot create/manage championships
- ❌ Cannot act on clearing disputes
- ❌ Cannot manage challenge invites

---

## 5. Error Handling Quality per Edge-Dependent Feature

| Feature | File | Error Handling | User Experience |
|---|---|---|---|
| Challenge join | `challenge_join_screen.dart` | try/catch, setState error | Error message shown |
| Challenge settle | `challenge_details_screen.dart` | catchError, log warning | **Stuck "Calculating..." UI** |
| Championship list | `athlete_championships_screen.dart` | try/catch, shows error | Error + retry button |
| Championship manage | `staff_championship_manage_screen.dart` | try/catch, `AppErrorState` | Error + retry button |
| Token create | `remote_token_intent_repo.dart` | try/catch, propagates | Error in calling screen |
| Clearing actions | `staff_disputes_screen.dart` | try/catch, SnackBar | Error SnackBar |
| Matchmaking | `matchmaking_screen.dart` | try/catch | Error message shown |
| Delete account | `profile_data_service.dart` | No catch — **throws** | Unhandled in caller? |
| Social login setup | `remote_auth_datasource.dart` | try/catch | Error propagated |
| Push notifications | `notification_rules_service.dart` | No error handling visible | **Silent failure** |

---

## 6. Reproduction Steps

### Edge Down — Flutter App
1. Block Supabase Edge Functions URL (e.g. `*.supabase.co/functions/v1/*`)
2. Keep PostgREST/GoTrue accessible
3. Launch app:
   - **Today:** Loads normally from direct DB ✓
   - **Challenges:** View works, join fails with error ✓
   - **Championships:** Shows error with retry ✓
   - **Wallet:** Balance loads from DB/Isar, QR scan fails ✓
   - **Staff Dashboard:** Loads normally from direct DB ✓
4. Try to join a challenge → error message
5. View an expired challenge → permanent "Calculating..." spinner

### Edge Down — Portal
1. Block edge function URLs
2. Navigate to any portal page → **everything works normally** ✓

---

## 7. Summary Table

| # | Area | Component | Finding | Works? | Severity |
|---|---|---|---|---|---|
| 1 | App | TodayScreen | All data from direct DB/Isar | YES | NONE |
| 2 | App | StaffDashboard | All data from direct DB | YES | NONE |
| 3 | App | WalletScreen | Balance from DB, QR scan blocked | PARTIAL | MEDIUM |
| 4 | App | Challenge join/create | Edge-only — completely blocked | NO | HIGH |
| 5 | App | Challenge auto-settle | Edge-only — stuck "calculating" UI | NO | HIGH |
| 6 | App | Championships (all) | Edge-only — completely blocked | NO | HIGH |
| 7 | App | Token intents (QR) | Edge-only — OmniCoin distribution blocked | NO | HIGH |
| 8 | App | Clearing actions | Edge-only — disputes can't be resolved | NO | MEDIUM |
| 9 | App | Matchmaking | Edge-only — blocked | NO | MEDIUM |
| 10 | App | Push notifications | Silent failure | NO | MEDIUM |
| 11 | App | Strava auto-sync (webhook) | Edge-only — new activities don't import | NO | MEDIUM |
| 12 | App | Strava manual backfill | Direct RPC | YES | NONE |
| 13 | App | New user onboarding | Edge-only — role/profile setup blocked | NO | HIGH |
| 14 | App | Account deletion | Edge-only — blocked | NO | LOW |
| 15 | App | Wrapped / DNA | Edge-only — blocked | NO | LOW |
| 16 | App | League | Edge-only — blocked | NO | LOW |
| 17 | App | Analytics submission | Edge-only — accumulates locally | NO | LOW |
| 18 | Portal | All features | No edge dependency — fully operational | YES | NONE |

---

## 8. Architectural Observations

### Why so many edge function calls?

The codebase uses edge functions for operations that need:
1. **Multi-step transactions** (challenge join: debit wallet + insert participant + update challenge)
2. **External API calls** (MercadoPago, Strava API)
3. **Complex business logic** (matchmaking, championship lifecycle)
4. **Admin-level operations** (service-role needed: delete account, token intents)

Direct DB calls (PostgREST + RPC) are used for:
1. **Simple CRUD** (read profile, list members, read sessions)
2. **Postgres functions** that can run with user JWT (badges, progress, attendance)

This is a reasonable architecture — but the **lack of graceful degradation in the UI** when edges are down means users encounter various error states without understanding why.

### Recommendation: Edge-Down Banner

A single connectivity check (ping a health endpoint on edge functions) could trigger an app-wide banner: "Algumas funcionalidades estão temporariamente indisponíveis" — preventing confusion when individual features fail.

---

## 9. Recommendations (for future remediation)

1. **Challenge auto-settle:** Add a fallback — if EF fails, show "Resultado será calculado em breve" instead of permanent spinner
2. **Championship listing:** Consider a direct-DB fallback for the list query (simple `.from('championships')`) when EF is unreachable
3. **Token intents:** Add offline enqueue — if EF fails, queue the intent for later replay
4. **Push notifications:** Already non-critical, but add logging for monitoring silent failures
5. **New user onboarding:** `set-user-role` and `complete-social-profile` are critical path — consider moving to direct RPC
6. **App-wide edge health check:** Implement a lightweight health ping to edge functions; show degraded-mode banner when down
7. **Edge function health endpoint:** Each function already has `/health` (webhook-mercadopago line 83). Expose a unified health check.
