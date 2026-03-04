# USERZERO_07 — UX Clarity Heuristic Evaluation

**Evaluator:** UX Research Lead (Nielsen's 10 Usability Heuristics)
**Date:** 2026-03-04
**Scope:** Flutter mobile app (`omni_runner/` — 100 screens) + Next.js portal (`portal/` — 55 pages)
**Target Audience:** Brazilian runners, coaches (assessoria staff), and platform admins

---

## Overall UX Score: 72/100

| Heuristic | Score | Weight |
|-----------|-------|--------|
| H1: Visibility of System Status | 8/10 | High |
| H2: Match Between System and Real World | 7/10 | High |
| H3: User Control and Freedom | 6/10 | High |
| H4: Consistency and Standards | 8/10 | Medium |
| H5: Error Prevention | 7/10 | High |
| H6: Recognition Rather Than Recall | 8/10 | Medium |
| H7: Flexibility and Efficiency of Use | 5/10 | Medium |
| H8: Aesthetic and Minimalist Design | 7/10 | Medium |
| H9: Help Users Recognize Errors | 8/10 | High |
| H10: Help and Documentation | 8/10 | Medium |

---

## Heuristic Evaluations

---

### H1: Visibility of System Status (8/10)

**Good:**

- **Shimmer loading skeletons (App):** A well-built `ShimmerLoading` widget system (`omni_runner/lib/presentation/widgets/shimmer_loading.dart`) provides `ShimmerListTile`, `ShimmerCard`, and `ShimmerListLoader` — content-aware placeholders that mirror final layout shapes. Used widely: `TodayScreen`, `WalletScreen`, `StaffDashboardScreen`, `AssessoriaFeedScreen`, and 20+ other screens.

- **RefreshIndicator (App):** Pull-to-refresh is implemented on ~40 screens including every list and dashboard screen. Users always have a manual way to trigger data reload.

- **Offline connectivity banner (App):** `NoConnectionBanner` (`omni_runner/lib/presentation/widgets/no_connection_banner.dart`) wraps the entire app, auto-detects connectivity changes via `connectivity_plus`, and shows a persistent orange `MaterialBanner` with a wifi-off icon. Disappears automatically on reconnect.

- **Portal loading pages (Portal):** 39 `loading.tsx` files cover virtually every route with skeleton UIs via `<PageSkeleton />`. Next.js Suspense boundaries ensure users see immediate feedback during server-side data fetching.

- **Spinner during auth (App):** Login screen (`login_screen.dart:243-247`) replaces all buttons with a `CircularProgressIndicator` while authentication is in progress, preventing double-taps and showing clear busy state.

- **Streak progress indicator (App):** `_StreakMilestones` in `today_screen.dart:830-865` shows a `LinearProgressIndicator` with current/target counts (e.g., "12/14") and textual next milestone. Users always know how close they are to the next reward.

- **WalletScreen offline indicator (App):** When wallet data comes from Isar cache, an explicit "Dados offline" chip is displayed, ensuring users understand data freshness.

**Bad:**

- **No progress indicators during multi-step flows (App):** Challenge creation (`challenge_create_screen.dart`) is a single long form with no step indicator. Users don't know how far along they are in a potentially complex form.

- **Some screens use plain `CircularProgressIndicator` instead of shimmer (App):** `settings_screen.dart:59` uses `const Center(child: CircularProgressIndicator())` — no skeleton, no message. Same pattern in several staff screens that could benefit from content-aware skeletons.

- **Portal lacks real-time update indicators (Portal):** Data tables on pages like Athletes, CRM, and Attendance are server-rendered and don't show "last updated" timestamps or auto-refresh indicators. A coach viewing athlete data has no idea if it's 1 minute or 1 hour stale.

**Recommendations:**
1. Add step indicators (e.g., `Stepper` or dot-based progress) to multi-step forms like challenge creation and workout builder.
2. Replace remaining bare `CircularProgressIndicator` instances with shimmer skeletons (especially `settings_screen.dart`).
3. Add "last updated" timestamps to portal data tables and offer a manual refresh button.

---

### H2: Match Between System and Real World (7/10)

**Good:**

- **Portuguese-first content (App):** All user-facing strings in the Flutter app are in Brazilian Portuguese: "Bora correr?", "Desafie outros corredores", "Tentar novamente", "Minha Assessoria", "Corrida de hoje". This matches the target audience perfectly.

- **Domain-specific terminology (App):** Uses natural running vocabulary — "pace" (universally understood), "assessoria" (Brazilian coaching group term), "OmniCoins", "Atleta Verificado". The `HowItWorksScreen` explains each concept in plain language.

- **Culturally relevant features:** Park detection (`ParkDetectionService` with `kBrazilianParksSeed`), Strava-centric workflow (the dominant platform for Brazilian runners), and challenge types that mirror real assessoria dynamics (1v1, group, team).

- **Meaningful labels (Portal):** Sidebar uses Portuguese for domain terms: "Custódia", "Compensações", "Auditoria", "Engajamento", "Presença", "Mural", "Entregas Pendentes".

- **Intuitive icons (App):** Consistent icon choices: 🔥 for streaks, 🏃 for running, ⚡ for XP, 📏 for distance, ❄️ for freeze tokens. `TodayScreen` uses emoji in context (mood picker: 😴 😐 😊 💪 🔥).

**Bad:**

- **Mixed language in portal (Portal):** Error pages use English: "Something went wrong" (`error.tsx:13`, `global-error.tsx:27`), "Try Again" (`error.tsx:22`). For a Brazilian-first product, this is jarring.

- **Mixed language in sidebar (Portal):** Some items are English ("Dashboard", "Exports", "CRM Atletas", "Swap de Lastro") while others are Portuguese ("Compensações", "Auditoria", "Presença"). "Conversao Cambial" is Portuguese but missing an accent ("Conversão").

- **Technical jargon leak (Portal):** "Swap de Lastro", "Custódia", "Compensações" (clearing) are financial back-office terms that may confuse coaches who think in terms of "distributing coins to athletes".

- **Some English labels in app (App):** `LoginScreen` has "Email" and "Senha" (correct) but the `l10n` system shows `continueWithGoogle`, `continueWithApple` keys suggesting some labels may render in English depending on locale setup.

**Recommendations:**
1. Translate all portal error pages and UI chrome to Portuguese.
2. Standardize sidebar labels — pick one language and stick with it (Portuguese preferred).
3. Fix "Conversao Cambial" → "Conversão Cambial".
4. Consider renaming "Custódia" to "Depósitos" and "Compensações" to "Pagamentos" for coaches.

---

### H3: User Control and Freedom (6/10)

**Good:**

- **Confirmation dialogs for destructive actions (Portal):** A well-built `ConfirmDialog` component (`portal/src/components/ui/confirm-dialog.tsx`) with `danger` variant, localized labels via `useTranslations("common")`, loading state, and proper `aria-labelledby`/`aria-describedby`. Used by `remove-button.tsx` and other destructive actions.

- **Announcement deletion confirmation (App):** `AnnouncementDetailScreen` shows a SnackBar "Aviso excluído" after deletion and uses `Navigator.pop()` to return — providing feedback on the destructive action.

- **Cancel in multi-step flows (App):** Login form has toggle between sign-up/sign-in modes ("Já tem conta? Entrar" / "Não tem conta? Criar agora") and a "Esqueci a senha" recovery path.

- **Onboarding skip button (App):** `OnboardingTourScreen` has a visible "Pular" button at top-right, allowing users to skip the entire 9-slide tour and jump straight to the app.

- **Staff dispute resolution (App):** `StaffDisputesScreen` includes multiple resolution options (approve, reject, request more info), giving staff control over dispute outcomes.

**Bad:**

- **No undo for coin distribution (Portal/App):** When coins are distributed to athletes, there's no undo mechanism. Once OmniCoins are sent, they're permanent. Given this is a financial action, even a brief undo window would help.

- **No confirmation for challenge creation (App):** `ChallengeCreateScreen` submits the challenge on button press without a final review/confirmation step. Users can accidentally create challenges with wrong parameters and no way to edit after creation.

- **Missing cancel button on some forms (App):** `AnnouncementCreateScreen` and `StaffWorkoutBuilderScreen` don't have obvious cancel/discard buttons — only the back arrow, which silently discards all input with no "Discard changes?" confirmation.

- **No back-navigation guard for unsaved forms (App):** Forms across the app (profile edit, challenge create, workout builder) don't warn when navigating away with unsaved changes.

- **Account deletion is available but no cool-down (App):** `settings_screen.dart` and the `delete-account` edge function allow account deletion, but there's no grace period or "your account will be deleted in 7 days" buffer.

**Recommendations:**
1. Add "Discard changes?" dialog when navigating away from forms with unsaved edits (use `WillPopScope` / `PopScope`).
2. Add a review/confirmation step before challenge creation.
3. Implement a 7-day grace period for account deletion.
4. Add undo capability (or at least a confirmation step) for coin distribution.

---

### H4: Consistency and Standards (8/10)

**Good:**

- **Design tokens system (App):** `DesignTokens` (`omni_runner/lib/core/theme/design_tokens.dart`) is a comprehensive single-source-of-truth with palette (dark + light mode), typography scale, spacing scale (xs=4, sm=8, md=16, lg=24, xl=32, xxl=48), border radii, shadows, and animation durations. Cross-referenced with `portal/src/styles/tokens.css`.

- **Reusable state widgets (App):** Standardized `AppLoadingState`, `AppErrorState`, `AppEmptyState` (`state_widgets.dart`), `ErrorState` (`error_state.dart`), `EmptyState` (`empty_state.dart`), `ShimmerLoading` — all using design tokens. This ensures every loading/error/empty state looks consistent.

- **Consistent card layouts (App):** `TodayScreen` uses a repeating card pattern: rounded container with `DesignTokens.radiusLg`, 14px padding, gradient backgrounds. The same card style appears in `WalletScreen`, `StaffDashboardScreen`, and challenge screens.

- **Consistent button styles (App):** `FilledButton` for primary actions, `OutlinedButton` for secondary, `TextButton` for tertiary. All use `BorderRadius.circular(14)` consistently. Login screen buttons are all 52px height with consistent text sizing.

- **Portal UI component library (Portal):** Shared components via `@/components/ui` barrel export including `StatBlock`, `DashboardCard`, `ConfirmDialog`, `PageSkeleton`. Portal pages consistently use `rounded-xl border border-border bg-surface p-5 shadow-sm` for cards.

- **CSS custom properties for branding (Portal):** `layout.tsx` injects `--brand-primary`, `--brand-sidebar-bg`, etc. as CSS variables, allowing per-assessoria branding without code changes.

**Bad:**

- **Two error state widgets (App):** Both `AppErrorState` (in `state_widgets.dart`) and `ErrorState` (in `error_state.dart`) exist. `ErrorState` is more sophisticated (with `humanize()`, accessibility Semantics, localization), while `AppErrorState` is simpler. Some screens use one, some the other — causing visual inconsistency.

- **Inconsistent AppBar background (App):** Some screens use `backgroundColor: cs.inversePrimary` (e.g., `TodayScreen`, `MoreScreen`), while others use the default. This creates visual inconsistency when navigating.

- **Portal sidebar has no icons (Portal):** `sidebar.tsx` uses text-only navigation with 24 items. Every other modern admin portal uses icons alongside labels. This makes scanning the sidebar harder and deviates from platform conventions.

**Recommendations:**
1. Consolidate to a single error state widget — adopt `ErrorState` (the richer one) and deprecate `AppErrorState`.
2. Standardize AppBar background treatment across all screens.
3. Add icons to portal sidebar navigation items.

---

### H5: Error Prevention (7/10)

**Good:**

- **Form validation (App):** `ChallengeCreateScreen` uses `GlobalKey<FormState>()` with validators. `StaffWorkoutBuilderScreen` validates before save: `if (!_formKey.currentState!.validate()) return;`. `LoginScreen` validates email emptiness and password length (>= 6 chars) before submission.

- **`_busy` guards prevent double-submission (App):** Login screen (`login_screen.dart:34`) uses `_busy` flag that disables all buttons and shows spinner during auth operations. Challenge creation has `_busy` flag preventing duplicate submissions. Found in 20+ screens across the app.

- **Verification gate for financial actions (App):** `VerificationGate` widget blocks unverified athletes from creating challenges with OmniCoin stakes. "Complete 7 corridas válidas para se tornar Verificado" — clear explanation of the requirement.

- **Connection check before auth (App):** `LoginScreen._checkConnection()` validates Supabase connectivity before attempting sign-in, preventing confusing timeout errors.

- **ConfirmDialog with danger variant (Portal):** `confirm-dialog.tsx` supports `variant="danger"` with red styling, making destructive actions visually distinct from regular confirmations. Buttons are disabled during loading to prevent double-clicks.

**Bad:**

- **Challenge creation allows 0 OmniCoin fee (App):** Users can create challenges with 0-coin entry fees, which may lead to spam challenges. No minimum threshold or warning.

- **No input masks for financial fields (Portal):** Swap, custody deposit, and FX pages accept raw numeric input without formatting or range validation on the client side.

- **Profile screen accepts any display name (App):** `ProfileScreen` has no length limits or character validation on display_name. Users could enter empty names, extremely long names, or inappropriate content.

- **No duplicate challenge detection (App):** Users can create multiple identical challenges in rapid succession without warning.

**Recommendations:**
1. Add minimum/maximum validations for OmniCoin entry fees in challenge creation.
2. Add client-side input validation and formatting for financial fields in the portal.
3. Add character limits and basic content validation for display names.
4. Implement duplicate detection for challenge creation (debounce + check recent).

---

### H6: Recognition Rather Than Recall (8/10)

**Good:**

- **Contextual tip banners (App):** `ContextualTipBanner` and `TipBanner` widgets show one-time hints keyed by `TipKey` enum. 14 distinct tip keys cover onboarding moments: `dashboardWelcome`, `challengeHowTo`, `matchmakingHowTo`, `stravaConnect`, `assessoriaHowTo`, `firstWalletVisit`, etc. Tips appear in context and dismiss with "Entendi".

- **TodayScreen shows everything relevant at a glance (App):** Active challenges with time remaining, streak with milestone progress, last run recap with comparison to previous run, park check-in, quick stats (level, XP, sessions this week). Users don't need to remember anything — it's all surfaced.

- **Challenge cards show time remaining (App):** `_ActiveChallengeRow` shows "Faltam 3h 20min" or "Encerrado" — users see deadline without navigating to the detail screen.

- **Wallet filter chips (App):** `WalletScreen` provides `_WalletFilter` enum with All/Earned/Spent tabs, making it easy to segment transaction history without recall.

- **Status badges on athlete list (Portal):** Athletes page (`athletes/page.tsx:20-27`) shows colored status labels: "Verificado" (green), "Calibrando" (blue), "Observação" (yellow), "Rebaixado" (red), "Sem status" (gray). Information is visible without clicking.

- **Sidebar shows active page (Portal):** `sidebar.tsx` highlights the current route with `bg-brand-soft text-brand` styling. Users always know where they are.

- **Group name in header and sidebar (Portal):** Layout shows `groupName` in both sidebar logo area and header, so staff always know which assessoria they're managing.

**Bad:**

- **Portal sidebar has 24 items with no grouping (Portal):** Navigation items are listed flatly without section headers or collapsible groups. "Custódia" sits next to "Badges" next to "Auditoria" — no logical grouping into Financial, Athletes, Content, etc.

- **No breadcrumbs in portal (Portal):** Deep pages like `/crm/[userId]` or `/announcements/[id]/edit` show no breadcrumb trail. Users must rely on browser back button or sidebar to orient.

**Recommendations:**
1. Group portal sidebar items into collapsible sections (Financial, Athletes, Content, Analytics, Settings).
2. Add breadcrumbs to portal detail and edit pages.

---

### H7: Flexibility and Efficiency of Use (5/10)

**Good:**

- **Pull-to-refresh everywhere (App):** Power users can quickly refresh any list screen with a single gesture.

- **Quick-start challenge from matchmaking (App):** `MatchmakingScreen` lets users find opponents automatically instead of manually creating and inviting — a shortcut for the common flow.

- **Challenge pre-fill from invitation (App):** `ChallengeCreateScreen` accepts `initialType`, `initialGoal`, `initialWindowMin`, `initialFee`, `initialTarget` parameters, allowing pre-populated forms when launched from specific contexts.

- **QR code scanning (App):** Athletes can scan QR codes for coin transactions instead of manual entry — efficient for in-person assessoria interactions.

- **Portal batch delivery (Portal):** `delivery-actions.tsx` supports batch operations on workout deliveries, allowing coaches to manage multiple athlete deliveries at once.

**Bad:**

- **No keyboard shortcuts in portal (Portal):** Zero keyboard shortcuts for common actions. No `Cmd+K` command palette, no `Cmd+N` for new, no `Esc` to close modals (except native dialog behavior).

- **No bulk athlete management (Portal):** Athletes page has no multi-select or bulk action capability. Distributing coins, changing verification status, or sending communications requires visiting each athlete individually.

- **No search on most portal pages (Portal):** Athletes, CRM, and other list pages lack client-side search/filter. With 50+ athletes, finding a specific person requires scrolling.

- **No quick actions from notifications (App):** Push notifications (streak at risk, challenge updates) don't deep-link to specific screens. Users must navigate manually.

- **No favorites or pinned items (App/Portal):** Frequently accessed athletes, challenges, or screens can't be bookmarked or pinned for quick access.

- **No dark mode in portal (Portal):** While the Flutter app supports system/light/dark modes via `ThemeNotifier`, the portal is light-only. Coaches working late would benefit from dark mode.

**Recommendations:**
1. Add `Cmd+K` command palette to portal for quick navigation and actions.
2. Implement bulk selection and batch actions on the Athletes page.
3. Add client-side search/filter to all portal data tables.
4. Implement deep links from push notifications to specific screens.
5. Add dark mode support to the portal.

---

### H8: Aesthetic and Minimalist Design (7/10)

**Good:**

- **TodayScreen information hierarchy (App):** Clear visual hierarchy: streak banner (bold gradient) → active challenges (subtle card) → Strava CTA (prominent when needed, subdued when done) → run recap (detailed card) → quick stats (compact chips). Each section has distinct visual weight.

- **Design tokens enforce consistency (App):** Spacing scale (4/8/16/24/32/48), radius scale (8/12/16/24), and semantic colors prevent arbitrary values. The premium dark theme (`bgPrimary: 0xFF0A0E17`) creates a polished, modern aesthetic.

- **Clean login screen (App):** `LoginScreen` uses generous whitespace with `Spacer` widgets, centered layout, and a clean hierarchy: icon → title → subtitle → buttons → error. No unnecessary elements.

- **Success overlay with delight (App):** `success_overlay.dart` shows an animated checkmark with confetti burst and haptic feedback on successful actions. Adds emotional delight without cluttering the UI.

- **Staggered animations (App):** `StaggeredList` and `FadeIn` widgets add subtle entrance animations to list items, giving the app a polished feel.

- **Portal KPI cards (Portal):** Dashboard and data pages use consistent `StatBlock` + `DashboardCard` components with clear visual hierarchy: label (small, muted) → value (large, bold) → trend indicator.

**Bad:**

- **Portal sidebar has 24 items (Portal):** The sidebar lists all 24 navigation items vertically with no grouping, collapsing, or search. For assistant-role users who see fewer items it's manageable, but for `admin_master` users it's overwhelming.

- **MoreScreen is text-heavy (App):** `MoreScreen` has 15+ list tiles with subtitles, resulting in a long scrollable list. No visual grouping, icons are small, and the information density is high. Section headers exist but are visually subtle.

- **Some screens are data-dense (App):** `StaffCrmListScreen` and `StaffDashboardScreen` pack many data points into cards without progressive disclosure. All information is shown at once.

- **Profile screen jugggles too many concerns (App):** Edit name, upload avatar, social handles, delete account, logout — all on one screen without clear sections.

**Recommendations:**
1. Collapse portal sidebar into grouped sections with expandable headers.
2. Redesign MoreScreen with visual card grouping and prominent icons instead of flat list tiles.
3. Add progressive disclosure to dense data screens (show summary first, expand for details).
4. Split profile screen into sections with clear visual separation.

---

### H9: Help Users Recognize, Diagnose, and Recover from Errors (8/10)

**Good:**

- **Error message humanization (App):** `ErrorState.humanize()` (`error_state.dart:19-46`) translates raw exceptions to user-friendly Portuguese messages:
  - `SocketException` / `ClientException` → "Sem conexão com a internet. Verifique sua rede e tente novamente."
  - `timeout` → "A requisição demorou demais. Tente novamente."
  - `401` / `unauthorized` → "Sua sessão expirou. Faça login novamente."
  - `403` / `forbidden` → "Você não tem permissão para esta ação."
  - `404` → "O conteúdo não foi encontrado."
  - `500` → "Erro no servidor. Tente novamente em alguns minutos."
  - Raw messages > 100 chars → "Algo deu errado. Tente novamente."

- **Localized error variant (App):** `ErrorState.humanizeLocalized()` uses `AppLocalizations` for context-aware translations. Accessible: wraps error display in `Semantics(liveRegion: true)`.

- **Retry buttons everywhere (App):** `AppErrorState` and `ErrorState` both include "Tentar novamente" / retry buttons. Found in 38+ screens. `TodayScreen` error state (`today_screen.dart:374-407`) shows a retry button that resets the load timer and re-fetches data.

- **Auth failure handling (App):** `LoginScreen._handleFailure()` converts `AuthFailure` subtypes to specific messages. `AuthSocialCancelled` is silently ignored (correct — user chose to cancel).

- **Portal error boundaries (Portal):** Both `error.tsx` (route-level) and `global-error.tsx` (app-level) provide "Try Again" buttons with `reset()` callbacks. The error boundary pattern prevents white screens.

**Bad:**

- **Portal error messages are English-only (Portal):** "Something went wrong", "An unexpected error occurred", "Try Again" — all in English for a Portuguese-speaking audience. (`error.tsx:13`, `global-error.tsx:27`).

- **Portal error messages are generic (Portal):** "An unexpected error occurred. Please try again or contact support if the problem persists." — no differentiation between network errors, auth errors, or server errors.

- **Some raw error strings may leak (App):** `coaching_group_details_screen.dart:178` uses `e.toString()` in error handling. `profile_screen.dart:296` also processes `e.toString()`. While `ErrorState.humanize()` catches most cases, edge cases could show raw exception text.

- **Settings screen shows sanitized but technical errors (App):** `settings_screen.dart:594` strips Bearer tokens from error messages but still shows technical error text to users.

**Recommendations:**
1. Translate all portal error pages to Portuguese.
2. Add error categorization to portal error boundaries (network vs. auth vs. server).
3. Audit all `e.toString()` usages in presentation layer — route through `ErrorState.humanize()`.
4. In settings screen, replace technical error messages with user-friendly equivalents.

---

### H10: Help and Documentation (8/10)

**Good:**

- **9-slide onboarding tour (App):** `OnboardingTourScreen` covers all key features: Strava connection, challenges, assessoria, streaks, evolution tracking, friends, challenge types, OmniCoins, and athlete verification. Each slide has icon, title, and body text in clear Portuguese. Skip button available. Page indicator dots show progress.

- **First-use tip system (App):** `FirstUseTips` with 14 `TipKey` values ensures contextual hints appear exactly once per feature. `ContextualTipBanner` and `TipBanner` show animated, dismissible banners at the right moment (e.g., first wallet visit, first challenge screen).

- **Dedicated "How It Works" screen (App):** `HowItWorksScreen` accessible from Settings provides detailed reference documentation for Challenges (types, goals, winner determination), OmniCoins (source, purpose, rules), Verification (requirements, process), and Integrity (fraud prevention).

- **Inline explanatory text (App):** Challenge creation form explains each option as users select it. Strava CTA on TodayScreen explains the connection process and compatible watches. Wallet contextual tip explains OmniCoins purpose.

- **Support screen (App):** `support_screen.dart` provides a support ticket system where users can create tickets and receive responses.

- **Verification status explanation (App):** `AthleteVerificationScreen` explains what "7 corridas válidas" means and why verification matters.

**Bad:**

- **Portal has no onboarding or help (Portal):** New coaches signing into the portal for the first time get zero guidance. No tour, no tooltips, no "Getting Started" flow. With 24 sidebar items, first-time orientation is poor.

- **No in-app FAQ or knowledge base (App):** While "How It Works" covers game mechanics, there's no FAQ for common questions like "Why aren't my runs syncing?", "How do I change assessoria?", or "What if my opponent cheats?".

- **No tooltip on portal components (Portal):** Data tables, KPI cards, and financial figures have no hover tooltips explaining what metrics mean. "Trust Score", "Volume 7d / 30d", "Swap de Lastro" go unexplained.

- **No contextual help in portal forms (Portal):** Settings forms (branding, auto-topup, gateway selector) lack help text or info icons explaining what each field does.

**Recommendations:**
1. Add a first-time tour or onboarding checklist for new portal users.
2. Add tooltips to portal KPI cards and financial terms.
3. Create an in-app FAQ section (can be static Markdown rendered in a screen).
4. Add help text / info icons to portal form fields.

---

## Summary

### Best UX Moment

**TodayScreen** (`omni_runner/lib/presentation/screens/today_screen.dart`) is the product's UX crown jewel. It synthesizes the entire user experience into a single, glanceable dashboard:

- **Streak banner** with gradient, emoji, progress bar, and next milestone — motivational and informative
- **Active challenges** with time remaining and OmniCoin stakes — urgent and actionable
- **Strava connection CTA** that transforms into a "Boa! Você já correu hoje!" celebration when done
- **Run recap** comparing current vs. previous performance with trend arrows and percentage changes
- **Park check-in** auto-detected from GPS data — delightful and unexpected
- **Quick stats** showing level, XP, weekly sessions, lifetime distance in compact chips
- **Shimmer loading** that mirrors the final layout structure
- **Error state** with friendly message and retry button
- **First-use tip** explaining Strava integration
- **Pull-to-refresh** for manual data reload
- **Run journal** with mood picker and auto-save

This screen demonstrates Nielsen's heuristics at their best: visibility of status, recognition over recall, match with real-world running culture, aesthetic minimalism with clear hierarchy, and contextual help.

### Worst UX Moment

**Portal error pages** (`portal/src/app/(portal)/error.tsx`, `portal/src/app/global-error.tsx`) are the weakest UX point in the entire product:

- **English-only** in a Portuguese product: "Something went wrong" / "Try Again"
- **No error categorization**: Same generic message for network issues, auth expiry, and server errors
- **No recovery guidance**: Doesn't suggest checking internet, re-logging, or contacting support with a ticket ID
- **No branding**: Uses hardcoded blue (`#2563eb`) instead of the assessoria's brand color
- **No navigation**: No sidebar, no header — user is stranded with only a "Try Again" button

This is exactly the moment users need the most help, and the product provides the least.

### Top 5 Quick Wins

| # | Quick Win | Impact | Effort | Files to Change |
|---|-----------|--------|--------|-----------------|
| 1 | **Translate portal error pages to Portuguese** | High — every user sees these eventually | Low | `portal/src/app/(portal)/error.tsx`, `portal/src/app/global-error.tsx` |
| 2 | **Add icons to portal sidebar** | High — used on every page visit | Low | `portal/src/components/sidebar.tsx` |
| 3 | **Group portal sidebar into collapsible sections** | High — reduces cognitive load for 24-item nav | Medium | `portal/src/components/sidebar.tsx` |
| 4 | **Add "Discard changes?" dialog to forms** | Medium — prevents accidental data loss | Low | `challenge_create_screen.dart`, `announcement_create_screen.dart`, `staff_workout_builder_screen.dart`, `profile_screen.dart` |
| 5 | **Add client-side search to portal data tables** | High — critical for assessorias with 50+ athletes | Medium | `portal/src/app/(portal)/athletes/page.tsx`, `portal/src/app/(portal)/crm/page.tsx` |

---

## Appendix: Evidence Inventory

### Pattern Coverage (App — 100 screens)

| Pattern | Screens with Pattern | Coverage |
|---------|---------------------|----------|
| Loading indicator (shimmer or spinner) | 89 | 89% |
| Error state with retry | 38 | 38% |
| Empty state with CTA | 16 | 16% |
| Pull-to-refresh | 40 | 40% |
| `_busy` guard | 20+ | ~20% |
| Form validation | 18 | 18% |
| Semantics/accessibility | 20 | 20% |
| SnackBar feedback | 50+ | ~50% |
| Confirm dialog for destructive actions | 12 | 12% |

### Pattern Coverage (Portal — 55 pages)

| Pattern | Pages with Pattern | Coverage |
|---------|-------------------|----------|
| `loading.tsx` skeleton | 39 | 71% |
| Error boundary | 2 (global) | 100% (via hierarchy) |
| `ConfirmDialog` for destructive actions | 5 | ~9% |
| Toast feedback | 7 files | ~13% |
| Form validation (client-side) | Limited | ~10% |
| Search/filter | 3 pages | ~5% |
| Keyboard shortcuts | 0 | 0% |
| i18n via `useTranslations` | 5 components | ~9% |
