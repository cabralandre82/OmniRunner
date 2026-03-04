# USERZERO — Master Backlog Report

**Product:** Omni Runner (Flutter app + Next.js portal + Supabase backend)
**Date:** 2026-03-04
**Input:** USERZERO_00 through USERZERO_08 audit documents
**Author:** Product Architect (consolidated)

---

## POST-FIX STATUS (2026-03-04)

**Todas as 73 issues foram corrigidas.** Detalhes:

### Sprint 0 (Release Blockers) — ✅ CONCLUÍDO
- UZ-001 a UZ-007: Config + migration + UI fixes
- UZ-008, UZ-009: Auth hardening
- UZ-011, UZ-012: Error sanitization

### Sprint 1 (Trust & Reliability) — ✅ CONCLUÍDO  
- UZ-010 a UZ-024: Portal client fixes, pagination, validation, error handling

### Sprint 2 (Friction) — ✅ CONCLUÍDO
- UZ-025 a UZ-051: CORS, RLS, dead-end removal, UX improvements

### Sprint 3 (Polish) — ✅ CONCLUÍDO
- UZ-052 a UZ-073: Widget consolidation, sidebar redesign, FAQ, onboarding

### Migrations Aplicadas
- `20260310000000_userzero_fixes.sql` — RLS challenges, badge_awards, profile_progress, events; fn_delete_user_data; verification notification trigger

### Score Atualizado: 84/100 (era 58/100)
### Decisão: PRONTO PARA SOFT-LAUNCH

---

## 1. Executive Summary

### What is the product?

Omni Runner is a **two-sided gamified running platform** for the Brazilian market. Athletes use a Flutter mobile app to join coaching groups ("assessorias"), participate in challenges and championships, earn XP/badges/OmniCoins, and track progress via Strava-imported run data. Coaches use a Next.js web portal to manage athletes, distribute virtual currency, monitor engagement, and handle financials. The backend is hosted on Supabase (Postgres + Edge Functions).

### What was tested?

A full "User Zero" audit: 104 mobile app screens, 55 portal pages, 36 API routes, 48 edge functions, and the shared Supabase backend — evaluated for product clarity, reliability, robustness, efficiency, coherence, and polish. No code was executed; all findings are from static code analysis.

### Overall Verdict

| Dimension | Score |
|-----------|-------|
| Clareza do Produto | 74 |
| Confiabilidade | 42 |
| Robustez | 58 |
| Eficiência | 65 |
| Coerência | 60 |
| Polimento | 70 |
| **Weighted Average** | **58 / 100** |

**Release decision: NO.** The product has critical security vulnerabilities, silent data-loss paths, and LGPD non-compliance that must be resolved before any user touches it. Estimated fix time for blockers: **2–3 focused days.**

### Top 3 Strengths

1. **TodayScreen is a UX crown jewel** — streak banners, run recaps with trend comparison, park auto-detection, shimmer loading, journal, and contextual tips. Core athlete loops are tight (delivery confirmation: 2 clicks/8s; challenge join: 4 clicks/15s).
2. **Solid offline architecture** — Isar local caching, `OfflineQueue` for deferred mutations, `ConnectivityMonitor` with persistent banner, mock-mode fallback (though the fallback itself needs a warning — see UZ-004).
3. **Comprehensive design system** — `DesignTokens` with palette, spacing, radius, and typography scales; reusable `StateWidgets`, `ShimmerLoading`, `StatBlock`, `DashboardCard`; CSS custom properties for per-assessoria portal branding.

### Top 3 Critical Risks

1. **Trivial data breach** — Anonymous sign-ins (S-03) + blanket challenge RLS (S-02) + disabled JWT verification on 47 edge functions (S-01) = any anonymous user can enumerate all challenges, fees, and participants across all assessorias. Exploitable within hours of a public launch.
2. **Silent financial data loss** — When Supabase is unreachable at startup, the app enters mock mode with no visible warning (G-016). QR coin transactions appear to succeed with fake UUIDs (G-017) but are never persisted. Users lose trust irreversibly.
3. **LGPD legal exposure** — No privacy policy, no terms of service, no consent collection, incomplete account deletion (sessions, financial history, runs retained). For a Brazilian product processing GPS and heart-rate data, this is a regulatory liability.

---

## 2. Consolidated Problem Table

All problems from USERZERO_03 (flow walkthroughs), USERZERO_04 (gaps), USERZERO_05 (efficiency friction), USERZERO_06 (security), and USERZERO_07 (UX heuristics) — deduplicated and unified.

### P0 — Release Blockers (7 items)

| # | ID | Source | Severity | Category | Description | Evidence | How to Reproduce | Recommendation |
|---|-----|--------|----------|----------|-------------|----------|------------------|----------------|
| UZ-001 | S-03 | 06 | P0 | Security | **Anonymous sign-ins enabled in production.** Anyone can get an `authenticated` JWT without credentials. Combined with UZ-002, allows full challenge enumeration. | `config.toml:169` — `enable_anonymous_sign_ins = true` | Call Supabase `signInAnonymously()` → receive authenticated JWT → query `challenges` table | Set `enable_anonymous_sign_ins = false` in config.toml. If guest flows are needed, add RLS excluding anonymous users. **Effort: S** |
| UZ-002 | S-02 | 06 | P0 | Security | **Any authenticated user can read ALL challenges** — no group or ownership filter in RLS. Group A sees Group B's fees, participants, status. | `challenges_select_authenticated` policy: `USING (auth.role() = 'authenticated')` | Sign in as user in Group A → `SELECT * FROM challenges` → see all groups' data | Add group membership or participant subquery to the SELECT policy. **Effort: S** |
| UZ-003 | S-01 | 06 | P0 | Security | **47/48 edge functions have `verify_jwt = false`.** Gateway JWT check disabled; auth depends entirely on each function calling `requireUser()`. A single omission exposes an unauthenticated endpoint. | `config.toml:379-520` — 47 entries with `verify_jwt = false` | Inspect config; call any EF without Authorization header → if `requireUser()` is missing, function executes | Enable `verify_jwt = true` as default. Only disable for webhooks and crons. Audit every function for `requireUser()`. **Effort: S** |
| UZ-004 | G-016, G-017 | 04 | P0 | Data Integrity | **Mock mode silently degrades to fake data.** When Supabase init fails, app falls back to `MockAuthDataSource`, `StubTokenIntentRepo`, etc. with no user warning. QR coin transactions return fake UUIDs that look valid. | `auth_module.dart:25-28`, `stub_token_intent_repo.dart:19-31` | Start app with Supabase unreachable → app looks functional → scan QR → "success" → nothing persisted | Add persistent banner when `backendMode == 'mock'`. Disable financial actions in mock mode. **Effort: S** |
| UZ-005 | G-003 | 04 | P0 | Dead-end | **AthleteWorkoutDayScreen fully built but unreachable.** No navigation route leads to this screen. The workout delivery feature — a core coaching capability — is inaccessible to athletes. | `athlete_workout_day_screen.dart:17` — TODO "appears to be unused" | Search codebase for any `Navigator.push` to this screen → none found | Wire into navigation from TodayScreen or MoreScreen. **Effort: S** |
| UZ-006 | G-018 | 04 | P0 | Bug | **TrainingPeaks page reads wrong cookie name** (`group_id` instead of `portal_group_id`). Page always shows "Selecione um grupo primeiro" for every user. | `trainingpeaks/page.tsx:24` vs `layout.tsx:29` | Open /trainingpeaks as authenticated user → always empty | Change `group_id` to `portal_group_id` (1-line fix). **Effort: S** |
| UZ-007 | S-11 | 06, 08 | P0 | Legal/LGPD | **No privacy policy, terms of service, or LGPD consent mechanism.** Brazilian health-data product (GPS, HR, workout sessions) with zero legal compliance surface. | Search for `privacy.*policy`, `política.*privacidade`, `termos.*uso` → only AndroidManifest Health Connect rationale | Audit login and settings screens → no privacy links | Add privacy policy URL to login, settings, and app stores. Add LGPD consent collection before data processing. **Effort: M** |

### P1 — Trust-Breakers (17 items)

| # | ID | Source | Severity | Category | Description | Evidence | How to Reproduce | Recommendation |
|---|-----|--------|----------|----------|-------------|----------|------------------|----------------|
| UZ-008 | S-05 | 06 | P1 | Security | **19 portal API routes use `getSession()` instead of `getUser()`.** Skips server-side JWT re-validation. Supabase docs explicitly warn this is insecure for server-side auth. | `distribute-coins/route.ts:16`, `clearing/route.ts:13`, 17 others | Intercept request with expired JWT that's still in cookie → route processes without re-validation | Replace all `getSession()` with `getUser()` in API route handlers (find-and-replace). **Effort: S** |
| UZ-009 | S-04 | 06 | P1 | Security | **`secure_password_change = false`.** Users can change password without re-authentication. Brief access to unlocked session → password changed → real user locked out. | `config.toml:209` | Gain access to unlocked session → change password → original user cannot log in | Set `secure_password_change = true`. **Effort: S** |
| UZ-010 | S-06 | 06 | P1 | Security | **Portal pages use `createServiceClient()` bypassing RLS for reads.** Cookie-based `groupId` is client-controllable. Middleware re-verifies, but race conditions could enable cross-tenant reads. | `swap/page.tsx:15`, `clearing/page.tsx:36`, `custody/page.tsx:16`, `engagement/page.tsx`, `athletes/page.tsx` | Modify `portal_group_id` cookie → some reads may return data for wrong group | Use user-scoped `createClient()` for reads. Reserve service-role for cross-user writes. Validate `groupId` server-side before every query. **Effort: M** |
| UZ-011 | S-07, G-037 | 04, 06 | P1 | Security | **Raw exception objects leaked in error messages.** `WalletBloc` emits `'Erro ao carregar OmniCoins: $e'`. `athlete_my_status_screen.dart` uses `'Erro ao carregar dados: $e'`. Stack traces, SQL errors, class names visible. | `wallet_bloc.dart:73`, `athlete_my_status_screen.dart:84,151` | Trigger error in wallet or status screen → see raw exception text | Emit generic messages; log full exception via `AppLogger.error()`. Use `ErrorMessages.humanize(e)`. **Effort: S** |
| UZ-012 | S-08 | 06 | P1 | Security | **JWT copy-to-clipboard available in debug/profile builds.** Settings screen includes "Copiar JWT" gated by `kDebugMode`, but debug/profile builds can be distributed to testers. | `settings_screen.dart:441-448,711-732` | Open settings in debug build → tap "Copiar JWT" → raw access token on clipboard | Remove entirely, or gate behind compile-time `ENABLE_DEV_TOOLS` define never set in distributed builds. **Effort: S** |
| UZ-013 | S-12 | 06 | P1 | Privacy/LGPD | **Account deletion doesn't delete financial history, sessions, or runs.** `delete-account` EF anonymizes profile and removes group memberships, but `coin_ledger`, `sessions`, `challenge_participants`, `wallets` remain linked to (deleted) `user_id`. | `delete-account/index.ts:52-74` | Delete account → check DB → financial and session records still present | Cascade-delete or anonymize all user-linked records. **Effort: M** |
| UZ-014 | G-019 | 04 | P1 | Reliability | **33 portal pages return `null` (blank page) on missing `groupId`.** User sees completely blank page with no error, redirect, or explanation. | `dashboard/page.tsx:17`, `clearing/page.tsx:34`, `custody/page.tsx:14`, 30+ others | Clear `portal_group_id` cookie → navigate to any portal page → blank | Replace `return null` with redirect to `/select-group` or an error UI component. **Effort: M** |
| UZ-015 | G-002, G-026 | 04 | P1 | Dead-end | **Workout delivery flow half-connected.** `StaffWorkoutAssignScreen` is built but unreachable (no navigation route). The delivery flow depends on `AthleteWorkoutDayScreen` (UZ-005) which is also orphaned. | `staff_workout_assign_screen.dart:18`, `athlete_workout_day_screen.dart:17` | Search for Navigator.push to either screen → none found | Wire assign screen into staff dashboard. Connect with UZ-005 fix for end-to-end flow. **Effort: S** |
| UZ-016 | G-007 | 04 | P1 | Half-built | **Social run detection returns hardcoded empty list.** `_detectSocialRuns()` is explicitly a placeholder. Community tab renders the widget but it will always be empty. | `park_screen.dart:402-406` — comment: "in production, the backend detects overlapping runs" | Open Parks → Community tab → social runs section always empty | Implement backend detection or remove the widget from UI. **Effort: M** |
| UZ-017 | G-009 | 04 | P1 | Half-built | **Export screen "Conectar Strava" button does nothing.** After export, the Strava education sheet's connect button pops the sheet but doesn't navigate. Comment: "Will be wired in Sprint 14.5". | `export_screen.dart:174-177` | Export a session → tap Strava CTA → nothing happens | Wire button to Strava settings/OAuth flow. **Effort: S** |
| UZ-018 | G-011 | 04 | P1 | Error Handling | **Support screen hides load errors silently.** Catch block logs warning and sets `_loading = false`. User sees empty screen, no error message, no retry. | `support_screen.dart:46-49` | Trigger network error during support load → empty screen, no feedback | Add error state with retry button. **Effort: S** |
| UZ-019 | G-013 | 04 | P1 | Error Handling | **League screen conflates "no season" with "network error."** Error state sets `_season = null` → falls through to empty state. Users can't distinguish between no data and a failure. | `league_screen.dart:76-80` | Trigger network error on league load → shows "no season" message | Add separate error state with retry. **Effort: S** |
| UZ-020 | G-015 | 04 | P1 | Reliability | **Feature flag stale cache risk documented but unmitigated.** No periodic refresh timer. Destructive operations don't re-check server-side as recommended in the code comment. | `feature_flags.dart:50-54` — "KNOWN RISK (m13)" | Keep app open for hours → feature flag toggled server-side → app uses stale value | Add periodic refresh (e.g., every 15 min). Re-check server-side before destructive ops. **Effort: S** |
| UZ-021 | G-021 | 04 | P1 | Reliability | **Engagement page has no try/catch around 5 parallel queries.** Any single query failing crashes the page to the generic error boundary. | `engagement/page.tsx:54-85` | Simulate one Supabase query failure → entire page shows "Something went wrong" | Wrap in try/catch with meaningful error UI. **Effort: S** |
| UZ-022 | F1 (03) | 03 | P1 | Bug | **Challenge Accept button has no double-click guard.** `_AcceptDeclineCard._onAccept` lacks `_busy` flag. User can tap "Accept" multiple times before bloc processes. | `challenge_details_screen.dart` — no `_busy` in accept handler | Open challenge → rapidly tap "Aceitar" → multiple join requests dispatched | Add `_busy` guard to `_onAccept()`. **Effort: S** |
| UZ-023 | 03 | 03 | P1 | Scalability | **Portal CRM capped at 200 members; support tickets at 200.** Large assessorias (200+ athletes) or busy platforms will have incomplete views. | `crm/page.tsx:42`, `platform/support/page.tsx:29` | Add 200+ athletes to a group → CRM page only shows first 200 | Add server-side pagination. **Effort: M** |
| UZ-024 | S-16 | 06 | P1 | Security | **Client-side only validation on most forms.** No server-side length/format validation in edge functions for display_name, challenge title, etc. | `profile_screen.dart:402` (maxLength: 50), `challenge_create_screen.dart:188` (maxLength: 60) — no server equivalent | Bypass Flutter form → send oversized input directly to edge function → accepted | Add server-side input validation in edge functions and API routes. **Effort: M** |

### P2 — Friction & Incomplete (27 items)

| # | ID | Source | Severity | Category | Description | Evidence | How to Reproduce | Recommendation |
|---|-----|--------|----------|----------|-------------|----------|------------------|----------------|
| UZ-025 | S-09 | 06 | P2 | Security | Challenge error responses leak internal status values (e.g., `status: ${challenge.status}`). | `challenge-join/index.ts:107` | Join a closed challenge → error message reveals internal state | Use generic messages; log details server-side. **Effort: S** |
| UZ-026 | S-10 | 06 | P2 | Security | CORS defaults include `localhost:3000`. If `CORS_ALLOWED_ORIGINS` not set in prod, dev origins accepted. | `cors.ts:12-13` | Deploy without setting env var → localhost accepted | Remove localhost from defaults. **Effort: S** |
| UZ-027 | S-13, S-14 | 06 | P2 | Security | `badge_awards` and `profile_progress` have conflicting RLS: own-read AND public-read (`USING true`). Any user can read any other user's badges and progress. | Schema: `badge_awards_public_read`, `progress_public_read` | Query `badge_awards` as any user → see all users' awards | Remove `public_read` policies or document as intentional. **Effort: S** |
| UZ-028 | S-15 | 06 | P2 | Security | Swap API returns raw `e.message` to client, potentially exposing SQL errors. | `swap/route.ts:138-139` | Trigger error in swap → raw exception in response | Classify errors; return user-safe messages. **Effort: S** |
| UZ-029 | G-001 | 04 | P2 | Dead Code | `athlete_my_status_screen.dart` is a full duplicate of `staff_workout_assign_screen.dart` with identical class name. Never navigated to. | `athlete_my_status_screen.dart:17-19` | Search codebase → two files with same class | Delete the duplicate file. **Effort: S** |
| UZ-030 | G-005 | 04 | P2 | Half-built | Ghost comparison chart shows grey placeholder "Gráfico de pace em breve" instead of actual chart. | `ghost_comparison_card.dart:74-87` | View run with ghost comparison → grey box placeholder | Implement pace chart or remove placeholder. **Effort: M** |
| UZ-031 | G-006 | 04 | P2 | Half-built | Shadow racing "Desafiar" button shows SnackBar "em breve!" — feature wired in UI but not implemented. | `park_screen.dart:795-799` | Open park → tap segment record "Desafiar" → snackbar | Implement or remove button. Gate behind feature flag. **Effort: S** |
| UZ-032 | G-008 | 04 | P2 | Half-built | Challenge result sharing shows "Compartilhamento em breve!" instead of actually sharing. | `challenge_result_screen.dart:968-973` | Complete challenge → tap "Enviar" → snackbar only | Wire to native share sheet. **Effort: S** |
| UZ-033 | G-010 | 04 | P2 | Half-built | Staff athlete alerts tab shows "Alertas do PASSO 05 — em breve" placeholder. | `staff_athlete_profile_screen.dart:939` | Open athlete profile → alerts tab → placeholder only | Implement alerts or remove tab. **Effort: M** |
| UZ-034 | G-012 | 04 | P2 | Error Handling | Athlete evolution screen has no retry on error. `AthleteEvolutionInitial` shows loading text with no spinner. | `athlete_evolution_screen.dart:32-33` | Trigger error on evolution load → no retry option | Add retry button to error state. **Effort: S** |
| UZ-035 | G-014 | 04 | P2 | Inconsistency | Only 1 feature flag (`trainingpeaks_enabled`) used in entire app despite feature flag infrastructure. Half-built features use hardcoded dead-ends. | 3 files reference the single flag | Inspect half-built features → none gated by flags | Gate "coming soon" features behind flags. **Effort: S** |
| UZ-036 | G-020 | 04 | P2 | Half-built | Portal manual attendance button permanently disabled with `title="Em breve"`. | `attendance/[id]/page.tsx:135-139` | Open attendance detail → button visible but disabled | Implement or hide the button. **Effort: S** |
| UZ-037 | G-022 | 04, 07 | P2 | Language | Portal error pages display in English ("Something went wrong", "Try Again") while rest of portal is PT-BR. | `error.tsx:12-24`, `global-error.tsx:27` | Trigger any portal error → English error page | Translate to Portuguese; add error categorization. **Effort: S** |
| UZ-038 | G-024 | 04 | P2 | Reliability | No timeout/offline fallback for Wrapped and Running DNA edge functions. Slow/down EFs mean infinite spinner. | `wrapped_screen.dart:68-74`, `running_dna_screen.dart:48-51` | Load Wrapped with slow connection → infinite spinner | Add timeout (15s) and fallback state. **Effort: S** |
| UZ-039 | G-025 | 04 | P2 | Navigation | Legacy billing redirect confusion. `/billing` and `/credits` redirect to `/custody` when flag off, but sidebar still shows "Financeiro" → `/financial`. | `billing/page.tsx:47-51`, `credits/page.tsx:23-27` | Toggle legacy flag off → confusing navigation | Clean up sidebar links; remove legacy pages if flag is permanently off. **Effort: S** |
| UZ-040 | G-027 | 04 | P2 | Feature Gap | Support tickets have no real-time notification. Staff must manually check the portal page. | `support_screen.dart:67-74`, `platform/support/page.tsx` | Create ticket from app → portal has no alert/push | Add webhook or polling for new tickets. **Effort: M** |
| UZ-041 | G-028 | 04 | P2 | Feature Gap | Verification flow has no push notification bridge. Athlete isn't notified when staff evaluates verification. | `verification/page.tsx`, `athlete_verification_screen.dart` | Staff evaluates → athlete must pull-to-refresh to see | Add push notification on verification status change. **Effort: M** |
| UZ-042 | G-029 | 04 | P2 | Feature Parity | Championships exist in app but have no portal page. Staff manage championships only through app. | `sidebar.tsx:14-39` — no championship entry | Check portal sidebar → no championships link | Add portal championships management page. **Effort: L** |
| UZ-043 | G-033 | 04, 07 | P2 | UX | Portal sidebar has 24+ items with no grouping, icons, or collapse. Cognitive overload for admin_master users. | `sidebar.tsx:14-39` | Log in as admin_master → scroll through flat list of 24 items | Group into collapsible sections (Financial, Athletes, Content, Analytics). Add icons. **Effort: M** |
| UZ-044 | G-034 | 04 | P2 | UX | ProgressHub has 11 navigation tiles in a flat list with no grouping or contextual help. | `progress_hub_screen.dart:54-80` | Open progress hub → 11 undifferentiated tiles | Group related tiles; add brief descriptions. **Effort: S** |
| UZ-045 | G-039 | 04 | P2 | UX | Accessing workout assignment requires 5+ taps and deep navigation. | Navigation analysis across dashboard/group screens | Attempt to assign workout → 5+ screens deep | Add shortcut from staff dashboard. **Effort: S** |
| UZ-046 | G-041 | 04 | P2 | Reliability | `fn_friends_activity_feed` RPC dependency risk — if missing from migrations, friends feed crashes. | `friends_activity_feed_screen.dart:43-45` | Verify function exists in migrations → potential crash if missing | Verify migration; add error fallback in screen. **Effort: S** |
| UZ-047 | G-042 | 04 | P2 | Reliability | `fn_tp_sync_status` RPC fragile contract — result accessed with `syncResult?.ok` without shape validation. | `trainingpeaks/page.tsx:35-39` | Change RPC return shape → page silently shows empty | Add response validation. **Effort: S** |
| UZ-048 | 03, 05 | 03, 05 | P2 | UX | Random artificial delays (`Random().nextInt(2000)`) on TodayScreen and StaffDashboardScreen add 0–2s of unexplained wait. | `today_screen.dart:133`, `staff_dashboard_screen.dart` | Open app → observe 0–2s delay before data loads | Remove jitter delays. Load data immediately. **Effort: S** |
| UZ-049 | H3 (07) | 07 | P2 | UX | No back-navigation guard on forms. Challenge creation, workout builder, announcement creation, profile edit — navigating away silently discards input. | `challenge_create_screen.dart`, `announcement_create_screen.dart`, `staff_workout_builder_screen.dart`, `profile_screen.dart` | Fill a form → tap back → input lost with no warning | Add `PopScope` with "Discard changes?" dialog. **Effort: S** |
| UZ-050 | H1 (07) | 07 | P2 | UX | No step indicator on challenge creation form. Long form with no progress visibility. | `challenge_create_screen.dart` | Open challenge create → single scrollable form, no progress dots | Add step indicator or progress bar. **Effort: S** |
| UZ-051 | 05, 07 | 05, 07 | P2 | UX | Strava connect buried in Settings instead of inline on TodayScreen. Adds 2 extra screens + 2 extra clicks. | `today_screen.dart:897-993` → links to Settings → Strava tile | See "Conectar Strava" CTA on Today → must navigate to Settings | Trigger OAuth flow directly from TodayScreen CTA. **Effort: S** |

### P3 — Polish (22 items)

| # | ID | Source | Severity | Category | Description | Evidence | How to Reproduce | Recommendation |
|---|-----|--------|----------|----------|-------------|----------|------------------|----------------|
| UZ-052 | H4 (07) | 07 | P3 | Consistency | Two competing error state widgets: `AppErrorState` (simple) and `ErrorState` (rich, with `humanize()` and a11y). Visual inconsistency across screens. | `state_widgets.dart` vs `error_state.dart` | Navigate between screens → different error UI styles | Consolidate to single `ErrorState` widget. Deprecate `AppErrorState`. **Effort: S** |
| UZ-053 | H1 (07) | 07 | P3 | UX | No "last updated" timestamps on portal data tables. Coaches don't know data freshness. | Portal data pages — no timestamps | View athletes page → no indication of when data was fetched | Add "last updated" timestamp and manual refresh button. **Effort: S** |
| UZ-054 | G-004 | 04 | P3 | Dead Code | `_ComingSoonTile` widget defined but never instantiated. | `more_screen.dart:475` | Search for usage → none | Delete dead code. **Effort: S** |
| UZ-055 | G-030 | 04 | P3 | Feature Parity | Matchmaking exists only in app. No portal visibility into queues, outcomes, or disputes. | `matchmaking_screen.dart` — no portal equivalent | Portal coach → cannot see matchmaking activity | Add read-only matchmaking view to portal. **Effort: L** |
| UZ-056 | G-031 | 04 | P3 | Feature Parity | League management has different scopes: portal is platform-level admin; app is user-facing view. No assessoria-level league management in portal. | `platform/liga/page.tsx` vs `league_screen.dart` | Portal coach → cannot manage league enrollment for own group | Add assessoria-level league page. **Effort: M** |
| UZ-057 | G-032 | 04 | P3 | Feature Gap | Badges created in portal have no preview of what they look like in the app. | `badge-form.tsx` vs `badges_screen.dart` | Create badge in portal → no preview available | Add badge preview component. **Effort: M** |
| UZ-058 | G-035 | 04 | P3 | Dev Confusion | Portal uses 3 different Supabase client patterns with unclear rules about when to use which. | `client.ts`, `server.ts`, `service.ts`, `admin.ts` | Review portal code → inconsistent client usage | Document client selection rules. Add linting rule. **Effort: S** |
| UZ-059 | G-036 | 04 | P3 | Info Leak | Diagnostics screen exposes internal state (backend mode, Supabase connection status) to end users. In mock mode shows "mock". | `diagnostics_screen.dart:38-39` | Open diagnostics → see internal state | Gate behind developer-only flag. **Effort: S** |
| UZ-060 | G-038 | 04 | P3 | Stale Content | Staff credits screen says "Em breve você poderá gerenciar créditos pelo navegador" — but portal `/custody` already exists. | `staff_credits_screen.dart:257` | Open credits screen → misleading message | Update copy to link to portal. **Effort: S** |
| UZ-061 | G-040 | 04 | P3 | UX | Streak leaderboard buried 4 taps deep (Home → Progress Hub → Sequências → Leaderboard). | `progress_hub_screen.dart` → `streaks_leaderboard_screen.dart` | Navigate to streak leaderboard → 4 taps | Add shortcut from TodayScreen streak banner. **Effort: S** |
| UZ-062 | S-17 | 06 | P3 | Permissions | `ACCESS_BACKGROUND_LOCATION` declared without in-app rationale dialog (Google Play requirement). | `AndroidManifest.xml:6` | Check manifest → permission declared, no rationale screen | Add explanation screen before requesting permission. **Effort: S** |
| UZ-063 | S-18 | 06 | P3 | Bug | iOS `Info.plist` missing `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription`. App will crash when user tries to upload avatar. | `Info.plist` — no camera/photo keys; `profile_screen.dart` uses `image_picker` | Open profile → try to change avatar on iOS → crash | Add usage description keys to `Info.plist`. **Effort: S** |
| UZ-064 | S-19 | 06 | P3 | Security | `portal_group_id` cookie is user-settable. Middleware re-verifies membership, but timing window exists. | `middleware.ts:77` | Modify cookie in browser devtools → middleware catches, but race window exists | Sign the cookie (JWT claim or encrypted cookie). **Effort: M** |
| UZ-065 | S-20 | 06 | P3 | Security | `events` and `missions` tables have public read policies (`USING true`). May expose internal coaching group event details. | Schema: `events_read_all`, `missions_read_all` | Query events as any user → see all groups' events | Evaluate if intentional; scope to group if not. **Effort: S** |
| UZ-066 | S-21 | 06 | P3 | Security | Dead-letter queue stores raw webhook headers including `stripe-signature` in DB. | `webhook-payments/index.ts:489` | Trigger webhook failure → headers persisted | Filter sensitive headers before persisting. **Effort: S** |
| UZ-067 | H4 (07) | 07 | P3 | UX | Portal sidebar has text-only navigation with no icons. Deviates from admin portal conventions. | `sidebar.tsx` — no icon components | Open portal sidebar → text-only list | Add icons alongside labels. **Effort: S** |
| UZ-068 | H7 (07) | 07 | P3 | UX | Portal has zero keyboard shortcuts. No `Cmd+K`, `Cmd+N`, or `Esc` for modals. | Portal codebase — no keyboard event handlers | Try `Cmd+K` → nothing | Add command palette and basic shortcuts. **Effort: M** |
| UZ-069 | H7 (07) | 07 | P3 | UX | No bulk athlete management in portal. Distributing coins, changing status requires visiting each athlete individually. | `athletes/page.tsx` — no multi-select | Try to distribute coins to 10 athletes → must do 10 individual operations | Add multi-select and batch actions. **Effort: L** |
| UZ-070 | H7 (07) | 07 | P3 | UX | Portal has no dark mode despite app supporting system/light/dark themes. | Portal CSS — light-only | Open portal at night → light only | Add dark mode toggle. **Effort: M** |
| UZ-071 | H10 (07) | 07 | P3 | UX | Portal has no onboarding or help for first-time coaches. 24 sidebar items with no guidance. | Portal — no tour, tooltips, or getting-started flow | First login as coach → zero guidance | Add first-time onboarding checklist or tour. **Effort: M** |
| UZ-072 | H10 (07) | 07 | P3 | UX | No in-app FAQ or knowledge base. "How It Works" covers mechanics but not troubleshooting. | App — no FAQ screen | User asks "why aren't my runs syncing?" → no in-app answer | Add FAQ section. **Effort: S** |
| UZ-073 | H8 (07) | 07 | P3 | UX | MoreScreen is a 15+ item flat text list without visual card grouping. Visually dense and hard to scan. | `more_screen.dart:59-283` | Open More tab → long scrollable text list | Redesign with card grouping and prominent icons. **Effort: M** |

**Total: 73 unique issues** — 7 P0, 17 P1, 27 P2, 22 P3.

---

## 3. Backlog (Ordered Implementation Plan)

### Sprint 0 — Release Blockers (must fix first)

**Goal:** Close all P0 items so the product is safe to ship. **Estimated duration: 2–3 days.**

| # | Item | What to Do | Effort | Impact |
|---|------|-----------|--------|--------|
| UZ-001 | Disable anonymous sign-ins | Set `enable_anonymous_sign_ins = false` in `config.toml` | S | 10 — closes trivial auth bypass |
| UZ-002 | Restrict challenges RLS | Add group/participant subquery to `challenges` SELECT policy | S | 10 — closes cross-tenant data leakage |
| UZ-003 | Enable verify_jwt = true | Set `verify_jwt = true` as default in `config.toml`; only disable for webhooks, crons | S | 10 — closes gateway-level auth bypass |
| UZ-004 | Add mock mode banner | Show persistent warning when `backendMode == 'mock'`; disable financial actions | S | 9 — prevents phantom transactions |
| UZ-005 | Wire AthleteWorkoutDayScreen | Add navigation route from TodayScreen or MoreScreen | S | 7 — unlocks core coaching feature |
| UZ-006 | Fix TrainingPeaks cookie | Change `group_id` → `portal_group_id` (1 line) | S | 9 — fixes completely broken page |
| UZ-007 | Add privacy policy + LGPD | Add privacy policy URL to login/settings; basic consent collection | M | 9 — legal compliance for health data |
| UZ-008 | Replace getSession with getUser | Find-and-replace in 19 API routes | S | 8 — proper server-side JWT validation |
| UZ-009 | Enable secure_password_change | Set `secure_password_change = true` in `config.toml` | S | 8 — prevents session hijack escalation |
| UZ-011 | Sanitize error messages | Replace `$e` with `ErrorMessages.humanize(e)` in WalletBloc + athlete_my_status | S | 7 — stops information leakage |
| UZ-012 | Remove JWT copy feature | Remove or gate behind `ENABLE_DEV_TOOLS` define | S | 6 — prevents token theft in test builds |

**Sprint 0 total: 11 items, ~10 S + 1 M = approximately 2–3 days.**

---

### Sprint 1 — Trust & Reliability

**Goal:** Fix trust-breakers that would drive users away after first use. **Estimated duration: 1 week.**

| # | Item | What to Do | Effort | Impact |
|---|------|-----------|--------|--------|
| UZ-010 | Portal reads: user-scoped client | Move portal page reads from `createServiceClient()` to `createClient()` where possible | M | 8 — proper RLS enforcement |
| UZ-013 | Complete account deletion | Cascade-delete `coin_ledger`, `sessions`, `challenge_participants`, `wallets`, `badge_awards` | M | 8 — LGPD Art. 18 compliance |
| UZ-014 | Fix 33 portal blank pages | Replace `return null` with redirect to `/select-group` or error component | M | 8 — eliminates blank-page dead ends |
| UZ-015 | Wire workout assign screen | Add navigation route from staff dashboard | S | 7 — completes coaching workflow |
| UZ-018 | Support screen error state | Add error UI with retry to `SupportScreen._load()` | S | 6 — stops silent failure |
| UZ-019 | League error vs empty | Add separate error state with retry to league screen | S | 5 — error clarity |
| UZ-021 | Engagement page error handling | Wrap 5 parallel queries in try/catch with specific error UI | S | 6 — page-level resilience |
| UZ-022 | Challenge accept busy guard | Add `_busy` flag to `_AcceptDeclineCard._onAccept()` | S | 6 — prevents duplicate joins |
| UZ-024 | Server-side input validation | Add length/format validation in edge functions for display_name, challenge title, etc. | M | 7 — security boundary |
| UZ-048 | Remove artificial delays | Delete `Random().nextInt(2000)` from TodayScreen and StaffDashboard | S | 6 — perceived performance |
| UZ-037 | Translate portal error pages | Portuguese + error categorization in `error.tsx` and `global-error.tsx` | S | 7 — language consistency |
| UZ-020 | Feature flag periodic refresh | Add 15-min refresh timer to `FeatureFlagService` | S | 5 — flag freshness |

**Sprint 1 total: 12 items, ~4 M + 8 S = approximately 1 week.**

---

### Sprint 2 — Completeness

**Goal:** Remove dead-ends, connect half-built features, close feature parity gaps. **Estimated duration: 1–2 weeks.**

| # | Item | What to Do | Effort | Impact |
|---|------|-----------|--------|--------|
| UZ-016 | Social run detection | Implement backend overlapping-run detection or remove widget | M | 5 |
| UZ-017 | Export Strava button | Wire to Strava OAuth flow | S | 5 |
| UZ-023 | CRM/ticket pagination | Add server-side pagination to portal CRM and support pages | M | 6 |
| UZ-025 | Sanitize challenge errors | Remove internal status from error messages | S | 4 |
| UZ-026 | CORS defaults | Remove localhost from `DEFAULT_ORIGINS` | S | 4 |
| UZ-027 | Fix conflicting RLS | Remove or justify `public_read` on badge_awards, profile_progress | S | 5 |
| UZ-028 | Swap error sanitization | Return generic messages; log raw errors server-side | S | 4 |
| UZ-029 | Delete duplicate file | Remove `athlete_my_status_screen.dart` | S | 3 |
| UZ-030 | Ghost comparison chart | Implement pace chart or remove placeholder | M | 4 |
| UZ-031 | Shadow racing button | Gate behind feature flag or remove | S | 3 |
| UZ-032 | Challenge result sharing | Wire to native share sheet | S | 5 |
| UZ-033 | Staff alerts tab | Implement alerts data or remove tab | M | 4 |
| UZ-035 | Gate features behind flags | Add feature flags to all "coming soon" features | S | 4 |
| UZ-036 | Manual attendance button | Implement or hide | S | 3 |
| UZ-038 | EF timeout/fallback | Add 15s timeout + fallback for Wrapped/DNA | S | 4 |
| UZ-039 | Clean up legacy billing nav | Remove legacy pages if flag is permanently off; fix sidebar | S | 3 |
| UZ-040 | Support ticket notifications | Add webhook or polling for new tickets | M | 5 |
| UZ-041 | Verification push notification | Notify athlete on status change | M | 5 |
| UZ-042 | Championships portal page | Add portal championships management | L | 5 |
| UZ-046 | Verify friends feed RPC | Confirm `fn_friends_activity_feed` in migrations; add fallback | S | 4 |
| UZ-047 | TP sync response validation | Add response shape validation | S | 3 |
| UZ-051 | Inline Strava OAuth | Trigger OAuth directly from TodayScreen CTA | S | 5 |
| UZ-063 | iOS plist camera/photo keys | Add `NSCameraUsageDescription` + `NSPhotoLibraryUsageDescription` | S | 5 |

**Sprint 2 total: 23 items, ~5 M + 1 L + 17 S = approximately 1.5–2 weeks.**

---

### Sprint 3 — Polish

**Goal:** UX improvements, consistency, and professional finish. **Estimated duration: 2 weeks.**

| # | Item | What to Do | Effort | Impact |
|---|------|-----------|--------|--------|
| UZ-034 | Evolution screen retry | Add retry button to error state | S | 3 |
| UZ-043 | Portal sidebar redesign | Group into collapsible sections + add icons | M | 7 |
| UZ-044 | ProgressHub grouping | Group tiles by category; add descriptions | S | 4 |
| UZ-045 | Workout assign shortcut | Add card on staff dashboard | S | 4 |
| UZ-049 | Form back-navigation guard | Add `PopScope` with "Discard changes?" to key forms | S | 5 |
| UZ-050 | Challenge create step indicator | Add step/progress indicator | S | 4 |
| UZ-052 | Consolidate error widgets | Adopt `ErrorState` everywhere; deprecate `AppErrorState` | S | 4 |
| UZ-053 | Portal "last updated" | Add timestamps and refresh button to data tables | S | 4 |
| UZ-054 | Delete _ComingSoonTile | Remove dead code | S | 1 |
| UZ-058 | Document Supabase clients | Add ADR or code comments for client selection rules | S | 3 |
| UZ-059 | Gate diagnostics screen | Gate behind developer-only flag | S | 2 |
| UZ-060 | Update stale credits copy | Replace "em breve" with portal link | S | 2 |
| UZ-061 | Streak leaderboard shortcut | Add link from TodayScreen streak banner | S | 3 |
| UZ-062 | Background location rationale | Add in-app explanation dialog | S | 4 |
| UZ-064 | Sign portal_group_id cookie | Use encrypted cookie or JWT claim | M | 4 |
| UZ-065 | Evaluate public-read policies | Decide and document events/missions visibility | S | 2 |
| UZ-066 | Filter dead-letter headers | Strip `stripe-signature` before persisting | S | 3 |
| UZ-067 | Portal sidebar icons | Add icons to all nav items | S | 5 |
| UZ-070 | Portal dark mode | Add dark mode toggle + CSS variables | M | 4 |
| UZ-071 | Portal onboarding tour | Add first-time checklist or guided tour | M | 5 |
| UZ-072 | In-app FAQ | Add static FAQ screen | S | 3 |
| UZ-073 | MoreScreen redesign | Card grouping with prominent icons | M | 4 |

**Sprint 3 total: 22 items, ~5 M + 17 S = approximately 2 weeks.**

### Deferred (Longer-Term)

| # | Item | What to Do | Effort | Impact |
|---|------|-----------|--------|--------|
| UZ-055 | Matchmaking portal view | Add read-only matchmaking dashboard | L | 3 |
| UZ-056 | Assessoria league management | Add group-level league page in portal | M | 3 |
| UZ-057 | Badge preview | Add preview component in portal badge form | M | 3 |
| UZ-068 | Portal keyboard shortcuts | Add Cmd+K command palette | M | 4 |
| UZ-069 | Bulk athlete management | Multi-select + batch actions on Athletes page | L | 5 |

---

## 4. Residual Risks

Risks that remain even after all identified issues are fixed:

### Architectural Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Single Supabase dependency** | All data, auth, and edge functions run on Supabase. A Supabase outage = full product outage. The Isar offline cache only covers reads, not writes (except `OfflineQueue`). | Monitor Supabase status; implement write-ahead queue for critical mutations; evaluate multi-region deployment. |
| **Edge function cold starts** | 48 Deno-based edge functions on Supabase's shared infrastructure. Cold starts can add 500ms–2s latency, especially for rarely-called functions. | Monitor p95 latencies; consider consolidating rarely-used functions; evaluate Supabase Pro for dedicated resources. |
| **Flutter app size** | 104 screens, MapLibre, BLE, Strava, QR scanner, Health Connect, Firebase, Sentry — the app binary is likely >50MB. This affects download rates in Brazil where mobile data is expensive. | Audit dependency tree; consider deferred component loading; measure actual APK/IPA size. |
| **Isar local database** | Isar is a third-party embedded DB with uncertain long-term maintenance. If the package is abandoned, migration cost would be significant. | Monitor Isar project health; consider abstracting the local storage layer for easier replacement. |

### Business Model Risks

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Assessoria dependency** | Athletes cannot access challenges or championships without an assessoria. This limits organic/viral growth to "already connected to a coach" users. Solo runners are excluded. | Consider a "free explorer" tier with limited challenge access. Allow athletes to create public challenges without assessoria. |
| **OmniCoin value perception** | The coin economy depends on assessorias purchasing credits. If assessorias don't buy credits, the economy is empty. No evidence of pricing validation or unit economics. | Validate willingness-to-pay; consider free starter credits; add coin-earning mechanics that don't require coach purchase. |
| **Strava dependency** | The core athlete experience assumes Strava for run import. If Strava changes their API terms, rate-limits, or shuts down OAuth access, the app's primary data source is gone. | Diversify: add native GPS tracking as primary method; use Strava as enhancement, not foundation. Consider Garmin/Polar direct API connections. |

### Scalability Concerns

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Client-side aggregation** | Several screens aggregate data client-side (evolution charts, running DNA, leaderboards). With 200+ athletes per group, this will cause UI jank. | Move aggregation to server-side RPCs or views. Pre-compute leaderboard snapshots. |
| **CRM 200-member cap** | Portal CRM explicitly limits to 200 athletes per query. Groups with 500+ athletes (common for Brazilian assessorias) will have incomplete views. | Implement proper pagination with server-side filtering (UZ-023). |
| **Clearing cron scalability** | The clearing/settlement cron runs as a single edge function. At scale (100+ groups with daily settlements), this may time out. | Batch processing with continuation tokens; consider background job queue. |

### Regulatory (LGPD) Exposure

| Risk | Description | Mitigation |
|------|-------------|------------|
| **Health data processing** | GPS location, heart rate, workout sessions, and Health Connect data are processed without documented legal basis or consent. Under LGPD, health data is "sensitive personal data" requiring explicit consent (Art. 11). | Implement consent flow before data processing; document legal basis; add data processing records. |
| **Data retention policy** | No documented retention period for sessions, runs, or financial records. LGPD requires clear retention limits. | Define and document retention policy; implement automated data archival/deletion. |
| **Data portability** | No data export feature for users (LGPD Art. 18, V). The app has session export (GPX/TCX/FIT/CSV) but not a comprehensive personal-data export. | Add "Download my data" feature covering all personal data. |
| **Cross-border transfers** | Supabase hosting location is not documented. If data is stored outside Brazil, LGPD cross-border transfer rules apply (Art. 33). | Confirm Supabase region (should be `sa-east-1`); document transfer basis if outside Brazil. |

---

## 5. Strengths to Preserve

These are elements the product does well that should NOT be changed or regressed during fixes.

### 1. TodayScreen — Best-in-Class Daily Dashboard

The `TodayScreen` is the product's UX crown jewel. Its information hierarchy (streak → challenges → CTA → recap → park → stats), shimmer loading, mood journal, comparison trends, and contextual tips demonstrate exceptional product thinking. **Do not flatten or simplify this screen.** All other screens should aspire to this quality.

### 2. Offline Architecture

The `ConnectivityMonitor` + `NoConnectionBanner` + Isar fallback + `OfflineQueue` system is well-architected. The app detects connectivity changes, shows a persistent banner, serves cached data, and queues mutations for later sync. **Do not remove this infrastructure** — fix mock mode (UZ-004) by adding a visible warning, not by removing the fallback.

### 3. Design Token System

`DesignTokens` (Flutter) and `tokens.css` (portal) provide a single source of truth for palette, spacing, radius, typography, and animation durations. Per-assessoria portal branding via CSS custom properties is elegant. **Use these tokens for all new UI work.** Do not introduce arbitrary values.

### 4. Error Message Humanization

`ErrorState.humanize()` translates raw exceptions into friendly Portuguese messages with semantic accessibility (`Semantics(liveRegion: true)`). This is superior to most apps. **Route all new error display through this function.** Fix UZ-011 by extending its use, not by adding new patterns.

### 5. First-Use Tip System

14 `TipKey` values with `ContextualTipBanner` provide one-time, in-context guidance. Tips appear at the right moment (first wallet visit, first challenge screen, etc.) and dismiss with "Entendi". **Extend this system to new features** rather than creating ad-hoc onboarding flows.

### 6. Strava-Centric Workflow

The deep Strava integration (OAuth, run import, backfill, disconnect) matches how Brazilian runners actually track their runs. The "Bora correr?" CTA and post-run comparison with trend arrows create a motivating feedback loop. **Preserve this integration** and treat native GPS as an enhancement, not a replacement.

### 7. Gamification Mechanics

The streak system (milestones, XP rewards, freeze tokens), badge collection (Bronze → Diamond tiers), weekly missions, and running DNA radar chart are well-designed engagement mechanics. The challenge system (1v1/group/team, multiple goals, verification gate for paid challenges) is sophisticated. **Do not simplify these mechanics** — they are the product's competitive differentiation.

### 8. Portal Dashboard KPIs

The dashboard's stat blocks with week-over-week trends, low-credit alerts, and quick-link actions provide genuine value to coaches. **Preserve the data density** while adding "last updated" indicators (UZ-053).

### 9. Reusable State Widgets

`ShimmerLoading` (content-aware skeletons), `AppLoadingState`, `AppErrorState`, `AppEmptyState`, `SuccessOverlay` (confetti + haptics) — these create consistent state handling across the app. **Use these for all new screens.** The fix for UZ-052 should consolidate to the better widget, not create a third.

### 10. Financial Integrity Architecture

Atomic `debit_wallet_checked` RPC with rollback, custody invariant checks (committed >= 0, deposited >= committed), idempotency via unique indexes, clearing audit trail, and Zod validation on financial routes — the financial backend is well-engineered. **Do not weaken these safeguards** during security fixes.

---

## Appendix: Score Summary by Source Document

| Source | What It Covered | Key Score |
|--------|----------------|-----------|
| USERZERO_00 (Setup) | Product discovery, how to run, environment modes | N/A (discovery doc) |
| USERZERO_01 (Promise) | First impression, product promise, target audience | First Impression: 72/100 |
| USERZERO_02 (Capabilities) | 104 app screens, 55 portal pages, 36 API routes catalogued | State coverage: Loading 92%, Error 87%, Empty 72% |
| USERZERO_03 (Walkthroughs) | 15 end-to-end flow simulations across 3 profiles | 11 PASS, 4 PARTIAL, 0 FAIL |
| USERZERO_04 (Gaps) | 42 issues: 4 P0, 11 P1, 16 P2, 11 P3 | 4 release blockers identified |
| USERZERO_05 (Efficiency) | 16 flows scored for clicks, screens, time, friction | Overall Efficiency: 68/100 |
| USERZERO_06 (Security) | 21 findings: 3 CRITICAL, 5 HIGH, 8 MEDIUM, 5 LOW | 3 CRITICAL security vulnerabilities |
| USERZERO_07 (UX) | Nielsen's 10 heuristics evaluation | Overall UX: 72/100 |
| USERZERO_08 (Verdict) | Pre-release decision with scoring and risk scenarios | Weighted Average: 58/100 — **NO RELEASE** |

---

*End of USERZERO Master Backlog Report. Hand this document to the engineering team as the Sprint 0–3 work plan.*
