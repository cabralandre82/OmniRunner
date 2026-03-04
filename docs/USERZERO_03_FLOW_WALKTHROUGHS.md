# User Zero — Flow Walkthroughs

Simulated end-to-end walkthroughs for the three main user profiles.
Each objective traces the actual code path, noting entry/exit points,
data requirements, and edge case behavior.

---

## PROFILE 1: ATHLETE (App only)

### [Athlete] Objective 1: "Sign up and join a coaching group"

**Entry:** `main.dart` → `AuthGate` (line 38, `auth_gate.dart`)

**Steps:**
1. `[AuthGate]` → checks `AppConfig.isSupabaseReady` + `authRepo.isSignedIn` → renders `WelcomeScreen` (auth_gate.dart:229-230)
2. `[WelcomeScreen]` → user taps "Start" → `_go(_GateDestination.login)` → renders `LoginScreen` (auth_gate.dart:369)
3. `[LoginScreen]` → user picks Google / Apple / Instagram / Email → calls `_auth.signInWithGoogle()` etc. (login_screen.dart:108-163) → on success calls `widget.onSuccess()` which triggers `_onLoginSuccess` in AuthGate
4. `[AuthGate._resolve]` → fetches profile via `sl<IProfileRepo>().getMyProfile()` → profile is null → destination = `onboarding` (auth_gate.dart:258-262)
5. `[OnboardingRoleScreen]` → user selects "ATLETA" → `_showConfirmDialog()` with permanent-choice warning → calls edge function `set-user-role` with retry (3 attempts) (onboarding_role_screen.dart:99-141)
6. `[AuthGate._resolve]` re-runs → profile.onboardingState = `ROLE_SELECTED`, userRole = `ATLETA` → destination = `joinAssessoria` (auth_gate.dart:279-281)
7. `[JoinAssessoriaScreen]` → user enters invite code or pastes link → calls `fn_request_join` RPC → join request created (auth_gate.dart:380-384)
8. `[AuthGate._resolve]` re-runs → profile.isOnboardingComplete → `_goHomeOrTour()` → first time shows `OnboardingTourScreen` → then `HomeScreen`

**Success criteria:** User lands on HomeScreen with athlete tab bar visible

**Failure points:**
- **F1:** If `set-user-role` edge function fails 3 times, user sees error message but CAN retry — button re-enables (onboarding_role_screen.dart:136-139). PASS.
- **F2:** If profile fetch fails in `_resolve`, retries up to 2 times with exponential backoff (2s, 4s), then falls back to HomeScreen — risky because user may land on HomeScreen without a profile (auth_gate.dart:296-321). **PARTIAL** — should show onboarding instead.
- **F3:** Deep link invite code is persisted across OAuth redirects via `handler.consumePendingInvite()` (auth_gate.dart:250-253). PASS.

**Edge cases:**
- **Empty:** Welcome screen renders correctly with no prior data. PASS.
- **Permission:** Anonymous users redirected to Welcome (auth_gate.dart:243-244). PASS.
- **Error:** Supabase not configured → WelcomeScreen shown, login buttons check `_checkConnection()` which shows "Sem conexão com o servidor" (login_screen.dart:140-147). PASS.
- **Double-click:** Login buttons use `_busy` flag to prevent double-tap — shows CircularProgressIndicator while busy (login_screen.dart:243-247). PASS.
- **State restore:** AuthGate re-resolves on every mount. If user kills app mid-onboarding, re-opens → resolve() re-fetches profile and routes to correct step. PASS.

**Verdict:** PASS

---

### [Athlete] Objective 2: "See today's training and log a session"

**Entry:** `HomeScreen` → `TodayScreen` (today_screen.dart:94)

**Steps:**
1. `[TodayScreen.initState]` → calls `_load()` (today_screen.dart:117) — adds random 0-2s jitter delay (line 133)
2. `_load()` → recalculates profile progress via `TodayDataService` → fetches `ProfileProgressEntity` from Supabase with Isar fallback (today_screen.dart:146-180)
3. Fetches local completed sessions via `ISessionRepo` + remote sessions from Supabase → merges by ID, dedup, sort most recent (today_screen.dart:183-201)
4. Checks Strava connection status (today_screen.dart:202)
5. Fetches active challenges and championships (today_screen.dart:204-256)
6. Renders: streak banner → active challenges card → "Bora Correr" CTA → run recap card → park check-in → quick stats (today_screen.dart:454-538)
7. User sees last run recap with distance/pace/duration, comparison with previous run, share and journal buttons
8. User taps "Journal" → `_openJournal()` opens modal bottom sheet → can type notes, select mood emoji → saves via `TodayDataService.upsertJournalEntry` with debounced auto-save (today_screen.dart:565-684)

**Success criteria:** TodayScreen displays streak, last run stats, active challenges. Run journal saves and shows confirmation snackbar.

**Failure points:**
- **F1:** 60-second throttle on `_load()` — if user navigates away and back within 60s, data won't refresh (today_screen.dart:129-132). Minor inconvenience. **PARTIAL**.
- **F2:** If all data loading fails, shows error state with retry button — good (today_screen.dart:374-407). PASS.
- **F3:** `Random().nextInt(2000)` jitter delay on every load — adds perceived latency for no user-facing benefit (today_screen.dart:133). Not a bug but hurts UX. **PARTIAL**.

**Edge cases:**
- **Empty:** No runs → no RunRecapCard, no ParkCheckinCard, no ComparisonRow. StreakBanner shows "Sem sequência ativa" with cold emoji. BoraCorrerCard shows Strava connect CTA if not connected. PASS.
- **Permission:** UserIdentityProvider.userId used throughout — authenticated. PASS.
- **Error:** Full error state with retry button when profile is null AND error occurs (today_screen.dart:374). If profile loaded but error occurs later, data just stays stale. PASS.
- **Double-click:** No explicit protection on share/journal buttons. Journal uses StatefulBuilder + debounced save, so double-tap on mood would just re-select same mood. Share button triggers native share sheet — OS handles duplicates. PASS.
- **State restore:** `didUpdateWidget` re-loads when `isVisible` changes from false→true. RefreshIndicator supports pull-to-refresh. PASS.

**Verdict:** PASS

---

### [Athlete] Objective 3: "Check challenges and compete"

**Entry:** `HomeScreen` → Challenge tab → `ChallengesListScreen` (challenges_list_screen.dart:44)

**Steps:**
1. `[ChallengesListScreen]` → checks Strava connection; shows banner if not connected (challenges_list_screen.dart:51-69, 100-102)
2. `BlocBuilder<ChallengesBloc>` renders list from `ChallengesLoaded` state — splits into "Ativos" and "Concluídos" sections (challenges_list_screen.dart:224-251)
3. User taps "+" in AppBar → navigates to `ChallengeCreateScreen` (challenges_list_screen.dart:87-95)
4. `[ChallengeCreateScreen]` → form with type (1v1/group/team), goal (distance/pace/time), window, entry fee, start mode → validates via `_formKey` → dispatches `CreateChallengeRequested` event (challenge_create_screen.dart:43-58)
5. On creation success → navigates to `ChallengeInviteScreen` to share link (challenge_create_screen.dart:15-16)
6. User taps challenge in list → dispatches `ViewChallengeDetails` → navigates to `ChallengeDetailsScreen` (challenges_list_screen.dart:289-302)
7. `[ChallengeDetailsScreen]` → shows header, rules, participants, accept/decline (if invited), results (if completed), share invite (if creator) (challenge_details_screen.dart:126-346)
8. If challenge window expired → auto-triggers `settle-challenge` edge function → shows settling indicator → refreshes with result (challenge_details_screen.dart:91-123)

**Success criteria:** User can create challenge, invite opponents, see real-time status, and view results after settlement.

**Failure points:**
- **F1:** `_AcceptDeclineCard._onAccept` has no `_busy` guard — user can tap "Accept" multiple times before the bloc processes. The bloc event `JoinChallengeRequested` should be idempotent server-side, but UI doesn't prevent rapid taps. **FAIL — no double-click protection on Accept.**
- **F2:** Auto-settlement timeout is 30 seconds (challenge_details_screen.dart:102). If edge function takes longer, shows "Apuração em andamento" message — user must come back later. PASS.
- **F3:** Settlement error only logs warning — no snackbar or user-visible error message (challenge_details_screen.dart:120-121). **PARTIAL** — user sees timeout message eventually.

**Edge cases:**
- **Empty:** Empty list shows helpful illustration + "Encontrar Oponente" and "Criar e convidar" buttons (challenges_list_screen.dart:130-181). PASS.
- **Permission:** Verification gate checks for challenges with entry fee — blocks if user not verified (challenge_details_screen.dart:666-674). PASS.
- **Error:** `ChallengesError` state shows `ErrorState` widget with retry callback (challenges_list_screen.dart:114-120). PASS.
- **Double-click:** Create button in ChallengeCreateScreen uses `_busy` flag (challenge_create_screen.dart:58). Accept/Decline does NOT (see F1). **PARTIAL**.
- **State restore:** Bloc state persists in widget tree. Returning to list triggers `LoadChallenges` refresh. PASS.

**Verdict:** PARTIAL (accept button double-click issue)

---

### [Athlete] Objective 4: "Track personal progress"

**Entry:** `HomeScreen` → Evolution tab → `AthleteMyEvolutionScreen` or `AthleteEvolutionScreen`

**Steps:**
1. `[AthleteMyEvolutionScreen]` → requires `groupId` and `userId` (athlete_my_evolution_screen.dart:18-19)
2. `_loadData()` → parallel fetch via `Future.wait`: `crmRepo.getStatus`, `crmRepo.getAthleteTags`, `attendanceRepo.listByAthlete` (athlete_my_evolution_screen.dart:50-61)
3. Renders: status badge card → tags card → attendance summary (total + streak) → recent attendance list (athlete_my_evolution_screen.dart:137-149)
4. `[AthleteEvolutionScreen]` (staff-facing, reusable) → BlocBuilder with `AthleteEvolutionBloc` → shows metric/period filters → trend card with direction + baseline card + metric summary grid (athlete_evolution_screen.dart:30-83)
5. User can filter by period (Weekly/Monthly) and metric (Pace/Distance/Volume/Frequency/HR/Moving Time) (athlete_evolution_screen.dart:111-179)

**Success criteria:** User sees their status, tags, attendance history, and trend analysis across multiple metrics.

**Failure points:**
- **F1:** `AthleteMyEvolutionScreen` depends on `groupId` — if athlete has no group (e.g., hasn't joined an assessoria), screen cannot load. Caller must provide groupId. **PARTIAL** — no validation or fallback if groupId is invalid.
- **F2:** Streak calculation uses simple date-set iteration (athlete_my_evolution_screen.dart:83-98) — works correctly but counts any presence, not just consecutive days. Logic is correct for consecutive days. PASS.

**Edge cases:**
- **Empty:** Tags card shows "Nenhuma tag"; attendance shows "Nenhuma presença registrada"; evolution bloc has `AthleteEvolutionEmpty` state showing "Sem dados de evolução" with helpful message (athlete_evolution_screen.dart:474-498). PASS.
- **Permission:** Uses authenticated user's own ID. PASS.
- **Error:** Error state in MyEvolution shows error icon + message + "Tentar novamente" button (athlete_my_evolution_screen.dart:114-133). Evolution screen shows error message in red (athlete_evolution_screen.dart:69-80). PASS.
- **Double-click:** Refresh button in AppBar — no guard, but re-fetching data is idempotent. PASS.
- **State restore:** RefreshIndicator on MyEvolution list. Bloc re-emits on period/metric change. PASS.

**Verdict:** PASS

---

### [Athlete] Objective 5: "Confirm a workout delivery"

**Entry:** `HomeScreen` → Delivery tab or navigation → `AthleteDeliveryScreen` (athlete_delivery_screen.dart:12)

**Steps:**
1. `[AthleteDeliveryScreen.initState]` → `_loadItems()` fetches published delivery items via `WorkoutDeliveryService.listPublishedItems(uid)` (athlete_delivery_screen.dart:38-67)
2. Renders list of delivery cards with template name, scheduled date, status badge (athlete_delivery_screen.dart:195-332)
3. User taps "Apareceu no relógio" → calls `_confirmItem(itemId, 'confirmed')` → `WorkoutDeliveryService.confirmItem()` (athlete_delivery_screen.dart:69-103)
4. User taps "Não apareceu" → `_showFailureDialog()` → radio picker with reasons ("Não sincronizou", "Treino diferente", "Erro no relógio", "Outro") → calls `_confirmItem(itemId, 'failed', reason: selected)` (athlete_delivery_screen.dart:105-143)
5. On success → haptic feedback + snackbar → reloads list (athlete_delivery_screen.dart:80-88)

**Success criteria:** Delivery item status changes from "Pendente" to "Confirmado" or "Falhou". List refreshes.

**Failure points:**
- **F1:** Confirm error → snackbar with humanized message, removes item from `_confirmingIds` set so user can retry (athlete_delivery_screen.dart:89-103). PASS.

**Edge cases:**
- **Empty:** Shows `AppEmptyState` with "Nenhuma entrega pendente" + check icon (athlete_delivery_screen.dart:176-179). PASS.
- **Permission:** Uses `UserIdentityProvider.userId` — only loads own deliveries. PASS.
- **Error:** Shows `AppErrorState` with message + retry button (athlete_delivery_screen.dart:169-173). PASS.
- **Double-click:** `_confirmingIds` Set prevents duplicate confirms — button disabled while ID is in set (athlete_delivery_screen.dart:69-71, 293-294). PASS.
- **State restore:** RefreshIndicator wraps ListView; AppBar has explicit refresh button (athlete_delivery_screen.dart:150-155, 182-193). PASS.

**Verdict:** PASS

---

## PROFILE 2: STAFF/COACH (App + Portal)

### [Staff] Objective 1: "Create and manage a coaching group"

**Entry:** `AuthGate` → role = `ASSESSORIA_STAFF` → `StaffSetupScreen` (auth_gate.dart:283-284, 385-388)

**Steps:**
1. `[OnboardingRoleScreen]` → user selects "Represento uma assessoria" → calls `set-user-role` with `ASSESSORIA_STAFF` (onboarding_role_screen.dart:198-201)
2. `[AuthGate._resolve]` → profile.onboardingState = ROLE_SELECTED, role = ASSESSORIA_STAFF → destination = `staffSetup` (auth_gate.dart:283-284)
3. `[StaffSetupScreen]` → user fills group name, city, description → creates group in Supabase → sets approval_status = `pending_approval`
4. `[AuthGate._resolve]` re-runs → profile.isOnboardingComplete → destination = `home` → `StaffDashboardScreen` shown
5. `[StaffDashboardScreen]` → checks `_approvalStatus` — if not "approved", shows pending approval screen with invite code (staff_dashboard_screen.dart:517-619)
6. Once approved → dashboard shows 10 cards: Atletas, Solicitações, Confirmações, Performance, Campeonatos, Convites, Créditos, Administração, Liga, Portal (staff_dashboard_screen.dart:621-773)
7. User taps "Atletas e Staff" → navigates to `CoachingGroupDetailsScreen` (staff_dashboard_screen.dart:243-252) → shows group info + member list from Supabase (coaching_group_details_screen.dart:39-99)

**Success criteria:** Group created, appears in platform admin queue, dashboard accessible after approval.

**Failure points:**
- **F1:** Platform approval is a blocking gate — staff sees "Aguardando aprovação da plataforma" with explain text + "Verificar status" button. No way to bypass. PASS (by design).
- **F2:** If group is rejected/suspended, shows appropriate message with reason (staff_dashboard_screen.dart:517-619). PASS.
- **F3:** Dashboard `_loadStatus` catches `PostgrestException` separately with "Dados não encontrados" message (staff_dashboard_screen.dart:222-229). Generic catch shows "Erro de conexão" (staff_dashboard_screen.dart:230-238). PASS.

**Edge cases:**
- **Empty:** No group found → shows "Nenhuma assessoria encontrada" with retry button (staff_dashboard_screen.dart:482-515). Pending professor request → shows "Solicitação pendente" with group name (staff_dashboard_screen.dart:411-480). PASS.
- **Permission:** Role checked via coaching_members query — must be admin_master, coach, or assistant (staff_dashboard_screen.dart:80-87). PASS.
- **Error:** Error state with retry button (staff_dashboard_screen.dart:375-406). PASS.
- **Double-click:** Dashboard cards are simple InkWell with navigation — tapping twice would push two screens. No guard. **PARTIAL** — no debounce on card taps.
- **State restore:** `_loadStatus()` called on initState; `.then((_) => _loadStatus())` after returning from sub-screens (staff_dashboard_screen.dart:251). PASS.

**Verdict:** PASS

---

### [Staff] Objective 2: "Create workout templates and deliver to athletes"

**Entry:** `StaffDashboardScreen` → Portal link OR App → `StaffWorkoutBuilderScreen`

**Steps (App):**
1. Staff navigates to workout builder via group details or workout menu → `StaffWorkoutBuilderScreen(groupId: gid)` (staff_workout_builder_screen.dart:15-33)
2. `BlocProvider` creates `WorkoutBuilderBloc` → `LoadTemplate` event (staff_workout_builder_screen.dart:28-29)
3. Form: name (required), description → Add blocks via bottom sheet (`_AddBlockSheet`) with type dropdown + fields (staff_workout_builder_screen.dart:69-89)
4. User taps Save → `_save()` validates form → dispatches `SaveTemplate` event → bloc saves to Supabase (staff_workout_builder_screen.dart:69-77)
5. Assign: `StaffWorkoutAssignScreen(groupId: gid)` → loads templates + athlete list → user picks template, athlete, date → saves assignment (staff_workout_assign_screen.dart:57-100)

**Steps (Portal):**
1. Portal → `/workouts` → lists templates with name, description, block count, date (portal workouts/page.tsx:49-80)
2. Portal → `/delivery` → batch delivery management
3. Portal → `/workouts/assignments` → assignment management

**Success criteria:** Template created with blocks, assigned to athlete(s) with date, delivery item appears in athlete's `AthleteDeliveryScreen`.

**Failure points:**
- **F1:** `StaffWorkoutAssignScreen` has a TODO comment: "This screen appears to be unused" (staff_workout_assign_screen.dart:18). May indicate dead code path. **PARTIAL** — needs verification that assignment flow is reachable.
- **F2:** Portal workouts page returns `null` if no groupId cookie (workouts/page.tsx:51). Silent null render — no error message. **FAIL** — user sees blank page.
- **F3:** Template save via bloc — errors handled by bloc state machine. Block removal has confirmation dialog. PASS.

**Edge cases:**
- **Empty:** Portal shows empty table with headers. App builder starts with empty block list. PASS.
- **Permission:** Portal uses `cookies().get("portal_group_id")` — set at login. App uses service locator. PASS.
- **Error:** Portal shows error div with "Erro ao carregar dados" (workouts/page.tsx:72-75). App builder has shimmer loader and error states via bloc. PASS.
- **Double-click:** Builder save button doesn't appear to have explicit `_busy` guard in the visible portion. Bloc processes sequentially. **PARTIAL**.
- **State restore:** BlocProvider scoped to screen. Returning re-creates bloc. PASS.

**Verdict:** PARTIAL (unused screen TODO, portal null render)

---

### [Staff] Objective 3: "Monitor athlete engagement"

**Entry (App):** `StaffDashboardScreen` → "Performance" card → `StaffPerformanceScreen` OR "Atletas" → `CoachingGroupDetailsScreen` → athlete tap → `StaffCrmListScreen`

**Entry (Portal):** Sidebar → `/dashboard`, `/crm`, `/attendance`, `/engagement`

**Steps (Portal Dashboard):**
1. `/dashboard` → server component fetches: token inventory, athlete members, purchases, week sessions, verified count, challenges, WAU, distance trends, daily breakdown (dashboard/page.tsx:14-80)
2. Renders stat blocks: Credits, Athletes, WAU, Week Distance, Verified, Challenges, etc.

**Steps (Portal CRM):**
1. `/crm` → fetches members → joins profiles, status, tags, attendance, alerts, notes (crm/page.tsx:28-80)
2. Shows filterable list with search, status filter, tag filter — each athlete shows status badge, tags, attendance count, alerts, last note (crm/page.tsx)
3. Click athlete → `/crm/[userId]` → detailed profile

**Steps (Portal Attendance):**
1. `/attendance` → fetches sessions + attendance by session with date filters → shows session list with attendance count and rate (attendance/page.tsx:10-60)
2. Click session → `/attendance/[id]` → detailed check-in list

**Steps (App CRM):**
1. `StaffCrmListScreen(groupId)` → `CrmListBloc` loads athletes with tags, status, avatars → filterable list with search/tag/status (staff_crm_list_screen.dart:18-34)
2. Tap athlete → `StaffAthleteProfileScreen` → detailed view

**Success criteria:** Staff can see all athletes' engagement metrics across both app and portal.

**Failure points:**
- **F1:** Dashboard returns `null` (no render) if groupId cookie missing (dashboard/page.tsx:17). **FAIL** — blank page, no error.
- **F2:** CRM page fetches up to 200 members (crm/page.tsx:42). Large groups (200+) will miss athletes. **PARTIAL** — pagination needed.
- **F3:** App CRM bloc has `LoadMoreCrmAthletes` event with scroll listener for infinite scroll (staff_crm_list_screen.dart:64-69). PASS.

**Edge cases:**
- **Empty:** CRM shows empty table. Dashboard renders with zero stats. App CRM shows empty state via bloc. PASS.
- **Permission:** Dashboard checks `role` cookie for conditional renders (dashboard/page.tsx:57-58). Sidebar filters by role (sidebar.tsx:72-76). PASS.
- **Error:** Dashboard has try/catch with `fetchError` flag (dashboard/page.tsx:34, not shown in visible portion). App CRM has error state in bloc. PASS.
- **Double-click:** Portal is server-rendered — no client-side double-click risk. App CRM uses navigation — standard push. PASS.
- **State restore:** Portal pages are `force-dynamic` — always fresh. App CRM bloc re-loads on mount. PASS.

**Verdict:** PARTIAL (dashboard null render, CRM 200-member cap)

---

### [Staff] Objective 4: "Manage challenges and championships"

**Entry (App):** `StaffDashboardScreen` → "Campeonatos" card → `StaffChampionshipTemplatesScreen`

**Steps:**
1. `[StaffDashboardScreen]` → user taps "Campeonatos" → navigates to `StaffChampionshipTemplatesScreen(groupId, groupName)` (staff_dashboard_screen.dart:276-281)
2. Championship templates screen lists existing templates and allows creation of new ones
3. "Convites" card → `StaffChampionshipInvitesScreen(groupId)` — shows received championship invitations from other groups (staff_dashboard_screen.dart:285-289)
4. Challenges are athlete-created (not staff-created) — staff only manages championships between assessorias
5. Challenge settlement handled by `settle-challenge` edge function (invoked from ChallengeDetailsScreen)
6. Clearing/disputes managed via "Confirmações" card → `StaffDisputesScreen(groupId, groupName)` (staff_dashboard_screen.dart:255-262)

**Success criteria:** Staff can create championship templates, receive invitations from other groups, and manage dispute cases.

**Failure points:**
- **F1:** Challenges are entirely athlete-driven — staff has no direct challenge management from dashboard. This is by design. PASS.
- **F2:** Championship creation and invitation flows exist in dedicated screens. PASS.

**Edge cases:**
- **Empty:** Dashboard shows 0 disputes count, no alert badge. Championship list shows empty state. PASS.
- **Permission:** Group-scoped queries filter by groupId. PASS.
- **Error:** Each sub-screen has its own error handling. PASS.
- **Double-click:** Navigation from dashboard cards — see Objective 1 notes. **PARTIAL**.
- **State restore:** Dashboard refreshes on return from sub-screens. PASS.

**Verdict:** PASS

---

### [Staff] Objective 5: "Handle support tickets"

**Entry (App):** `StaffDashboardScreen` → "Suporte" card → `SupportScreen(groupId)`
**Entry (Portal):** `/platform/support` (platform admin view)

**Steps (App — Staff creating/viewing tickets):**
1. `[SupportScreen]` → `_load()` fetches tickets from `support_tickets` table filtered by groupId, ordered by updated_at (support_screen.dart:31-49)
2. User taps "+" FloatingActionButton → `_newTicket()` → shows `_NewTicketDialog` with subject + message fields (support_screen.dart:52-60)
3. Dialog submits → inserts into `support_tickets` + `support_messages` → reloads list (support_screen.dart:63-80)
4. Tap ticket → `SupportTicketScreen(ticketId, subject)` — chat-style view (support_ticket_screen.dart:9-12)
5. `[SupportTicketScreen]` → loads ticket status + messages ordered by created_at → renders as chat bubbles (support_ticket_screen.dart:46-71)
6. User types message → sends → inserts into `support_messages` → reloads messages (support_ticket_screen.dart)
7. Auto-scrolls to bottom on load and after sending (support_ticket_screen.dart:74-80)

**Success criteria:** Ticket created, messages exchanged, ticket status visible (open/answered/closed).

**Failure points:**
- **F1:** `_newTicket()` uses `_busy` flag to prevent double-submit (support_screen.dart:53). PASS.
- **F2:** Message send uses `_sending` flag (support_ticket_screen.dart:28). PASS.
- **F3:** `_pendingTicket` preserves form data if dialog cancelled — restores on next open (support_screen.dart:57-59). PASS.

**Edge cases:**
- **Empty:** Empty ticket list — no explicit empty state shown (just empty ListView). **PARTIAL** — should show "Nenhum ticket" message.
- **Permission:** Tickets scoped to groupId. Messages use authenticated userId. PASS.
- **Error:** Catches exceptions with logger but only sets `_loading = false` — no error message shown to user (support_screen.dart:46-49). **PARTIAL** — silent failure.
- **Double-click:** Both `_busy` and `_sending` flags protect against double-submit. PASS.
- **State restore:** Ticket list reloads on return from ticket detail. Messages reload on screen init. PASS.

**Verdict:** PARTIAL (no empty state, silent error on ticket list load)

---

## PROFILE 3: PLATFORM ADMIN (Portal only)

### [Admin] Objective 1: "Approve a new assessoria"

**Entry:** Portal sidebar → "Admin Plataforma" → `/platform/assessorias`

**Steps:**
1. `[AssessoriasPage]` → server component using `createAdminClient()` → fetches all coaching_groups with approval fields (assessorias/page.tsx:19-27)
2. Joins coach profiles + member counts via parallel queries (assessorias/page.tsx:33-46)
3. Splits into 4 sections: Pendentes, Aprovadas, Rejeitadas, Suspensas with stat cards (assessorias/page.tsx:63-74, 86-100)
4. Each group card shows: name, city, coach name, member count, approval status, created date
5. `AssessoriaActions` component provides approve/reject/suspend actions (assessorias/page.tsx:2) — server actions update `approval_status` field
6. On approval → staff's `StaffDashboardScreen._loadStatus()` will see `approval_status = 'approved'` on next load → dashboard unlocks (staff_dashboard_screen.dart:187-188)

**Success criteria:** Admin sees pending groups, can approve/reject with reason, staff sees status change immediately.

**Failure points:**
- **F1:** `createAdminClient()` uses service role key — bypasses RLS. Admin-only page guarded by middleware. PASS.
- **F2:** No optimistic update — page must be refreshed to see changes (server-rendered). **PARTIAL**.

**Edge cases:**
- **Empty:** Stat cards show 0 for each category. Empty section not rendered. PASS.
- **Permission:** Admin client used only on `/platform/*` routes. Middleware checks `platform_admin` role. PASS.
- **Error:** No visible try/catch on the main query — Next.js error boundary would catch. Page has `global-error.tsx` and `error.tsx` boundaries. PASS.
- **Double-click:** Server actions are idempotent (setting same status twice is safe). Form submission may not have explicit guard. **PARTIAL**.
- **State restore:** Server-rendered — full page reload shows current state. PASS.

**Verdict:** PASS

---

### [Admin] Objective 2: "Manage platform products and badges"

**Entry (Products):** `/platform/produtos`
**Entry (Badges):** `/platform/conquistas`

**Steps (Products):**
1. `[ProdutosPage]` → fetches `billing_products` ordered by sort_order (produtos/page.tsx:23-27)
2. Splits into active/inactive sections (produtos/page.tsx:29-30)
3. Renders `ProductCard` for each product showing name, credits, price, status
4. Bottom: `ProductForm` for creating new product with name, description, credits, price, currency, type (produtos/page.tsx:74-79)

**Steps (Badges):**
1. `[ConquistasPage]` → fetches `badges` ordered by category/tier + count of total `badge_awards` (conquistas/page.tsx:31-39)
2. Groups by category (Distance, Frequency, Speed, Endurance, Social, Special) (conquistas/page.tsx:46-47)
3. Table shows: name, tier badge (Bronze/Silver/Gold/Diamond), description, XP reward, coins reward, criteria type, secret flag (conquistas/page.tsx:62-80)
4. `BadgeForm` at top for creating new badges (conquistas/page.tsx:60)

**Success criteria:** Admin can view all products/badges, create new ones, toggle active status.

**Failure points:**
- **F1:** Products page shows error from `error` variable of Supabase query for badges (conquistas/page.tsx:41-43) but products page has no error handling shown. **PARTIAL**.
- **F2:** No delete functionality visible — only create and toggle. Safe by design. PASS.

**Edge cases:**
- **Empty:** Products: both active/inactive sections conditionally render — if empty, sections not shown. Badges: empty category not rendered. PASS.
- **Permission:** `createAdminClient()` — admin-only access. PASS.
- **Error:** Badges page logs error and continues with empty array (conquistas/page.tsx:41-43). Products page no visible error handling. **PARTIAL**.
- **Double-click:** Server actions for form submission. No visible client-side guard. **PARTIAL**.
- **State restore:** Server-rendered — always fresh on load. PASS.

**Verdict:** PASS

---

### [Admin] Objective 3: "View platform financials"

**Entry:** `/platform/financeiro` (platform-wide) + `/clearing` and `/custody` (per-group)

**Steps (Platform Financeiro):**
1. `[FinanceiroPage]` → fetches `billing_purchases` with filters (status, period) → joins group names (financeiro/page.tsx:19-67)
2. Stats: total revenue (fulfilled), total pending (financeiro/page.tsx:69-74)
3. Table: purchase list with group name, credits, price, status, payment method, date
4. Filters: status dropdown (all/pending/paid/fulfilled/refunded), period (all/week/month) (financeiro/page.tsx:22-48)

**Steps (Clearing — per group):**
1. `/clearing` → fetches receivables + payables from `clearing_settlements` + events from `clearing_events` (clearing/page.tsx:38-42)
2. Stats: total receivable, total payable, total settled in/out, fees paid, avg settle time (clearing/page.tsx:65-78)

**Steps (Custody — per group):**
1. `/custody` → fetches custody account, deposits, withdrawals, coin ledger, settlements (custody/page.tsx:18-26)
2. Stats: deposited, committed, available, settled, coins alive
3. Invariant checks: total = committed + available, reserved = coins alive (custody/page.tsx:40-41)
4. Ledger view with all transactions

**Success criteria:** Admin can see platform-wide revenue, per-group clearing/custody, and verify financial invariants.

**Failure points:**
- **F1:** Custody invariant checks calculated client-side — if data is stale or query fails, invariants may show false alarms. The checks are informational (display only). PASS.
- **F2:** Financeiro page has no error handling visible — relies on Next.js error boundary. **PARTIAL**.

**Edge cases:**
- **Empty:** Zero stats displayed. Empty tables. PASS.
- **Permission:** Platform financeiro uses `createAdminClient()`. Clearing/Custody use `createServiceClient()` with group cookie. PASS.
- **Error:** Relies on Next.js error boundaries. PASS.
- **Double-click:** Read-only pages — no actions. PASS.
- **State restore:** `force-dynamic` — always server-rendered. PASS.

**Verdict:** PASS

---

### [Admin] Objective 4: "Handle support escalations"

**Entry:** `/platform/support`

**Steps:**
1. `[SupportListPage]` → fetches ALL support tickets (cross-group) using `createAdminClient()` with optional status filter (platform/support/page.tsx:22-33)
2. Joins group names + message counts (platform/support/page.tsx:41-51)
3. Stats: open count, answered count, closed count (platform/support/page.tsx:68-70)
4. Table: ticket list with group name, subject, status badge, message count, dates
5. Status filter tabs: All / Aberto / Respondido / Fechado (platform/support/page.tsx:23, 72-80)
6. Click ticket → `/platform/support/[id]` → `ticket-chat.tsx` — admin can read and respond to messages

**Success criteria:** Admin sees all tickets across groups, can filter by status, can respond to individual tickets.

**Failure points:**
- **F1:** Fetches up to 200 tickets (platform/support/page.tsx:29). Large platforms may exceed this. **PARTIAL** — no pagination.
- **F2:** Admin response changes ticket status to "answered" — staff sees update on next load. PASS.

**Edge cases:**
- **Empty:** Table shows no rows. Stats show 0 counts. PASS.
- **Permission:** `createAdminClient()` — admin-only. PASS.
- **Error:** No visible try/catch — relies on error boundary. PASS.
- **Double-click:** Server actions for message send. No visible guard. **PARTIAL**.
- **State restore:** Server-rendered — always current. PASS.

**Verdict:** PASS

---

### [Admin] Objective 5: "Manage feature flags"

**Entry:** `/platform/feature-flags`

**Steps:**
1. `[FeatureFlagsPage]` → fetches `feature_flags` table: id, key, enabled, rollout_pct, timestamps (feature-flags/page.tsx:7-11)
2. Renders table with columns: Flag key, Status (enabled/disabled), Rollout %, Updated at (feature-flags/page.tsx:27-42)
3. Each row is a `FeatureFlagRow` client component — allows toggling enabled status and adjusting rollout percentage (feature-flags/page.tsx:54-56)
4. Client-side `FeatureFlagService` in Flutter app loads flags at startup via `load()` → caches in memory → `isEnabled(key)` checks enabled + rollout_pct using deterministic hash bucketing (feature_flags.dart:21-68)
5. Admin toggles flag → DB updated → next app refresh picks up change

**Success criteria:** Admin can see all flags, toggle them, adjust rollout percentage. Changes propagate to app on next load.

**Failure points:**
- **F1:** Known risk documented in code (feature_flags.dart:50-54): mid-operation flag toggle may cause stale cache. Callers of destructive operations should re-check server-side. Documented. PASS.
- **F2:** No "create new flag" UI visible — only toggle existing. Admin must insert directly in DB or there's a form in `FeatureFlagRow`. **PARTIAL** — no create button on page.
- **F3:** App-side cache has no TTL or periodic refresh — only refreshes on explicit call. If user keeps app open for hours, flags may be stale. **PARTIAL** — no automatic periodic refresh.

**Edge cases:**
- **Empty:** Shows "Nenhuma feature flag cadastrada" in empty table state (feature-flags/page.tsx:44-52). PASS.
- **Permission:** `createAdminClient()` — admin-only. PASS.
- **Error:** No visible error handling — relies on error boundary. PASS.
- **Double-click:** Toggle is a server action — sequential processing. Idempotent. PASS.
- **State restore:** Server-rendered page — always shows current DB state. App caches until manual refresh. PASS.

**Verdict:** PASS

---

## Summary Matrix

| Profile | Objective | Verdict | Key Issues |
|---------|-----------|---------|------------|
| Athlete | 1. Sign up & join group | **PASS** | Retry fallback to HomeScreen may skip onboarding |
| Athlete | 2. Today & log session | **PASS** | 60s throttle + random jitter delays |
| Athlete | 3. Challenges & compete | **PARTIAL** | No double-click guard on Accept button |
| Athlete | 4. Track progress | **PASS** | Requires groupId from caller |
| Athlete | 5. Confirm delivery | **PASS** | All edge cases handled well |
| Staff | 1. Create/manage group | **PASS** | No debounce on dashboard card taps |
| Staff | 2. Workout templates | **PARTIAL** | Unused screen TODO, portal null render |
| Staff | 3. Monitor engagement | **PARTIAL** | Dashboard null render, CRM 200-member cap |
| Staff | 4. Championships | **PASS** | |
| Staff | 5. Support tickets | **PARTIAL** | No empty state, silent error on list load |
| Admin | 1. Approve assessoria | **PASS** | No optimistic update |
| Admin | 2. Products & badges | **PASS** | |
| Admin | 3. Platform financials | **PASS** | |
| Admin | 4. Support escalations | **PASS** | 200-ticket limit, no pagination |
| Admin | 5. Feature flags | **PASS** | No create button, no TTL on app cache |

**Overall: 11 PASS, 4 PARTIAL, 0 FAIL**

### Critical Action Items

1. **[HIGH] Challenge Accept double-click** — Add `_busy` guard to `_AcceptDeclineCard._onAccept()` in `challenge_details_screen.dart`
2. **[MED] Portal null renders** — Dashboard, workouts, and other portal pages return `null` when `groupId` cookie is missing. Should show an error/redirect instead.
3. **[MED] CRM 200-member cap** — Portal CRM page limits to 200 athletes. Large assessorias will have incomplete views. Add server-side pagination.
4. **[MED] Support ticket list errors** — `SupportScreen._load()` swallows exceptions silently. Show error state.
5. **[LOW] Support empty state** — Add "Nenhum ticket de suporte" empty state to `SupportScreen`.
6. **[LOW] Feature flag create** — Add "New flag" button to feature flags page or document DB-only creation.
7. **[LOW] Random jitter on TodayScreen** — The `Random().nextInt(2000)` delay on every load adds 0-2s of unnecessary latency.
