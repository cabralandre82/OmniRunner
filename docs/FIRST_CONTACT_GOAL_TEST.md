# FASE 3 — Intuitive Goal Test

**Tester:** UX Researcher (first-time user, no docs, no backend code)
**Date:** 2026-03-04
**Method:** Screen-by-screen trace through Flutter source at `omni_runner/lib/presentation/screens/`

---

## Chosen Goal: B — "I want to join a challenge"

**Rationale:** The very first bullet on the Welcome screen is "Desafie corredores" (Challenge runners). This is the single clearest call-to-action the app communicates to a new user. The onboarding tour also devotes 3 of 9 slides to challenges. A new user's most natural first goal is: *"Let me challenge someone."*

---

### End-to-End Flow Trace

| Step | Screen (file) | Action | Result | BLOCKER? |
|------|--------------|--------|--------|----------|
| 1 | `welcome_screen.dart` | See logo + 4 bullets + "COMEÇAR" button. Tap **COMEÇAR**. | Navigates to Login screen. | No |
| 2 | `login_screen.dart` | See "Entrar no Omni Runner" + 4 sign-in options (Google, Instagram, Email, Apple on iOS). Tap **Continuar com Google**. | OAuth flow triggers. On success, calls `onSuccess`. | No |
| 3 | `onboarding_role_screen.dart` | See "Como você quer usar o Omni Runner?" with 2 role cards. Select **"Sou atleta"**. Tap **Continuar**. | Confirmation dialog appears: "Essa escolha é permanente." | No |
| 4 | `onboarding_role_screen.dart` (dialog) | Read scary warning about permanent choice. Tap **"Sim, sou Atleta"**. | Calls `set-user-role` Edge Function. Resolves to JoinAssessoria step. | **Friction** — permanent choice with no "undo" creates anxiety |
| 5 | `join_assessoria_screen.dart` | See "Encontre sua assessoria" with search bar, QR scanner, and "Tenho um código" button. **I don't have a code yet.** Tap **"Pular — posso entrar depois"**. | Sets `onboarding_state → READY`. Navigates to tour. | No |
| 6 | `onboarding_tour_screen.dart` | See 9-slide tour (Strava, challenges, assessoria, streaks, evolution, friends, challenge types, OmniCoins, verification). Tap **Pular** to skip. | Marks tour as seen. Navigates to HomeScreen. | No |
| 7 | `home_screen.dart` → `athlete_dashboard_screen.dart` | See "Olá, atleta!" + "O que deseja fazer hoje?" + TipBanner with first steps + grid of 7 cards. See **"Meus desafios"** card with subtitle "Competir e acompanhar". Tap it. | Guard check: `LoginRequiredSheet.guard` → passes (logged in). **Guard check: `AssessoriaRequiredSheet.guard` → BLOCKS** because `_assessoriaGroupId == null` (we skipped assessoria). | **YES — BLOCKER** |
| 8 | (bottom sheet from `AssessoriaRequiredSheet`) | See message explaining assessoria is required. Options: go join one or dismiss. | User is stuck. Must go back, find an assessoria, get approved, then retry. | **YES — BLOCKER** |

**Flow BREAKS at Step 8.** The user cannot access challenges without belonging to an assessoria.

---

### Recovery Path (if user goes to join assessoria)

| Step | Screen (file) | Action | Result | BLOCKER? |
|------|--------------|--------|--------|----------|
| 9 | `athlete_dashboard_screen.dart` | Tap **"Entrar em assessoria"** card (shows "Toque para se juntar"). | Navigates to `JoinAssessoriaScreen`. | No |
| 10 | `join_assessoria_screen.dart` | Search by name, scan QR, or enter code. Suppose I search "Minha assessoria". | Calls `fn_search_coaching_groups` RPC. Shows results. | No |
| 11 | `join_assessoria_screen.dart` | Tap a result. Confirmation dialog: "Solicitar entrada?" | User taps **Solicitar**. Request is sent. | No |
| 12 | `join_assessoria_screen.dart` (dialog) | See "Solicitação enviada!" with message that staff must approve. | User taps "Entendi". Returns to dashboard. | **YES — BLOCKER** (must wait for approval) |
| 13 | `athlete_dashboard_screen.dart` | Pending request banner shown: "Aguardando aprovação da assessoria". Cannot access challenges until approved. | Dead end — user must wait indefinitely for human approval. | **YES — BLOCKER** |

**Total steps to reach challenges (if ever approved):** 13+ (requires external human action)

---

### Alternative Path: Challenges via "Hoje" Tab

| Step | Screen (file) | Action | Result | BLOCKER? |
|------|--------------|--------|--------|----------|
| 7b | `today_screen.dart` (tab "Hoje") | See streak banner (0 streak), Strava connect prompt, and empty run recap. Active challenges section only shows if user has challenges. | No challenges visible, no way to create one from here. | **YES — Dead end** |

---

### Alternative Path: Challenges via "Meu progresso"

| Step | Screen (file) | Action | Result | BLOCKER? |
|------|--------------|--------|--------|----------|
| 7c | `athlete_dashboard_screen.dart` | Tap **"Meu progresso"** card. | Opens `ProgressHubScreen`. | No |
| 8c | `progress_hub_screen.dart` | See list with "Desafios — Desafios 1v1 e em grupo" tile. Tap it. | Opens `ChallengesListScreen` (with its own BlocProvider). **But this path bypasses the assessoria guard!** | No (but guard may fire elsewhere) |

**Observation:** The progress hub route to challenges does NOT have the assessoria guard — it creates its own BlocProvider and navigates directly. This is an inconsistency. The challenge list will load, but creating/joining challenges with OmniCoins requires verification (7 valid runs).

---

### Flow Summary — Goal B

| Metric | Value |
|--------|-------|
| **Total steps to complete goal** | 13+ (never fully completes without external approval) |
| **Steps where user gets stuck** | 3 (step 8: assessoria required; step 12-13: approval wait; step 7b: no challenges visible) |
| **Steps where feedback is clear** | 7 of 8 initial steps (clear feedback on buttons, transitions, dialogs) |
| **Does the flow succeed end-to-end?** | **NO** — blocked by assessoria requirement + approval wait |

### Key Issues Found

1. **BLOCKER: Assessoria required for challenges.** The welcome screen says "Desafie corredores" as the #1 value prop, but a new user cannot access challenges without joining an assessoria AND being approved by staff. This is a broken promise.

2. **BLOCKER: Approval is asynchronous.** Even after requesting to join an assessoria, the user must wait for a human to approve. There's no estimated time, no way to expedite, no fallback.

3. **Inconsistent guard:** Dashboard → Challenges has the assessoria guard, but Progress Hub → Challenges does NOT. Users could discover the backdoor by accident.

4. **No Strava = no challenge data.** Even if the user reaches challenges, runs are only imported via Strava. A user without Strava connected has zero runs and cannot participate.

5. **Missing "Start Run" button.** The "Hoje" tab shows "Bora correr?" but there's no button to start a run — the app relies entirely on Strava import. This violates the expectation set by "Bora correr?".

---

## Portal Goal: D — "I want to see how my group is doing"

**Persona:** Assessoria staff member logging into the app to check group performance.

### End-to-End Flow Trace

| Step | Screen (file) | Action | Result | BLOCKER? |
|------|--------------|--------|--------|----------|
| 1 | `welcome_screen.dart` | Tap **COMEÇAR**. | → Login screen. | No |
| 2 | `login_screen.dart` | Sign in with Google (or other method). | → Auth resolves. | No |
| 3 | `onboarding_role_screen.dart` | Select **"Represento uma assessoria"**. Tap Continuar → Confirm. | Calls `set-user-role` with `ASSESSORIA_STAFF`. → StaffSetupScreen. | No |
| 4 | `staff_setup_screen.dart` | (Not fully traced — requires creating or joining an assessoria as staff.) Assume setup completes. | `onboarding_state → READY`. → HomeScreen with `userRole = 'ASSESSORIA_STAFF'`. | No |
| 5 | `home_screen.dart` → `staff_dashboard_screen.dart` | See assessoria name + "Painel da assessoria" + grid of 12 cards. See **"Performance"** card with subtitle "Visão geral da assessoria". Tap it. | Opens `StaffPerformanceScreen`. | No |
| 6 | `staff_performance_screen.dart` | See performance overview for the group. | Data displayed based on group members' activity. | No |
| 7 | `staff_dashboard_screen.dart` | Alternative: Tap **"Atletas e Staff"** card. | Opens `CoachingGroupDetailsScreen` showing member list + roles. | No |
| 8 | `staff_dashboard_screen.dart` | Alternative: Tap **"Portal"** card. | Opens `https://omnirunner.app` in external browser via `url_launcher`. | No |

### Portal Path Summary

| Metric | Value |
|--------|-------|
| **Total steps to see group performance** | 6 (Welcome → Login → Role → Setup → Dashboard → Performance) |
| **Steps where user gets stuck** | 0 (assuming assessoria setup succeeds) |
| **Steps where feedback is clear** | 6/6 — clear labels, card titles descriptive |
| **Does the flow succeed end-to-end?** | **YES** — the staff dashboard is well-organized and provides direct access to all management features |

### Portal Observations

1. **Staff tabs are minimal:** only 2 bottom tabs (Início, Mais) vs. athlete's 4. This is clean and appropriate — staff doesn't need "Hoje" or "Histórico".

2. **Dashboard card grid is dense:** 12 cards in a 2-column grid requires scrolling. The cards are well-labeled but a new staff member may feel overwhelmed.

3. **"Portal" card opens external URL.** This is a browser redirect to `https://omnirunner.app` — the user leaves the app entirely. No indication of what the portal offers vs. the app. The card subtitle says only "Abrir no navegador" which is unhelpful.

4. **No inline preview of group metrics.** The dashboard shows member count but no KPIs (total km this week, active athletes %, etc.). Staff must tap into sub-screens to see any data.

5. **Approval gating exists:** If the platform hasn't approved the assessoria yet (`approval_status != 'approved'`), the staff sees only a "Aguardando aprovação" message and cannot access ANY feature. This is appropriate but should show estimated wait time.

---

## Overall Assessment

| Goal | Completable? | Steps | Blockers | Verdict |
|------|-------------|-------|----------|---------|
| B: Join a challenge | **NO** | 13+ | 3 | Welcome screen promises "Desafie corredores" but cannot be fulfilled without assessoria + approval |
| D: See group status (portal) | **YES** | 6 | 0 | Clean, functional flow for staff role |

**Most critical finding:** The app's #1 value proposition (challenges) is gated behind a multi-step process that requires an external human to approve. A new user who downloads the app because "Desafie corredores" excited them will hit a wall within 2 minutes of onboarding.
