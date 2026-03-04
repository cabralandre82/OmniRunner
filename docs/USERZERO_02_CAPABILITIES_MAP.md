# USERZERO_02 — Capabilities Map

---

## Part A — Mobile App (Flutter)

### USERZERO 02 — App Capabilities Inventory

> **Generated:** 2026-03-04  
> **Scope:** Flutter mobile app at `omni_runner/`  
> **Total screens audited:** 104 (99 in `presentation/screens/` + 5 in features)  
> **Method:** Every `*_screen.dart` file was read and catalogued.

---

### Table of Contents

1. [Navigation Architecture](#1-navigation-architecture)
2. [Authentication & Onboarding](#2-authentication--onboarding)
3. [Athlete — Dashboard & Daily](#3-athlete--dashboard--daily)
4. [Athlete — Running & Sessions](#4-athlete--running--sessions)
5. [Athlete — Training & Coaching](#5-athlete--training--coaching)
6. [Athlete — Challenges](#6-athlete--challenges)
7. [Athlete — Championships](#7-athlete--championships)
8. [Athlete — Progress & Gamification](#8-athlete--progress--gamification)
9. [Athlete — Social](#9-athlete--social)
10. [Athlete — Groups & Assessoria](#10-athlete--groups--assessoria)
11. [Staff — Dashboard & Management](#11-staff--dashboard--management)
12. [Staff — CRM & Athletes](#12-staff--crm--athletes)
13. [Staff — Training Sessions](#13-staff--training-sessions)
14. [Staff — Workouts](#14-staff--workouts)
15. [Staff — Championships & Competitions](#15-staff--championships--competitions)
16. [Staff — QR Operations & Credits](#16-staff--qr-operations--credits)
17. [Staff — Analytics & Reports](#17-staff--analytics--reports)
18. [Shared — Profile, Settings, Support](#18-shared--profile-settings-support)
19. [Events & Announcements](#19-events--announcements)
20. [Integration & Export](#20-integration--export)
21. [Infrastructure Screens](#21-infrastructure-screens)
22. [Capability Summary Matrix](#22-capability-summary-matrix)

---

### 1. Navigation Architecture

#### Bottom Navigation Tabs

| Role | Tab 1 | Tab 2 | Tab 3 | Tab 4 |
|------|-------|-------|-------|-------|
| **Athlete** | Início (AthleteDashboardScreen) | Hoje (TodayScreen) | Histórico (HistoryScreen) | Mais (MoreScreen) |
| **Staff** | Início (StaffDashboardScreen) | — | — | Mais (MoreScreen) |

#### Auth Gate Flow
```
App Start → RecoveryScreen (if active session) → AuthGate
  ├── No session → WelcomeScreen → LoginScreen
  ├── NEW user → OnboardingRoleScreen
  │    ├── ATLETA → JoinAssessoriaScreen → [OnboardingTourScreen] → HomeScreen
  │    └── ASSESSORIA_STAFF → StaffSetupScreen → HomeScreen
  └── READY user → HomeScreen(userRole)
```

#### Role-Based Routing
- `HomeScreen` switches between athlete shell (4 tabs) and staff shell (2 tabs) based on `userRole`
- `MoreScreen` shows different menu items per role (athlete: assessoria/social/friends; staff: QR operations/partners)
- Deep links: challenge invites, assessoria invites, Strava callbacks
- Push notifications: challenge events, friend requests, streaks, championships

---

### 2. Authentication & Onboarding

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **WelcomeScreen** | Value prop + CTA for new users | Tap "COMEÇAR" | None | Public | N/A | N/A | N/A | Animated bullets: challenge, train, championships, metrics |
| **LoginScreen** | Social + email sign-in | Google, Apple (iOS), Instagram, Email/Password, Sign Up, Reset Password | `AuthRepository` | Public | N/A | ✅ inline error message | ✅ spinner | Pending invite banner; connection check |
| **OnboardingRoleScreen** | Choose ATLETA or ASSESSORIA_STAFF | Select role → confirm dialog → `set-user-role` EF | Edge Function `set-user-role` | Authenticated | N/A | ✅ error text | ✅ spinner in button | Permanent choice warning; 3 retries |
| **JoinAssessoriaScreen** | Find and request to join assessoria | Search, QR scan, enter code, accept invite, skip | `fn_search_coaching_groups`, `fn_request_join`, `fn_lookup_group_by_invite_code`, `coaching_invites`, `coaching_join_requests` | Athlete onboarding | ✅ "search prompt" | ✅ error text | ✅ spinner | Pending invites section; cancel previous request |
| **StaffSetupScreen** | Create or join assessoria as coach | Create (name/city/state), Search, QR, enter code | `fn_create_assessoria`, `fn_search_coaching_groups`, `fn_request_join` | Staff onboarding | ✅ search prompt | ✅ error text | ✅ spinner | All 27 BR states; approval dialog |
| **OnboardingTourScreen** | 9-slide feature tour | Swipe, Next, Skip | None (local) | First-time athlete | N/A | N/A | N/A | Tips: Strava, Challenges, Assessoria, Streaks, Evolution, Friends, Challenge types, OmniCoins, Verification |
| **HowItWorksScreen** | Reference page for rules | Scroll | None | Both | N/A | N/A | N/A | Sections: Challenges, OmniCoins, Verification, Integrity |
| **RecoveryScreen** | Recover crashed session | Resume, Discard | `RecoverActiveSession`, `FinishSession`, `DiscardSession` | Both | N/A | N/A | N/A | Shows distance/pace/status of found session |

---

### 3. Athlete — Dashboard & Daily

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **AthleteDashboardScreen** | Home hub with 7 feature cards | Navigate to Challenges, Assessoria, Progress, Verification, Championships, Parks, Credits | `profiles`, `coaching_members`, `coaching_groups`, `coaching_join_requests`, `StravaConnectController` | Athlete | ✅ "join assessoria" CTA when unbound | ✅ (graceful) | ✅ shimmer grid | Pending request banner; Strava warning badge; feed link |
| **TodayScreen** | Daily status with streak/run recap | Pull-to-refresh, share run, journal (bottom sheet with mood emoji), navigate to challenges/championships/parks/settings | `TodayDataService`, `IProfileProgressRepo`, `ISessionRepo`, `IChallengeRepo`, `ParkDetectionService`, `StravaConnectController`, `NotificationRulesService` | Athlete | ✅ "Bora correr" CTA | ✅ offline icon + retry button | ✅ shimmer placeholders | Strava connect prompt; streak banner with milestones; run comparison vs previous; park check-in; active challenges/championships cards |
| **HistoryScreen** | Last 30 completed sessions | Tap → RunDetailsScreen; pull-to-refresh; sync sessions; load more pagination | `ISessionRepo`, `ISyncRepo`, `sessions` table (Supabase) | Athlete | ✅ EmptyState widget | ✅ (implicit) | ✅ shimmer list | Ghost pick mode; merges local Isar + remote sessions; filters ≥1km |

---

### 4. Athlete — Running & Sessions

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **RunSummaryScreen** | Post-run summary with map | Share run card, view metrics, challenge session banner | MapLibre map, `LocationPointEntity`, Supabase | Athlete | N/A | N/A | N/A | Full polyline; ghost comparison card; invalidated run card |
| **RunDetailsScreen** | Detailed view of a past session | Export, replay, view metrics, map | `IPointsRepo`, `sessions` table, `FilterLocationPoints` | Athlete | N/A | N/A | ✅ | MapLibre map; pace splits; invalidated run warning |
| **RunReplayScreen** | Animated replay of a run | Play/pause, speed control, view splits | `LocationPointEntity`, `ReplayAnalyzer` | Athlete | N/A | N/A | N/A | Animated polyline; sprint highlights; km split markers |
| **MapScreen** | Base map display | Pan/zoom | MapLibre GL (MapTiler) | Both | N/A | N/A | N/A | MapTiler streets-v2 or fallback demo tiles |

---

### 5. Athlete — Training & Coaching

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **AthleteTrainingListScreen** | List group training sessions | View upcoming/past, check-in QR | `TrainingListBloc`, `training_sessions` | Athlete | ✅ BlocBuilder handles | N/A | ✅ shimmer | Check-in QR button per session |
| **AthleteCheckinQrScreen** | Generate QR for attendance check-in | Auto-generate QR, countdown timer, refresh | `CheckinBloc`, `ITrainingAttendanceRepo` | Athlete | N/A | ✅ error state | ✅ | QR with expiry countdown |
| **AthleteAttendanceScreen** | View personal attendance history | View calendar of check-ins | `ITrainingAttendanceRepo` | Athlete | ✅ empty list | ✅ error string | ✅ shimmer | Calendar view; attendance rate |
| **AthleteWorkoutDayScreen** | View assigned workout for today | Mark completed, view blocks, navigate to deliveries | `IWorkoutRepo`, `WorkoutDeliveryService` | Athlete | ✅ "no workout today" | ✅ error text | ✅ shimmer | Pending delivery count badge |
| **AthleteLogExecutionScreen** | Manual workout execution log | Form: duration, distance, pace, HR, source device | `ImportExecution` use case | Athlete | N/A | ✅ error display | ✅ spinner | Source picker: Manual/Garmin/Apple/Polar/Suunto |
| **AthleteDeliveryScreen** | Confirm workout deliveries | Confirm success, report failure (with reason) | `WorkoutDeliveryService` | Athlete | ✅ StateWidgets | ✅ error text | ✅ | Failure reasons: didn't sync, different workout, watch error, other |
| **AthleteDeviceLinkScreen** | Link wearable devices | Link/unlink: Garmin, Apple Watch, Polar, Suunto, TrainingPeaks | `LinkDevice` use case | Athlete | ✅ StateWidgets | ✅ error text | ✅ shimmer | Feature flag gated (TrainingPeaks) |

---

### 6. Athlete — Challenges

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **ChallengesListScreen** | Browse/filter own challenges | Create challenge, matchmaking, filter by status, tap for details | `ChallengesBloc`, `StravaConnectController` | Athlete | ✅ TipBanner | ✅ ErrorState | ✅ shimmer | Strava requirement check; verification gate; FAB for create; matchmaking button |
| **ChallengeCreateScreen** | Create new challenge | Pick type (1v1/group/team), goal, target, window, entry fee, title | `ChallengesBloc`, `VerificationBloc`, `NotificationRulesService`, `ProductEventTracker` | Athlete | N/A | ✅ (bloc state) | ✅ | Verification gate for paid challenges; 4 goal types; success overlay → invite screen |
| **ChallengeDetailsScreen** | View challenge details + progress | Join, leave, share, view participants, submit dispute, see result | `ChallengesBloc`, `VerificationBloc`, `sessions`, `challenge_participants` | Athlete | N/A | ✅ | ✅ | Dispute card; real-time participant list; share deep link; result navigation |
| **ChallengeJoinScreen** | Join challenge from deep link | Fetch details, join with single tap | `challenges`, `challenge_participants`, `challenge-join` EF | Athlete | N/A | ✅ error text | ✅ | LoginRequiredSheet guard; success overlay |
| **ChallengeInviteScreen** | Share challenge invite link | Copy link, share via native sheet | Challenge entity (local) | Athlete | N/A | N/A | N/A | Deep link format: `omnirunner.app/challenge/{id}` |
| **ChallengeResultScreen** | Post-challenge results | Rematch, challenge again, add friend, view leaderboards | Challenge/result entities, `IFriendshipRepo`, `SendFriendInvite` | Athlete | N/A | N/A | N/A | Winner banner; metrics comparison; reward status; next-action CTAs |
| **MatchmakingScreen** | Queue-based opponent finding | Configure intent (metric/target/duration/fee), search, cancel | `fn_matchmaking_enqueue`, `fn_matchmaking_dequeue`, `fn_matchmaking_check`, `VerificationBloc`, `ISessionRepo`, `ICoachingMemberRepo`, `ParkDetectionService` | Athlete | N/A | ✅ | ✅ | Verification gate; Strava check; animated search state; park-based matchmaking preference |

---

### 7. Athlete — Championships

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **AthleteChampionshipsScreen** | Browse and join championships | Filter (all/open/active/enrolled), self-enroll | `champ-list` EF, `champ-enroll` EF | Athlete | ✅ "no championships" | ✅ error text | ✅ shimmer | Status pills; enrollment confirmation |
| **AthleteChampionshipRankingScreen** | View championship ranking | Scroll participant list, tap profiles | `champ-ranking` via Supabase | Athlete | ✅ empty list | ✅ error text | ✅ | Top-3 medals; metric display (distance/pace/sessions) |

---

### 8. Athlete — Progress & Gamification

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **ProgressHubScreen** | Central progress hub — 10 feature cards | Navigate to: Progression, Badges, Missions, Leaderboards, Streaks, League, DNA, Challenges, Wrapped, Feed, Championships, Evolution | `ICoachingMemberRepo`, Supabase | Athlete | N/A | N/A | N/A | Grid of navigation cards |
| **ProgressionScreen** | XP, level, weekly goals, streak details | View level progress, weekly goal gauge, XP history, set weekly goal | `ProgressionBloc`, `IProfileProgressRepo` | Athlete | ✅ BlocBuilder | ✅ | ✅ | Level bar; weekly goal editor; XP milestones; tip banners |
| **BadgesScreen** | Badge collection gallery | View earned/locked badges, tap for details | `BadgesBloc`, `badge_awards`, `badge_definitions` | Athlete | ✅ "no badges" tip | ✅ | ✅ | Earned vs locked grouping; badge detail bottom sheet |
| **MissionsScreen** | Weekly/daily missions tracker | View missions, track progress, claim rewards | `MissionsBloc`, `missions`, `mission_progress` | Athlete | ✅ | ✅ | ✅ | Progress bars; reward indicators |
| **LeaderboardsScreen** | Assessoria weekly leaderboards | Filter by metric (distance/pace/sessions/XP), view ranking | `LeaderboardsBloc`, `v_leaderboard`, Supabase | Athlete | ✅ tip banner | ✅ | ✅ | Highlight own position; top-3 medals; assessoria context |
| **StreaksLeaderboardScreen** | Streak-based consistency ranking | View active streaks, consistency ranking | `coaching_members`, `v_user_progression` | Athlete | ✅ "no assessoria" fallback | ✅ | ✅ | Two sections: active streaks + best streaks |
| **LeagueScreen** | Liga de Assessorias — inter-group ranking | View season, ranked groups, personal contribution | `league-list` EF | Athlete | ✅ "no data" | ✅ | ✅ | Season timer; top-3 medals; own assessoria highlight |
| **PersonalEvolutionScreen** | 12-week performance charts | View pace/distance/frequency trends | `sessions` table, client-side aggregation | Athlete | ✅ "no data" | ✅ | ✅ | fl_chart line/bar charts; ISO week bucketing |
| **RunningDnaScreen** | 6-axis radar profile | View/share DNA card | `sessions`, computed client-side: endurance, speed, consistency, volume, progression, heart | Athlete | ✅ "need more runs" | ✅ | ✅ | Radar chart via fl_chart; shareable image export |
| **WrappedScreen** | Monthly retrospective "stories" | Swipe through slides, share card | `sessions`, `v_user_progression`, `badge_awards` | Athlete | ✅ "not enough data" | ✅ | ✅ | Stories-style PageView; shareable summary image |
| **AthleteVerificationScreen** | Verification status & progress | View progress (7 valid runs needed), trigger re-evaluation | `VerificationBloc`, `sessions`, Supabase | Athlete | N/A | ✅ ErrorView | ✅ | Progress ring; session list with flags; verification levels: unverified → verified → monitored |
| **AthleteEvolutionScreen** | Evolution trends for specific athlete | Filter by metric/period, view trend chart | `AthleteEvolutionBloc` | Staff (viewing athlete) | ✅ | ✅ | ✅ | Metric/period filters; baseline comparison |
| **AthleteMyEvolutionScreen** | Athlete's own evolution within group | View status, tags, attendance history | `ICrmRepo`, `ITrainingAttendanceRepo` | Athlete | ✅ | ✅ error text | ✅ shimmer | CRM tags; attendance calendar; status badge |
| **AthleteMyStatusScreen** | Athlete status within coaching group | View coach tags, workout templates, status | `coaching_members`, `workout_templates` | Athlete | ✅ | ✅ | ✅ | Feature-flagged content |

---

### 9. Athlete — Social

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **FriendsScreen** | Manage friend list | Search users, send/accept/reject/block requests, view profiles | `FriendsBloc`, `IFriendshipRepo` | Athlete | ✅ EmptyState | ✅ ErrorState | ✅ shimmer | Tabs: friends, pending, search; block user |
| **FriendProfileScreen** | View friend's public profile | Send friend request, view DNA, open social links | `profiles`, `IFriendshipRepo`, `SendFriendInvite`, `v_user_progression` | Athlete | N/A | ✅ | ✅ | Avatar, level, assessoria, DNA scores, Instagram/TikTok links |
| **FriendsActivityFeedScreen** | Recent runs from friends | Scroll feed, tap for profile | `fn_friends_activity_feed` RPC | Athlete | ✅ "no activity" | ✅ | ✅ | Paginated (30 per page); verified sessions only |
| **InviteFriendsScreen** | Invite friends to app | Copy referral link, show QR, share via native sheet | Local (user ID) | Athlete | N/A | N/A | N/A | 3 methods: link, QR, native share; referral URL format |

---

### 10. Athlete — Groups & Assessoria

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **MyAssessoriaScreen** | Assessoria hub for athletes | View group info, navigate to feed/rankings/evolution/challenges/championships, switch assessoria | `MyAssessoriaBloc`, `coaching_members`, `coaching_groups` | Athlete | ✅ "join" CTA | ✅ | ✅ | Tabbed: info, feed, rankings, training, evolution |
| **AssessoriaFeedScreen** | Social feed within assessoria | View recent activities, interact | `AssessoriaFeedBloc`, `feed_items` | Both | ✅ | ✅ | ✅ | Run completions, badges earned, challenges won |
| **CoachingGroupsScreen** | List all coaching groups user belongs to | Tap for group details | `CoachingGroupsBloc` | Both | ✅ | ✅ | ✅ | Group logos; member count |
| **CoachingGroupDetailsScreen** | Detailed view of a coaching group | View members, roles, invite QR | `coaching_groups`, `coaching_members`, Supabase | Both | N/A | ✅ error text | ✅ | Member list; role badges; invite QR button |
| **GroupsScreen** | Generic groups list | View, refresh | `GroupsBloc` | Athlete | ✅ | ✅ | ✅ | |
| **GroupDetailsScreen** | Group info + members + goals | View | Group/member/goal entities | Athlete | ✅ | N/A | N/A | |
| **GroupMembersScreen** | Full member list for a group | View members, roles | `CoachingMemberEntity` | Both | ✅ | N/A | N/A | Current user highlighted |
| **GroupRankingsScreen** | Intra-group rankings | Filter by metric (distance/pace/sessions/XP) | `CoachingRankingsBloc` | Both | ✅ | ✅ | ✅ | Weekly rankings; metric toggles |
| **GroupEvolutionScreen** | Group-level evolution trends | Filter by metric, view trends | `GroupEvolutionBloc` | Both | ✅ | ✅ | ✅ | Aggregate trends across group athletes |
| **GroupEventsScreen** | Group race events | View upcoming/past races | `RaceEventsBloc` | Both | ✅ | ✅ | ✅ | Race calendar |
| **PartnerAssessoriasScreen** | Inter-assessoria partnerships | View partners, propose partnership, manage invites | `coaching_partnerships`, Supabase | Staff | ✅ | ✅ | ✅ | Tabbed: partners, sent invites, received invites |
| **InviteQrScreen** | Permanent invite QR for assessoria | Display QR, copy link, share | Local (invite code) | Staff | N/A | N/A | N/A | Persistent QR (no expiry); `omnirunner.app/invite/{code}` |

---

### 11. Staff — Dashboard & Management

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffDashboardScreen** | Staff home — 6 management cards | Navigate to: Athletes, Confirmations, Performance, Championships, Credits, Admin (QR) | `coaching_members`, `coaching_groups`, `IWalletRepo`, `challenges`, Supabase | Staff | ✅ shimmer | ✅ (graceful) | ✅ shimmer grid | Join requests badge count; pending clearing count; league link; support link; portal URL |
| **StaffJoinRequestsScreen** | View/approve/reject athlete requests | Approve, Reject with reason | `coaching_join_requests`, `fn_approve_join`, `NotificationRulesService` | Staff | ✅ "no requests" | ✅ | ✅ | Pending requests list; push notification on approval |

---

### 12. Staff — CRM & Athletes

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffCrmListScreen** | Filterable athlete list with CRM data | Search, filter by tag/status/risk, tap for profile | `CrmListBloc`, `ICrmRepo`, `ManageTags` | Staff | ✅ | ✅ | ✅ shimmer | Risk indicators; tag chips; status badges; bulk tag management |
| **StaffAthleteProfileScreen** | Tabbed athlete profile (staff view) | View/edit status, tags, notes, attendance, evolution | `AthleteProfileBloc`, `ICrmRepo`, `ITrainingAttendanceRepo` | Staff | ✅ per tab | ✅ | ✅ | Tabs: overview, notes, attendance, evolution; add notes; manage tags |
| **CoachInsightsScreen** | AI-generated coaching insights | View insights, dismiss | `CoachInsightsBloc` | Staff | ✅ | ✅ | ✅ | Insight types: at-risk, opportunity, trend |

---

### 13. Staff — Training Sessions

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffTrainingListScreen** | List group training sessions | Create, view details, filter upcoming/past | `TrainingListBloc`, `training_sessions` | Staff | ✅ | ✅ | ✅ shimmer | FAB to create; date display |
| **StaffTrainingDetailScreen** | Training session detail + attendance | View attendees, scan check-in QR, mark attendance | `TrainingDetailBloc`, `training_attendance` | Staff | ✅ | ✅ | ✅ | Scan button; attendance percentage |
| **StaffTrainingCreateScreen** | Create/edit training session | Form: title, date, time, location, description | `ITrainingSessionRepo`, `CreateTrainingSession` | Staff | N/A | ✅ | ✅ | Edit mode with pre-filled fields |
| **StaffTrainingScanScreen** | Scan athlete check-in QR | Camera scan → validate → record attendance | `CheckinBloc`, mobile_scanner | Staff | N/A | ✅ | N/A | Haptic feedback on success |

---

### 14. Staff — Workouts

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffWorkoutTemplatesScreen** | List workout templates | View, edit, create templates | `IWorkoutRepo` | Staff | ✅ shimmer → empty | ✅ | ✅ shimmer | FAB to create; template cards |
| **StaffWorkoutBuilderScreen** | Create/edit workout template with blocks | Add/remove/reorder blocks, save | `WorkoutBuilderBloc` | Staff | N/A | ✅ | ✅ shimmer | Block types: warmup, intervals, cooldown, etc. |
| **StaffWorkoutAssignScreen** | Assign workout to athlete | Select template, athlete, date, notes | `IWorkoutRepo`, `ICoachingMemberRepo`, `PushToTrainingPeaks` | Staff | ✅ | ✅ error text | ✅ shimmer | TrainingPeaks push (feature-flagged) |

---

### 15. Staff — Championships & Competitions

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffChampionshipTemplatesScreen** | Manage championship templates | Create template, launch championship from template | `championship_templates`, `champ-create` EF | Staff | ✅ "no templates" | ✅ | ✅ | Template: name, metric, duration, badge, max participants |
| **StaffChampionshipManageScreen** | Manage single championship | Open, invite groups, view invites, see participants | `champ-open`, `champ-invite`, `champ-accept-invite`, `champ-participant-list` EFs | Staff | ✅ | ✅ | ✅ | Badge QR generation; participant list |
| **StaffChampionshipInvitesScreen** | View/respond to championship invitations | Accept, reject invitations from other groups | `championship_invites`, Supabase | Staff | ✅ StateWidgets | ✅ | ✅ | Invitation details with group info |
| **StaffChallengeInvitesScreen** | View/respond to team challenge invitations | Accept, reject inter-assessoria challenges | `challenge_invites`, Supabase | Staff | ✅ StateWidgets | ✅ | ✅ | Team challenge details |
| **StaffDisputesScreen** | Manage clearing/dispute cases | View cases, take action | `clearing_cases`, Supabase | Staff | ✅ StateWidgets | ✅ | ✅ | Status tracking; deadline display |

---

### 16. Staff — QR Operations & Credits

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffQrHubScreen** | Hub for QR operations | Issue token, burn token, activate badge, invite QR | `ITokenIntentRepo`, `ICoachingGroupRepo` | Staff | ✅ access denied if not staff | N/A | N/A | 3 operations + scan + invite QR |
| **StaffGenerateQrScreen** | Generate QR for token intent | Select amount, generate, auto-expire countdown | `StaffQrBloc`, `ITokenIntentRepo` | Staff | N/A | ✅ | ✅ | QR with TTL countdown; amount selector |
| **StaffScanQrScreen** | Scan athlete's QR to process token | Camera scan → validate → consume intent | `StaffQrBloc`, mobile_scanner | Both | N/A | ✅ | N/A | Client-side expiry validation |
| **StaffCreditsScreen** | OmniCoin inventory and distribution | View available/distributed, contact platform | `coaching_group_credits`, `token_intents`, Supabase | Staff | ✅ StateWidgets | ✅ | ✅ | No monetary values; GAMIFICATION_POLICY compliant |

---

### 17. Staff — Analytics & Reports

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **StaffPerformanceScreen** | 4-KPI performance dashboard | View: active athletes, weekly runs, challenges, championships; drill-down to retention/weekly report | `coaching_members`, `sessions`, `challenges`, `championship_participants` | Staff | ✅ | ✅ | ✅ | Drill-down links; metric cards |
| **StaffRetentionDashboardScreen** | Engagement and growth metrics | View DAU/WAU, 4-week retention trend, active users | `sessions`, `coaching_members`, `coaching_groups` | Staff | ✅ | ✅ | ✅ | DAU/WAU gauge; retention chart |
| **StaffWeeklyReportScreen** | Weekly assessoria report | Navigate between weeks (prev/next) | `coaching_members`, `sessions`, `v_user_progression` | Staff | ✅ | ✅ | ✅ | Summary KPIs; avg progression; internal ranking by distance |

---

### 18. Shared — Profile, Settings, Support

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **ProfileScreen** | View/edit user profile | Edit display name, Instagram, TikTok handles; upload avatar; delete account | `IProfileRepo`, `ProfileDataService`, `AuthRepository`, image_picker | Both | N/A | ✅ error text | ✅ | Avatar upload; social links; delete account confirmation |
| **SettingsScreen** | App settings | Toggle theme (light/dark/system); Strava connect/disconnect; distance unit (km/mi); diagnostics; "How it works" | `ICoachSettingsRepo`, `StravaConnectController`, `ThemeNotifier` | Both | N/A | N/A | ✅ | Strava OAuth flow; coach-specific settings (staff); units toggle |
| **SupportScreen** | Support ticket list + create | Create ticket (category + subject + message), view list | `support_tickets`, `support_messages`, Supabase | Both | ✅ "no tickets" | ✅ | ✅ | Category picker; group context |
| **SupportTicketScreen** | Ticket chat view | Send messages, view conversation, close ticket | `support_tickets`, `support_messages`, Supabase | Both | ✅ "no messages" | ✅ | ✅ | Chat-style UI; status badge |
| **DiagnosticsScreen** | Debug/diagnostic info | View app version, Supabase status, sync status, pending queue | `AppConfig`, `ISyncRepo`, package_info_plus | Both (debug) | N/A | N/A | ✅ | Backend mode; connection status; debug-only |
| **MoreScreen** | Navigation hub for secondary features | Assessoria, QR scan, deliveries, friends, invite, profile, settings, about, logout | Various | Both | N/A | N/A | N/A | Role-aware menu; anonymous mode banner; logout with confirmation |

---

### 19. Events & Announcements

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **EventsScreen** | List group events | View, join/leave events | `EventsBloc`, `events`, `event_participations` | Both | ✅ | ✅ | ✅ | Upcoming/past grouping |
| **EventDetailsScreen** | Event detail view | RSVP, view participants | Event/participation entities | Both | N/A | N/A | N/A | Participant list; RSVP status |
| **GroupEventsScreen** | Race events for a specific group | View upcoming/past races | `RaceEventsBloc`, `race_events` | Both | ✅ | ✅ | ✅ | Race calendar by group |
| **RaceEventDetailsScreen** | Race event details + results | View race info, participants, results | `RaceEventDetailsBloc`, `race_participations`, `race_results` | Both | N/A | ✅ | ✅ | Race results table |
| **AnnouncementFeedScreen** | Group announcements feed | View, create (staff), tap for details | `AnnouncementFeedBloc`, `announcements` | Both | ✅ shimmer → empty | ✅ | ✅ shimmer | FAB for staff to create |
| **AnnouncementCreateScreen** | Create/edit announcement | Form: title, body, category | `IAnnouncementRepo`, `CreateAnnouncement` | Staff | N/A | ✅ | ✅ | Edit mode for existing |
| **AnnouncementDetailScreen** | View single announcement | Auto-mark as read, edit (staff) | `AnnouncementDetailBloc` | Both | N/A | ✅ | ✅ | Read tracking; staff edit button |

---

### 20. Integration & Export

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **ExportScreen** | Export session data to file | Choose format (GPX/TCX/FIT/CSV), share file | `ExportSheetController`, `WorkoutSessionEntity` | Athlete | N/A | ✅ | ✅ | Post-export education sheet; Strava import guide |
| **SettingsScreen** (Strava section) | Connect/disconnect Strava | OAuth flow via FlutterWebAuth2 | `StravaConnectController`, Supabase | Athlete | N/A | ✅ strava failures | ✅ | Connect/disconnect toggle; error handling |

---

### 21. Infrastructure Screens

| Screen | Purpose | Actions | Data Sources | Access | Empty | Error | Loading | Evidence |
|--------|---------|---------|-------------|--------|-------|-------|---------|----------|
| **AuthGate** | Route guard — determines destination | Auto-resolve auth + onboarding state | `UserIdentityProvider`, `IProfileRepo`, `DeepLinkHandler` | System | N/A | ✅ retry with backoff | ✅ spinner | 3 retries; deep link handling; invite code persistence |
| **HomeScreen** | Tab navigation shell | Switch tabs | None | System | N/A | N/A | N/A | NoConnectionBanner; IndexedStack for tab persistence |
| **RecoveryScreen** | Recover crashed in-progress session | Resume or discard | `RecoverActiveSession` | System | N/A | N/A | N/A | Session metrics display |

---

### 22. Capability Summary Matrix

#### By Module — Feature Count

| Module | Screens | Key Capabilities |
|--------|---------|-----------------|
| Auth & Onboarding | 8 | Google/Apple/Instagram/Email login, role selection, assessoria join, feature tour |
| Athlete Dashboard | 3 | Home hub, daily status, session history |
| Running & Sessions | 4 | Post-run summary, session detail, animated replay, map |
| Training & Coaching | 7 | Training list, check-in QR, attendance, workout day, execution log, deliveries, device link |
| Challenges | 7 | List, create, details, join (deep link), invite, results, matchmaking |
| Championships | 2 | Browse/join, view ranking |
| Progress & Gamification | 14 | Progression/XP/level, badges, missions, leaderboards, streaks, league, evolution, DNA, wrapped, verification |
| Social | 4 | Friends, friend profile, activity feed, invite friends |
| Groups & Assessoria | 12 | My assessoria, feed, groups, details, members, rankings, evolution, events, partners, invite QR |
| Staff Dashboard | 2 | Home hub, join requests |
| Staff CRM | 3 | Athlete list, athlete profile, coach insights |
| Staff Training | 4 | Training list, detail, create, scan check-in |
| Staff Workouts | 3 | Templates, builder, assignment |
| Staff Championships | 5 | Templates, manage, championship invites, challenge invites, disputes |
| Staff QR & Credits | 4 | QR hub, generate, scan, credits inventory |
| Staff Analytics | 3 | Performance KPIs, retention dashboard, weekly report |
| Shared | 6 | Profile, settings, support list, ticket chat, diagnostics, more menu |
| Events & Announcements | 7 | Events list, detail, group events, race details, announcements feed/create/detail |
| Integration | 1 | Export (GPX/TCX/FIT/CSV) |
| Infrastructure | 3 | Auth gate, home shell, recovery |

#### State Handling Coverage

| State | Screens with handling | Screens missing | Coverage |
|-------|----------------------|-----------------|----------|
| **Loading** | 90+ | ~10 (static/navigation screens) | ~92% |
| **Error** | 85+ | ~15 (mostly static/info screens) | ~87% |
| **Empty** | 70+ | ~30 (mostly detail/form screens) | ~72% |

#### Data Sources Summary

| Source | Usage |
|--------|-------|
| **Supabase Tables** | `profiles`, `sessions`, `coaching_groups`, `coaching_members`, `coaching_join_requests`, `coaching_invites`, `challenges`, `challenge_participants`, `championships`, `championship_templates`, `championship_invites`, `championship_participants`, `support_tickets`, `support_messages`, `announcements`, `badge_awards`, `badge_definitions`, `missions`, `mission_progress`, `token_intents`, `coaching_group_credits`, `clearing_cases`, `training_sessions`, `training_attendance`, `workout_templates`, `workout_assignments`, `friendships`, `feed_items`, `race_events`, `events`, `event_participations`, `session_journal_entries` |
| **Supabase RPCs** | `fn_search_coaching_groups`, `fn_request_join`, `fn_create_assessoria`, `fn_lookup_group_by_invite_code`, `fn_switch_assessoria`, `fn_approve_join`, `fn_friends_activity_feed`, `fn_matchmaking_enqueue/dequeue/check`, `recalculate_profile_progress` |
| **Edge Functions** | `set-user-role`, `challenge-join`, `champ-list`, `champ-enroll`, `champ-ranking`, `champ-create`, `champ-open`, `champ-invite`, `champ-accept-invite`, `champ-participant-list`, `league-list` |
| **Supabase Views** | `v_user_progression`, `v_leaderboard` |
| **Local (Isar)** | `ISessionRepo`, `IProfileProgressRepo`, `IChallengeRepo`, `ICoachingGroupRepo`, `ICoachingMemberRepo`, `IPointsRepo` |
| **External** | Strava OAuth (FlutterWebAuth2), Firebase (FCM push), MapLibre/MapTiler (maps), Sentry (error tracking) |

#### Access Role Matrix

| Feature Area | Athlete | Staff | Both | Public |
|-------------|---------|-------|------|--------|
| Auth & Onboarding | — | — | — | ✅ |
| Dashboard | ✅ | ✅ | — | — |
| Running/Sessions | ✅ | — | — | — |
| Training | ✅ | ✅ | — | — |
| Challenges | ✅ | — | — | — |
| Championships | ✅ | ✅ | — | — |
| Progress/Gamification | ✅ | — | — | — |
| Social | ✅ | — | — | — |
| Groups/Assessoria | — | — | ✅ | — |
| CRM | — | ✅ | — | — |
| QR Operations | — | ✅ | — | — |
| Analytics | — | ✅ | — | — |
| Profile/Settings/Support | — | — | ✅ | — |
| Events/Announcements | — | — | ✅ | — |
| Export | ✅ | — | — | — |

#### Guards & Gates

| Guard | Where Used | Behavior |
|-------|-----------|----------|
| `LoginRequiredSheet` | Dashboard cards, More screen actions | Bottom sheet prompting login if anonymous |
| `AssessoriaRequiredSheet` | Challenges, Championships | Bottom sheet prompting assessoria join |
| `VerificationGate` | ChallengeCreate, ChallengeDetails, Matchmaking | Blocks paid challenges if not verified |
| `AuthGate` | App root | Full routing guard based on auth + onboarding state |
| `StaffQrHubScreen` | QR operations | Access denied if not staff role |

---

*End of Part A — Mobile App*

---

## Part B — Portal (Next.js)

### Portal Capabilities Inventory

> **Generated:** 2026-03-04  
> **Scope:** Next.js portal at `portal/src/app/`  
> **Total pages:** 55 page files \| 36 API routes  
> **Roles:** `admin_master`, `coach`, `assistant`, `platform_admin`

---

### Access Control Summary

| Layer | Mechanism |
|-------|-----------|
| **Auth** | Supabase session via `updateSession()` middleware |
| **Group binding** | `portal_group_id` + `portal_role` cookies, verified server-side against `coaching_members` |
| **Multi-group** | Users with 2+ groups are redirected to `/select-group` |
| **Role enforcement** | Sidebar filters by role; middleware blocks admin-only routes (`/credits`, `/billing`, `/settings`) for non-`admin_master`; platform routes require `platform_role = "admin"` on `profiles` |
| **Error boundary** | `error.tsx` (portal) + `global-error.tsx` (app root) — both with "Try Again" button |

---

### Module 1: Authentication & Onboarding

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/login` | Email/password + social login (Google, Apple) | Sign in with email; OAuth redirect (Google/Apple) | `supabase.auth` | Public | N/A | Inline error message | Client component with Suspense |
| `/select-group` | Choose assessoria when user has 2+ memberships | Click to select group (sets cookies via server action) | `coaching_members`, `coaching_groups` | Authenticated | Redirect to `/no-access` if 0 groups | N/A | Auto-selects if only 1 group |
| `/no-access` | Blocked page for non-staff users | Sign out button | `profiles`, `coaching_members` | Authenticated | N/A | N/A | Shows specific message for athletes vs. non-members |
| `/` (root) | Root redirect | None | None | Any | N/A | N/A | Redirects to `/dashboard` |

---

### Module 2: Dashboard / Overview

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/dashboard` | Overview KPIs: credits, athletes, sessions, challenges, weekly charts | Quick links to Credits, Athletes, Engagement, Verification, Settings (admin only) | `coaching_token_inventory`, `coaching_members`, `sessions`, `athlete_verification`, `challenge_participants`, `billing_purchases` | admin_master, coach, assistant | Shows 0 values | Full error block "Erro ao carregar dados" | Low-credit alert with "Recarregar" CTA (admin); daily session chart; week-over-week trend |

---

### Module 3: Athletes Management

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/athletes` | List all athletes with stats | Export CSV; Distribute OmniCoins (admin only, per-athlete button) | `coaching_members`, `athlete_verification`, `fn_athlete_session_stats` (RPC) | admin_master, coach, assistant | "Nenhum atleta vinculado" | Error block | Shows: name, verification status, trust score, sessions, distance, join date |
| `/verification` | Athlete verification status dashboard | Reevaluate button (admin/coach) | `coaching_members`, `athlete_verification` | admin_master, coach, assistant | "Nenhum atleta vinculado" | N/A | Read-only verification; sorted by risk (DOWNGRADED first); info banner explains automation |

---

### Module 4: Engagement & Analytics

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/engagement` | DAU/WAU/MAU, retention, engagement scores, inactive athletes | Period filter (7/14/30 days); link to CRM per athlete | `coaching_members`, `sessions`, `challenge_participants`, `coaching_kpis_daily`, `coaching_athlete_kpis_daily`, `profiles` | admin_master, coach, assistant | Shows 0 values | N/A | Warning banner for inactive athletes; engagement score trend chart; inactive athlete list |
| `/attendance` | Training session attendance report | Date range filter; session filter; Export CSV | `coaching_training_sessions`, `coaching_training_attendance`, `coaching_members` | admin_master, coach, assistant | "Nenhum treino encontrado" | Error block | Links to session detail |
| `/attendance/[id]` | Single session attendance detail | Manual attendance button (disabled, "Em breve") | `coaching_training_sessions`, `coaching_training_attendance`, `profiles`, `coaching_members` | admin_master, coach, assistant | "Nenhum check-in registrado" | "Treino não encontrado" | Shows check-in method (QR/Manual), status (Present/Late/Excused/Absent) |
| `/attendance-analytics` | Advanced attendance analytics | Period filter (7/14/30/custom); per-athlete breakdown | `coaching_training_sessions`, `coaching_training_attendance`, `coaching_members`, `profiles` | admin_master, coach, assistant | "Nenhum atleta no grupo" | N/A | Low-attendance sessions flagged; per-athlete rate table |

---

### Module 5: CRM

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/crm` | CRM list with tags, status, alerts, notes | Filter by tag/status/search; Export CSV; link to at-risk page | `coaching_members`, `profiles`, `coaching_member_status`, `coaching_athlete_tags`, `coaching_training_attendance`, `coaching_alerts`, `coaching_athlete_notes` | admin_master, coach, assistant | "Nenhum atleta encontrado" | Error block | Shows last note preview; truncated to 200 athletes |
| `/crm/[userId]` | Individual athlete detail profile | Add notes (form); view alerts, attendance chart | `profiles`, `coaching_members`, `coaching_member_status`, `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_training_attendance`, `coaching_alerts` | admin_master, coach, assistant | "Atleta não encontrado" | N/A | 30-day attendance sparkline; alert severity colors |
| `/crm/at-risk` | Athletes with active alerts | Click to navigate to CRM detail | `coaching_alerts`, `profiles`, `coaching_member_status`, `coaching_athlete_tags` | admin_master, coach, assistant | "Nenhum atleta em risco" | N/A | Card layout; shows up to 2 alerts per card |

---

### Module 6: Risk & Alerts

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/risk` | Alert management — high/medium risk athletes | Resolve alerts (RiskActions client component) | `coaching_alerts`, `profiles`, `coaching_member_status` | admin_master, coach | Empty state per section | Error block | Split into High Risk / Medium Risk sections; KPI: resolved in 30d |

---

### Module 7: Announcements & Communication

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/announcements` | Bulletin board — list announcements with read rates | Create announcement (via client component, admin/coach) | `coaching_announcements`, `coaching_announcement_reads`, `coaching_members`, `profiles` | admin_master, coach, assistant | "Nenhum aviso publicado" | Error block | KPIs: total, avg read rate, this week |
| `/announcements/[id]` | View single announcement + read stats | Edit link (staff only) | `coaching_announcements`, `coaching_announcement_reads`, `profiles`, `coaching_members` | admin_master, coach, assistant | "Aviso não encontrado" | N/A | Shows who read it and when |
| `/announcements/[id]/edit` | Edit announcement title/body/pin | Form to update announcement | `coaching_announcements` | admin_master, coach | "Aviso não encontrado" | N/A | Redirects assistants away |
| `/communications` | Communication overview — paginated announcements | Pagination (Prev/Next); link to `/announcements` | `coaching_announcements`, `coaching_announcement_reads`, `coaching_members`, `profiles` | admin_master, coach | "Nenhum aviso ainda" | N/A | KPIs: total published, avg read %, pinned count, this week |

---

### Module 8: Workouts & Training

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/workouts` | Workout templates list | View only | `coaching_workout_templates`, `coaching_workout_blocks` | admin_master, coach | "Nenhum template criado" | Error block | Shows block count per template |
| `/workouts/analytics` | Workout analytics — completion rates | View KPIs | `coaching_workout_templates`, `coaching_workout_assignments`, `coaching_workout_executions` | admin_master, coach | Illustrated empty state "Sem dados de treinos" | Error block with message | Active templates, monthly assignments, completion %, avg duration |
| `/workouts/assignments` | Workout assignments list | Date filter; pagination | `coaching_workout_assignments`, `profiles`, `coaching_workout_templates` | admin_master, coach | "Nenhuma atribuição encontrada" | Error block | Status: Planned/Completed/Missed |
| `/executions` | Workout execution log | Date range filter | `coaching_workout_executions`, `coaching_workout_assignments`, `coaching_workout_templates`, `profiles` | admin_master, coach, assistant | "Nenhuma execução registrada" | Error block | Shows duration, distance, pace, HR, calories, source |
| `/delivery` | Workout delivery batches for Treinus | Create batch (admin/coach); generate items; publish items; copy payload | `workout_delivery_batches`, `workout_delivery_items`, `profiles` | admin_master, coach | "Nenhum item de entrega encontrado" | Error block | Batch lifecycle: draft → publishing → published → closed; per-item publish |

---

### Module 9: Integrations

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/trainingpeaks` | TrainingPeaks sync status | View linked athletes and sync status | `fn_tp_sync_status` (RPC), `coaching_device_links` | admin_master, coach | "Nenhum atleta vinculou" / "Nenhum treino sincronizado" | Feature-gated: shows "indisponível" if flag off | Feature flag: `trainingpeaks_enabled` |

---

### Module 10: Economy — Custody & Token System

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/custody` | Custody account dashboard — deposits, withdrawals, ledger | Deposit button; link to Swap | `custody_accounts`, `custody_deposits`, `custody_withdrawals`, `fn_sum_coin_ledger_by_group` (RPC), `clearing_settlements` | admin_master | N/A (shows 0 values) | N/A | Invariant badges (Total = Reserved + Available); blocked account warning; tabbed ledger view |
| `/clearing` | Interclub clearing settlements | Filter by tab (receivables/payables) via ClearingFilters client component | `clearing_settlements`, `clearing_events`, `coaching_groups` | admin_master, coach | N/A (shows 0 values) | N/A | KPIs: A Receber, A Pagar, Recebido, Pago, Fees, Avg SLA |
| `/swap` | B2B collateral swap marketplace | Create swap order; accept open offers (SwapActions) | `swap_orders`, `platform_fee_config`, `custody_accounts`, `coaching_groups` | admin_master | "Nenhuma oferta disponivel" | N/A | Shows open offers from other groups; order history; fee rate display |
| `/fx` | Foreign exchange operations (USD ↔ BRL) | Withdraw button; FX simulator tool | `custody_deposits`, `custody_withdrawals`, `platform_fee_config`, `custody_accounts` | admin_master | "Nenhuma operacao registrada" | N/A | Shows spread, provider fees; FX policy section; simulator |
| `/audit` | Clearing audit trail — burn → breakdown → settlements | View only | `clearing_events`, `clearing_settlements`, `coaching_groups` | admin_master, coach | "Nenhum burn registrado" | N/A | Drill-down: each burn shows issuer breakdown + settlements with status |
| `/distributions` | OmniCoin distribution history to athletes | View only (distributing done from `/athletes`) | `coaching_members`, `coaching_token_inventory`, `coin_ledger`, `profiles` | admin_master, coach | "Nenhuma distribuição realizada" with link to Athletes | N/A | Shows who distributed, when, how many coins; KPIs: balance, total distributed, last 30d |
| `/badges` | Championship badge inventory & purchase | Buy badge packages (admin only) | `coaching_badge_inventory`, `billing_products` (type=badges), `billing_customers` | admin_master, coach | "Nenhum pacote disponível" | N/A | Non-admins see "contact admin" message |

---

### Module 11: Credits & Billing (Legacy)

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/credits` | Buy credit packages | Buy button per product (admin only) | `coaching_token_inventory`, `billing_products`, `billing_customers` | admin_master (middleware) | N/A | N/A | **LEGACY** — redirects to `/custody` if `legacy_billing_enabled` flag is off |
| `/billing` | Purchase history & invoices | Link to buy credits | `billing_purchases` | admin_master (middleware) | "Nenhuma compra registrada" | N/A | **LEGACY** — same flag gate; shows status breakdown, receipts |
| `/billing/success` | Checkout success confirmation | Links to Credits / Dashboard | None | admin_master | N/A | N/A | Tracks `billing_checkout_returned` event |
| `/billing/cancelled` | Checkout cancellation page | Links to Retry / Dashboard | None | admin_master | N/A | N/A | Tracks `billing_checkout_returned` event |

---

### Module 12: Financial Management

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/financial` | Financial dashboard — revenue, subscribers, growth | Export Ledger CSV; links to Subscriptions & Plans | `coaching_financial_ledger`, `coaching_subscriptions` | admin_master, coach | N/A (shows 0 values) | Error block | Month-over-month growth % |
| `/financial/subscriptions` | Subscription management | Status filter tabs (All/Active/Late/Paused/Cancelled) | `coaching_subscriptions`, `coaching_plans`, `profiles` | admin_master, coach | "Nenhuma assinatura encontrada" | Error block | Shows athlete, plan, status, next due, last payment |
| `/financial/plans` | Coaching plan configuration | View only | `coaching_plans`, `coaching_subscriptions` | admin_master, coach | "Nenhum plano criado" | Error block | Shows price, billing cycle, workout limits, subscriber count |

---

### Module 13: Exports

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/exports` | Central export hub for all CSV exports | Date range pickers + download buttons for 5 modules | API routes: `/api/export/{engagement,attendance,crm,announcements,alerts}` | admin_master, coach | N/A | N/A | Client component; exports: Engagement, Attendance, CRM, Announcements, Alerts |

---

### Module 14: Settings & Configuration

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/settings` | Group settings: billing, team, branding | Gateway selector (MercadoPago/Stripe); Stripe portal; auto-topup config; branding (logo/colors); invite member; remove member | `coaching_members`, `billing_auto_topup_settings`, `billing_products`, `billing_customers`, `platform_fee_config`, `custody_accounts`, `portal_branding` | admin_master (billing/branding/invite); all staff (view team) | "Nenhum membro de staff" | N/A | Shows platform fees; custody status; team list with role badges |

---

### Module 15: Platform Admin (Super-admin)

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/platform` | Platform dashboard — global KPIs | Quick links to all platform modules | `coaching_groups`, `coaching_members`, `athlete_verification`, `billing_purchases`, `support_tickets`, `billing_refund_requests`, `sessions` | platform_admin | N/A | N/A | Alerts for pending approvals & refunds; revenue trends; recent groups |
| `/platform/assessorias` | Manage all assessorias | Approve/reject/suspend groups (AssessoriaActions) | `coaching_groups`, `profiles`, `coaching_members` | platform_admin | N/A | N/A | Shows approval status, member count, coach name |
| `/platform/produtos` | Manage billing products | Create/edit/toggle products (ProductForm) | `billing_products` | platform_admin | N/A | N/A | Active/Inactive sections; sort order |
| `/platform/conquistas` | Manage achievement badges | Create new badge (BadgeForm) | `badges`, `badge_awards` | platform_admin | N/A | Error logged | By category; tier labels (Bronze→Diamond) |
| `/platform/fees` | Configure platform fee rates | Edit fee % per type (FeeRow inline edit) | `platform_fee_config` | platform_admin | N/A | N/A | Fee types: Clearing, Swap, Maintenance |
| `/platform/support` | Support ticket list | Filter by status; link to ticket detail | `support_tickets`, `coaching_groups`, `support_messages` | platform_admin | N/A | N/A | Shows ticket count, group name |
| `/platform/support/[id]` | Support ticket chat | Reply to ticket (TicketChat) | `support_tickets`, `support_messages`, `coaching_groups` | platform_admin | N/A | Redirect if not found | Real-time chat interface |
| `/platform/financeiro` | All-platform purchase history | Filter by status/period (week/month) | `billing_purchases`, `coaching_groups` | platform_admin | N/A | N/A | KPIs: total revenue, month revenue, pending; per-group breakdown |
| `/platform/reembolsos` | Refund request management | Approve/reject refunds (RefundActions) | `billing_refund_requests`, `billing_purchases`, `coaching_groups` | platform_admin | N/A | N/A | Status filter; review notes |
| `/platform/feature-flags` | Feature flag management | Toggle flags on/off; adjust rollout % (FeatureFlagRow) | `feature_flags` | platform_admin | "Nenhuma feature flag cadastrada" | N/A | Key, enabled status, rollout % |
| `/platform/invariants` | System invariant checker | View violations | `custody_accounts`, `coin_ledger` (via service client) | platform_admin | N/A | N/A | Checks: committed >= 0, deposited >= committed, coin supply matches |
| `/platform/liga` | League/Championship admin | Manage seasons (LeagueAdmin client component) | `league_seasons`, `league_enrollments`, `league_snapshots`, `coaching_groups` | platform_admin | N/A | N/A | Rankings, scores, enrollment management |

---

### Module 16: Public Pages (No Auth Required)

| Route | Purpose | Actions | Data Sources | Access | Empty State | Error State | Notes |
|-------|---------|---------|--------------|--------|-------------|-------------|-------|
| `/challenge/[id]` | Challenge deep-link landing | Open in app; download from stores | None (static) | Public | N/A | N/A | Deep link: `omnirunner://challenge/{id}`; OG metadata |
| `/invite/[code]` | Invite deep-link landing | Open in app; download from stores | None (static) | Public | N/A | N/A | Deep link: `omnirunner://invite/{code}`; OG metadata |

---

### API Routes (36 total)

#### Authentication
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/auth/callback` | GET | OAuth callback handler |
| `/api/health` | GET | Health check |

#### Exports (CSV)
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/export/athletes` | GET | Export athletes CSV |
| `/api/export/crm` | GET | Export CRM data CSV |
| `/api/export/engagement` | GET | Export engagement KPIs CSV |
| `/api/export/attendance` | GET | Export attendance CSV |
| `/api/export/announcements` | GET | Export announcements CSV |
| `/api/export/alerts` | GET | Export alerts CSV |
| `/api/export/financial` | GET | Export financial ledger CSV |

#### Economy Operations
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/clearing` | POST | Trigger clearing operation |
| `/api/swap` | POST | Create/accept swap order |
| `/api/custody` | POST | Custody deposit operation |
| `/api/custody/withdraw` | POST | Custody withdrawal |
| `/api/custody/webhook` | POST | Payment provider webhook for custody |
| `/api/distribute-coins` | POST | Distribute OmniCoins to athlete |
| `/api/auto-topup` | POST | Trigger auto top-up |

#### Billing & Payments
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/checkout` | POST | Create checkout session |
| `/api/billing-portal` | POST | Create Stripe billing portal session |
| `/api/gateway-preference` | POST | Set preferred payment gateway |

#### Team Management
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/team/invite` | POST | Invite staff member |
| `/api/team/remove` | POST | Remove staff member |

#### Announcements
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/announcements` | POST | Create announcement |
| `/api/announcements/[id]` | PATCH/DELETE | Update/delete announcement |

#### CRM
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/crm/tags` | POST | Manage athlete tags |
| `/api/crm/notes` | POST | Add athlete notes |

#### Verification
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/verification/evaluate` | POST | Trigger re-evaluation |

#### Branding
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/branding` | POST | Update portal branding |

#### Platform Admin
| Route | Method | Purpose |
|-------|--------|---------|
| `/api/platform/products` | POST/PATCH | Manage billing products |
| `/api/platform/fees` | PATCH | Update fee configuration |
| `/api/platform/feature-flags` | PATCH | Toggle feature flags |
| `/api/platform/support` | POST | Reply to support ticket |
| `/api/platform/invariants` | GET | Check system invariants |
| `/api/platform/invariants/enforce` | POST | Enforce/fix invariant violations |
| `/api/platform/liga` | POST | Manage league seasons |
| `/api/platform/assessorias` | POST | Approve/reject/suspend groups |
| `/api/platform/refunds` | POST | Process refund requests |

---

### Cross-Cutting Observations

#### Consistent Patterns
- **All data pages** use `force-dynamic` export for SSR
- **KPI cards** use a consistent `StatBlock` or local `KpiCard` component
- **Tables** use consistent styling: `rounded-xl border`, hover states, status badges
- **Error handling**: Most pages wrap data fetch in try/catch with a red error banner
- **Empty states**: Most pages have explicit empty-state messages
- **Date formatting**: Uses shared `formatDateISO`, `formatDateTime`, `formatKm` utilities

#### Loading States
- Loading pages exist for: announcements (detail, edit), attendance (list, detail), audit, badges, billing (success, cancelled), clearing, communications, CRM (detail, at-risk), custody, engagement, executions, exports, financial (plans, subscriptions), fx, swap, workouts (analytics, assignments)
- These are Suspense-based skeleton loaders

#### Access Control Gaps to Verify
1. `/distributions` — sidebar says admin_master + coach, but no middleware enforcement beyond portal layout
2. `/custody`, `/swap`, `/fx` — sidebar restricts to admin_master only; middleware doesn't explicitly block coaches (relies on sidebar hiding)
3. Many pages check `role` via cookie but the cookie is verified in middleware, so this is defense-in-depth

#### Feature Flags in Use
- `trainingpeaks_enabled` — gates `/trainingpeaks` page and sidebar link
- `legacy_billing_enabled` — gates `/credits` and `/billing` pages (redirect to `/custody`)

#### Supabase Client Types Used
- `createClient()` — user-scoped, respects RLS
- `createServiceClient()` — service role, bypasses RLS (used for cross-user queries)
- `createAdminClient()` — admin role, platform pages only

#### Portal Branding
- Custom logo, colors (primary, sidebar bg, sidebar text, accent) per group
- Stored in `portal_branding` table, applied via CSS variables in layout

---

*End of Part B — Portal*

---

## Part C — Cross-Product Summary

### Counts

| Metric | Value |
|--------|-------|
| **Total app screens** | 104 |
| **Total portal pages** | 55 page files |
| **Total portal API routes** | 36 |

### Shared Data (Tables & RPCs used by both app and portal)

**Tables:**
- `profiles`
- `sessions`
- `coaching_groups`
- `coaching_members`
- `coaching_join_requests`
- `challenge_participants`
- `support_tickets`
- `support_messages`
- `announcements` (app) / `coaching_announcements` (portal — may be same or schema alias)
- `badge_awards`
- `badge_definitions` (app) / `badges` (portal — platform admin)
- `training_sessions` (app) / `coaching_training_sessions` (portal)
- `training_attendance` (app) / `coaching_training_attendance` (portal)
- `workout_templates` (app) / `coaching_workout_templates` (portal)
- `workout_assignments` (app) / `coaching_workout_assignments` (portal)
- `clearing_cases` (app) / `clearing_settlements`, `clearing_events` (portal)
- `token_intents` (app) / `coaching_token_inventory`, `coin_ledger` (portal)
- `championship_templates`
- `championship_invites`
- `challenge_invites`
- `coaching_group_credits` (app) — overlaps with custody/token concepts in portal

**RPCs:**
- No exact overlap; app uses `fn_search_coaching_groups`, `fn_approve_join`, etc.; portal uses `fn_athlete_session_stats`, `fn_tp_sync_status`, `fn_sum_coin_ledger_by_group`. Both touch `coaching_members` and related entities.

**Views:**
- `v_user_progression` (app)
- `athlete_verification` (portal — table or view)

### Gaps — App-only (not in portal)

| Area | Capabilities |
|------|--------------|
| **Running & GPS** | Run tracking, RunSummaryScreen, RunDetailsScreen, RunReplayScreen, MapScreen, session polyline, pace splits |
| **Athlete social** | FriendsScreen, FriendProfileScreen, FriendsActivityFeedScreen, InviteFriendsScreen, friendships |
| **Challenges (athlete)** | Create challenge, matchmaking, challenge join (deep link), challenge result, rematch |
| **Progress & gamification** | ProgressionScreen (XP/level), MissionsScreen, LeaderboardsScreen, StreaksLeaderboardScreen, LeagueScreen (view), PersonalEvolutionScreen, RunningDnaScreen, WrappedScreen |
| **Assessoria feed** | AssessoriaFeedScreen (run completions, badges earned, challenges won) |
| **QR operations (mobile)** | StaffQrHubScreen, StaffGenerateQrScreen, StaffScanQrScreen, AthleteCheckinQrScreen, token burn/activate QR |
| **Onboarding** | WelcomeScreen, OnboardingRoleScreen, JoinAssessoriaScreen, StaffSetupScreen, OnboardingTourScreen, HowItWorksScreen, RecoveryScreen |
| **Session export (athlete)** | ExportScreen (GPX/TCX/FIT/CSV) |
| **Strava** | Strava OAuth connect/disconnect |
| **Device linking** | AthleteDeviceLinkScreen (Garmin, Apple, Polar, Suunto, TrainingPeaks) |
| **Events (athlete)** | EventsScreen, EventDetailsScreen, GroupEventsScreen, RaceEventDetailsScreen (RSVP, join/leave) |
| **Park detection** | Park check-in, park-based matchmaking |
| **Push notifications** | Challenge events, friend requests, streaks, championships |

### Gaps — Portal-only (not in app)

| Area | Capabilities |
|------|--------------|
| **Economy & custody** | Custody dashboard, deposits, withdrawals, ledger; `/custody`, `/swap`, `/fx` |
| **Clearing** | Interclub clearing settlements; receivables/payables; `/clearing`, `/audit` |
| **Billing & subscriptions** | Credits purchase (legacy), billing portal, purchase history; coaching plans, subscriptions; `/credits`, `/billing`, `/financial`, `/financial/subscriptions`, `/financial/plans` |
| **Platform admin** | Super-admin: assessorias approval, products, badges, fees, support tickets, invariants, league admin, refunds, feature flags; `/platform/*` |
| **Exports (staff)** | Central export hub; CSV exports for engagement, attendance, CRM, announcements, alerts; `/exports` |
| **Risk & alerts** | Dedicated risk page; resolve alerts; high/medium risk sections; `/risk` |
| **Attendance analytics** | Advanced attendance analytics; per-athlete breakdown; `/attendance-analytics` |
| **Workout delivery** | Treinus batch lifecycle; create batch, generate items, publish; `/delivery` |
| **Settings & configuration** | Gateway selector (MercadoPago/Stripe), auto-topup, portal branding, team invite/remove; `/settings` |
| **Distributions** | OmniCoin distribution history; `/distributions` |
| **Badge purchase** | Buy badge packages (admin); `/badges` |
| **Multi-group select** | `/select-group` when user has 2+ assessorias |
| **Public deep-link pages** | `/challenge/[id]`, `/invite/[code]` (web landing for app deep links) |

---

*End of USERZERO_02 — Capabilities Map*
