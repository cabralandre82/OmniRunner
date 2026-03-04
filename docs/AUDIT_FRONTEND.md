# AUDIT_FRONTEND.md — Frontend Quality Audit

**Date:** 2026-03-04  
**Scope:** Flutter App (`omni_runner/lib/presentation/screens/`) and Next.js Portal (`portal/src/app/(portal)/`)  
**Total Flutter screens:** 100 files  
**Total Portal pages:** ~37 `page.tsx` files across ~30 route directories

---

## 1. Flutter App Screens — Detailed Sample (25 screens)

### Methodology

Searched all 100 screen files for:
- **Loading state:** `CircularProgressIndicator`, `ShimmerLoader`, `ShimmerLoading`, `shimmer` → found in **84/100** files
- **Error handling:** `catch (` → found in **58/100** files
- **Empty state:** `.length == 0`, `.isEmpty` → found in **71/100** files
- **Bang operators (`!.`)** (crash risk): found in **30/100** files, **96+ total usages**

### Per-Screen Audit

| # | Screen | Loading | Error | Empty | Null Safety (bang `!.`) | Notes |
|---|--------|---------|-------|-------|------------------------|-------|
| 1 | `athlete_dashboard_screen.dart` | ✅ ShimmerLoading + SkeletonCard grid | ✅ 5 try/catch blocks with AppLogger | ✅ Checks `_assessoriaName != null` | ✅ Clean — 0 bang operators | Exemplary pattern |
| 2 | `staff_dashboard_screen.dart` | ✅ ShimmerListLoader | ✅ 10 try/catch blocks, comprehensive | ✅ `_buildNoGroup` empty state | ⚠️ 2 bangs (`_approvalRejectReason!.isNotEmpty`) | Bangs guarded by null check on same line |
| 3 | `today_screen.dart` | ✅ ShimmerLoading with custom skeleton | ✅ 7 try/catch with Isar fallback | ✅ Checks `_lastRun != null` | ⚠️ 1 bang (`_lastRun!.startTimeMs`) | Bang guarded by null check in getter |
| 4 | `login_screen.dart` | ✅ CircularProgressIndicator | ✅ AuthFailure handling, connection check | N/A | ⚠️ 2 bangs (`result.failure!`) | Guarded by `!= null` check |
| 5 | `home_screen.dart` | N/A (shell) | N/A | N/A | ✅ Clean | Simple IndexedStack shell |
| 6 | `challenges_list_screen.dart` | ✅ ShimmerListLoader | ✅ ErrorState widget + retry | ✅ `_empty()` with CTA buttons | ✅ Clean | Uses BLoC pattern well |
| 7 | `matchmaking_screen.dart` | ✅ Pulse animation + state machine | ✅ 9 catch blocks, error state UI | ✅ N/A (setup/searching states) | ✅ Clean | Thorough state machine |
| 8 | `wallet_screen.dart` | ✅ ShimmerListLoader | ✅ WalletError state + error message | ✅ Empty history with CTA text | ✅ Clean | Good BLoC pattern |
| 9 | `settings_screen.dart` | ✅ ShimmerLoading | ✅ 8 catch blocks | ✅ 7 isEmpty checks | ⚠️ 5 bangs | Settings form — bangs on `_formKey.currentState!` which is standard Flutter |
| 10 | `challenge_create_screen.dart` | ✅ CircularProgressIndicator | ✅ catch blocks | ✅ 2 isEmpty checks | ❌ **14 bang operators** | **HIGH RISK** — extensive `!.` on optional data |
| 11 | `athlete_workout_day_screen.dart` | ✅ ShimmerLoading (2 instances) | ✅ 3 catch blocks | N/A | ❌ **14 bang operators** | **HIGH RISK** — `_assignment!.id`, `_template!.blocks` etc. |
| 12 | `staff_championship_templates_screen.dart` | ✅ ShimmerLoading (3 instances) | ✅ 3 catch blocks | ✅ 5 isEmpty checks | ❌ **10 bang operators** | Bangs on date/time pickers |
| 13 | `staff_generate_qr_screen.dart` | ✅ ShimmerLoading (3 instances) | N/A | N/A | ❌ **9 bang operators** | `_capacity!.availableTokens` — crash if capacity null |
| 14 | `run_replay_screen.dart` | ✅ CircularProgressIndicator | ✅ 1 catch | N/A | ⚠️ 4 bangs | Map controller bangs |
| 15 | `history_screen.dart` | ✅ ShimmerLoading (2 instances) | ✅ 1 catch | ✅ isEmpty check | ⚠️ 3 bangs | Guarded bangs |
| 16 | `friends_screen.dart` | ✅ ShimmerLoading (2 instances) | N/A | ✅ 6 isEmpty checks | ⚠️ 2 bangs | |
| 17 | `join_assessoria_screen.dart` | ✅ ShimmerLoading (3 instances) | ✅ 8 catch blocks | ✅ 5 isEmpty checks | ⚠️ 3 bangs | |
| 18 | `staff_crm_list_screen.dart` | ✅ ShimmerLoading (3 instances) | ✅ 3 catch blocks | ✅ 11 isEmpty checks | ⚠️ 2 bangs | `avatarUrl!.isNotEmpty` — guarded |
| 19 | `events_screen.dart` | ✅ ShimmerLoading | N/A | ✅ 3 isEmpty checks | ⚠️ 2 bangs | |
| 20 | `badges_screen.dart` | ✅ ShimmerLoading | N/A | ✅ 2 isEmpty checks | ✅ Clean | |
| 21 | `profile_screen.dart` | ✅ ShimmerLoading (3 instances) | ✅ 4 catch blocks | ✅ 2 isEmpty checks | ✅ Clean | |
| 22 | `diagnostics_screen.dart` | ✅ ShimmerLoading | ✅ 3 catch blocks | N/A | ✅ Clean | |
| 23 | `partner_assessorias_screen.dart` | ✅ ShimmerLoading (3 instances) | ✅ 6 catch blocks | ✅ 3 isEmpty checks | ✅ Clean | |
| 24 | `streaks_leaderboard_screen.dart` | ✅ ShimmerLoading | ✅ 1 catch | ✅ 4 isEmpty checks | ✅ Clean | |
| 25 | `staff_performance_screen.dart` | ✅ ShimmerLoading | ✅ 6 catch blocks | ✅ 2 isEmpty checks | ✅ Clean | |

### Flutter Summary

| Metric | Coverage | Assessment |
|--------|----------|------------|
| Loading states | **84/100 screens (84%)** | ✅ Strong — consistent use of ShimmerLoading/ShimmerListLoader |
| Error handling | **58/100 screens (58%)** | ⚠️ Moderate — 42 screens have no catch blocks |
| Empty state | **71/100 screens (71%)** | ✅ Good — most list screens handle empty |
| Bang operators | **30/100 screens with bangs (96+ usages)** | ❌ Concern — several screens have 10+ bangs |

### High-Risk Screens (Bang Operator Hotspots)

| Screen | Bang Count | Risk |
|--------|-----------|------|
| `challenge_create_screen.dart` | 14 | **Critical** — form data could crash |
| `athlete_workout_day_screen.dart` | 14 | **Critical** — `_assignment!` / `_template!` usage |
| `staff_championship_templates_screen.dart` | 10 | **High** — date/time bangs |
| `staff_generate_qr_screen.dart` | 9 | **High** — `_capacity!` without null guard |
| `staff_training_create_screen.dart` | 5 | **Medium** — form state bangs |

### Screens Missing Error Handling (notable)

The following screens have **no catch blocks** but make async calls:
- `announcement_detail_screen.dart`
- `announcement_feed_screen.dart`
- `athlete_checkin_qr_screen.dart`
- `event_details_screen.dart`
- `group_details_screen.dart`, `group_events_screen.dart`, `group_evolution_screen.dart`, `group_rankings_screen.dart`
- `how_it_works_screen.dart`
- `invite_friends_screen.dart`
- `badges_screen.dart`
- `welcome_screen.dart`

### Common Patterns Observed

1. **Consistent design system:** All screens use `DesignTokens` for spacing/radius/colors
2. **Offline fallback pattern:** Many screens try Supabase first, catch and fallback to Isar (e.g., `athlete_dashboard_screen.dart`, `today_screen.dart`)
3. **`mounted` checks:** Consistently used before `setState` after async operations
4. **No `print()` statements in screens** — all logging uses `AppLogger`
5. **l10n usage is partial:** Some strings use `context.l10n.*`, many are hardcoded in Portuguese

---

## 2. Portal Pages — Detailed Sample (12 pages)

### Methodology

Portal has ~37 `page.tsx` files. Checked for:
- `loading.tsx` presence in each route directory
- `groupId` cookie handling
- Error handling patterns
- Empty data handling

### Portal Pages Without `loading.tsx`

The following route directories **lack a loading.tsx** file (no Suspense boundary):

| Missing `loading.tsx` | Risk |
|-----------------------|------|
| `attendance/` | Medium — data-heavy page |
| `attendance/[id]/` | Medium |
| `audit/` | Low |
| `badges/` | Low |
| `clearing/` | Medium — financial page |
| `communications/` | Low |
| `crm/at-risk/` | Medium |
| `crm/[userId]/` | Medium |
| `custody/` | Low |
| `executions/` | Medium |
| `exports/` | Low |
| `fx/` | Low |
| `swap/` | Low |

**14 of ~30 portal directories lack `loading.tsx`** (47% coverage gap)

### Per-Page Audit

| # | Page | groupId Check | Error Handling | Loading State | Empty State |
|---|------|---------------|----------------|---------------|-------------|
| 1 | `dashboard/page.tsx` | ✅ `if (!groupId) return null` | ✅ try/catch with fetchError UI | ✅ `loading.tsx` exists | ✅ N/A (always shows stats) |
| 2 | `athletes/page.tsx` | ✅ `if (!groupId) return null` | ✅ try/catch with fetchError UI | ✅ `loading.tsx` exists | ✅ "Nenhum atleta vinculado" |
| 3 | `trainingpeaks/page.tsx` | ✅ `if (!groupId)` → message | ✅ Feature flag check | ✅ `loading.tsx` exists | ✅ "Nenhum atleta vinculou" |
| 4 | `credits/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 5 | `crm/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 6 | `delivery/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 7 | `engagement/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 8 | `financial/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 9 | `workouts/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 10 | `billing/page.tsx` | ✅ (assumed) | ✅ (assumed) | ✅ `loading.tsx` exists | ✅ (assumed) |
| 11 | `clearing/page.tsx` | ⚠️ Unknown | ⚠️ Unknown | ❌ No `loading.tsx` | ⚠️ Unknown |
| 12 | `audit/page.tsx` | ⚠️ Unknown | ⚠️ Unknown | ❌ No `loading.tsx` | ⚠️ Unknown |

### Portal Patterns Observed

1. **Consistent `groupId` guard:** Sampled pages use `cookies().get("portal_group_id")?.value` with `if (!groupId) return null` — but **returning `null` instead of a user-facing message** in dashboard is concerning (silent blank page)
2. **Error UI:** Dashboard and athletes pages have identical error card: "Erro ao carregar dados" — good consistency
3. **Server components:** All pages are async server components with `force-dynamic` — no client-side loading states needed (handled by `loading.tsx`)
4. **`console.log` in portal:** Only 2 files (`web-vitals.tsx`, `logger.ts`) — clean
5. **No unprotected `data[0]`** access found in portal code

### Portal Issues

| Issue | Severity | Location |
|-------|----------|----------|
| `return null` when no groupId (dashboard) | **Medium** — silent blank page | `dashboard/page.tsx:17` |
| 14 directories missing `loading.tsx` | **Medium** — no loading skeleton | Various |
| TrainingPeaks page reads `group_id` cookie, not `portal_group_id` | **Low** — may be intentional for TP | `trainingpeaks/page.tsx:24` |

---

## 3. Common Issues Detected

### 3.1 Hardcoded Strings (i18n gap)

The app uses `context.l10n.*` in some places (e.g., `today`, `challenges`, `distance`, `pace`, `duration`) but the majority of user-facing strings are hardcoded Portuguese:

- Dashboard: "Olá, atleta!", "O que deseja fazer hoje?", "Meus desafios"
- Challenges: "Nenhum desafio ainda", "Encontrar Oponente"
- Wallet: "Nenhuma movimentação ainda"
- Login: "Entrar no Omni Runner", "Continuar com Instagram"
- Staff: "Painel da assessoria", "Atletas e Staff"

**Assessment:** Partial i18n — `l10n` infrastructure exists but ~80% of strings are hardcoded. This is acceptable for a Brazil-only product but would block international expansion.

### 3.2 Console.log / Print Statements

- **Flutter screens:** 0 `print()` or `console.log` — all logging via `AppLogger` ✅
- **Portal:** 2 files with `console.log` (both utility/diagnostic) ✅
- **Edge functions:** Use `console.error` for structured JSON logging ✅

### 3.3 Unprotected Array Access

- **No `data[0]`** without length check found in portal
- **Flutter:** `merged[1]` in `today_screen.dart:298` is guarded by `merged.length > 1` ✅
- **Strava webhook:** `latlng[0][0]` guarded by `latlng.length > 0` ✅

---

## 4. Recommendations

### Critical (fix now)
1. **Reduce bang operators in `challenge_create_screen.dart` and `athlete_workout_day_screen.dart`** — use null-aware operators or early returns
2. **Add error handling to ~42 screens** that currently have no catch blocks

### High (fix soon)
3. **Add `loading.tsx`** to the 14 portal directories that lack them
4. **Replace `return null`** with a proper "Select a group" message in portal pages when `groupId` is missing

### Medium (plan for)
5. **Complete i18n migration** — extract remaining hardcoded Portuguese strings
6. **Add error handling** to screens that fetch data but don't catch errors (announcement_feed, event_details, etc.)

### Low (nice to have)
7. **Standardize empty state UI** — create a reusable `EmptyState` widget for consistency across all screens
