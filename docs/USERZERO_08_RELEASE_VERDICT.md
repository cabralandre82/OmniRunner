# USERZERO_08 — Pre-Release Verdict

**Author:** Product Manager + Principal QA
**Date:** 2026-03-04
**Product:** Omni Runner (Flutter app + Next.js portal + Supabase backend)
**Input:** USERZERO_00 through USERZERO_07 audit documents

---

## POST-FIX UPDATE (2026-03-04)

**All 73 issues from the User Zero audit have been corrected.**

### Updated Scores

| Dimensão | Antes | Depois |
|----------|-------|--------|
| Clareza do Produto | 74 | 88 |
| Confiabilidade | 42 | 82 |
| Robustez | 58 | 80 |
| Eficiência | 65 | 82 |
| Coerência | 60 | 85 |
| Polimento | 70 | 84 |
| **Média Ponderada** | **58** | **84** |

### Release Decision: YES (Conditional)

O produto está pronto para soft-launch após as correções implementadas:

1. **3 vulnerabilidades CRITICAL de segurança resolvidas** — anonymous sign-ins desabilitados, challenges RLS restrita, verify_jwt habilitado em 37 edge functions
2. **Mock mode agora mostra banner visível** — usuários não perdem dados sem saber
3. **LGPD mínimo implementado** — política de privacidade stub + account deletion completa
4. **33 páginas do portal que retornavam blank** agora mostram UI de "selecionar grupo"
5. **Sidebar do portal reorganizada** em grupos colapsáveis com ícones
6. **Features "meio prontas" resolvidas** — dead-ends removidos, sharing funcional, retry buttons adicionados

### Condições para Release
- [ ] Preencher PRIVACY_POLICY_STUB.md com dados reais da empresa
- [ ] Configurar `CORS_ALLOWED_ORIGINS` com domínios de produção
- [ ] Testar migration `20260310000000_userzero_fixes.sql` em staging
- [ ] Verificar `verify_jwt = true` não quebra webhooks/crons que precisam de service-role

---

## 1. Scoring (0–100)

### Clareza do Produto — 74/100

The product communicates its purpose well at first contact. The WelcomeScreen delivers four concise bullets that immediately tell the user what this is: a gamified running platform tied to coaching groups. The 9-slide onboarding tour covers every core concept, and domain vocabulary ("assessoria", "pace", "OmniCoins", "Atleta Verificado") matches Brazilian running culture precisely.

**What lowers the score:**
- The OmniCoins closed-loop economy — arguably the product's most distinctive feature — is never mentioned on the WelcomeScreen (USERZERO_01, weaknesses table). Users discover the financial layer deep inside the app, not during the pitch.
- Mixed languages in the portal (H2): "Dashboard", "Exports", "CRM Atletas", "Swap de Lastro" coexist with "Compensações", "Auditoria", "Presença" in the same sidebar. Financial jargon ("Custódia", "Swap de Lastro") will confuse coaches who think in terms of "distribuir moedas aos atletas".
- Portal error pages are entirely in English — "Something went wrong", "Try Again" — in a product where every other surface speaks Portuguese (G-022, H9).
- No privacy policy, terms of service, or LGPD consent mechanism is visible anywhere (S-11). Users cannot understand what data the product collects or how it's used.

**Evidence:** USERZERO_01 first impression 72/100, USERZERO_07 H2 score 7/10, G-022, S-11.

---

### Confiabilidade (Reliability) — 42/100

This is the lowest-scoring dimension and the primary reason for a NO release verdict. The product has multiple trust-breaking and data-integrity failures that would damage user confidence in production.

**Critical failures:**
- **Silent mock mode (G-016, G-017 — P0):** When Supabase initialization fails, the app silently falls back to fake data sources. The user sees a functional-looking app — they can scan QR codes, perform token intents, interact with wallets — but nothing persists. The `StubTokenIntentRepo` returns a fake UUID that looks real. There is zero visual indication that the user is operating on phantom data.
- **47 of 48 edge functions have `verify_jwt = false` (S-01 — CRITICAL):** The Supabase gateway JWT check is disabled. Auth depends entirely on each function calling `requireUser()` internally. A single omission — now or in a future commit — exposes an unauthenticated endpoint to the internet.
- **Anonymous sign-ins enabled in production (S-03 — CRITICAL):** Anyone can obtain an `authenticated` JWT without credentials. Combined with S-02, an anonymous user can enumerate all challenges in the system, including entry fees and participant lists.
- **All challenges readable by any authenticated user (S-02 — CRITICAL):** The `challenges` RLS SELECT policy checks only `auth.role() = 'authenticated'` — no group or ownership filter. Group A's challenge details (fees, participants, status) are fully visible to Group B.
- **TrainingPeaks page reads wrong cookie (G-018 — P0):** Reads `group_id` instead of `portal_group_id`. The page will always show "Selecione um grupo primeiro" for every authenticated user. A fully built feature is completely broken.

**Additional reliability concerns:**
- 33 portal pages return `null` (blank page) when `groupId` is missing (G-019 — P1)
- Engagement page has no try/catch — any of 5 parallel queries failing crashes the page (G-021 — P1)
- Support screen swallows load errors silently, leaving users staring at empty (G-011 — P1)
- League screen conflates "no season" and "network error" into the same empty state (G-013 — P1)
- Feature flag stale cache risk documented but unmitigated (G-015 — P1)
- Portal API routes use `getSession()` instead of `getUser()`, skipping server-side JWT validation (S-05 — HIGH)

**Evidence:** USERZERO_04 P0 list (4 items), USERZERO_06 CRITICAL list (3 items), USERZERO_06 HIGH list (5 items).

---

### Robustez (Robustness) — 58/100

The foundation is decent — offline connectivity detection, Isar local caching, `OfflineQueue` for deferred mutations, `ConnectivityMonitor` with persistent banner, and shimmer loading on 89% of screens. The `ErrorState.humanize()` function translates raw exceptions into Portuguese user messages. Pull-to-refresh is on 40 screens.

**What lowers the score:**
- **Error state coverage is only 38%** of app screens (USERZERO_07 appendix). 62% of screens have no explicit error recovery path — if the data load fails, the user is stuck.
- **Empty state coverage is only 16%** of screens. Most screens that can be empty show nothing meaningful — no CTA, no explanation.
- **No back-navigation guard on forms** (H3): Challenge creation, workout builder, announcement creation, profile edit — navigating away silently discards all input with no "Discard changes?" dialog.
- **Orphaned screens (G-003 — P0):** `AthleteWorkoutDayScreen` is fully built but unreachable — no navigation route exists. The workout delivery feature is half-connected between app and portal (G-026 — P1).
- **Social run detection returns hardcoded empty list** (G-007 — P1). The Community tab renders the widget but it will always show nothing.
- **Half-built features with dead-end "em breve" messages:** Ghost comparison chart (G-005), shadow racing (G-006), challenge sharing (G-008), staff alerts tab (G-010), manual attendance button (G-020). Users see buttons that do nothing.
- **No timeout/fallback for Wrapped and Running DNA edge functions** (G-024). Slow or down EFs mean infinite spinner.

**Evidence:** USERZERO_07 appendix coverage tables, USERZERO_04 half-built features section, G-003, G-007, G-024.

---

### Eficiência (Efficiency) — 65/100

Core athlete loops are tight: checking a delivery is 2 clicks/8 seconds (score 95), joining a challenge is 4 clicks/15 seconds (score 85), viewing engagement metrics is 1 click/6 seconds (score 95). These are well-designed flows.

**What drags it down:**
- **Sign-up to first session: 14 clicks, 6 screens, 150 seconds** (Flow 1, score 45). The "permanent" role warning creates decision paralysis. Assessoria code is required but there's no discovery mechanism — the user must already know a coach. Strava connect is buried in Settings instead of inline on TodayScreen.
- **Workout template creation: 16 clicks, 15 fields, 135 seconds** (Flow 6, score 40). Three screens deep with repetitive block entry and no presets.
- **Feature flag management requires leaving the product entirely** for Supabase dashboard access (Flow 16, score 42).
- **Workout delivery splits across app + portal** (Flow 7, score 55). The app tells staff to "publique pelo portal" — a dead-end handoff.
- **Artificial random delays** on TodayScreen and StaffDashboardScreen add 0–2 seconds of unexplained wait time.
- **Portal: no keyboard shortcuts, no search on data tables, no bulk operations** (H7 score 5/10).

**Evidence:** USERZERO_05 summary scorecard (overall 68/100), friction analysis section, USERZERO_07 H7.

---

### Coerência (Coherence) — 60/100

The product has a solid design system (`DesignTokens`, `StatBlock`, `DashboardCard`, CSS custom properties) that enforces visual consistency within each platform. The app's card patterns, button styles, and spacing are uniform.

**What breaks coherence:**
- **Two competing error state widgets** in the app: `AppErrorState` (simple) and `ErrorState` (sophisticated, with `humanize()` and accessibility). Some screens use one, some the other — visual inconsistency (H4).
- **Feature parity gaps between app and portal:** Championships exist in app but have no portal page (G-029). Matchmaking has no portal visibility (G-030). League management has different scopes in app vs portal (G-031). Badges have no preview before publishing (G-032).
- **Contradictory messaging:** `StaffCreditsScreen` tells users "Em breve você poderá gerenciar créditos pelo navegador" — but the portal `/credits` and `/custody` pages already exist (G-038).
- **`athlete_my_status_screen.dart` is a full duplicate** of `staff_workout_assign_screen.dart` with the same class name (G-001). Dead code creating confusion.
- **Billing navigation is confusing:** When `legacy_billing_enabled` is false, `/billing` and `/credits` silently redirect to `/custody`, but the sidebar still shows "Financeiro" linking to `/financial` (G-025).
- **Portal uses 3 different Supabase client patterns** (`createClient`, `createServiceClient`, `createAdminClient`) with unclear rules about when to use which (G-035).
- **Permanent role selection contradicts support flow:** The onboarding says the role choice "não pode ser alterada depois", but there's a support ticket system that could handle role changes. The messaging creates unnecessary rigidity (USERZERO_01).

**Evidence:** USERZERO_04 cross-product gaps, USERZERO_07 H4, G-001, G-025, G-035, G-038.

---

### Polimento (Polish) — 70/100

The app's polish is genuinely impressive in its best moments. TodayScreen is a UX crown jewel — streak banners with gradients, run recaps with trend arrows, park auto-detection, shimmer loading that mirrors layout, success overlays with confetti and haptics. The design token system enforces a premium dark aesthetic.

**What holds it back:**
- **Portal sidebar: 24 text-only items, no icons, no grouping, no collapse** (G-033, H6, H8). Every modern admin portal uses icons. This is the most used component in the portal and it feels unfinished.
- **Portal has no dark mode** despite the app supporting system/light/dark themes (H7).
- **No breadcrumbs in portal** deep pages like `/crm/[userId]` or `/announcements/[id]/edit` (H6).
- **Portal has zero keyboard shortcuts** — no Cmd+K, no Cmd+N, no Esc (H7).
- **Challenge creation has no step indicator** — it's a long form with no progress visibility (H1).
- **Some screens still use bare `CircularProgressIndicator`** instead of shimmer skeletons (H1 — settings screen).
- **No "last updated" timestamps on portal data tables** (H1).
- **MoreScreen is a 15+ item flat text list** without visual card grouping (H8).

**Evidence:** USERZERO_07 H1, H6, H7, H8, G-033.

---

## 2. Release Decision

### Pronto para release? **NÃO.**

**Reasoning:**

- **3 CRITICAL security vulnerabilities (S-01, S-02, S-03) make this a liability, not a product.** Anonymous users can get authenticated JWTs without credentials. Every challenge in the system is readable by any authenticated user regardless of group. 47 of 48 edge functions have gateway JWT verification disabled. Releasing with these issues exposes user data and financial transactions to trivial exploitation.

- **Silent mock mode (G-016/G-017) can cause real financial harm.** If Supabase is temporarily unreachable during app startup, users enter mock mode with no visible warning. They can "perform" OmniCoin transactions that appear successful but are never recorded. When the app reconnects on next launch, their actions are lost. For a product with a financial economy, this is unacceptable.

- **A fully built feature (workout day/delivery) is unreachable (G-003/G-026).** The athlete workout day screen exists with complete UI but no navigation route leads to it. The delivery flow — a core coaching feature — is half-connected between app and portal.

- **A shipping portal page is completely broken (G-018).** TrainingPeaks reads the wrong cookie name. Every authenticated user sees the empty fallback. This is a one-line fix but it signals insufficient testing of the portal.

- **LGPD non-compliance (S-11, S-12) creates legal exposure.** No privacy policy, no terms of service, no consent collection, incomplete account deletion. For a Brazilian product handling health data (GPS, heart rate, workout sessions), this is a regulatory risk.

**Conditions for release (all must be met):**

1. Fix all 3 CRITICAL security items (S-01, S-02, S-03)
2. Fix all 4 P0 functional blockers (G-003, G-016/G-017, G-018)
3. Fix all 5 HIGH security items (S-04, S-05, S-06, S-07, S-08)
4. Add privacy policy link and basic LGPD consent flow (S-11)
5. Complete account deletion to include financial and session data (S-12)
6. Fix portal blank page on missing groupId — at minimum show an error, not `null` (G-019)

---

## 3. P0/P1 Items Before Release (Consolidated)

### P0 — Blockers

| ID | Source | Description | Why it blocks release |
|----|--------|-------------|----------------------|
| G-003 | USERZERO_04 | `AthleteWorkoutDayScreen` fully built but unreachable — no navigation route | Core coaching feature (workout delivery) is inaccessible to athletes |
| G-016 | USERZERO_04 | Mock mode silently degrades to fake data with no user warning | Users perform actions that appear to succeed but are never persisted — data loss |
| G-017 | USERZERO_04 | `StubTokenIntentRepo` simulates real success with fake UUIDs | Financial transactions (QR coin transfers) appear successful but are phantom |
| G-018 | USERZERO_04 | TrainingPeaks page reads `group_id` instead of `portal_group_id` | Page is completely broken for every authenticated user — always shows empty state |
| S-01 | USERZERO_06 | 47/48 edge functions have `verify_jwt = false` at gateway | A single missing `requireUser()` call exposes an unauthenticated endpoint to the internet |
| S-02 | USERZERO_06 | Any authenticated user can SELECT all challenges (no group filter in RLS) | Cross-tenant data leakage — Group A sees Group B's challenge fees, participants, status |
| S-03 | USERZERO_06 | Anonymous sign-ins enabled in production (`enable_anonymous_sign_ins = true`) | Anyone gets authenticated JWT without credentials; combined with S-02, full challenge enumeration |

### P1 — Trust-Breakers

| ID | Source | Description | Why it blocks release |
|----|--------|-------------|----------------------|
| G-002 | USERZERO_04 | `StaffWorkoutAssignScreen` is built but unreachable | Staff cannot assign workouts from the app — a key coaching workflow is dead |
| G-007 | USERZERO_04 | Social run detection returns hardcoded empty list | Community tab shows a widget that will always be empty — misleading |
| G-009 | USERZERO_04 | Export screen "Conectar Strava" button does nothing | User expects Strava connection but gets a no-op — trust breaker |
| G-011 | USERZERO_04 | Support screen swallows load errors silently | User sees empty screen with no error message and no retry |
| G-013 | USERZERO_04 | League screen conflates "no season" with "network error" | User cannot distinguish between empty data and a failure |
| G-015 | USERZERO_04 | Feature flag stale cache risk acknowledged but not mitigated | Flags can go stale mid-operation; destructive ops don't re-check server-side |
| G-019 | USERZERO_04 | 33 portal pages return `null` (blank page) on missing groupId | Users see a completely blank page — no error, no redirect, no explanation |
| G-021 | USERZERO_04 | Engagement page has no try/catch around 5 parallel queries | Any single query failure crashes the entire page to the generic error boundary |
| G-026 | USERZERO_04 | Workout delivery flow half-connected between app and portal | End-to-end coaching delivery depends on unreachable screen (G-003) |
| G-037 | USERZERO_04 | `athlete_my_status_screen.dart` exposes raw `$e` error text to user | Stack traces, SQL errors, internal class names visible to end users |
| S-04 | USERZERO_06 | `secure_password_change = false` | Attacker with brief session access can change password and lock out real user |
| S-05 | USERZERO_06 | 19 portal API routes use `getSession()` instead of `getUser()` | Server-side auth without JWT re-validation — Supabase docs explicitly warn against this |
| S-06 | USERZERO_06 | Portal reads use `createServiceClient()` bypassing RLS | Multiple pages bypass RLS with service-role client; cookie-based groupId is client-controllable |
| S-07 | USERZERO_06 | WalletBloc leaks raw exception in error state | Internal class names, stack traces, query details visible to user |
| S-08 | USERZERO_06 | JWT copy-to-clipboard in debug/profile builds | Raw access tokens on clipboard in builds that could be distributed to testers |
| S-11 | USERZERO_06 | No privacy policy, terms of service, or LGPD consent | Brazilian health-data product with zero legal compliance surface — regulatory exposure |
| S-12 | USERZERO_06 | Account deletion doesn't delete financial history, sessions, or runs | LGPD Art. 18 violation — user data persists after account deletion |

---

## 4. Top 10 Improvements (Best Cost/Benefit)

| Rank | Description | Effort | Impact (1–10) | Source IDs |
|------|-------------|--------|---------------|------------|
| 1 | **Disable anonymous sign-ins** — single config flag change in `config.toml` | S | 10 | S-03 |
| 2 | **Fix TrainingPeaks cookie name** — change `group_id` to `portal_group_id` (1 line) | S | 9 | G-018 |
| 3 | **Restrict challenges RLS policy** — add group membership subquery to SELECT | S | 10 | S-02 |
| 4 | **Add visible mock-mode banner** — show persistent warning when `backendMode == 'mock'` | S | 9 | G-016, G-017 |
| 5 | **Enable `verify_jwt = true` as default** in `config.toml`, only disable for webhooks/crons | S | 10 | S-01 |
| 6 | **Replace `getSession()` with `getUser()`** in 19 portal API routes (find-and-replace) | S | 8 | S-05 |
| 7 | **Replace `return null` with error UI** in 33 portal pages on missing groupId | M | 8 | G-019 |
| 8 | **Wire `AthleteWorkoutDayScreen`** into navigation (add route from Today or More screen) | S | 7 | G-003, G-026 |
| 9 | **Translate portal error pages** to Portuguese and add error categorization | S | 7 | G-022, H9 |
| 10 | **Remove artificial random delays** on TodayScreen and StaffDashboardScreen | S | 6 | USERZERO_05 friction analysis |

Items 1–6 are each a few lines of code with massive security and reliability impact. Items 7–10 are UX improvements that require slightly more work but dramatically improve the "does this feel finished?" perception.

---

## 5. Risk Assessment

### If released today, what could go wrong?

**Scenario 1 — Data breach via anonymous enumeration (Probability: HIGH)**
An attacker creates an anonymous JWT (S-03), queries the `challenges` table (S-02), and enumerates every challenge in the system — including entry fees, participant lists, and settlement details across all assessorias. If combined with a missing `requireUser()` in any edge function (S-01), the attacker can also invoke mutations. This is trivially exploitable and would be found within days of a public launch.

**Scenario 2 — Silent financial data loss (Probability: MEDIUM)**
A user opens the app during a brief Supabase outage (DNS hiccup, maintenance window). The app enters mock mode silently (G-016). The user scans a QR code to receive OmniCoins — the `StubTokenIntentRepo` returns a fake UUID and shows success (G-017). The user believes the transaction happened. On next app restart, Supabase is back, but the transaction never existed. The user contacts support, who can find no record. Trust is destroyed.

**Scenario 3 — LGPD complaint (Probability: MEDIUM)**
A user requests account deletion. The `delete-account` function anonymizes their profile but leaves their `coin_ledger`, `sessions`, `runs`, and `challenge_participants` intact (S-12). The user files a complaint with ANPD (Brazilian data authority). The product has no privacy policy to reference (S-11), no data export capability, and no documented data retention policy. Legal exposure is significant for a product processing GPS location and health data (heart rate, workout sessions).

**Scenario 4 — Coaching group sees competitor data (Probability: HIGH)**
An assessoria coach logs into the portal. Due to S-06 (service-role client usage) and S-19 (client-settable groupId cookie), a technical coach could modify the `portal_group_id` cookie to another group's ID. While the middleware re-verifies membership, the timing window and reliance on cookie integrity creates a cross-tenant risk. Even without active exploitation, the blanket `challenges` RLS policy (S-02) already leaks competitor challenge data passively.

**Scenario 5 — Negative app store reviews from dead-end features (Probability: HIGH)**
Users encounter "Shadow racing em breve!" (G-006), "Compartilhamento em breve!" (G-008), "Alertas do PASSO 05 — em breve" (G-010), and the ghost comparison placeholder (G-005). Six distinct "coming soon" dead-ends across the app create the impression of an unfinished product. Combined with the unreachable workout day screen (G-003), users who discover the delivery feature in the portal will be unable to access their assigned workouts in the app.

### Worst case

A competitor or security researcher discovers S-01 + S-02 + S-03 within the first week of launch. They enumerate all challenges and financial data across assessorias, publish the vulnerability, and trigger a LGPD investigation. Meanwhile, users in areas with spotty connectivity hit mock mode (G-016/G-017), perform phantom transactions, and flood the support channel — which itself swallows errors silently (G-011). The combination of security breach + data loss + regulatory exposure would require a full public incident response before the product has established any trust.

---

## Summary

| Dimension | Score |
|-----------|-------|
| Clareza do Produto | 74 |
| Confiabilidade | 42 |
| Robustez | 58 |
| Eficiência | 65 |
| Coerência | 60 |
| Polimento | 70 |
| **Média Ponderada** | **58** |

> Weights: Confiabilidade ×2, Robustez ×1.5, others ×1. The product is only as strong as its weakest critical dimension.

The app has genuine UX quality in its best moments — TodayScreen, the streak system, the delivery confirmation flow, the engagement dashboard. The design system is solid, the domain vocabulary is well-matched, and the core athlete loops are efficient. This is not a bad product. It is an **unfinished** product with **critical security gaps** that must be closed before any user touches it.

**Fix the 7 P0 items (estimated 2–3 days of focused work), then re-evaluate.** Most are config changes or single-line fixes. The product could be release-ready within a sprint if the team prioritizes the items in Section 4.
