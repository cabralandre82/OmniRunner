# DISASTER SIMULATION: Database Completely Down

**Scenario:** Supabase Postgres is completely unreachable. PostgREST returns 5xx / timeouts for all `.from()`, `.rpc()`, and `auth.getUser()` calls.

**Date:** 2026-03-04  
**Analyst:** Principal SRE (automated analysis)

---

## 1. Flutter App

### 1.1 TodayScreen — `today_screen.dart`

**What happens:** The `_load()` method (line 127) has a layered try/catch architecture:

- **Profile progress** (line 146–179): Tries Supabase first via `TodayDataService.getProfileProgress()`, catches and falls back to local Isar via `IProfileProgressRepo.getByUserId()`. **Handled — graceful degradation.**
- **Remote sessions** (line 191–196): Wrapped in isolated try/catch. Falls back to empty list. Local Isar sessions still load (line 182–186). **Handled.**
- **Active challenges** (line 204–244): Tries Supabase first, catches and falls back to Isar `IChallengeRepo.getByUserId()`. **Handled.**
- **Championships** (line 247–255): Wrapped in try/catch. Falls back to empty list silently. **Handled but no offline data.**
- **Outer catch** (line 279–282): If everything fails catastrophically, sets `_loading = false` and shows empty state.

| Sub-feature | Offline Fallback | Severity |
|---|---|---|
| Profile XP/streak | Isar cache | LOW |
| Last run display | Isar sessions | LOW |
| Active challenges | Isar cache | LOW |
| Championships | None — shows empty | MEDIUM |
| Journal save | Silent fail (line 543-553) | LOW |

**Verdict:** TodayScreen is the **best-handled** screen for DB-down. It has proper Isar fallback at every layer.

**Risk:** `recalculateProfileProgress()` (line 138–142) calls `rpc('recalculate_profile_progress')` — fails silently, which is correct. However, if this RPC was recently needed (e.g. after a Strava import), the progress shown will be stale.

### 1.2 StaffDashboardScreen — `staff_dashboard_screen.dart`

**What happens:** `_loadStatus()` (line 67) makes **direct Supabase calls** with `Supabase.instance.client.from(...)` — no Isar fallback at the top level.

- Line 74: Queries `coaching_members` directly via PostgREST
- Line 91: Queries `coaching_groups` directly
- Lines 128–149: 4 parallel queries (`coaching_members`, wallet, `clearing_cases`, `coaching_join_requests`) — each has `.catchError()` returning empty defaults
- Lines 144–149: Individual `catchError` blocks handle sub-query failures

**Outer catch** (line 221–224): Sets `_loading = false` with `_groupId` still empty.

**Result when DB is down:**
1. The main `memberRows` query at line 74 throws → caught at line 221
2. `_loading` set to false, `_groupId` remains empty
3. Build method (line 347–356) → `_groupId.isEmpty` → shows `_buildNoGroup()` (line 359)
4. User sees "Nenhuma assessoria encontrada" ("No coaching group found") with retry button

| Sub-feature | Offline Fallback | Severity |
|---|---|---|
| Dashboard load | None — shows "no group" | HIGH |
| Member count | None | HIGH |
| Disputes count | catchError → 0 | MEDIUM |
| Join requests | catchError → 0 | MEDIUM |

**Verdict:** **CRITICAL.** Staff sees misleading "no group found" message that implies data is gone, not that DB is down. No Isar fallback for the primary membership query despite having Isar repos available (`ICoachingGroupRepo`, `ICoachingMemberRepo`).

### 1.3 LoginScreen — `login_screen.dart`

**What happens:** All auth methods (`_signInWithGoogle`, `_signInWithEmail`, etc.) go through `AuthRepository` which calls Supabase Auth (GoTrue), not Postgres directly.

- Line 140–147: `_checkConnection()` checks `AppConfig.isSupabaseReady`. If false, shows "Sem conexão com o servidor" message.
- Auth calls surface failures via `AuthFailure` → displayed as `_errorMessage` (line 168).
- No loading spinner trap — `_busy` is always set to false in the `if (!mounted) return; setState(() => _busy = false);` pattern.

**Result when DB is down:**
- GoTrue auth service may still work (it has its own connection pool), but if Postgres is fully down, GoTrue can't verify users.
- User sees auth error message. Login is blocked. **Expected behavior.**

| Sub-feature | Offline Fallback | Severity |
|---|---|---|
| Social login | Error shown to user | MEDIUM |
| Email login | Error shown to user | MEDIUM |
| Connection check | AppConfig.isSupabaseReady | LOW |

**Verdict:** Acceptable. Login requires network. Error messages are user-friendly.

### 1.4 WalletScreen — `wallet_screen.dart` + `wallet_bloc.dart`

**What happens:** WalletBloc `_fetch()` (wallet_bloc.dart line 45–65):

1. Calls `_remote.fetchWallet()` — Supabase query, throws on DB down
2. Calls `_remote.fetchLedger()` — Supabase query, throws on DB down
3. If any throw → `WalletError('Erro ao carregar OmniCoins: $e')` at line 63

BUT: The catch is `on Exception`, and lines 48–56 are sequential. If `fetchWallet` succeeds but `fetchLedger` fails, partial data is saved to Isar but the UI shows error anyway.

**Result when DB is down:**
- If wallet was previously loaded (Isar has data), the error state still shows instead of cached data.
- UI shows `WalletError` → `Center(child: Text(message))` at line 167–169 — plain error text, no retry button in the error state widget itself.
- Refresh button exists in AppBar (line 49) so user can retry.

| Sub-feature | Offline Fallback | Severity |
|---|---|---|
| Balance display | Error — no Isar fallback in bloc | HIGH |
| Ledger history | Error — no Isar fallback in bloc | HIGH |
| QR scan (FAB) | Calls edge function — will also fail | HIGH |

**Verdict:** **HIGH severity.** WalletBloc has Isar repos (`_walletRepo`, `_ledgerRepo`) but the `_fetch()` method doesn't fall back to local reads when remote fails. A simple `try { remote } catch { }` + always read from local would fix this.

### 1.5 ChallengeDetailsScreen — `challenge_details_screen.dart`

**What happens:** Uses BLoC pattern (`ChallengesBloc`). The UI handles states:
- `ChallengesLoading` → spinner (line 39–40)
- `ChallengesError` → shows error message with styling (line 41–49)
- Default → spinner (line 50)

Auto-settle mechanism (line 94–104): Calls `functions.invoke('settle-challenge')` — if DB is down, `.catchError` at line 102 logs a warning. **Safe.**

`_ClearingInfo` widget (line 1407–1493): Makes direct Supabase queries. On error, catches at line 1475 and sets `_loaded = true` — shows nothing. **Safe.**

| Sub-feature | Offline Fallback | Severity |
|---|---|---|
| Challenge detail load | BLoC error state | MEDIUM |
| Auto-settle | catchError — safe | LOW |
| Clearing status | catch → hidden | LOW |

**Verdict:** MEDIUM. Error is shown but the BLoC determines whether Isar cache is used.

### 1.6 Cross-Cutting: Offline Queue

**File:** `core/offline/offline_queue.dart`

The offline queue stores failed RPC calls in SharedPreferences and replays them later. Key properties:
- Max 3 retries per item (line 15)
- Max 7 day age (line 16)
- Exponential backoff is NOT present in replay — items are replayed sequentially
- Queue is for **RPC calls only** — not for PostgREST `.from()` calls

**Risk:** The queue only covers a subset of operations. Most screen-level Supabase calls do NOT enqueue on failure.

### 1.7 Cross-Cutting: Retry Utility

**File:** `core/utils/retry.dart`

- Exponential backoff with jitter, max 3 attempts (default)
- Used in `supabase_wearable_repo.dart` for device linking and execution import
- **NOT used in most screen-level data fetching** — screens do their own try/catch

**Risk:** Most data fetching has no retry. A transient DB blip fails immediately. Only wearable operations retry.

### 1.8 Infinite Retry / Battery Drain Analysis

- **TodayScreen:** Has a 60-second debounce (line 128–131) preventing reload spam. `didUpdateWidget` only reloads on tab visibility change. **No infinite retry risk.**
- **StaffDashboardScreen:** Retry button requires manual press. No auto-retry loop. **Safe.**
- **WalletBloc:** RefreshWallet event is user-triggered only. **Safe.**
- **OfflineQueue replay:** Bounded by `_maxRetryCount = 3`. **Safe.**

**No infinite retry / battery drain vectors found.**

### 1.9 Permanent Loading States

- **StaffDashboardScreen:** If the outer catch fires, `_loading = false` is set. But if the `Future.wait` at line 144 hangs (timeout rather than error), the shimmer loading persists indefinitely.
- **WalletBloc:** If `_remote.fetchWallet()` hangs without throwing, the bloc stays in `WalletLoading` state forever.
- **ChallengeDetailsScreen:** If BLoC fetch hangs, shows spinner indefinitely.

**No explicit timeouts on Supabase PostgREST calls.** Supabase client default timeout is ~60s. During a DB outage with connection refused, errors are fast. During a DB overload with slow responses, **screens can hang on loading for up to 60 seconds.**

---

## 2. Portal (Next.js RSC)

### 2.1 Layout — `layout.tsx`

**What happens:** The layout (line 16–130) is a **Server Component** that makes 6+ Supabase queries sequentially:

1. `supabase.auth.getUser()` — line 23
2. `supabase.from("profiles")` — line 33 (conditional)
3. `supabase.from("coaching_members")` — line 46
4. `Promise.all` with 4 queries (line 63–84): coaching_groups, profiles, portal_branding, custody_accounts

**There is NO try/catch wrapping these calls.**

**Result when DB is down:**
- `supabase.auth.getUser()` may return null user → redirect to `/login` (line 26)
- If auth succeeds but profile/group queries fail → **unhandled exception** → Next.js will show the default error page (500)
- Since there is **no `error.tsx` boundary** in `(portal)/` and **no `global-error.tsx`**, the user sees Next.js's default 500 page or a white screen in production.

| Query | Effect of Failure | Severity |
|---|---|---|
| auth.getUser() | Redirect to /login | MEDIUM |
| coaching_members | **Unhandled crash** | CRITICAL |
| Promise.all (4 queries) | **Unhandled crash** | CRITICAL |

**Verdict:** **CRITICAL.** The layout RSC has zero error handling. Any DB query failure crashes the entire portal shell, making ALL child routes inaccessible. Every page under `(portal)/` depends on this layout.

### 2.2 Custody Page — `custody/page.tsx`

**What happens:** Line 18–26 runs `Promise.all` with 6 Supabase queries using the service client. No try/catch.

**Result when DB is down:** Unhandled exception → 500. Same issue as layout.

**Verdict:** CRITICAL — but the layout would already have crashed before reaching this page.

### 2.3 Error Boundaries

**Analysis:** No `error.tsx`, `global-error.tsx`, or React ErrorBoundary components found anywhere in the portal. This means:
- Any unhandled throw in an RSC page → default Next.js error handling
- In production, this is a generic error page with no retry capability
- In development, it shows the error stack

---

## 3. Edge Functions

### 3.1 `requireUser()` — `_shared/auth.ts`

**What happens (line 44–106):**
1. Extracts JWT from header
2. Creates a Supabase client with service key
3. Calls `verifyClient.auth.getUser(jwt)` at line 69

`auth.getUser()` calls GoTrue, which itself queries Postgres. If DB is down:
- GoTrue returns error → `authError` is truthy → `AuthError` thrown with status 401
- All authenticated edge functions fail with 401, not 500

**Risk:** Users get "Invalid JWT" instead of "Service temporarily unavailable". The 401 status may cause clients to incorrectly invalidate their session/token.

| Behavior | Status Code | Severity |
|---|---|---|
| JWT validation fails | 401 | HIGH |
| Misleading error (JWT seems invalid) | 401 | HIGH |
| Client may drop auth session | - | HIGH |

**Verdict:** HIGH. The error code is misleading — a 503 (Service Unavailable) would be more appropriate when the DB is unreachable vs. when the token is genuinely invalid.

### 3.2 `_shared/http.ts`

Standard JSON response helpers. `jsonErr()` supports arbitrary status codes and error codes. Properly structured.

### 3.3 Webhook Functions — General Pattern

Edge functions use a top-level try/catch pattern (e.g., webhook-mercadopago line 388–398):
```typescript
} catch (err) {
  status = 500;
  return jsonErr(500, "INTERNAL", "Unexpected error", requestId);
}
```

DB failures within the try block will be caught and return 500 with structured JSON.

---

## 4. Webhooks & Payment Loss Analysis

### 4.1 `webhook-mercadopago/index.ts`

**Critical flow when DB is down:**

1. MercadoPago sends POST webhook notification
2. Function validates HMAC signature (lines 113–147) — **does NOT need DB** ✓
3. Fetches payment details from MP API (lines 175–204) — **does NOT need DB** ✓
4. **DB operations begin** at line 216 (creates Supabase client)
5. `billing_purchases.update()` at line 235 → **FAILS** (DB down)
6. `insertEvent()` at line 249 → **FAILS**
7. `db.rpc('fn_fulfill_purchase')` at line 275 → **FAILS**
8. All caught by outer catch (line 388) → returns 500

**What MercadoPago does on 500:**
- MercadoPago IPN retries automatically with exponential backoff
- Default retry schedule: immediate, 5min, 30min, 6h, 2d
- Retries continue for approximately 2 days
- If all retries fail, the notification is **dropped**

**Is the payment lost?**
- The **payment at MercadoPago is confirmed** regardless of webhook
- The **purchase in our DB stays in "pending" status** because the webhook couldn't update it
- Credits are never allocated (fn_fulfill_purchase never ran)
- **The user paid but never received their OmniCoins**

**Dead-letter mechanism:** None found. No `dead_letter`, `dlq`, or similar patterns exist in the codebase.

| Failure Mode | Impact | Severity |
|---|---|---|
| Webhook returns 500 | MP retries ~2 days | MEDIUM |
| DB down > 2 days | Payment lost — user paid but got no credits | CRITICAL |
| No dead-letter queue | No safety net for expired retries | CRITICAL |
| No reconciliation job | Orphaned payments never recovered | CRITICAL |

**Verdict:** **CRITICAL.** If DB is down for >2 days, confirmed payments are permanently lost. Even shorter outages create a window where users see "pending" purchases indefinitely. There is no reconciliation cron that queries MercadoPago for unprocessed payments.

### 4.2 Idempotency (if DB comes back during retry window)

The webhook has 3 layers of idempotency (documented in header comments):
- L1: `billing_events` dedup via `mp_payment_id`
- L2: Conditional UPDATE with `WHERE status = 'pending'`
- L3: `fn_fulfill_purchase` checks `status = 'paid'` with `FOR UPDATE` lock

**This is well-designed for the happy path.** The issue is only when all retries exhaust during a prolonged outage.

---

## 5. Reproduction Steps

### DB Down — Flutter App
1. Block Supabase PostgREST URL at network level (e.g., `/etc/hosts` or firewall rule)
2. Launch app, authenticate (session cached locally)
3. Navigate to each tab:
   - **Today:** Should show cached data from Isar ✓
   - **Staff Dashboard:** Shows "Nenhuma assessoria encontrada" ✗
   - **Wallet:** Shows error text ✗
   - **Challenge Details:** Shows error or spinner ✗

### DB Down — Portal
1. Block Supabase Postgres/PostgREST URL
2. Navigate to any portal page
3. Layout crashes → 500 error / white screen ✗
4. All routes inaccessible

### DB Down — Webhooks
1. Block Supabase Postgres
2. Trigger a MercadoPago test payment
3. Observe edge function returns 500
4. Check: no billing_events inserted, purchase stays "pending"
5. Restore DB → MP retry delivers → payment processed (if within retry window)

---

## 6. Summary Table

| # | Area | Component | Finding | Handled? | Severity |
|---|---|---|---|---|---|
| 1 | App | TodayScreen | Supabase→Isar fallback at each sub-query | YES | LOW |
| 2 | App | StaffDashboardScreen | Shows misleading "no group found" instead of DB error | PARTIAL | HIGH |
| 3 | App | LoginScreen | Auth fails with user-facing error | YES | MEDIUM |
| 4 | App | WalletBloc | Has Isar repos but doesn't fallback — shows raw error | NO | HIGH |
| 5 | App | ChallengeDetailsScreen | BLoC error state shown | PARTIAL | MEDIUM |
| 6 | App | OfflineQueue | Only covers RPC calls, not PostgREST reads | PARTIAL | MEDIUM |
| 7 | App | retry.dart | Only used in wearable repo, not broadly | PARTIAL | MEDIUM |
| 8 | App | No timeout on Supabase calls | Potential 60s loading hang during DB overload | NO | MEDIUM |
| 9 | Portal | layout.tsx | No try/catch on 6+ DB queries — crashes entire shell | NO | CRITICAL |
| 10 | Portal | custody/page.tsx | No try/catch on 6 queries | NO | CRITICAL |
| 11 | Portal | No error.tsx / global-error.tsx | No error boundary anywhere | NO | CRITICAL |
| 12 | Edge | requireUser() | Returns 401 instead of 503 — misleading | NO | HIGH |
| 13 | Edge | webhook-mercadopago | Returns 500, relies on MP retry (2-day window) | PARTIAL | HIGH |
| 14 | Webhook | Payment loss risk | No dead-letter, no reconciliation cron | NO | CRITICAL |
| 15 | Webhook | Credits never allocated | User pays but gets nothing if retries exhaust | NO | CRITICAL |

---

## 7. Recommendations (for future remediation)

1. **Portal:** Add `error.tsx` boundary in `(portal)/` and `global-error.tsx` at app root
2. **Portal layout:** Wrap DB queries in try/catch with degraded fallback (show cached group name or redirect to error page)
3. **WalletBloc:** Add Isar-first fallback: try remote → catch → read local anyway
4. **StaffDashboard:** Add Isar fallback for membership/group queries (repos exist)
5. **requireUser():** Distinguish between "DB unreachable" (503) and "token invalid" (401)
6. **Webhook:** Add dead-letter table for failed webhook payloads; add reconciliation cron that checks MercadoPago API for unmatched payments
7. **All Supabase calls:** Add configurable timeout (e.g. 10s) to prevent prolonged loading states
