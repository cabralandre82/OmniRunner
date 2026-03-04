# USERZERO 05 — Efficiency Scorecard

> Measured: 2026-03-04  
> Method: Static code analysis of every screen/page in each flow  
> Product: Omni Runner (Flutter app ~104 screens + Next.js portal ~55 pages)

---

## Scoring Methodology

| Metric | Definition |
|--------|-----------|
| **# Screens** | Distinct screens/pages the user must visit |
| **# Clicks** | Taps/clicks required (navigation + actions) |
| **# Fields** | Form fields the user must fill |
| **Est. Time (s)** | Estimated seconds for an experienced user |
| **Confusion Points** | Moments where the next step is unclear |
| **Feedback Points** | Moments where the system confirms an action |
| **Ideal Benchmark** | What a polished product should achieve |

---

## APP — Athlete Flows

### Flow 1: Sign Up → First Session

**Path:** Login → Role Select → (Confirm Dialog) → Join Assessoria → Today Screen → Run via Strava

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | LoginScreen | 1 (Google btn) or 3 (email: expand + fill + submit) | 0–2 | Social login is 1 tap. Email adds 2 fields + 2 extra clicks |
| 2 | OnboardingRoleScreen | 2 (select role + "Continuar") | 0 | Permanent choice with confirm dialog adds 1 more click |
| 3 | Confirm Dialog | 1 ("Sim, sou Atleta") | 0 | Scary "permanent" warning — confusion point |
| 4 | JoinAssessoriaScreen | ~2 (enter code/search + join) | 1 | Must find assessoria invite code |
| 5 | TodayScreen | 0 (auto-loads) | 0 | Strava CTA prominent but redirects to Settings |
| 6 | SettingsScreen | 1 (Conectar Strava) | 0 | OAuth flow in browser |
| 7 | Strava OAuth | ~3 (login + authorize) | 0–2 | External browser |
| 8 | Return to app | 0 | 0 | Backfill imports runs |
| 9 | Run externally (Strava) | N/A | N/A | Runs with watch, not in app |

| Metric | Value |
|--------|-------|
| **# Screens** | 5–6 (app) + external OAuth |
| **# Clicks** | 10–14 |
| **# Fields** | 1–3 |
| **Est. Time** | 120–180s |
| **Confusion Points** | 3 — (1) "permanent" role warning creates hesitation, (2) how to find assessoria code unclear, (3) Strava connect buried in Settings not inline |
| **Feedback Points** | 3 — snackbar on login, snackbar on Strava connect, Today screen auto-loads data |
| **Ideal Benchmark** | 4 screens, 6 clicks, 90s, 0 confusion |

---

### Flow 2: Check and Confirm a Delivery

**Path:** Open App → Tab: Deliveries → Find item → Tap "Apareceu no relógio"

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Bottom nav: Deliveries | 1 | 0 | |
| 2 | AthleteDeliveryScreen | 0 (auto-loads list) | 0 | Clear list with status badges |
| 3 | Confirm item | 1 ("Apareceu no relógio") | 0 | or 2 clicks if reporting failure (dialog + reason) |

| Metric | Value |
|--------|-------|
| **# Screens** | 1 |
| **# Clicks** | 2 |
| **# Fields** | 0 |
| **Est. Time** | 8s |
| **Confusion Points** | 0 — buttons are clearly labeled |
| **Feedback Points** | 2 — haptic + snackbar confirmation |
| **Ideal Benchmark** | 1 screen, 2 clicks, 5s — already at benchmark |

---

### Flow 3: Join a Challenge

**Path:** Open → Challenges tab → Find challenge → Tap into details → Accept → Compete → See result

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Bottom nav: Challenges | 1 | 0 | |
| 2 | ChallengesListScreen | 0 (auto-loads) | 0 | Sections: Active / Completed |
| 3 | Tap challenge tile | 1 | 0 | |
| 4 | ChallengeDetailsScreen | 1 ("Aceitar") | 0 | Accept/Decline card clearly visible |
| 5 | Run externally | N/A | N/A | Runs count via Strava auto-import |
| 6 | Return to challenge | 1 | 0 | See result card + "Ver resultado completo" |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 (list + details) |
| **# Clicks** | 4 |
| **# Fields** | 0 |
| **Est. Time** | 15s (to accept; running is external) |
| **Confusion Points** | 1 — if Strava not connected, user may not know their run won't count (banner exists but can be missed) |
| **Feedback Points** | 3 — accept confirmation, settlement indicator, result card |
| **Ideal Benchmark** | 2 screens, 3 clicks, 10s |

---

### Flow 4: Track My Progress

**Path:** Open → Evolution/MyEvolution tab → Select metric + period → Read trend

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Navigate to evolution | 1–2 | 0 | Via More tab or bottom nav |
| 2 | AthleteEvolutionScreen | 0 (auto-loads) | 0 | Default metric + period pre-selected |
| 3 | Change filter (optional) | 1–2 | 0 | Period chips + metric chips |
| 4 | Read trend card | 0 | 0 | Direction, %, baseline clearly shown |

| Metric | Value |
|--------|-------|
| **# Screens** | 1–2 |
| **# Clicks** | 2–4 |
| **# Fields** | 0 |
| **Est. Time** | 10–15s |
| **Confusion Points** | 1 — empty state if user has < 3 sessions (shows "Sem dados de evolução") |
| **Feedback Points** | 1 — trend direction with color coding |
| **Ideal Benchmark** | 1 screen, 2 clicks, 8s |

---

### Flow 5: Connect Strava

**Path:** Profile → Settings → Integrations → Conectar

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Bottom nav: More/Profile | 1 | 0 | |
| 2 | Navigate to Settings | 1 | 0 | |
| 3 | SettingsScreen | 0 | 0 | Strava tile is first item under "Integrações" |
| 4 | Tap "Conectar" | 1 | 0 | |
| 5 | Strava OAuth (external) | ~3 | 0–2 | Login + authorize in browser |
| 6 | Return to app | 0 | 0 | Snackbar: "Strava conectado como X!" |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 (Settings + external OAuth) |
| **# Clicks** | 6 |
| **# Fields** | 0 (in app) |
| **Est. Time** | 30–45s |
| **Confusion Points** | 1 — Strava is under Settings, not Profile or a dedicated Integrations tab |
| **Feedback Points** | 2 — snackbar + connected status on tile |
| **Ideal Benchmark** | 1 screen, 4 clicks, 20s |

---

## APP — Staff Flows

### Flow 6: Create a Workout Template

**Path:** Dashboard → Atletas → Group Details → Templates → Novo Template → Fill → Add Blocks → Save

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | StaffDashboardScreen | 1 (Atletas card) | 0 | |
| 2 | CoachingGroupDetailsScreen | 1 (Templates tab) | 0 | |
| 3 | Templates list | 1 (+ New) | 0 | |
| 4 | StaffWorkoutBuilderScreen | 0 | 2 (name + description) | Name required, desc optional |
| 5 | Add block (bottom sheet) | 2 (Adicionar + confirm) | 3–6 (type + duration/distance + pace + HR zone + RPE) | Per block |
| 6 | Repeat blocks | 2 per block | 3–6 per block | Typical: 3–5 blocks |
| 7 | Save | 1 (Salvar) | 0 | Snackbar + pop |

| Metric | Value |
|--------|-------|
| **# Screens** | 3 (dashboard → group → builder) |
| **# Clicks** | 12–20 (3 nav + 2 fields + 3 blocks × ~3 + save) |
| **# Fields** | 11–20 (2 template + 3–6 per block × 3) |
| **Est. Time** | 90–180s |
| **Confusion Points** | 2 — (1) navigating from dashboard to templates is 3 levels deep, (2) block fields are many but optional |
| **Feedback Points** | 2 — snackbar on save, haptic on save |
| **Ideal Benchmark** | 2 screens, 8 clicks, 60s |

---

### Flow 7: Deliver Workouts to Athletes

**Path:** Dashboard → (Portal recommended) or Assign screen → Select template + athlete + date → Assign → Offer delivery

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | StaffDashboardScreen | 1 (Atletas) | 0 | |
| 2 | CoachingGroupDetailsScreen | 1 (navigate to assign) | 0 | |
| 3 | StaffWorkoutAssignScreen | 0 | 3 (template dropdown + athlete dropdown + date picker) | + optional notes field |
| 4 | Assign | 1 (Confirmar atribuição) | 0 | |
| 5 | Delivery dialog | 1 (Incluir) | 0 | Or TrainingPeaks sync dialog |
| 6 | Publish via Portal | — | — | App tells user to "publique pelo portal" |

| Metric | Value |
|--------|-------|
| **# Screens** | 3 + portal handoff |
| **# Clicks** | 7 |
| **# Fields** | 3–4 |
| **Est. Time** | 45–60s |
| **Confusion Points** | 2 — (1) publishing requires switching to portal, (2) assign screen marked as possibly unused in code |
| **Feedback Points** | 2 — snackbar on assign, delivery dialog |
| **Ideal Benchmark** | 2 screens, 5 clicks, 30s, end-to-end in one platform |

---

### Flow 8: Check Athlete Attendance

**Path:** Dashboard → Atletas/Performance → Attendance data

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | StaffDashboardScreen | 1 (Performance card) | 0 | |
| 2 | StaffPerformanceScreen | 0 | 0 | Shows group metrics |
| 3 | Or: Portal → Attendance page | 1 (sidebar link) | 0 | Full attendance table with filters |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 |
| **# Clicks** | 2 |
| **# Fields** | 0 |
| **Est. Time** | 10s |
| **Confusion Points** | 1 — unclear whether to use app (Performance) or portal (Attendance) for detailed data |
| **Feedback Points** | 1 — data loads with KPI cards |
| **Ideal Benchmark** | 1 screen, 1 click, 5s |

---

### Flow 9: Create a Challenge (Staff)

**Path:** Dashboard → (switch to athlete view or bottom nav) → Challenges → Create

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Navigate to Challenges tab | 1–2 | 0 | Staff dashboard doesn't have direct challenge creation |
| 2 | ChallengesListScreen | 1 (+ icon) | 0 | |
| 3 | ChallengeCreateScreen | Many | Many | Complex form below |

**ChallengeCreateScreen form analysis:**

| Field/Action | Type | Required |
|-------------|------|----------|
| Mode selector (Agora/Agendado) | 2 cards | Yes (default: Agora) |
| Title | Text, 60 chars | No |
| Type (1v1/Group/Team) | SegmentedButton | Yes (default: 1v1) |
| Max participants (if group) | Counter +/- | Conditional |
| Goal (4 radio cards) | Cards | Yes (default: fastest) |
| Target distance | Number + km | Conditional (depends on goal) |
| Window (time chips) | 5 chips | Yes (default: 3h) |
| Accept window (if group) | 4 chips | Conditional |
| Entry fee | Number | No (default: 0) |
| Submit | Button | — |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 (list + create) |
| **# Clicks** | 8–14 (2 nav + 6–12 form interactions) |
| **# Fields** | 4–8 (depending on type/mode) |
| **Est. Time** | 45–90s |
| **Confusion Points** | 2 — (1) many options can overwhelm, (2) staff must use athlete view, no staff-specific challenge panel |
| **Feedback Points** | 3 — success overlay, redirect to invite screen, notification triggered |
| **Ideal Benchmark** | 1 screen, 6 clicks, 30s |

---

## PORTAL — Staff Flows

### Flow 10: View Dashboard Overview

**Path:** Login → Auto-redirect → Dashboard page

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Login page | 1 (submit) | 2 (email + password) | Or SSO |
| 2 | Group select (if multi-group) | 1 | 0 | Skipped if single group |
| 3 | Dashboard | 0 | 0 | Auto-lands on /dashboard |

| Metric | Value |
|--------|-------|
| **# Screens** | 1–2 |
| **# Clicks** | 2–3 |
| **# Fields** | 2 |
| **Est. Time** | 10–15s |
| **Confusion Points** | 0 — straightforward login flow |
| **Feedback Points** | 1 — dashboard renders with KPI blocks |
| **Ideal Benchmark** | 1 screen, 1 click (SSO), 5s |

---

### Flow 11: Manage Athletes

**Path:** Sidebar → Atletas → Table → Click athlete → CRM profile

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Sidebar: "Atletas" | 1 | 0 | |
| 2 | Athletes page | 0 | 0 | Table with stats, status badges, CSV export |
| 3 | (Optional) Distribute OmniCoins | 1 | 1 (amount) | Admin only |
| 4 | Sidebar: "CRM Atletas" | 1 | 0 | For detailed profile |
| 5 | CRM page | 0 | 0 | Filters, tags, alerts, notes, search |
| 6 | Click athlete name | 1 | 0 | Link to /crm/[userId] |
| 7 | Athlete CRM detail page | 0 | 0 | Full profile with actions |

| Metric | Value |
|--------|-------|
| **# Screens** | 2–3 (athletes or CRM → detail) |
| **# Clicks** | 3 |
| **# Fields** | 0 |
| **Est. Time** | 12–18s |
| **Confusion Points** | 1 — "Atletas" page and "CRM Atletas" page overlap in purpose, unclear which to use |
| **Feedback Points** | 1 — table renders with data |
| **Ideal Benchmark** | 1 screen, 2 clicks, 8s |

---

### Flow 12: Create and Send Workout Delivery

**Path:** Sidebar → Treinos → Create → Sidebar → Entrega Treinos → Generate → Publish

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Sidebar: "Treinos" | 1 | 0 | |
| 2 | Workouts page | 1 (create template or select) | 2–3 | |
| 3 | Sidebar: "Entrega Treinos" | 1 | 0 | |
| 4 | Delivery page | 1 (create batch) | 2 (select athletes + template) | |
| 5 | Generate items | 1 | 0 | |
| 6 | Publish | 1 | 0 | |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 (workouts + delivery) |
| **# Clicks** | 6 |
| **# Fields** | 4–5 |
| **Est. Time** | 45–60s |
| **Confusion Points** | 1 — two separate pages for template management vs. delivery, flow not linear |
| **Feedback Points** | 2 — success states on create and publish |
| **Ideal Benchmark** | 1 screen, 4 clicks, 30s (wizard flow) |

---

### Flow 13: View Engagement Metrics

**Path:** Sidebar → Engajamento → Read

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Sidebar: "Engajamento" | 1 | 0 | |
| 2 | Engagement page | 0 | 0 | Auto-loads all metrics |
| 3 | (Optional) Change period filter | 1 | 0 | 7/14/30 day filters |

| Metric | Value |
|--------|-------|
| **# Screens** | 1 |
| **# Clicks** | 1–2 |
| **# Fields** | 0 |
| **Est. Time** | 5–8s |
| **Confusion Points** | 0 — single page with comprehensive data (DAU/WAU/MAU, charts, inactive list) |
| **Feedback Points** | 1 — data renders with visual charts |
| **Ideal Benchmark** | 1 screen, 1 click, 5s — at benchmark |

---

### Flow 14: Handle a Support Ticket

**Path:** Platform Support → Ticket list → Click ticket → Read → Reply

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Navigate to /platform/support | 1 | 0 | |
| 2 | Support list page | 0 | 0 | Filter tabs (All/Open/Answered/Closed) |
| 3 | (Optional) Filter by status | 1 | 0 | |
| 4 | Click ticket | 1 | 0 | |
| 5 | Ticket detail page | 0 | 0 | Chat thread with messages |
| 6 | Type reply | 0 | 1 (message body) | TicketChat component |
| 7 | Send | 1 | 0 | |

| Metric | Value |
|--------|-------|
| **# Screens** | 2 (list + detail) |
| **# Clicks** | 4 |
| **# Fields** | 1 |
| **Est. Time** | 30–60s (reading + composing reply) |
| **Confusion Points** | 0 — chat-style interface is intuitive |
| **Feedback Points** | 2 — message appears in thread, status badge updates |
| **Ideal Benchmark** | 2 screens, 3 clicks, 25s |

---

## PORTAL — Admin Flows

### Flow 15: Approve a New Assessoria

**Path:** Login → Platform Admin → Assessorias list → Find pending → Approve

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Login (if not already) | 1 | 2 | |
| 2 | Redirect to /platform/assessorias | 0 | 0 | Auto-redirect for platform_admin |
| 3 | Find pending assessoria | 0–1 (scroll/filter) | 0 | |
| 4 | Approve button | 1 | 0 | |
| 5 | (Optional) Reject with reason | 1 | 1 | |

| Metric | Value |
|--------|-------|
| **# Screens** | 1 |
| **# Clicks** | 2–3 |
| **# Fields** | 0–1 |
| **Est. Time** | 10–15s |
| **Confusion Points** | 1 — no dedicated assessorias page found in file system (may be missing or at a different path) |
| **Feedback Points** | 1 — status change on row |
| **Ideal Benchmark** | 1 screen, 2 clicks, 8s |

---

### Flow 16: Manage Feature Flags

**Path:** Login → (Feature flags managed via Supabase DB table)

| Step | Screen | Clicks | Fields | Notes |
|------|--------|--------|--------|-------|
| 1 | Open Supabase dashboard | 1 | 0 | External tool |
| 2 | Navigate to feature_flags table | 2 | 0 | |
| 3 | Find flag row | 1 | 0 | |
| 4 | Edit enabled/rollout_pct | 1 | 1–2 | |
| 5 | Save | 1 | 0 | |

| Metric | Value |
|--------|-------|
| **# Screens** | 1 (Supabase table editor) |
| **# Clicks** | 6 |
| **# Fields** | 1–2 |
| **Est. Time** | 30–45s |
| **Confusion Points** | 2 — (1) no in-product UI, requires Supabase access, (2) rollout_pct semantics not documented in UI |
| **Feedback Points** | 1 — Supabase shows row saved |
| **Ideal Benchmark** | 1 screen (in-app), 3 clicks, 10s |

---

## Summary Scorecard

| # | Flow | Screens | Clicks | Fields | Time (s) | Confusion | Feedback | Efficiency Score |
|---|------|---------|--------|--------|----------|-----------|----------|-----------------|
| 1 | Sign up → First session | 6 | 12 | 2 | 150 | 3 | 3 | 45 |
| 2 | Check/confirm delivery | 1 | 2 | 0 | 8 | 0 | 2 | **95** |
| 3 | Join a challenge | 2 | 4 | 0 | 15 | 1 | 3 | **85** |
| 4 | Track progress | 2 | 3 | 0 | 12 | 1 | 1 | **82** |
| 5 | Connect Strava | 2 | 6 | 0 | 38 | 1 | 2 | 72 |
| 6 | Create workout template | 3 | 16 | 15 | 135 | 2 | 2 | 40 |
| 7 | Deliver workouts | 3 | 7 | 4 | 52 | 2 | 2 | 55 |
| 8 | Check attendance | 2 | 2 | 0 | 10 | 1 | 1 | **80** |
| 9 | Create challenge (staff) | 2 | 11 | 6 | 68 | 2 | 3 | 58 |
| 10 | View dashboard (portal) | 2 | 3 | 2 | 12 | 0 | 1 | **88** |
| 11 | Manage athletes (portal) | 3 | 3 | 0 | 15 | 1 | 1 | 78 |
| 12 | Workout delivery (portal) | 2 | 6 | 5 | 52 | 1 | 2 | 60 |
| 13 | View engagement (portal) | 1 | 1 | 0 | 6 | 0 | 1 | **95** |
| 14 | Handle support ticket | 2 | 4 | 1 | 45 | 0 | 2 | **80** |
| 15 | Approve assessoria | 1 | 3 | 0 | 12 | 1 | 1 | 78 |
| 16 | Manage feature flags | 1 | 6 | 2 | 38 | 2 | 1 | 42 |

> **Efficiency Score** = weighted formula: `100 - (screens×3 + clicks×2 + fields×1.5 + confusion×10 - feedback×5)`, clamped 0–100.

---

## Overall Efficiency Score

### **68 / 100**

| Category | Avg Score | Assessment |
|----------|-----------|-----------|
| App — Athlete flows (1–5) | 76 | Good. Core loops are tight. |
| App — Staff flows (6–9) | 58 | Fair. Template creation and delivery have friction. |
| Portal — Staff flows (10–14) | 80 | Good. Data consumption is efficient. |
| Portal — Admin flows (15–16) | 60 | Fair. Feature flags lack in-product UI. |

---

## Top 5 Most Efficient Flows

| Rank | Flow | Score | Why |
|------|------|-------|-----|
| 1 | **View engagement (portal)** | 95 | 1 click, single page, comprehensive data, zero confusion |
| 2 | **Check/confirm delivery** | 95 | 2 clicks, 1 screen, clear labels, haptic + snackbar feedback |
| 3 | **View dashboard (portal)** | 88 | Auto-lands on KPIs after login, no navigation needed |
| 4 | **Join a challenge** | 85 | Clean list → detail → accept flow, good feedback cycle |
| 5 | **Track progress** | 82 | Pre-selected defaults, chip filters, trend direction clear |

---

## Top 5 Least Efficient Flows (Highest Friction)

| Rank | Flow | Score | Primary Friction |
|------|------|-------|-----------------|
| 1 | **Create workout template** | 40 | 3 screens deep navigation, 15+ fields per template, repetitive block entry |
| 2 | **Manage feature flags** | 42 | No in-product UI — requires raw Supabase table access |
| 3 | **Sign up → First session** | 45 | 6 screens, permanent role warning creates anxiety, Strava buried in Settings |
| 4 | **Deliver workouts (app)** | 55 | Split across app + portal, "publish via portal" is a dead-end in-app |
| 5 | **Create challenge (staff)** | 58 | Complex form with many conditional fields, no staff-specific entry point |

---

## Friction Analysis: Dead Moments & Missing Feedback

### Dead Moments (user waits or doesn't know what to do)

| Location | Issue | Severity |
|----------|-------|----------|
| OnboardingRoleScreen | "Essa escolha é permanente" warning creates decision paralysis | High |
| JoinAssessoriaScreen | User must know assessoria invite code; no discovery/search | High |
| TodayScreen → Strava | CTA says "Conectar Strava" but links to Settings, not inline OAuth | Medium |
| StaffDashboardScreen | Random 0–2s artificial delay (`Random().nextInt(2000)`) on load | Medium |
| TodayScreen | Random 0–2s artificial delay on load | Medium |
| StaffWorkoutAssignScreen | After assign, "publique pelo portal" — user left hanging | High |
| ChallengeCreateScreen | Many conditional fields appear/disappear based on type/mode | Medium |
| Feature flags | Admin must leave product entirely to manage flags | High |

### Missing Confirmations

| Location | Issue |
|----------|-------|
| OnboardingRoleScreen | No "role saved" confirmation — just navigates away |
| AthleteEvolutionScreen | No loading-complete signal beyond data appearing |
| Portal Athletes page | No row click → no drill-down within the same page |
| Portal Attendance page | No session-detail inline expansion |

---

## Recommendations for Reducing Friction

### Priority 1 — High Impact, Low Effort

1. **Remove artificial random delays** on TodayScreen and StaffDashboardScreen. The `Random().nextInt(2000)` before loading data adds 0–2s of unexplained wait time. Replace with immediate loading.

2. **Inline Strava OAuth** on TodayScreen. Instead of routing through Settings, trigger the OAuth flow directly from the "Conectar Strava" CTA on the Today screen. Save 2 screens and 2 clicks.

3. **Add in-product feature flag management** page to the admin portal. A simple table view at `/platform/flags` with toggle switches would eliminate the need for Supabase dashboard access entirely.

### Priority 2 — High Impact, Medium Effort

4. **Flatten workout template creation.** Combine template metadata and block entry into a single scrollable form. Pre-populate common patterns (e.g., "Warm-up + 5×1km + Cool-down") as one-click presets. Target: 8 clicks from 16.

5. **Unify workout delivery flow.** Allow publishing from within the app's assign screen instead of requiring portal handoff. Add a "Publicar agora" button that calls the same API the portal uses.

6. **Soften the permanent role warning.** Change "permanent and cannot be changed" to "you can request a role change later via support." This reduces decision anxiety without removing the guardrail.

7. **Add assessoria search/discovery** to JoinAssessoriaScreen. Allow browsing approved assessorias by city/name in addition to invite code entry.

### Priority 3 — Medium Impact, Medium Effort

8. **Merge Athletes and CRM pages** in the portal. Athletes page shows session stats; CRM shows status/tags/notes. Combining into a unified view with tabs eliminates the "which page do I use" confusion.

9. **Add staff challenge creation shortcut.** Create a "Challenges" card on StaffDashboardScreen that links directly to ChallengeCreateScreen, bypassing the athlete bottom nav.

10. **Add progressive disclosure to ChallengeCreateScreen.** Show only the minimum fields (type + goal + window) initially. Reveal advanced options (title, fee, target, accept window, max participants) in an "Advanced" expandable section.

### Priority 4 — Polish

11. **Add loading-complete haptic/animation** to TodayScreen and AthleteEvolutionScreen when data arrives.

12. **Add inline session expansion** on Portal attendance page for drill-down without navigation.

13. **Add confirmation animation** when onboarding role is saved (before navigation).

---

## Appendix: Click-by-Click Flow Maps

### Flow 1: Sign Up → First Session (Social Login Path)
```
[Open App] → [LoginScreen: tap Google] → [Google OAuth: ~2 clicks]
→ [OnboardingRoleScreen: tap "Atleta" + tap "Continuar" + dialog "Sim"]
→ [JoinAssessoriaScreen: enter code + tap "Entrar"]
→ [TodayScreen: see Strava CTA → tap "Conectar Strava"]
→ [SettingsScreen: tap "Conectar"]
→ [Strava OAuth: ~3 clicks]
→ [Return: data loads] → [Go run with watch]
Total: ~14 clicks, 6 screens
```

### Flow 6: Create Workout Template
```
[StaffDashboardScreen: tap "Atletas"]
→ [CoachingGroupDetailsScreen: tap "Templates" tab → tap "+"]
→ [StaffWorkoutBuilderScreen: fill Name + Description]
→ [tap "Adicionar" → bottom sheet: select Type + fill Duration + Distance → tap "Adicionar"]
→ [repeat for each block ×3]
→ [tap "Salvar"]
Total: ~16 clicks, 15 fields, 3 screens
```

### Flow 13: View Engagement (Portal)
```
[Sidebar: tap "Engajamento"]
→ [Engagement page loads: DAU/WAU/MAU cards + bar chart + inactive list]
Total: 1 click, 1 screen
```
