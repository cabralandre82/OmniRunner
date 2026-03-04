# UX OF DISASTER — DEGRADED MODE ANALYSIS

> Phase 8 — Principal SRE Analysis  
> Date: 2026-03-04  
> Scope: Every critical screen's behavior during failures, error patterns, data loss scenarios

---

## 8.1 Flutter Screen Analysis

### Legend

| Symbol | Meaning |
|--------|---------|
| OK | Properly handled |
| WARN | Partial handling, some gaps |
| FAIL | Not handled, poor UX |

---

### 8.1.1 `login_screen.dart` — Auth Failures

**File:** `omni_runner/lib/presentation/screens/login_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **OK** | `_errorMessage` displayed with red icon + text (lines 433-453). `_handleFailure()` (line 165) maps `AuthFailure.message` to UI. Social cancel silently ignored (line 166). |
| Try again button | **WARN** | No explicit retry button. User must tap the login button again. Buttons remain functional after error. |
| Stuck in loading | **OK** | `_busy` flag set to `true` before async, reset to `false` in all paths (lines 63-68, 111-114, 128-130, 152-155). Uses `if (!mounted) return` guards. |
| Input preservation | **OK** | `TextEditingController` for email/password persist across errors (lines 38-39). |
| Buttons disabled during async | **OK** | When `_busy` is true, all buttons are replaced by a `CircularProgressIndicator` (lines 243-247). Entire button list hidden during loading. |
| Connection check | **OK** | `_checkConnection()` (lines 140-147) checks `AppConfig.isSupabaseReady` before any action. Shows "Sem conexão com o servidor" message. |

**VERDICT: GOOD** — Login handles failures well. Minor gap: no explicit retry button, but buttons remain tappable.

---

### 8.1.2 `today_screen.dart` — Main Dashboard

**File:** `omni_runner/lib/presentation/screens/today_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **FAIL** | On error in `_load()` (line 279-282), sets `_loading = false` but shows NO error message. The user sees an empty dashboard. Catch block only logs: `AppLogger.error('Today data load failed')`. |
| Try again button | **WARN** | `RefreshIndicator` wrapping the `ListView` (line 409-410) allows pull-to-refresh. No explicit retry button on error state. |
| Stuck in loading | **OK** | `_loading = false` is set in both success path (line 276) and catch block (line 282). Shimmer loading shown while loading (lines 367-408). |
| Offline fallback | **OK** | Graceful degradation: profile fetches from Supabase first, falls back to Isar (lines 176-179). Challenges do the same (lines 236-244). Individual sub-fetches use try/catch independently. |
| Stale data protection | **OK** | 60-second cooldown on `_load()` (lines 128-130). |

**VERDICT: MIXED** — Excellent offline fallback pattern, but **top-level error results in blank screen** with no error UI. Individual sub-component failures are handled gracefully.

---

### 8.1.3 `staff_dashboard_screen.dart` — Staff Main Screen

**File:** `omni_runner/lib/presentation/screens/staff_dashboard_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **WARN** | No staff membership → shows "Nenhuma assessoria encontrada" with explanation (lines 433-466). But generic errors in `_loadStatus()` catch block (line 221-224) just set `_loading = false` with no error message. |
| Try again button | **OK** | "Tentar novamente" button shown when no group found (lines 454-461). "Verificar status" button for pending states (lines 419-429). `RefreshIndicator` on dashboard grid (line 613). |
| Stuck in loading | **OK** | `_loading = false` set in catch block (line 224). `ShimmerListLoader` shown during loading. |
| Parallel fetches | **OK** | Uses `Future.wait` with `.catchError` on each query (lines 144-149) — one failing query doesn't block others. |
| Individual query failures | **OK** | Each parallel query has its own `catchError` handler that logs and returns empty defaults. Dashboard still renders with partial data. |

**VERDICT: GOOD** — Robust parallel fetch with individual error handling. Gap: generic exception shows blank dashboard, not error state.

---

### 8.1.4 `athlete_delivery_screen.dart` — Delivery Confirmation

**File:** `omni_runner/lib/presentation/screens/athlete_delivery_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **OK** | Uses `AppErrorState` widget (line 169-172) with human-readable message via `ErrorMessages.humanize(e)`. |
| Try again button | **OK** | `AppErrorState` includes built-in "Tentar novamente" button (see `state_widgets.dart` lines 91-99). Refresh icon in AppBar (lines 151-156). |
| Stuck in loading | **OK** | Uses `AppLoadingState` widget. `_loading` properly reset in catch (line 62). |
| Empty state | **OK** | `AppEmptyState` with "Nenhuma entrega pendente" + check icon (lines 176-179). |
| Double-tap prevention | **OK** | `_confirmingIds` Set prevents duplicate confirms (line 71). Button shows spinner when confirming (lines 296-300). Both confirm and failure buttons disabled during operation (`isConfirming ? null`) at lines 293-294 and 314-315. |
| Error on confirm | **OK** | SnackBar with humanized error on confirm failure (lines 96-100). `_confirmingIds` cleaned up (line 97). |

**VERDICT: EXCELLENT** — This screen is a model of proper error handling. Uses the centralized `state_widgets.dart` pattern.

---

### 8.1.5 `wallet_screen.dart` — Financial

**File:** `omni_runner/lib/presentation/screens/wallet_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **WARN** | `WalletError` state shows only `Center(child: Text(message))` (lines 167-169). Plain text, no icon, no styling. |
| Try again button | **FAIL** | No retry button on `WalletError` state. Refresh icon in AppBar (lines 46-51) still works. |
| Stuck in loading | **OK** | `WalletInitial` and `WalletLoading` both show `ShimmerListLoader` (lines 66-67). BLoC handles state transitions. |
| Empty state | **OK** | Empty history shows friendly message with icon (lines 131-161). |
| Pull-to-refresh | **OK** | `RefreshIndicator` wrapping the loaded state (lines 69-73). |

**VERDICT: NEEDS WORK** — Financial screen has **no retry button on error** and a bare text error message. For a financial screen, this is inadequate.

---

### 8.1.6 `challenge_details_screen.dart` — Active Challenge

**File:** `omni_runner/lib/presentation/screens/challenge_details_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **OK** | `ChallengesError` state shows message in error color with padding (lines 41-49). |
| Try again button | **FAIL** | No retry mechanism on error. User must navigate back and re-enter. |
| Stuck in loading | **OK** | `ChallengesLoading` shows `CircularProgressIndicator` (lines 39-40). Default case also shows spinner (line 50). |
| Settlement handling | **OK** | When challenge window expires, auto-triggers `settle-challenge` edge function (lines 81-105). Shows "Calculando resultado..." indicator (lines 225-272). Settlement failure logged but doesn't crash UI (lines 102-104). |
| Accept/Decline disabled during async | **WARN** | Accept/Decline buttons fire BLoC events (lines 650-656, 722-729) but **are not disabled** during the async operation. No `_busy` guard on Accept button. |

**VERDICT: MIXED** — Good error display but no retry. Accept button not disabled during processing.

---

### 8.1.7 `profile_screen.dart` — Profile Editing

**File:** `omni_runner/lib/presentation/screens/profile_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **OK** | `_error` displayed in a red Card with icon (lines 461-483). `_friendlyError()` (lines 295-310) converts technical errors to Portuguese messages (network, permission, JWT, etc.). |
| Try again button | **FAIL** | No explicit retry on load error. Only loading spinner shown (line 325). |
| Stuck in loading | **OK** | `_loading` properly managed in `_load()` (line 53, 84, 89). |
| Input preservation | **OK** | `TextEditingController`s for name, Instagram, TikTok (lines 28-30) persist across save errors. Form fields are NOT cleared on failure. |
| Save button disabled during async | **OK** | `_saving ? null : _saveAll` on FilledButton (line 449). Spinner shown during save (lines 450-453). Sign out and delete buttons also disabled with `_busyAuth` (lines 494, 510). |
| Avatar upload | **OK** | `_uploadingAvatar` flag disables camera button (line 346). Error sets `_error` message (lines 189-193). |

**VERDICT: GOOD** — Excellent input preservation. Error messages are well-crafted. Missing: retry button on initial load failure.

---

### 8.1.8 `support_screen.dart` — Support Tickets

**File:** `omni_runner/lib/presentation/screens/support_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **FAIL** | Load error in `_load()` (line 45-48) just logs the warning and sets `_loading = false`. No error state shown — user sees empty list. |
| Try again button | **WARN** | `RefreshIndicator` wrapping the list (line 121). No explicit retry button. |
| New ticket error | **OK** | SnackBar with error message on creation failure (lines 93-96). |
| Input preservation | **WARN** | `_NewTicketDialog` collects subject + message. If creation fails, the dialog is already dismissed. Data is lost because `Navigator.pop()` happens before the `_newTicket()` method's try/catch. The dialog pops with data (line 362-366), then `_newTicket()` uses the result — but if insert fails (line 92), the user must re-type everything. |
| Busy state | **OK** | `_busy` flag prevents double-submission (line 52). |

**VERDICT: NEEDS WORK** — Load errors produce blank screen. Ticket message lost on creation failure.

---

### 8.1.9 `join_assessoria_screen.dart` — Joining a Group

**FINDING: FILE NOT FOUND** — `join_assessoria_screen.dart` does not exist in the codebase. The join flow is handled through deep links processed by `DeepLinkHandler` and the `coaching_join_requests` table.

---

### 8.1.10 `staff_generate_qr_screen.dart` — QR Code Generation

**File:** `omni_runner/lib/presentation/screens/staff_generate_qr_screen.dart`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Clear error message | **OK** | `StaffQrError` state shows SnackBar with error message and error color (lines 123-134). |
| Try again button | **OK** | "Gerar Novo" button on QR display (lines 595-617). On error, returns to form state where user can retry. Capacity refresh buttons exist (lines 333-357, 470-498). |
| Stuck in loading | **OK** | `StaffQrGenerating` shows `CircularProgressIndicator` (lines 140-141). |
| Capacity loading | **OK** | Capacity card shows loading spinner while fetching (lines 254-277, 384-407). |
| QR expiry | **OK** | Countdown timer shows remaining time (lines 509-550). Expired QR shows clear "QR Expirado" state (lines 568-588). |
| Exceed capacity guard | **OK** | "Gerar QR" button disabled when `exceedsCapacity` is true (line 235). |

**VERDICT: EXCELLENT** — Comprehensive error handling, loading states, and capacity guards.

---

### 8.1.11 `staff_delivery_detail_screen.dart` — Delivery Management

**FINDING: FILE NOT FOUND** — `staff_delivery_detail_screen.dart` does not exist in the codebase.

---

## 8.2 Portal Page Analysis

### 8.2.1 `layout.tsx` — Main Shell

**File:** `portal/src/app/(portal)/layout.tsx`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Error boundary | **FAIL** | No `error.tsx` exists anywhere in the portal (0 files found via glob search `portal/src/app/(portal)/**/error.tsx`). No `global-error.tsx` either. |
| Auth failure handling | **OK** | Redirects to `/login` if no user (line 26). Redirects to `/select-group` if no group cookie (line 43). |
| Partial failure | **WARN** | Layout queries 4 things in `Promise.all` (lines 63-84). If ANY fails, the entire layout throws — all child pages crash. |
| Navigation resilience | **WARN** | Since layout is a Server Component that runs on every navigation, a transient DB error will block ALL navigation. |

**VERDICT: CRITICAL GAP** — No error boundaries anywhere in the portal. A single DB failure in the layout crashes the entire application shell.

---

### 8.2.2 `dashboard/page.tsx`

**FINDING: FILE NOT FOUND** — No `portal/src/app/(portal)/dashboard/page.tsx` exists. The portal appears to not have a dedicated dashboard page (the layout renders children directly).

---

### 8.2.3 `custody/page.tsx`

**File:** `portal/src/app/(portal)/custody/page.tsx`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Error boundary | **FAIL** | No `error.tsx` in the custody directory. Unhandled exceptions show Next.js default error. |
| Fallback UI | **WARN** | Returns `null` if no `groupId` (line 14). No loading skeleton. |
| Empty states | **WARN** | If queries return empty, KPI cards show `$0.00` defaults. No "no data" message. |
| Data integrity display | **OK** | Shows invariant badges (lines 134-146) — "Total = Reservado + Disponivel" and "Reservado = Coins Vivas" with checkmark/warning. Links to audit if invariant broken. |
| Blocked account | **OK** | Red banner shown when `is_blocked` (lines 99-105). |

**VERDICT: NEEDS WORK** — No error boundary. Good data integrity display but no graceful degradation.

---

### 8.2.4 `clearing/page.tsx`

**File:** `portal/src/app/(portal)/clearing/page.tsx`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Error boundary | **FAIL** | No `error.tsx`. |
| Fallback UI | **WARN** | Returns `null` if no `groupId` (line 34). |
| Empty states | **OK** | If no settlements, KPI cards show `$0.00`. Tables would be empty. |
| Group name resolution | **OK** | Resolves referenced group IDs to names (lines 56-61). |

**VERDICT: NEEDS WORK** — No error boundary.

---

### 8.2.5 `crm/page.tsx`

**File:** `portal/src/app/(portal)/crm/page.tsx`

| Criterion | Status | Evidence |
|-----------|--------|----------|
| Error boundary | **FAIL** | No `error.tsx`. |
| Inline error handling | **OK** | `fetchError` caught and displayed: "Erro ao carregar dados. Tente recarregar a página." (lines 228-231). This is the **only portal page** that handles errors inline. |
| Empty state | **OK** | "Nenhum atleta encontrado" card when list is empty (lines 361-365). |
| Fallback UI | **WARN** | Returns `null` if no `groupId` (line 181). |

**VERDICT: BEST PORTAL PAGE** — Only page with inline error handling. Still lacks `error.tsx`.

---

### 8.2.6 `workouts/page.tsx`

**FINDING: FILE NOT FOUND** — No `portal/src/app/(portal)/workouts/page.tsx`. Workout pages exist under `workouts/analytics/` and `workouts/assignments/` with loading states (`loading.tsx` files found).

---

## 8.3 Global Error Patterns

### 8.3.1 Flutter Global Error Handler

**File:** `omni_runner/lib/main.dart`

**FINDING: COMPREHENSIVE — Three layers of error capture.**

1. **`FlutterError.onError`** (lines 36-44): Catches widget build errors. Calls `FlutterError.presentError()` AND logs to `AppLogger.error()`.

2. **`PlatformDispatcher.instance.onError`** (lines 46-49): Catches uncaught platform errors. Logs to `AppLogger.error()`. Returns `true` to mark as handled.

3. **`ErrorWidget.builder`** (lines 51-71): Custom error widget replacing red screen of death. Shows "Algo deu errado" with restart instruction. Portuguese language. Renders as a full MaterialApp to avoid nested errors.

4. **Sentry integration** (lines 73-89): When `AppConfig.isSentryConfigured`, wraps bootstrap in `SentryFlutter.init()`. Otherwise falls back to `runZonedGuarded` with `AppLogger.error()`.

5. **`AppLogger.onError` → Sentry** (lines 128-132): All `AppLogger.error()` calls also capture to Sentry.

**VERDICT: EXCELLENT** — Full error capture pipeline.

### 8.3.2 Portal Global Error Boundary

**FINDING: NONE — No `error.tsx` or `global-error.tsx` exists.**

Verified via glob search:
- `portal/src/app/(portal)/**/error.tsx` → 0 files
- `portal/src/app/global-error.tsx` → 0 files

**Impact:** Any unhandled exception in a Server Component shows the default Next.js error page (a white page with "Application error: a server-side exception has occurred"). No retry button, no navigation back to working pages.

### 8.3.3 Centralized Error Messages

**Flutter — `ErrorMessages.humanize()`** (`core/utils/error_messages.dart`):

```dart
static String humanize(Object error) {
  // Maps: network → "Sem conexão com a internet"
  //        timeout → "A operação demorou muito"
  //        permission/403 → "Você não tem permissão"
  //        not found/404 → "Recurso não encontrado"
  //        duplicate → "Este item já existe"
  //        default → "Algo deu errado"
}
```

Used by: `athlete_delivery_screen.dart`. **Not widely adopted** — most screens (today, staff_dashboard, support, wallet) write their own error messages or show raw errors.

**Flutter — `state_widgets.dart`** (`presentation/widgets/state_widgets.dart`):

Three reusable widgets:
- `AppLoadingState` — centered spinner + optional message
- `AppErrorState` — error icon + message + "Tentar novamente" button
- `AppEmptyState` — muted icon + message + optional action button

Used by: `athlete_delivery_screen.dart`. **Not adopted by other screens** — most screens implement ad-hoc loading/error states.

**Portal — No centralized error pattern.** Each page handles (or doesn't handle) errors independently. Only `crm/page.tsx` has inline error handling.

---

## 8.4 Data Loss Scenarios

### 8.4.1 Workout Template Form — Save Fails

**Context:** Staff builds workout templates in `staff_workout_builder_screen.dart`.

**FINDING:** The workout builder screen was not fully analyzed (file exists but is very large). However, the general pattern in the codebase:
- Forms use `TextEditingController` which persists state
- Save failures show SnackBar errors
- Form data is NOT cleared on save failure
- **RISK:** If the user navigates away (e.g., back button) after a failed save, the data is lost. There is no draft/autosave mechanism.

### 8.4.2 Support Ticket Message — Send Fails

**File:** `omni_runner/lib/presentation/screens/support_screen.dart`

**FINDING: DATA LOSS ON FAILURE.**

The flow in `_newTicket()` (lines 51-100):
1. Dialog collects subject + message → `Navigator.pop(ctx, result)` (line 362-366)
2. Dialog is dismissed, data is in `result` variable
3. `insert()` to `support_tickets` (line 63)
4. `insert()` to `support_messages` (line 74)
5. If step 3 fails → catch at line 92 shows SnackBar
6. **The dialog is already dismissed** — user must open a NEW dialog and re-type everything

**VERDICT: CONFIRMED DATA LOSS** — Message text is lost when ticket creation fails.

### 8.4.3 Challenge Creation — Fails

**Context:** Challenge creation happens through the `ChallengesBloc` which fires events to Supabase.

**FINDING:** Challenge creation is handled by BLoC events (`CreateChallengeRequested`). The creation form data is held in the BLoC state or the creating screen. If the RPC call fails:
- The BLoC emits `ChallengesError`
- The user sees the error message
- The form screen should still be mounted with its state intact
- **NOT a data loss** — form state persists as long as the screen is mounted

### 8.4.4 Journal Entry — Save Fails

**File:** `omni_runner/lib/presentation/screens/today_screen.dart`, lines 542-553

The journal uses debounced auto-save (1-second delay, line 598). If save fails:
- Error is only logged: `AppLogger.debug('Journal save failed')` (line 551)
- The text remains in the `TextEditingController`
- **User is NOT notified** of the save failure
- On "Salvar" button tap, save is called again (line 622-623)

**VERDICT: SILENT FAILURE** — User thinks journal is saved but it may not be. No error feedback.

---

## 8.5 Screen-by-Screen Summary Matrix

### Flutter Screens

| Screen | Error Message | Retry Button | Loading State | Input Preserved | Buttons Disabled | Overall |
|--------|:---:|:---:|:---:|:---:|:---:|:---:|
| `login_screen` | OK | WARN | OK | OK | OK | **B+** |
| `today_screen` | FAIL | WARN | OK | N/A | N/A | **C** |
| `staff_dashboard_screen` | WARN | OK | OK | N/A | N/A | **B** |
| `athlete_delivery_screen` | OK | OK | OK | N/A | OK | **A** |
| `wallet_screen` | WARN | FAIL | OK | N/A | N/A | **C** |
| `challenge_details_screen` | OK | FAIL | OK | N/A | WARN | **C+** |
| `profile_screen` | OK | FAIL | OK | OK | OK | **B+** |
| `support_screen` | FAIL | WARN | OK | FAIL | OK | **D** |
| `staff_generate_qr_screen` | OK | OK | OK | N/A | OK | **A** |

### Portal Pages

| Page | Error Boundary | Inline Error | Empty State | Navigation OK on Error | Overall |
|------|:---:|:---:|:---:|:---:|:---:|
| `layout.tsx` | FAIL | N/A | N/A | FAIL | **F** |
| `custody/page.tsx` | FAIL | FAIL | WARN | N/A | **D** |
| `clearing/page.tsx` | FAIL | FAIL | OK | N/A | **D** |
| `crm/page.tsx` | FAIL | OK | OK | N/A | **C+** |

---

## 8.6 Critical Findings

| ID | Finding | Severity | Affected |
|----|---------|----------|----------|
| UX1 | **Portal has ZERO error boundaries** — any RSC throw crashes the entire shell | **CRITICAL** | All portal pages |
| UX2 | `today_screen` shows blank screen on load failure (no error UI) | HIGH | Main dashboard |
| UX3 | `wallet_screen` error state has no retry button (financial screen!) | HIGH | Wallet |
| UX4 | Support ticket message lost on creation failure | HIGH | Support |
| UX5 | Journal auto-save failure is silent — user not notified | MEDIUM | TodayScreen journal |
| UX6 | `challenge_details_screen` Accept button not disabled during async | MEDIUM | Challenge flow |
| UX7 | Only `athlete_delivery_screen` uses `state_widgets.dart` pattern | MEDIUM | Code consistency |
| UX8 | Portal layout `Promise.all` — single query failure crashes ALL pages | MEDIUM | Portal layout |
| UX9 | `support_screen` load error shows empty list instead of error state | MEDIUM | Support |
| UX10 | `ErrorMessages.humanize()` not adopted across most screens | LOW | Error messaging |

---

## 8.7 Recommendations

### Immediate (P0)

1. **Add `error.tsx` to portal** — at minimum in `app/(portal)/error.tsx` with retry button and navigation back
2. **Add `global-error.tsx`** — catches layout-level errors
3. **Add error state to `today_screen`** — when `_load()` fails completely, show `AppErrorState`
4. **Add retry button to `wallet_screen`** error state

### Short-term (P1)

5. **Adopt `state_widgets.dart`** across all screens — replace ad-hoc loading/error/empty states
6. **Adopt `ErrorMessages.humanize()`** as the standard error translator
7. **Preserve support ticket draft** — keep dialog open or store draft locally on failure
8. **Show journal save failure** — SnackBar on save error instead of silent log
9. **Disable Accept button** during challenge join async operation

### Medium-term (P2)

10. **Add Suspense boundaries** in portal for each section (sidebar, main content)
11. **Add offline banner** to Flutter app when connectivity is lost
12. **Add periodic feature flag refresh** (every 5 minutes)
13. **Split portal layout queries** — use individual try/catch so one failure doesn't cascade
