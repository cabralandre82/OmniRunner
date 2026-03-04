# USERZERO_04 — Gaps, Failures, and "Half-Built" Features

> **Auditor:** Principal QA gaps analysis
> **Date:** 2026-03-04
> **Scope:** Flutter app (`omni_runner/`), Next.js portal (`portal/`), Supabase backend

---

## POST-FIX STATUS

Todos os 42 gaps/failures identificados foram corrigidos. Cada item abaixo foi resolvido no commit de correção.

---

## Summary

| Severity | Count | Meaning |
|----------|-------|---------|
| **P0**   | 4     | Blocker — feature cannot be used |
| **P1**   | 11    | Trust-breaker — serious error/ambiguity |
| **P2**   | 16    | Friction — inefficient or confusing |
| **P3**   | 11    | Polish — rough edges |
| **Total**| **42**| |

---

## Issues by Area

### App — Dead-End / Unreachable Screens

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-001 | `athlete_my_status_screen.dart` is a **full duplicate** of `staff_workout_assign_screen.dart`. It declares a class named `StaffWorkoutAssignScreen` (identical class name as the other file), is tagged as unused, and is **never navigated to** from any screen. Dead code creating confusion. | `omni_runner/lib/presentation/screens/athlete_my_status_screen.dart:17-19` | P2 | Dead code |
| G-002 | `staff_workout_assign_screen.dart` is tagged TODO as "appears to be unused". No Navigator push to this screen exists in any file — it's built but unreachable. | `omni_runner/lib/presentation/screens/staff_workout_assign_screen.dart:18` | P1 | Dead-end screen |
| G-003 | `athlete_workout_day_screen.dart` is tagged TODO as "appears to be unused". While it imports `AthleteDeliveryScreen` and has a delivery badge, **no navigation anywhere pushes to it**. The athlete's "workout of the day" feature is fully built but orphaned. | `omni_runner/lib/presentation/screens/athlete_workout_day_screen.dart:17` | P0 | Blocker — fully built feature is inaccessible |
| G-004 | `_ComingSoonTile` widget is defined (`more_screen.dart:475`) but **never instantiated** anywhere in the codebase. It was likely intended for upcoming features in the More screen but those menu items were never added. | `omni_runner/lib/presentation/screens/more_screen.dart:475` | P3 | Dead code |

### App — Incomplete / Half-Built Features

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-005 | **Ghost comparison chart is a placeholder.** The `GhostComparisonCard` shows a grey box with text "Gráfico de pace em breve" instead of an actual pace-over-distance chart. Users see a visual dead-end. | `omni_runner/lib/presentation/widgets/ghost_comparison_card.dart:74-87` | P2 | Half-built |
| G-006 | **Shadow Racing button is a dead-end.** In park_screen.dart, the "Desafiar" button on segment records just shows a SnackBar "Shadow racing em breve!" — the feature is wired in UI but not implemented. | `omni_runner/lib/features/parks/presentation/park_screen.dart:795-799` | P2 | Half-built |
| G-007 | **Social Run Detection returns hardcoded empty list.** `_detectSocialRuns()` is explicitly a placeholder with comment "in production, the backend detects overlapping runs". The Community tab renders the widget but it will always be empty. | `omni_runner/lib/features/parks/presentation/park_screen.dart:402-406` | P1 | Half-built |
| G-008 | **Challenge result sharing is a dead-end.** The "Enviar" (share) button on `ChallengeResultScreen` shows "Compartilhamento em breve!" SnackBar instead of actually sharing. | `omni_runner/lib/presentation/screens/challenge_result_screen.dart:968-973` | P2 | Half-built |
| G-009 | **Export screen "Connect Strava" button does nothing.** After exporting a file, the Strava education sheet's "Conectar Strava" button pops the sheet but doesn't navigate anywhere. The comment says "Will be wired in Sprint 14.5". | `omni_runner/lib/features/integrations_export/presentation/export_screen.dart:174-177` | P1 | Placeholder navigation |
| G-010 | **Staff athlete alerts tab shows placeholder.** The alerts tab in `staff_athlete_profile_screen.dart` just shows an icon and "Alertas do PASSO 05 — em breve" — no real alert data, no timeline for completion. | `omni_runner/lib/presentation/screens/staff_athlete_profile_screen.dart:939` | P2 | Half-built |

### App — Missing Error Handling / UX Gaps

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-011 | **Support screen hides load errors silently.** When the ticket list fails to load, the catch block just logs a warning and sets `_loading = false`, leaving the user staring at an empty screen with no error message and no retry. | `omni_runner/lib/presentation/screens/support_screen.dart:46-49` | P1 | Missing error state |
| G-012 | **Athlete evolution screen has no retry on error.** The `AthleteEvolutionInitial` state shows "Carregando evolução..." text with no spinner, and the error state doesn't appear to have a retry mechanism in the BLoC pattern. | `omni_runner/lib/presentation/screens/athlete_evolution_screen.dart:32-33` | P2 | Missing retry |
| G-013 | **League screen loses error details.** When the league load fails, error state sets `_season = null` and `_ranking = []` but the error state UI falls through to the "no season" empty state. Users can't distinguish between "no season exists" and "network error". | `omni_runner/lib/presentation/screens/league_screen.dart:76-80` | P1 | Error vs empty ambiguity |

### App — Feature Flag Gaps

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-014 | **Only 1 feature flag used in the entire app.** The `FeatureFlagService` supports rollout-based flags, but only `trainingpeaks_enabled` is checked (in 3 files). Other features that are clearly "half-built" or "coming soon" don't use feature flags at all — they're just hardcoded dead-ends. | `omni_runner/lib/presentation/screens/staff_workout_assign_screen.dart:135`, `athlete_device_link_screen.dart:37`, `athlete_my_status_screen.dart:134` | P2 | Inconsistent gating |
| G-015 | **Feature flag stale cache risk acknowledged but not mitigated.** The `FeatureFlagService` documents a "KNOWN RISK (m13)" that flags can go stale mid-operation. No periodic refresh timer is set up, and no destructive operations re-check server-side as recommended. | `omni_runner/lib/core/config/feature_flags.dart:50-54` | P1 | Risk acknowledged but unmitigated |

### App — Mock/Stub Fallbacks

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-016 | **Mock mode silently degrades to fake data.** When Supabase init fails, the app silently falls back to `MockAuthDataSource`, `MockProfileDataSource`, `StubTokenIntentRepo`, and `StubSwitchAssessoriaRepo`. The user sees a functional-looking app with fake data and no warning. The mock auth generates a local UUID — any actions taken appear to succeed but aren't persisted. | `omni_runner/lib/core/di/auth_module.dart:25-28`, `data_module.dart:290-305` | P0 | Silent data loss |
| G-017 | **StubTokenIntentRepo simulates real success.** When in mock mode, QR code token intent creation returns a fake UUID that looks valid. The athlete could scan it, see "success", but nothing is actually recorded. | `omni_runner/lib/data/repositories_impl/stub_token_intent_repo.dart:19-31` | P0 | Trust-breaker — fake transactions |

---

### Portal — Dead-Ends and Bugs

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-018 | **TrainingPeaks page reads wrong cookie name.** All other portal pages read `portal_group_id` from cookies, but the TrainingPeaks page reads `group_id` (without the `portal_` prefix). This means the page will **always show "Selecione um grupo primeiro"** even for authenticated users with a valid group. | `portal/src/app/(portal)/trainingpeaks/page.tsx:24` vs `portal/src/app/(portal)/layout.tsx:29` | P0 | Blocker — page never loads data |
| G-019 | **33 portal pages return `null` on missing groupId** — the user sees a completely blank page with no error message, no redirect, no explanation. The layout handles auth redirect but not the groupId-missing case at page level. | `portal/src/app/(portal)/dashboard/page.tsx:17`, `clearing/page.tsx:34`, `custody/page.tsx:14`, and 30+ others | P1 | Silent blank page |
| G-020 | **"Marcar presença manualmente" button is permanently disabled.** The attendance detail page has a button that is `disabled` with `title="Em breve"`. Users see the button but can never click it. No timeline or feature flag controls this. | `portal/src/app/(portal)/attendance/[id]/page.tsx:135-139` | P2 | Half-built |
| G-021 | **Engagement page has no try/catch.** The page makes 5 parallel Supabase queries with no error handling. If any query fails, the entire page crashes to the generic `error.tsx` boundary with no specific message. | `portal/src/app/(portal)/engagement/page.tsx:54-85` | P1 | Missing error handling |
| G-022 | **Portal error page displays in English** while the rest of the portal is in Portuguese. The `error.tsx` says "Something went wrong" and "Try Again" instead of matching the PT-BR language used everywhere else. | `portal/src/app/(portal)/error.tsx:12-24` | P2 | Language inconsistency |

### Portal — Missing Loading States

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-023 | **Several portal pages lack dedicated `loading.tsx` files.** While 39 pages have loading states, the following portal sections are missing: `/dashboard`, `/announcements/page.tsx` base level (though nested routes have them), `/financial/page.tsx` base. The global `(portal)/loading.tsx` catches these but may not match the expected layout. | Comparison of page.tsx vs loading.tsx glob results | P3 | Missing loading state |

---

### Supabase — Edge Function Gaps

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-024 | **No `generate-wrapped` or `generate-running-dna` edge functions are missing.** They exist (57 EFs total), but the app's `WrappedScreen` and `RunningDnaScreen` call them without any offline fallback. If the EF is slow or down, the user sees a spinner indefinitely with no timeout. | `omni_runner/lib/presentation/screens/wrapped_screen.dart:68-74`, `running_dna_screen.dart:48-51` | P2 | Missing timeout/offline fallback |
| G-025 | **Legacy billing feature flag creates invisible redirect loop.** When `legacy_billing_enabled` is false (expected normal state), `/billing` and `/credits` pages silently redirect to `/custody`. But the sidebar still shows "Financeiro" which links to `/financial`, creating confusion about where billing actually lives. | `portal/src/app/(portal)/billing/page.tsx:47-51`, `credits/page.tsx:23-27` | P2 | Confusing navigation |

---

### Cross-Product Gaps (App ↔ Portal)

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-026 | **Workout delivery exists in both but with no portal-side "publish" action visible in sidebar.** The portal has a `/delivery` page and the app has `AthleteDeliveryScreen`, but the full flow depends on `AthleteWorkoutDayScreen` which is unreachable (G-003). The delivery flow is half-connected. | `portal/src/components/sidebar.tsx:35` (delivery link exists), `omni_runner/lib/presentation/screens/athlete_workout_day_screen.dart:17` | P1 | Flow gap |
| G-027 | **Support ticket flow has no portal notification.** The app creates tickets via `support_tickets` table, and the portal platform admin can view them. But there's no real-time notification, webhook, or polling — support staff must manually check the page. | `omni_runner/lib/presentation/screens/support_screen.dart:67-74`, `portal/src/app/platform/support/page.tsx` | P2 | Missing notification |
| G-028 | **Verification flow: portal can evaluate, app can request — but no push notification bridges them.** The app has `AthleteVerificationScreen` and the portal has `/verification` page, but when staff evaluates a verification, the athlete isn't notified in real-time. They must pull-to-refresh. | `portal/src/app/(portal)/verification/page.tsx`, `omni_runner/lib/presentation/screens/athlete_verification_screen.dart` | P2 | Missing notification |
| G-029 | **Championships exist in app but have no portal page.** The app has `athlete_championships_screen.dart`, `athlete_championship_ranking_screen.dart`, and multiple `champ-*` edge functions, but the portal sidebar has no "Championships" link. Staff manage championships only through dedicated `staff_championship_manage_screen.dart` in the app, not through the web portal. | Sidebar nav items in `portal/src/components/sidebar.tsx:14-39` — no championship entry | P2 | Feature parity gap |
| G-030 | **Matchmaking exists only in app.** The `MatchmakingScreen` and `matchmake` edge function exist, but there's no portal visibility into matchmaking queues, match outcomes, or dispute resolution for automated matches. | `omni_runner/lib/presentation/screens/matchmaking_screen.dart`, `supabase/functions/matchmake/index.ts` | P3 | Feature parity gap |
| G-031 | **League management: portal has admin page, app has view — but different scopes.** Portal has `/platform/liga/page.tsx` (platform-level admin), while the app has `league_screen.dart` (user-facing view). There's no assessoria-level league management in the portal. | `portal/src/app/platform/liga/page.tsx`, `omni_runner/lib/presentation/screens/league_screen.dart` | P3 | Scope mismatch |
| G-032 | **Badges: portal creates, app displays — but no preview.** The portal has a badge creation form (`badge-form.tsx`), and the app has `badges_screen.dart`. But there's no preview of what the badge will look like in the app before publishing. | `portal/src/app/platform/conquistas/badge-form.tsx`, `omni_runner/lib/presentation/screens/badges_screen.dart` | P3 | Missing preview |

---

### Confusing UX

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-033 | **Portal sidebar has 25+ items** for admin_master role with no grouping, collapsible sections, or search. Finding a specific page requires scrolling through a flat list. | `portal/src/components/sidebar.tsx:14-39` (25 NAV_ITEMS for admin_master) | P2 | Navigation overload |
| G-034 | **App ProgressHub has 11 navigation tiles** in a single flat list. "Nível e XP", "Retrospectiva", "DNA de Corredor", "Evolução", "Desafios", "Missões", "Badges", "Ranking", "Sequências", "Liga", "OmniCoins" — no grouping, no contextual help. | `omni_runner/lib/presentation/screens/progress_hub_screen.dart:54-80` | P2 | Information overload |
| G-035 | **Multiple Supabase client instantiation patterns in portal.** Some pages use `createClient()` (server), some use `createServiceClient()` (service), some use `createAdminClient()` (admin). The distinction isn't clear and `support/page.tsx` uses admin client for a page that should probably use service client. | `portal/src/app/platform/support/page.tsx:1` (admin), `portal/src/app/(portal)/dashboard/page.tsx:3-4` (both server + service) | P3 | Developer confusion |

---

### Data Integrity / Trust Issues

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-036 | **Diagnostics screen exposes internal state** (backend mode, Supabase connection status, auth state) to the user. In mock mode, it shows "mock" backend which could confuse end users. | `omni_runner/lib/presentation/screens/diagnostics_screen.dart:38-39` | P3 | Information leak |
| G-037 | **`athlete_my_status_screen.dart` exposes raw error to user.** Error messages use `'Erro ao carregar dados: $e'` and `'Erro ao atribuir: $e'` which can leak exception details (stack traces, SQL errors). The duplicated `staff_workout_assign_screen.dart` correctly uses `ErrorMessages.humanize(e)` instead. | `omni_runner/lib/presentation/screens/athlete_my_status_screen.dart:84,151` vs `staff_workout_assign_screen.dart:85,152` | P1 | Raw error exposure |
| G-038 | **Staff credits screen tells users to use the portal** with "Em breve você poderá gerenciar créditos e equipe pelo navegador." — this is already possible via `/credits` and `/custody` pages. Misleading message. | `omni_runner/lib/presentation/screens/staff_credits_screen.dart:257` | P3 | Stale messaging |

---

### Navigation Depth

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-039 | **Accessing workout assignment requires 5+ taps.** Path: Home → More → Minha Assessoria → Group Details → (no route exists). The `StaffWorkoutAssignScreen` is unreachable. Even if wired, the path would be: Staff Dashboard → (navigate to assign) — which requires the screen to be linked from staff dashboard or workout templates. | Navigation analysis across `more_screen.dart`, `staff_dashboard_screen.dart` | P2 | Deep navigation |
| G-040 | **Accessing streak leaderboard: 4 taps.** Home → Progress Hub → Sequências → Streaks Leaderboard. For a social/engagement feature, this is buried deep. | `progress_hub_screen.dart` → `streaks_leaderboard_screen.dart` | P3 | Buried feature |

---

### Missing Edge Functions

| ID | Description | Evidence | Severity | Category |
|----|-------------|----------|----------|----------|
| G-041 | **No `fn_friends_activity_feed` RPC exists as an edge function** — it's called as an RPC in `friends_activity_feed_screen.dart`, meaning it must be a Postgres function. If the function doesn't exist in migrations, the friends feed crashes. | `omni_runner/lib/presentation/screens/friends_activity_feed_screen.dart:43-45` | P2 | Dependency risk |
| G-042 | **No `fn_tp_sync_status` RPC validation.** The portal TrainingPeaks page calls `fn_tp_sync_status` RPC but the result is accessed with `syncResult?.ok` pattern — if the RPC doesn't return a `{ok, data}` shape, the page silently shows empty. | `portal/src/app/(portal)/trainingpeaks/page.tsx:35-39` | P2 | Fragile contract |

---

## Priority Action Items

### Immediate (P0 — Blockers)

1. **G-003**: Wire `AthleteWorkoutDayScreen` into navigation (likely from Today screen or More screen)
2. **G-016 / G-017**: Add a visible banner or toast in mock mode so users know data won't persist
3. **G-018**: Fix TrainingPeaks page cookie name from `group_id` to `portal_group_id`

### Next Sprint (P1 — Trust-Breakers)

4. **G-002**: Either wire `StaffWorkoutAssignScreen` into staff dashboard or remove it
5. **G-007**: Implement social run detection backend or remove the placeholder from UI
6. **G-009**: Wire the "Conectar Strava" button to the actual Strava settings screen
7. **G-011**: Add error state with retry to Support screen
8. **G-013**: Distinguish error vs empty state in League screen
9. **G-015**: Add periodic feature flag refresh (e.g., every 15 minutes)
10. **G-019**: Replace `return null` with redirect or error UI in portal pages
11. **G-021**: Add try/catch with meaningful error UI to Engagement page
12. **G-026**: Complete the workout delivery flow end-to-end
13. **G-037**: Replace raw `$e` error messages with `ErrorMessages.humanize(e)`

### Cleanup (P2/P3)

14. **G-001**: Delete the duplicate `athlete_my_status_screen.dart`
15. **G-005**: Implement the pace chart or remove the placeholder
16. **G-022**: Translate portal error page to PT-BR
17. **G-033**: Group sidebar items into collapsible sections
