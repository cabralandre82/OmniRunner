# Disaster Dependency Map — Omni Runner Monorepo

> Generated: 2026-03-04 | Scope: Full repository scan  
> Purpose: Exhaustive dependency map for disaster simulation and SRE planning  
> Repo root: `/home/usuario/project-running`

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [App Mobile (Flutter)](#2-app-mobile-flutter)
3. [Portal (Next.js)](#3-portal-nextjs)
4. [Supabase Backend — Database](#4-supabase-backend--database)
5. [Edge Functions (57 total)](#5-edge-functions-57-total)
6. [External Integrations](#6-external-integrations)
7. [Mission-Critical Flows — Full Chain Traces](#7-mission-critical-flows--full-chain-traces)
8. [Failure Impact Matrix](#8-failure-impact-matrix)
9. [Cascading Failure Chains](#9-cascading-failure-chains)

---

## 1. Architecture Overview

```
┌─────────────┐    ┌──────────────┐    ┌─────────────────────────┐
│ Flutter App  │───▶│  Supabase    │◀───│  Portal (Next.js)       │
│ (iOS/Android)│    │  PostgREST   │    │  SSR + RSC              │
│              │    │  + Auth      │    │  server/client/admin/svc │
└──────┬───────┘    └──────┬───────┘    └───────────┬─────────────┘
       │                   │                        │
       │            ┌──────▼───────┐                │
       └───────────▶│ 57 Edge Fns  │◀───────────────┘
                    │ (Deno Deploy) │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌─────────┐ ┌──────────┐
        │  Strava  │ │MercadoPago│ │  Stripe  │
        │  API     │ │  API     │ │  API     │
        └──────────┘ └─────────┘ └──────────┘
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        ┌──────────┐ ┌─────────┐ ┌──────────┐
        │  FCM     │ │Training │ │  Sentry  │
        │  (Push)  │ │ Peaks   │ │ (Errors) │
        └──────────┘ └─────────┘ └──────────┘
```

**Backend modes (Flutter)**: `AppConfig.backendMode` — `mock` (no Supabase), `local` (local Supabase), `integrated` (production Supabase)

**Supabase client modes (Portal)**:
- `server.ts` — SSR with user JWT via cookies (respects RLS)
- `client.ts` — Browser client with user JWT (respects RLS)
- `admin.ts` — `service_role` key, bypasses RLS, 15s timeout
- `service.ts` — `service_role` key, bypasses RLS, 15s timeout, no session persistence

---

## 2. App Mobile (Flutter)

### 2.1 All Screens (100 total)

#### Auth & Onboarding
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `auth_gate.dart` | Auth routing, session check | `auth.getUser()` | **YES** |
| `login_screen.dart` | Email/password + OAuth (Google, Apple, Facebook) | `auth.signIn*`, `profiles` | **YES** |
| `welcome_screen.dart` | Landing for unauthenticated users | None | No |
| `onboarding_tour_screen.dart` | First-use tutorial | None (local) | No |
| `onboarding_role_screen.dart` | Role selection post-signup | `profiles` UPDATE | No |

#### Running Core
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `home_screen.dart` | Main tab hub, navigation root | Multiple (sessions, profile_progress) | **YES** |
| `today_screen.dart` | Daily summary, streak, goals | `sessions`, `profile_progress`, `wallets`, `weekly_goals` | **YES** |
| `map_screen.dart` | Live run tracking (GPS) | Offline-first (Isar), syncs via `sessions` | **YES** |
| `run_summary_screen.dart` | Post-run summary + share | `sessions`, `verify-session` EF, `calculate-progression` EF, `evaluate-badges` EF | **YES** |
| `run_details_screen.dart` | Historical run detail view | `sessions`, `session-points` storage | No |
| `run_replay_screen.dart` | GPS replay animation | `session-points` storage | No |
| `recovery_screen.dart` | Crash recovery of active session | Isar local DB | **YES** |
| `history_screen.dart` | Past sessions list | `sessions` | No |

#### Challenges & Gamification
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `challenges_list_screen.dart` | Active/past challenges | `challenges`, `challenge_participants` | **YES** |
| `challenge_details_screen.dart` | Single challenge view | `challenges`, `challenge_participants`, `challenge_results` | **YES** |
| `challenge_create_screen.dart` | Create new challenge | `challenge-create` EF, `wallets`, `coin_ledger` | **YES** |
| `challenge_join_screen.dart` | Join a challenge | `challenge-join` EF, `wallets`, `coin_ledger` | **YES** |
| `challenge_invite_screen.dart` | Invite friends to challenge | `challenge-invite-group` EF | No |
| `challenge_result_screen.dart` | Final results display | `challenge_results`, `coin_ledger` | No |
| `leaderboards_screen.dart` | Global/assessoria ranking | `compute-leaderboard` EF, `leaderboard_snapshots` | No |
| `streaks_leaderboard_screen.dart` | Streak rankings | `leaderboard_snapshots` | No |

#### Wallet & Financial
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `wallet_screen.dart` | Balance, ledger history | `wallets`, `coin_ledger` | **YES** |

#### Profile & Progression
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `profile_screen.dart` | User profile, avatar, settings | `profiles`, `delete-account` EF | **YES** |
| `progression_screen.dart` | XP, level, season progress | `profile_progress`, `xp_transactions`, `season_progress` | No |
| `badges_screen.dart` | Badge collection | `badges`, `badge_awards` | No |
| `missions_screen.dart` | Daily/weekly missions | `missions`, `mission_progress` | No |
| `progress_hub_screen.dart` | Progression overview hub | `profile_progress` | No |
| `personal_evolution_screen.dart` | Performance trends | `athlete_trends`, `athlete_baselines` | No |
| `running_dna_screen.dart` | 6-axis radar profile | `generate-running-dna` EF | No |
| `wrapped_screen.dart` | Period retrospective | `generate-wrapped` EF | No |
| `diagnostics_screen.dart` | App diagnostics/debug | Local only | No |

#### Coaching / Assessoria
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `coaching_groups_screen.dart` | List coaching groups | `coaching_groups`, `coaching_members` | No |
| `coaching_group_details_screen.dart` | Group detail + members | `coaching_groups`, `coaching_members` | No |
| `my_assessoria_screen.dart` | Athlete's own assessoria | `coaching_groups`, `coaching_members`, `switch_assessoria` RPC | No |
| `join_assessoria_screen.dart` | Join an assessoria | `fn_search_coaching_groups` RPC | No |
| `partner_assessorias_screen.dart` | Partnership listings | `coaching_groups` | No |
| `invite_qr_screen.dart` | QR code for invite | `invite_codes` | No |
| `invite_friends_screen.dart` | Share invite link | Deep links | No |
| `coach_insights_screen.dart` | Coach analytics | `coach_insights` (Isar) | No |
| `matchmaking_screen.dart` | Find running partners | `matchmake` EF | No |

#### Social
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `friends_screen.dart` | Friends list | `friendships` | No |
| `friend_profile_screen.dart` | Friend's profile | `profiles`, `sessions` | No |
| `friends_activity_feed_screen.dart` | Friends' recent runs | `fn_friends_activity_feed` RPC | No |
| `groups_screen.dart` | Social running groups | `groups`, `group_members` | No |
| `group_details_screen.dart` | Group detail | `groups`, `group_members` | No |
| `group_members_screen.dart` | Group member list | `group_members` | No |
| `group_rankings_screen.dart` | Group leaderboard | `leaderboard_snapshots` | No |
| `group_evolution_screen.dart` | Group trends | `athlete_trends` | No |
| `group_events_screen.dart` | Group events | `events` | No |

#### Championships & League
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `athlete_championships_screen.dart` | Active championships | `championships`, `championship_participants` | No |
| `athlete_championship_ranking_screen.dart` | Championship leaderboard | `championship_participants` | No |
| `league_screen.dart` | League standings | `league-list` EF, `league_snapshots` | No |

#### Events & Races
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `events_screen.dart` | Upcoming events | `events` | No |
| `event_details_screen.dart` | Event detail | `events`, `event_registrations` | No |
| `race_event_details_screen.dart` | Race event + results | `race_events`, `race_results` | No |

#### Staff Screens (coach/admin_master role)
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `staff_dashboard_screen.dart` | KPI dashboard | `v_kpi_dashboard`, `sessions`, `profiles` | **YES** |
| `staff_crm_list_screen.dart` | CRM athlete list | `coaching_members`, `coaching_tags`, `coaching_notes`, `member_status` | No |
| `staff_athlete_profile_screen.dart` | Athlete detail (staff) | `profiles`, `sessions`, `wallets`, `coaching_tags`, `coaching_notes` | No |
| `staff_generate_qr_screen.dart` | Generate token QR | `token-create-intent` EF | **YES** |
| `staff_qr_hub_screen.dart` | QR management hub | `token_intents` | **YES** |
| `staff_scan_qr_screen.dart` | Scan athlete QR | `token-consume-intent` EF | **YES** |
| `staff_credits_screen.dart` | Credit management | `coaching_token_inventory`, `coin_ledger` | **YES** |
| `staff_workout_builder_screen.dart` | Build workout templates | `workout_templates`, `workout_blocks` | **YES** |
| `staff_workout_assign_screen.dart` | Assign workouts | `workout_assignments` | **YES** |
| `staff_disputes_screen.dart` | Challenge disputes | `clearing_cases`, `clearing_case_events` | No |
| `staff_challenge_invites_screen.dart` | Challenge management | `challenges`, `challenge_participants` | No |
| `staff_championship_manage_screen.dart` | Championship CRUD | `championships` | No |
| `staff_championship_templates_screen.dart` | Championship templates | `championship_templates` | No |
| `staff_championship_invites_screen.dart` | Championship invitations | `champ-invite` EF | No |
| `staff_performance_screen.dart` | Performance analytics | `sessions`, aggregate views | No |
| `staff_retention_dashboard_screen.dart` | Retention metrics | `v_kpi_retention` | No |
| `staff_weekly_report_screen.dart` | Weekly summary | Aggregate queries | No |
| `staff_setup_screen.dart` | Assessoria setup | `coaching_groups` | No |
| `staff_join_requests_screen.dart` | Manage join requests | `coaching_join_requests` | No |
| `staff_workout_templates_screen.dart` | Workout template list | `workout_templates` | No |

#### Training & Attendance
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `staff_training_list_screen.dart` | Training session list | `training_sessions` | No |
| `staff_training_detail_screen.dart` | Training detail + attendance | `training_sessions`, `training_attendance` | No |
| `staff_training_create_screen.dart` | Create training session | `training_sessions` INSERT | No |
| `staff_training_scan_screen.dart` | Scan check-in QR | `training_attendance` | No |
| `athlete_training_list_screen.dart` | Athlete's training schedule | `training_sessions` | No |
| `athlete_checkin_qr_screen.dart` | Athlete check-in QR | `training_attendance` | No |
| `athlete_attendance_screen.dart` | Attendance history | `training_attendance` | No |

#### Athlete Data Screens
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `athlete_dashboard_screen.dart` | Athlete overview | Multiple tables | No |
| `athlete_delivery_screen.dart` | Workout delivery | `workout_assignments`, `workout_delivery_batches` | **YES** |
| `athlete_workout_day_screen.dart` | Daily workout plan | `workout_assignments`, `workout_blocks` | **YES** |
| `athlete_log_execution_screen.dart` | Log workout execution | `workout_executions` INSERT | No |
| `athlete_device_link_screen.dart` | Link wearable device | `device_links` | No |
| `athlete_evolution_screen.dart` | Performance evolution | `athlete_trends`, `athlete_baselines` | No |
| `athlete_my_evolution_screen.dart` | Personal evolution chart | `athlete_trends` | No |
| `athlete_my_status_screen.dart` | Verification status | `athlete_verification` | No |
| `athlete_verification_screen.dart` | Verification checklist | `eval-athlete-verification` EF | **YES** |

#### Announcements & Support
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `announcement_feed_screen.dart` | Assessoria announcements | `announcements`, `announcement_reads` | No |
| `announcement_detail_screen.dart` | Single announcement | `announcements` | No |
| `announcement_create_screen.dart` | Create announcement (staff) | `announcements` INSERT | No |
| `assessoria_feed_screen.dart` | Assessoria activity feed | `fn_assessoria_feed` RPC | No |
| `support_screen.dart` | Support ticket list | `support_tickets` | No |
| `support_ticket_screen.dart` | Single support ticket | `support_tickets`, `support_messages` | No |

#### Settings & Integrations
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `settings_screen.dart` | App settings | `profiles`, `coach_settings` | No |
| `more_screen.dart` | Additional options menu | Navigation only | No |

#### Features (separate modules)
| Screen | Purpose | Supabase Dependency | Mission Critical |
|--------|---------|-------------------|-----------------|
| `export_screen.dart` | Export to FIT/TCX/GPX | Local only (file export) | No |
| `ble_heart_rate_source.dart` | BLE HR monitor | BLE hardware | No |
| `park_screen.dart` | Park activities | `parks`, `park_activities` | No |
| `my_parks_screen.dart` | Personal park history | `park_activities` | No |

### 2.2 Navigation Graph

```
AuthGate
  ├─▶ WelcomeScreen (unauthenticated)
  │     └─▶ LoginScreen ─▶ AuthGate (loop)
  │
  └─▶ HomeScreen (authenticated)
        ├── TodayScreen (tab)
        │     ├─▶ MapScreen (start run) ─▶ RunSummaryScreen ─▶ ChallengeResultScreen
        │     ├─▶ AthleteWorkoutDayScreen
        │     └─▶ ProgressionScreen
        │
        ├── ChallengesListScreen (tab)
        │     ├─▶ ChallengeDetailsScreen
        │     ├─▶ ChallengeCreateScreen
        │     ├─▶ ChallengeJoinScreen
        │     └─▶ ChallengeInviteScreen
        │
        ├── LeaderboardsScreen (tab)
        │     ├─▶ GroupRankingsScreen
        │     └─▶ StreaksLeaderboardScreen
        │
        ├── MoreScreen (tab)
        │     ├─▶ ProfileScreen ─▶ SettingsScreen
        │     ├─▶ WalletScreen
        │     ├─▶ BadgesScreen
        │     ├─▶ MissionsScreen
        │     ├─▶ FriendsScreen ─▶ FriendProfileScreen
        │     ├─▶ GroupsScreen ─▶ GroupDetailsScreen
        │     ├─▶ CoachingGroupsScreen ─▶ CoachingGroupDetailsScreen
        │     ├─▶ MyAssessoriaScreen
        │     ├─▶ AthleteChampionshipsScreen
        │     ├─▶ LeagueScreen
        │     ├─▶ EventsScreen ─▶ EventDetailsScreen
        │     ├─▶ RunningDnaScreen
        │     ├─▶ WrappedScreen
        │     ├─▶ SupportScreen ─▶ SupportTicketScreen
        │     └─▶ DiagnosticsScreen
        │
        └── Staff sub-graph (role-gated)
              ├─▶ StaffDashboardScreen
              ├─▶ StaffCrmListScreen ─▶ StaffAthleteProfileScreen
              ├─▶ StaffQrHubScreen ─▶ StaffGenerateQrScreen / StaffScanQrScreen
              ├─▶ StaffWorkoutBuilderScreen / StaffWorkoutAssignScreen
              ├─▶ StaffTrainingListScreen ─▶ StaffTrainingDetailScreen
              ├─▶ StaffCreditsScreen
              ├─▶ StaffChampionshipManageScreen
              └─▶ StaffDisputesScreen
```

### 2.3 Feature Flags & Modes

**Feature Flag Service** (`FeatureFlagService`):
- Backed by `feature_flags` table (key, enabled, rollout_pct)
- Loaded at startup, cached in-memory
- Deterministic per-user bucket (`userId:flagKey` hash mod 100)
- Known flags checked server-side: `trainingpeaks_enabled`
- Risk: stale cache if flag toggled mid-operation (m13 risk)

**Backend Modes** (`AppConfig`):
- `isSupabaseConfigured` — env vars present
- `isSupabaseReady` — `Supabase.initialize()` succeeded
- Fallbacks: `MockAuthDataSource`, `MockProfileDataSource`, `StubTokenIntentRepo`, `StubSwitchAssessoriaRepo`

### 2.4 DI Container Map (GetIt)

**Auth Module**: DeepLinkHandler → IAuthDataSource → AuthRepository → UserIdentityProvider → FeatureFlagService → IProfileRepo

**Data Module**: SharedPreferences → CacheMetadataStore → MembershipCache → OfflineQueue → ConnectivityMonitor → IsarDatabaseProvider → Isar → All Isar repos → All Supabase repos → All use cases

**Presentation Module**: All BLoCs → All remote sources

---

## 3. Portal (Next.js)

### 3.1 Supabase Client Variants

| Client | File | Key Type | RLS | Use |
|--------|------|----------|-----|-----|
| `server.ts` | `createClient()` | anon + user cookie JWT | Yes | SSR pages |
| `client.ts` | `createClient()` | anon + browser JWT | Yes | Client components |
| `admin.ts` | `createAdminClient()` | `service_role` | **NO** | Admin operations |
| `service.ts` | `createServiceClient()` | `service_role` | **NO** | Server actions |

### 3.2 Middleware Auth Flow

1. Public routes: `/login`, `/no-access`, `/api/auth/callback`, `/api/health`, `/challenge/*`, `/invite/*`
2. Auth-only prefixes: `/platform`, `/api/platform/` — requires user + `platform_role = 'admin'`
3. Portal routes: requires user + `coaching_members` with role `admin_master|coach|assistant`
4. Multi-group users redirected to `/select-group`
5. Cookies: `portal_group_id`, `portal_role` (httpOnly, 8h TTL, re-verified per request)
6. Admin-only routes: `/credits/*`, `/billing`, `/settings` — requires `admin_master`

### 3.3 All Portal Pages

#### Dashboard & Overview
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Dashboard | `/dashboard` | KPI overview, charts | `sessions`, `profiles`, `coaching_members`, aggregate views | user JWT | **YES** |

#### Financial & Billing (Mission Critical)
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Custody | `/custody` | Deposit/commit/settle cycle | `custody_accounts`, `custody_transactions`, `custody_settlements` | user JWT | **YES** |
| Clearing | `/clearing` | Inter-group prize compensation | `clearing_cases`, `clearing_case_items`, `clearing_weeks`, `clearing_case_events` | user JWT | **YES** |
| Swap | `/swap` | Backing asset swap | `custody_accounts`, `coaching_token_inventory` | user JWT | **YES** |
| FX | `/fx` | Currency conversion | `custody_accounts`, withdrawal RPCs | user JWT | **YES** |
| Credits | `/credits` | Buy/manage OmniCoins | `billing_products`, `create-checkout-*` EF | user JWT | **YES** |
| Billing | `/billing` | Purchase history | `billing_purchases`, `billing_events` | user JWT (admin_master) | **YES** |
| Billing Success | `/billing/success` | Post-checkout callback | `billing_purchases` | user JWT | **YES** |
| Billing Cancelled | `/billing/cancelled` | Cancelled checkout | None | user JWT | No |
| Financial | `/financial` | Financial overview | `billing_purchases`, `coaching_token_inventory` | user JWT | **YES** |
| Financial Plans | `/financial/plans` | Credit plans | `billing_products` | user JWT | No |
| Financial Subscriptions | `/financial/subscriptions` | Subscription management | `coaching_subscriptions` | user JWT | No |
| Distributions | `/distributions` | Token distribution history | `coin_ledger`, `token_intents` | user JWT | No |

#### Athlete Management
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Athletes | `/athletes` | Athlete roster | `coaching_members`, `profiles`, `wallets` | user JWT | No |
| CRM | `/crm` | CRM list with tags | `coaching_members`, `coaching_tags`, `coaching_notes`, `member_status` | user JWT | No |
| CRM Detail | `/crm/[userId]` | Single athlete CRM | `profiles`, `coaching_tags`, `coaching_notes`, `sessions` | user JWT | No |
| CRM At-Risk | `/crm/at-risk` | At-risk athletes | `member_status`, `sessions` (inactivity) | user JWT | No |
| Verification | `/verification` | Athlete verification status | `athlete_verification` | user JWT | No |
| Engagement | `/engagement` | Engagement metrics | `sessions`, `challenge_participants`, `profile_progress` | user JWT | No |
| Risk | `/risk` | Risk alerts | `member_status`, activity analysis | user JWT | No |

#### Attendance & Training
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Attendance | `/attendance` | Attendance records | `training_attendance`, `training_sessions` | user JWT | No |
| Attendance Detail | `/attendance/[id]` | Single session attendance | `training_attendance` | user JWT | No |
| Attendance Analytics | `/attendance-analytics` | Attendance trends | Aggregate views | user JWT | No |

#### Workouts
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Workouts | `/workouts` | Workout templates | `workout_templates`, `workout_blocks` | user JWT | **YES** |
| Workout Assignments | `/workouts/assignments` | Assignment management | `workout_assignments` | user JWT | **YES** |
| Workout Analytics | `/workouts/analytics` | Workout adherence | `workout_executions`, aggregate views | user JWT | No |
| Delivery | `/delivery` | Workout delivery batches | `workout_delivery_batches`, `workout_assignments` | user JWT | **YES** |
| Executions | `/executions` | Execution log | `workout_executions` | user JWT | No |
| TrainingPeaks | `/trainingpeaks` | TP integration (feature-flagged) | `trainingpeaks-sync` EF | user JWT | No |

#### Communication
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Announcements | `/announcements` | Announcement board | `announcements`, `announcement_reads` | user JWT | No |
| Announcement Detail | `/announcements/[id]` | Single announcement | `announcements` | user JWT | No |
| Announcement Edit | `/announcements/[id]/edit` | Edit announcement | `announcements` UPDATE | user JWT | No |
| Communications | `/communications` | Push notification mgmt | `send-push` EF, `device_tokens` | user JWT | No |

#### Badges & Gamification
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Badges | `/badges` | Badge catalog management | `badges`, `badge_awards` | user JWT | No |

#### Audit & Export
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Audit | `/audit` | Audit trail | `portal_audit_log` | user JWT | No |
| Exports | `/exports` | Data export | Various aggregate queries | user JWT | No |

#### Settings
| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Settings | `/settings` | Group settings, branding, auto-topup, gateway selection | `coaching_groups`, `portal_branding`, `auto_topup_settings`, `billing_gateway_config` | user JWT (admin_master) | **YES** |

### 3.4 Platform Admin Pages (platform_role = 'admin')

| Page | Path | Purpose | Tables/RPCs | Auth | Critical |
|------|------|---------|-------------|------|----------|
| Assessorias | `/platform/assessorias` | Manage all coaching groups | `coaching_groups` (service_role) | platform admin | **YES** |
| Produtos | `/platform/produtos` | Product catalog | `billing_products` (service_role) | platform admin | **YES** |
| Fees | `/platform/fees` | Fee configuration | `platform_fees` (service_role) | platform admin | **YES** |
| Conquistas | `/platform/conquistas` | Badge management | `badges` (service_role) | platform admin | No |
| Feature Flags | `/platform/feature-flags` | Feature flag admin | `feature_flags` (service_role) | platform admin | **YES** |
| Invariants | `/platform/invariants` | System invariant checks | Multiple tables (service_role) | platform admin | No |
| Liga | `/platform/liga` | League management | `league_*` tables | platform admin | No |
| Financeiro | `/platform/financeiro` | Platform financials | Aggregate queries | platform admin | No |
| Reembolsos | `/platform/reembolsos` | Refund management | `billing_refund_requests` | platform admin | **YES** |
| Support | `/platform/support` | Support ticket admin | `support_tickets`, `support_messages` | platform admin | No |
| Support Detail | `/platform/support/[id]` | Ticket detail + chat | `support_tickets`, `support_messages` | platform admin | No |

---

## 4. Supabase Backend — Database

### 4.1 All Tables with RLS Status

#### Core User Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `profiles` | Yes — read all, update own | `auth.users(id)` ON DELETE CASCADE | **YES** |
| `sessions` | Yes — own read/insert/update | `auth.users(id)` ON DELETE CASCADE | **YES** |
| `wallets` | Yes — own read | `auth.users(id)` ON DELETE CASCADE | **YES** |
| `coin_ledger` | Yes — own read | `auth.users(id)` ON DELETE CASCADE | **YES** |
| `profile_progress` | Yes — read all, own read | `auth.users(id)` ON DELETE CASCADE | **YES** |
| `xp_transactions` | Yes — own read | `auth.users(id)` ON DELETE CASCADE | No |

#### Gamification Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `seasons` | Yes — read all | None | No |
| `badges` | Yes — read all | `seasons(id)` | No |
| `badge_awards` | Yes — own+public read | `auth.users(id)` CASCADE, `badges(id)`, `sessions(id)` | No |
| `season_progress` | Yes — own read | `auth.users(id)` CASCADE, `seasons(id)` | No |
| `missions` | Yes — read all | `seasons(id)` | No |
| `mission_progress` | Yes — own read | `auth.users(id)` CASCADE, `missions(id)` | No |
| `weekly_goals` | Yes — own read | `auth.users(id)` CASCADE | No |

#### Challenge Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `challenges` | Yes — participant read | `auth.users(id)` (creator) | **YES** |
| `challenge_participants` | Yes — own + co-participant read | `challenges(id)` CASCADE, `auth.users(id)` | **YES** |
| `challenge_results` | Yes — participant read | `challenges(id)`, `auth.users(id)` | **YES** |

#### Coaching / Assessoria Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `coaching_groups` | Yes — member read | None | **YES** |
| `coaching_members` | Yes — member read | `coaching_groups(id)` CASCADE, `auth.users(id)` CASCADE | **YES** |
| `coaching_invites` | Yes — target user read | `coaching_groups(id)` CASCADE | No |
| `coaching_join_requests` | Yes — staff + requester read | `coaching_groups(id)` CASCADE | No |
| `coaching_token_inventory` | Yes — staff read | `coaching_groups(id)` | **YES** |
| `coaching_badge_inventory` | Yes — staff read | `coaching_groups(id)` | No |
| `coaching_tags` | Yes — staff read/write | `coaching_groups(id)` CASCADE | No |
| `coaching_notes` | Yes — staff read/write | `coaching_members` | No |
| `member_status` | Yes — staff read/write | `coaching_members` | No |
| `coach_settings` | Yes — own read/write | `auth.users(id)` CASCADE | No |

#### Social Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `friendships` | Yes — participant read | `auth.users(id)` CASCADE (both) | No |
| `groups` | Yes — public+member read | None | No |
| `group_members` | Yes — member read | `groups(id)` CASCADE, `auth.users(id)` CASCADE | No |
| `group_goals` | Yes — member read | `groups(id)` CASCADE | No |

#### Billing Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `billing_products` | Yes — read all | None | **YES** |
| `billing_purchases` | Yes — group staff read | `billing_products(id)`, `coaching_groups(id)` | **YES** |
| `billing_events` | Yes — group staff read | `billing_purchases(id)` CASCADE | **YES** |
| `billing_customers` | Yes — staff read | `coaching_groups(id)` | No |
| `billing_refund_requests` | Yes — requester/admin read | `billing_purchases(id)` | No |
| `auto_topup_settings` | Yes — admin_master read | `coaching_groups(id)` | No |

#### Custody & Clearing Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `custody_accounts` | Yes — group staff read | `coaching_groups(id)` | **YES** |
| `custody_transactions` | Yes — staff read | `custody_accounts(id)` | **YES** |
| `custody_settlements` | Yes — staff read | `custody_accounts(id)` | **YES** |
| `clearing_weeks` | Yes — staff read | None | **YES** |
| `clearing_cases` | Yes — involved group staff read | `clearing_weeks(id)` | **YES** |
| `clearing_case_items` | Yes — case-linked read | `clearing_cases(id)` CASCADE | **YES** |
| `clearing_case_events` | Yes — case-linked read | `clearing_cases(id)` CASCADE | No |
| `clearing_settlements` | Yes — staff read | `clearing_cases(id)` | **YES** |

#### Championship Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `championships` | Yes — participant/host staff read | `coaching_groups(id)` | No |
| `championship_participants` | Yes — participant read | `championships(id)` CASCADE | No |
| `championship_templates` | Yes — staff read | `coaching_groups(id)` | No |

#### Token Intent Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `token_intents` | Yes — staff read | `coaching_groups(id)` | **YES** |
| `invite_codes` | Yes — staff read | `coaching_groups(id)` | No |

#### Strava Integration Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `strava_connections` | Yes — own read | `auth.users(id)` CASCADE | No |
| `strava_event_queue` | No (service_role only) | None | No |

#### Training / Attendance Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `training_sessions` | Yes — group member read | `coaching_groups(id)` | No |
| `training_attendance` | Yes — member read | `training_sessions(id)` CASCADE | No |

#### Workout Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `workout_templates` | Yes — staff read | `coaching_groups(id)` | **YES** |
| `workout_blocks` | Yes — template-linked read | `workout_templates(id)` CASCADE | **YES** |
| `workout_assignments` | Yes — assignee/staff read | `workout_templates(id)`, `coaching_members` | **YES** |
| `workout_delivery_batches` | Yes — staff read | `coaching_groups(id)` | **YES** |
| `workout_executions` | Yes — athlete + staff read | `workout_assignments` | No |

#### Financial Engine Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `coaching_subscriptions` | Yes — member read | `coaching_groups(id)` | No |
| `coaching_plans` | Yes — read all | `coaching_groups(id)` | No |

#### Announcement Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `announcements` | Yes — group member read | `coaching_groups(id)` CASCADE | No |
| `announcement_reads` | Yes — own read | `announcements(id)` CASCADE | No |

#### Analytics & Observation Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `product_events` | Yes — own insert | `auth.users(id)` | No |
| `portal_audit_log` | Yes — staff read | `coaching_groups(id)` | No |
| `device_tokens` | Yes — own read/write | `auth.users(id)` CASCADE | No |
| `notification_log` | No (service_role only) | None | No |
| `api_rate_limits` | No (service_role only) | None | No |

#### Athlete Verification Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `athlete_verification` | Yes — own + staff read | `auth.users(id)` CASCADE | **YES** |

#### Leaderboard Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `leaderboard_snapshots` | Yes — read all | `auth.users(id)` | No |

#### League Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `league_snapshots` | Yes — read all | `coaching_groups(id)` | No |
| `league_tiers` | Yes — read all | None | No |

#### Misc Tables
| Table | RLS | FK Cascade | Critical |
|-------|-----|-----------|----------|
| `feature_flags` | Yes — read all | None | **YES** |
| `parks` | Yes — read all | None | No |
| `park_activities` | Yes — own read | `parks(id)`, `auth.users(id)` | No |
| `support_tickets` | Yes — own + staff read | `auth.users(id)` | No |
| `support_messages` | Yes — ticket-linked read | `support_tickets(id)` CASCADE | No |
| `user_wrapped` | Yes — own read | `auth.users(id)` | No |
| `running_dna` | Yes — own read | `auth.users(id)` | No |
| `portal_branding` | Yes — staff read | `coaching_groups(id)` | No |
| `device_links` | Yes — own read | `auth.users(id)` | No |
| `billing_gateway_config` | Yes — admin read | `coaching_groups(id)` | No |

### 4.2 Critical SECURITY DEFINER RPCs

| RPC | Tables Touched | Purpose |
|-----|---------------|---------|
| `handle_new_user()` | `profiles` INSERT | Trigger on `auth.users` INSERT |
| `fn_fulfill_purchase(p_purchase_id)` | `billing_purchases` (FOR UPDATE), `coaching_token_inventory`, `coin_ledger` | Atomic billing fulfillment |
| `fn_credit_institution(p_group_id, p_delta, p_reason)` | `coaching_token_inventory`, `coin_ledger` | Credit/debit group inventory |
| `fn_increment_wallets_batch(p_entries)` | `wallets` UPDATE, `coin_ledger` INSERT | Batch wallet credit |
| `increment_wallet_balance(p_user_id, p_delta)` | `wallets` UPDATE | Single wallet credit |
| `increment_profile_progress(p_user_id, p_xp, p_distance_m, p_moving_ms)` | `profile_progress` UPDATE | XP/distance increment |
| `fn_mark_progression_applied(p_session_id)` | `sessions` UPDATE | Idempotency guard |
| `reconcile_all_wallets()` | `wallets`, `coin_ledger` | Drift detection/correction |
| `eval_athlete_verification(p_user_id)` | `athlete_verification`, `sessions` | Verification status calc |
| `recalculate_profile_progress(p_user_id)` | `profile_progress`, `sessions` | Full recalculation |
| `evaluate_badges_retroactive(p_user_id)` | `badge_awards`, `badges`, `sessions` | Retroactive badge check |
| `check_daily_token_usage(p_group_id, p_type)` | `token_intents` | Daily limit enforcement |
| `settle_clearing(p_settlement_id)` | `clearing_settlements`, `custody_accounts`, `custody_transactions` | Clearing settlement |
| `aggregate_clearing_window(p_window_start, p_window_end)` | `clearing_settlements` | Netting aggregation |
| `fn_switch_assessoria(p_user_id, p_new_group_id)` | `coaching_members` | Move athlete between groups |
| `fn_search_coaching_groups(p_query)` | `coaching_groups` | Search groups |
| `fn_friends_activity_feed(p_user_id, p_limit)` | `friendships`, `sessions`, `profiles` | Friends feed |
| `fn_assessoria_feed(p_group_id, p_limit)` | `coaching_members`, `sessions`, `profiles` | Group feed |
| `compute_leaderboard_global(...)` | `sessions`, `leaderboard_snapshots` | Global leaderboard |
| `compute_leaderboard_assessoria(...)` | `sessions`, `coaching_members`, `leaderboard_snapshots` | Group leaderboard |
| `compute_leaderboard_championship(...)` | `championship_participants`, `sessions`, `leaderboard_snapshots` | Championship leaderboard |
| `fn_remove_member(p_group_id, p_user_id)` | `coaching_members` DELETE | Remove member from group |

### 4.3 Triggers

| Trigger | On Table | Function | Purpose |
|---------|----------|----------|---------|
| `on_auth_user_created` | `auth.users` (INSERT) | `handle_new_user()` | Auto-create profile |

### 4.4 Critical Foreign Key Cascade Chains

**User deletion cascade** (`auth.users` DELETE):
```
auth.users
  ├──▶ profiles (CASCADE)
  ├──▶ sessions (CASCADE)
  │      └──▶ badge_awards.trigger_session_id (SET NULL)
  ├──▶ wallets (CASCADE)
  ├──▶ coin_ledger (CASCADE)
  ├──▶ profile_progress (CASCADE)
  ├──▶ xp_transactions (CASCADE)
  ├──▶ badge_awards (CASCADE)
  ├──▶ coaching_members (CASCADE)
  ├──▶ friendships (CASCADE, both columns)
  ├──▶ group_members (CASCADE)
  ├──▶ strava_connections (CASCADE)
  ├──▶ device_tokens (CASCADE)
  ├──▶ athlete_verification (CASCADE)
  └──▶ device_links (CASCADE)
```

**Coaching group deletion cascade** (`coaching_groups` DELETE):
```
coaching_groups
  ├──▶ coaching_members (CASCADE)
  ├──▶ coaching_invites (CASCADE)
  ├──▶ coaching_join_requests (CASCADE)
  ├──▶ training_sessions (CASCADE)
  │      └──▶ training_attendance (CASCADE)
  ├──▶ announcements (CASCADE)
  │      └──▶ announcement_reads (CASCADE)
  └──▶ workout_templates (CASCADE)
         └──▶ workout_blocks (CASCADE)
```

**Challenge deletion cascade** (`challenges` DELETE):
```
challenges
  └──▶ challenge_participants (CASCADE)
```

### 4.5 Critical UNIQUE Constraints

| Table | Constraint | Impact |
|-------|-----------|--------|
| `badge_awards` | `(user_id, badge_id)` | Prevents duplicate badge awards |
| `challenge_participants` | `(challenge_id, user_id)` | Prevents double-join |
| `challenge_results` | `(challenge_id, user_id)` | Prevents double-settle |
| `friendships` | `(user_id_a, user_id_b)` | Prevents duplicate friendships |
| `group_members` | `(group_id, user_id)` | Prevents duplicate group membership |
| `coaching_members` | `(group_id, user_id)` implied | Prevents duplicate coaching membership |
| `billing_events` | partial on `stripe_event_id` | Stripe webhook idempotency (L1) |
| `strava_event_queue` | `(owner_id, object_id, aspect_type)` | Strava webhook dedup |
| `wallets` | PK `user_id` | One wallet per user |
| `profile_progress` | PK `user_id` | One progress record per user |

---

## 5. Edge Functions (57 total)

### 5.1 Function Catalog

#### Authentication & User Management
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `validate-social-login` | requireUser | `profiles` | None | Social login broken |
| `complete-social-profile` | requireUser | `profiles` | None | Profile incomplete after OAuth |
| `set-user-role` | requireUser | `profiles`, `coaching_members` | None | Role assignment fails |
| `delete-account` | requireUser + adminDb | `coaching_members`, `challenge_participants`, `profiles`, `strava_connections`, `auth.users` | None | Account deletion stuck |

#### Session & Verification
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `verify-session` | requireUser | `sessions` UPDATE | None | Sessions not verified, blocks challenges |
| `submit-analytics` | requireUser | `product_events` | None | Analytics gap (non-critical) |
| `eval-athlete-verification` | requireUser | `athlete_verification`, `sessions` | None | Verification status stale |
| `eval-verification-cron` | service_key | `athlete_verification`, `sessions` | None | Periodic re-eval missed |

#### Progression & Gamification
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `calculate-progression` | requireUser | `sessions`, `profile_progress`, `xp_transactions`, `weekly_goals` | None | XP not awarded, streaks not updated |
| `evaluate-badges` | requireUser | `sessions`, `badges`, `badge_awards`, `xp_transactions`, `coin_ledger`, `wallets`, `profile_progress` | FCM (via notify-rules) | Badges not unlocked |
| `generate-running-dna` | requireUser | `sessions`, `running_dna` | None | DNA profile unavailable |
| `generate-wrapped` | requireUser | `sessions`, `user_wrapped` | None | Wrapped unavailable |

#### Challenge Lifecycle
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `challenge-create` | requireUser | `challenges`, `challenge_participants`, `coin_ledger`, `wallets` | None | Cannot create challenges |
| `challenge-join` | requireUser | `challenges`, `challenge_participants`, `coin_ledger`, `wallets` | None | Cannot join challenges |
| `challenge-get` | requireUser | `challenges`, `challenge_participants` | None | Cannot view challenge |
| `challenge-list-mine` | requireUser | `challenges`, `challenge_participants` | None | Challenge list empty |
| `challenge-invite-group` | requireUser | `challenges`, `coaching_members` | FCM (via notify-rules) | Cannot invite to challenges |
| `challenge-accept-group-invite` | requireUser | `challenge_participants`, `coin_ledger`, `wallets` | None | Cannot accept invites |
| `settle-challenge` | requireUser | `challenges`, `challenge_participants`, `challenge_results`, `coin_ledger`, `wallets`, `athlete_verification` | FCM (via notify-rules) | **Challenges never settle, coins stuck** |

#### Championship Lifecycle
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `champ-create` | requireUser | `championships`, `championship_participants` | None | Cannot create championships |
| `champ-enroll` | requireUser | `championship_participants` | None | Cannot enroll |
| `champ-invite` | requireUser | `championship_participants`, `coaching_members` | None | Cannot invite |
| `champ-accept-invite` | requireUser | `championship_participants` | None | Cannot accept |
| `champ-open` | requireUser | `championships` UPDATE | None | Cannot open championship |
| `champ-cancel` | requireUser | `championships` UPDATE | None | Cannot cancel |
| `champ-list` | requireUser | `championships`, `championship_participants` | None | List empty |
| `champ-participant-list` | requireUser | `championship_participants` | None | Participant list empty |
| `champ-lifecycle` | service_key | `championships`, `championship_participants` | `settle-challenge` EF | Championship transitions stuck |
| `champ-update-progress` | requireUser | `championship_participants` | None | Progress not tracked |
| `champ-activate-badge` | requireUser | `championship_participants`, `coaching_badge_inventory` | None | Badge activation fails |

#### Billing & Payments
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `create-checkout-session` | requireUser | `billing_purchases`, `billing_events`, `billing_products`, `coaching_members` | **Stripe API** | **Cannot purchase credits** |
| `create-checkout-mercadopago` | requireUser | `billing_purchases`, `billing_events`, `billing_products`, `coaching_members` | **MercadoPago API** | **Cannot purchase credits (BR)** |
| `webhook-payments` | webhook signature (Stripe) | `billing_purchases`, `billing_events`, `coaching_token_inventory`, `coin_ledger` | None | **Payments not fulfilled** |
| `webhook-mercadopago` | webhook signature (MP) | `billing_purchases`, `billing_events`, `coaching_token_inventory`, `coin_ledger` | **MercadoPago API** (payment fetch) | **Payments not fulfilled (BR)** |
| `list-purchases` | requireUser | `billing_purchases` | None | Purchase history unavailable |
| `process-refund` | requireUser | `billing_refund_requests`, `billing_purchases` | Stripe/MP API | Refunds delayed |
| `create-portal-session` | requireUser | `billing_customers` | Stripe API | Customer portal unavailable |
| `auto-topup-check` | service_key | `auto_topup_settings`, `coaching_token_inventory`, `billing_purchases` | Stripe/MP API | Auto-topup missed |
| `auto-topup-cron` | service_key | `auto_topup_settings` | `auto-topup-check` EF | Auto-topup not triggered |

#### Clearing & Custody
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `clearing-cron` | service_key | `clearing_weeks`, `clearing_cases`, `clearing_case_items`, `clearing_case_events`, `coin_ledger`, `challenges`, `challenge_participants`, `clearing_settlements`, `custody_accounts` | None | **Clearing cases not created, prizes stuck** |
| `clearing-confirm-sent` | requireUser | `clearing_cases`, `clearing_case_events` | None | Cannot confirm send |
| `clearing-confirm-received` | requireUser | `clearing_cases`, `clearing_case_events`, `custody_accounts` | None | Cannot confirm receipt |
| `clearing-open-dispute` | requireUser | `clearing_cases`, `clearing_case_events` | None | Cannot dispute |

#### Token Intents (QR Operations)
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `token-create-intent` | requireUser | `token_intents`, `coaching_members`, `coaching_token_inventory`, `coaching_badge_inventory` | None | **Cannot issue/burn tokens via QR** |
| `token-consume-intent` | requireUser | `token_intents`, `wallets`, `coin_ledger`, `coaching_token_inventory` | None | **Cannot redeem tokens via QR** |

#### Leaderboard & League
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `compute-leaderboard` | requireUser | `leaderboard_snapshots`, `sessions`, `coaching_members`, `championship_participants` | None | Leaderboards stale |
| `league-list` | requireUser | `league_snapshots`, `league_tiers` | None | League list empty |
| `league-snapshot` | service_key | `league_snapshots`, `coaching_groups` | None | League rankings stale |

#### Strava Integration
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `strava-webhook` | webhook (verify_token) | `strava_event_queue` | None | **Strava activities not queued** |
| `strava-register-webhook` | requireUser | `strava_connections` | **Strava API** | Cannot register webhook |

#### TrainingPeaks Integration
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `trainingpeaks-oauth` | requireUser | `trainingpeaks_connections` | **TrainingPeaks API** | Cannot connect TP |
| `trainingpeaks-sync` | requireUser | `workout_templates`, `workout_blocks`, `trainingpeaks_connections` | **TrainingPeaks API** | Workout sync to TP fails |

#### Notifications
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `send-push` | service_key | `device_tokens` | **FCM HTTP v1 API** | **All push notifications fail** |
| `notify-rules` | service_key | `challenges`, `challenge_participants`, `profiles`, `friendships`, `championships`, `notification_log`, `device_tokens` | `send-push` EF → FCM | Smart notifications not sent |

#### Cron / Lifecycle
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `lifecycle-cron` | service_key | `championships`, `championship_participants`, `challenges` | `settle-challenge` EF, `notify-rules` EF, `league-snapshot` EF | **All lifecycle transitions stop** |
| `reconcile-wallets-cron` | service_key | `wallets`, `coin_ledger` | None | Wallet drift undetected |

#### Social & Matchmaking
| Function | Auth Mode | Tables Touched | External APIs | Failure Impact |
|----------|-----------|---------------|---------------|----------------|
| `matchmake` | verify_jwt (gateway) | `profiles`, `sessions`, `coaching_members` | None | Matchmaking unavailable |

### 5.2 Shared Dependencies (_shared/)

| Module | Used By | Purpose |
|--------|---------|---------|
| `auth.ts` | 40+ EFs | `requireUser()` — JWT validation, user/admin DB clients |
| `cors.ts` | All EFs | CORS headers, origin allowlist |
| `http.ts` | All EFs | `jsonOk()`, `jsonErr()` — standardized responses |
| `obs.ts` | All EFs | `startTimer()`, `logRequest()`, `logError()` — observability |
| `rate_limit.ts` | 30+ EFs | `checkRateLimit()` — per-user per-function rate limiting |
| `validate.ts` | 30+ EFs | `requireJson()`, `requireFields()` — input validation |
| `errors.ts` | 20+ EFs | `classifyError()` — DB error classification |
| `logger.ts` | 10+ EFs | `log()` — structured logging |
| `integrity_flags.ts` | `verify-session`, `strava-webhook` | Anti-cheat flag constants |
| `retry.ts` | Select EFs | Retry with exponential backoff |

---

## 6. External Integrations

### 6.1 Strava (Webhook + OAuth)

**OAuth Flow**:
- App: `StravaAuthRepositoryImpl` → `https://www.strava.com/oauth/authorize` → callback via `omnirunner://localhost/exchange_token?code=XXX`
- DeepLinkHandler parses `StravaCallbackAction` → token exchange → stored in `strava_connections`

**Webhook Pipeline**:
1. Strava sends POST to `strava-webhook` EF
2. EF validates `hub.verify_token` (GET) or enqueues event to `strava_event_queue` (POST)
3. Queue processor calls `processStravaEvent()`:
   - Looks up `strava_connections` by `strava_athlete_id`
   - Refreshes token if expired (`https://www.strava.com/oauth/token`)
   - Fetches activity detail (`/api/v3/activities/{id}`)
   - Fetches GPS streams (`/api/v3/activities/{id}/streams`)
   - Runs anti-cheat checks (speed, teleport, cadence, GPS gaps)
   - Creates `sessions` record with `source='strava'`
   - Links to active challenges via `challenge_participants` update
   - Triggers `eval_athlete_verification`, `recalculate_profile_progress`, `evaluate_badges_retroactive`
   - Detects and links parks

**Env Vars**: `STRAVA_VERIFY_TOKEN`, `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`

**Failure Impact**: Strava activities not imported → challenges not updated → leaderboards stale

### 6.2 MercadoPago (Webhook + Checkout)

**Checkout Flow**:
1. Portal → `create-checkout-mercadopago` EF → creates `billing_purchases` (pending) → creates MP Preference → returns `init_point` URL
2. User pays on MercadoPago hosted checkout
3. MP sends IPN to `webhook-mercadopago` EF

**Webhook Processing**:
1. HMAC signature verification (`MERCADOPAGO_WEBHOOK_SECRET`)
2. Fetch payment from `https://api.mercadopago.com/v1/payments/{id}`
3. Routes by `mpStatus`:
   - `approved` → UPDATE `billing_purchases` (pending→paid) → RPC `fn_fulfill_purchase` → credits `coaching_token_inventory`
   - `cancelled/rejected/expired` → UPDATE `billing_purchases` (pending→cancelled)
   - `refunded` → clawback credits via `fn_credit_institution(delta=-amount)`

**Idempotency**: L1 (dedup via `billing_events`), L2 (conditional UPDATE WHERE status='pending'), L3 (fn_fulfill_purchase checks status='paid' with FOR UPDATE lock)

**Env Vars**: `MERCADOPAGO_ACCESS_TOKEN`, `MERCADOPAGO_WEBHOOK_SECRET`

**Failure Impact**: Credits not fulfilled → assessorias cannot operate → token issuance blocked

### 6.3 Stripe (Webhook + Checkout)

**Checkout Flow**: Same pattern as MP but via `create-checkout-session` EF → Stripe Checkout Session

**Webhook Processing** (`webhook-payments` EF):
1. Stripe signature verification (`stripe.webhooks.constructEvent`)
2. Events handled: `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired`, `charge.refunded`, `charge.dispute.created`
3. Same fulfillment pipeline: pending → paid → `fn_fulfill_purchase` → fulfilled

**Env Vars**: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`

**Failure Impact**: Same as MercadoPago — credits not fulfilled

### 6.4 FCM (Push Notifications)

**Architecture**:
1. `send-push` EF receives `{ user_ids, title, body, data }`
2. Fetches `device_tokens` for target users
3. Gets FCM OAuth2 access token from Firebase service account (RS256 JWT → Google OAuth)
4. Sends to `https://fcm.googleapis.com/v1/projects/{id}/messages:send`
5. Handles stale tokens (NOT_FOUND/UNREGISTERED → delete from `device_tokens`)
6. Concurrency cap: 10 parallel sends, batch size 500, 50s deadline

**Callers**: `notify-rules` EF → `send-push` EF (fire-and-forget from `evaluate-badges`, `settle-challenge`, `lifecycle-cron`)

**Env Vars**: `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT` (base64)

**Failure Impact**: No push notifications → reduced engagement, missed challenge deadlines not alerted

### 6.5 TrainingPeaks (Frozen/Feature-Flagged)

**OAuth**: `trainingpeaks-oauth` EF → `https://oauth.trainingpeaks.com/oauth/authorize` → token stored in `trainingpeaks_connections`

**Sync**: `trainingpeaks-sync` EF → reads `workout_templates` + `workout_blocks` → maps to TP structured workout → POST to `https://api.trainingpeaks.com/v1/workouts`

**Status**: Feature-flagged via `trainingpeaks_enabled` flag. Hidden in sidebar when disabled.

**Env Vars**: `TRAININGPEAKS_CLIENT_ID`, `TRAININGPEAKS_CLIENT_SECRET`

**Failure Impact**: Workout sync to TrainingPeaks fails (low impact — feature-flagged)

---

## 7. Mission-Critical Flows — Full Chain Traces

### 7.1 Authentication

#### Sign-Up (Email)
```
LoginScreen → Supabase.auth.signUp(email, password)
  → auth.users INSERT
  → TRIGGER on_auth_user_created → handle_new_user() → profiles INSERT
  → auth.email.confirm → confirm token
  → AuthGate → HomeScreen
```

#### Sign-In (Email)
```
LoginScreen → Supabase.auth.signInWithPassword(email, password)
  → JWT issued → stored in client
  → AuthGate checks auth.getUser() → HomeScreen
```

#### OAuth (Google/Apple/Facebook)
```
LoginScreen → Supabase.auth.signInWithOAuth(provider)
  → redirect to provider
  → callback: omnirunner://auth-callback#access_token=...
  → DeepLinkHandler → AuthCallbackAction
  → supabase_flutter auto-handles token exchange
  → TRIGGER handle_new_user() (if new)
  → complete-social-profile EF (optional)
  → AuthGate → HomeScreen
```

#### Password Reset
```
LoginScreen → Supabase.auth.resetPasswordForEmail(email)
  → email sent with reset link
  → user clicks → supabase auth handles → new password set
```

### 7.2 Workout Creation → Assignment → Delivery → Publish → Confirmation

```
[Staff Portal]
  1. StaffWorkoutBuilderScreen / Portal /workouts
     → INSERT workout_templates (name, group_id, type)
     → INSERT workout_blocks[] (order_index, block_type, duration, distance, pace, hr_zone, notes)

  2. StaffWorkoutAssignScreen / Portal /workouts/assignments
     → INSERT workout_assignments (template_id, user_id, scheduled_date, status='pending')
     → For batch: INSERT workout_delivery_batches (group_id, template_id, scheduled_date)
                 → bulk INSERT workout_assignments for all group members

  3. Portal /delivery page
     → UPDATE workout_delivery_batches SET status='published'
     → UPDATE workout_assignments SET status='published' WHERE batch_id=...
     → notify-rules EF (rule: 'workout_published') → send-push EF → FCM

[Athlete App]
  4. AthleteDeliveryScreen → fetches workout_assignments WHERE user_id=me AND status='published'
  5. AthleteWorkoutDayScreen → fetches workout_blocks via template_id
  6. AthleteLogExecutionScreen → INSERT workout_executions (assignment_id, session_id, compliance_score)
     → UPDATE workout_assignments SET status='completed'
```

### 7.3 Challenge Lifecycle

```
[Create]
  1. ChallengeCreateScreen → challenge-create EF
     → INSERT challenges (type, goal, target, window_ms, entry_fee_coins)
     → INSERT challenge_participants (creator, status='accepted')
     → IF entry_fee_coins > 0:
         INSERT coin_ledger (delta=-fee, reason='challenge_entry_fee')
         UPDATE wallets SET balance_coins -= fee

[Join]
  2. ChallengeJoinScreen → challenge-join EF
     → INSERT challenge_participants (status='accepted')
     → IF entry_fee_coins > 0:
         INSERT coin_ledger (delta=-fee, reason='challenge_entry_fee')
         UPDATE wallets SET balance_coins -= fee
     → IF start_mode='on_accept' AND min_participants met:
         UPDATE challenges SET status='active', starts_at_ms, ends_at_ms

[Active — Run Submission]
  3. RunSummaryScreen → PostSessionChallengeDispatcher (client)
     → SubmitRunToChallenge → UPDATE challenge_participants SET progress_value, contributing_session_ids
  3b. Strava webhook → processStravaEvent → linkSessionToChallenges
     → UPDATE challenge_participants SET progress_value, contributing_session_ids

[Settle]
  4. lifecycle-cron EF (every 5 min) → finds challenges WHERE status='active' AND ends_at_ms <= now
     → calls settle-challenge EF for each:
       a. Atomic claim: UPDATE challenges SET status='completing' WHERE status IN ('active','completing')
       b. Fetch challenge_participants WHERE status='accepted'
       c. Sort by progress_value (goal-dependent: lower or higher is better)
       d. Dense ranking
       e. Determine outcomes (won/lost/tied/did_not_finish)
       f. Verification check: unverified players forfeit pool winnings
       g. Stake cap guard: total_coins_out <= 10,000
       h. INSERT challenge_results (upsert on challenge_id,user_id)
       i. INSERT coin_ledger entries for winners
       j. RPC fn_increment_wallets_batch → UPDATE wallets
       k. UPDATE challenges SET status='completed'
       l. notify-rules EF → send-push EF → FCM

[Wallet Credit]
  5. Winner's wallet balance visible in WalletScreen
     → coin_ledger shows reason='challenge_one_vs_one_won' or 'challenge_group_completed'
```

### 7.4 Championship Lifecycle

```
[Create]
  1. StaffChampionshipManageScreen → champ-create EF
     → INSERT championships (host_group_id, name, metric, start_at, end_at, status='draft')

[Invite & Enroll]
  2. champ-invite EF → INSERT championship_participants (status='invited')
  3. champ-accept-invite EF → UPDATE championship_participants SET status='enrolled'
  4. champ-enroll EF → direct enrollment

[Open]
  5. champ-open EF → UPDATE championships SET status='open'

[Activate] (via lifecycle-cron)
  6. lifecycle-cron → WHERE status='open' AND start_at <= now
     → UPDATE championship_participants SET status='active'
     → UPDATE championships SET status='active'

[Progress Update]
  7. champ-update-progress EF → UPDATE championship_participants SET progress_value

[Complete] (via lifecycle-cron)
  8. lifecycle-cron → WHERE status='active' AND end_at <= now
     → Rank participants by progress_value
     → UPDATE championship_participants SET final_rank, status='completed'
     → UPDATE championships SET status='completed'
```

### 7.5 Billing (Purchase → Checkout → Payment → Fulfillment → Credit)

```
[Initiate — Stripe]
  1. Portal /credits → BuyButton → create-checkout-session EF
     → Verify admin_master role
     → Fetch billing_products
     → INSERT billing_purchases (status='pending')
     → INSERT billing_events (event_type='created')
     → Stripe.checkout.sessions.create()
     → Return checkout_url → redirect to Stripe

[Payment — Stripe]
  2. User pays on Stripe hosted checkout
  3. Stripe sends webhook → webhook-payments EF
     → Verify Stripe signature
     → checkout.session.completed:
       a. UPDATE billing_purchases SET status='paid' WHERE status='pending' (L2)
       b. INSERT billing_events (dedup via stripe_event_id) (L1)
       c. RPC fn_fulfill_purchase (L3: FOR UPDATE lock):
          → UPDATE billing_purchases SET status='fulfilled'
          → UPDATE coaching_token_inventory SET available_tokens += credits_amount
          → INSERT coin_ledger audit trail

[Initiate — MercadoPago]
  1. Portal /credits → BuyButton → create-checkout-mercadopago EF
     → Same flow as Stripe but creates MP Preference
     → Return init_point URL → redirect to MercadoPago

[Payment — MercadoPago]
  2. User pays on MP hosted checkout
  3. MP sends IPN → webhook-mercadopago EF
     → HMAC signature verification
     → Fetch payment from MP API
     → approved: same fulfillment pipeline as Stripe

[Refund]
  4. charge.refunded → INSERT billing_events (refunded)
     → IF status='fulfilled': clawback via fn_credit_institution(delta=-credits)
     → UPDATE billing_purchases SET status='refunded'
```

### 7.6 Custody (Deposit → Commit → Settle)

```
[Deposit]
  1. Portal /custody → DepositButton
     → Billing purchase flow → credits arrive in coaching_token_inventory
     → INSERT custody_transactions (type='deposit')
     → UPDATE custody_accounts SET balance += amount

[Commit]
  2. Token issuance via QR (token-create-intent → token-consume-intent)
     → INSERT custody_transactions (type='commit')
     → UPDATE custody_accounts SET committed += amount, available -= amount

[Settle]
  3. clearing-cron EF → aggregate_clearing_window RPC → settle_clearing RPC
     → UPDATE custody_accounts (debit losing group, credit winning group)
     → INSERT custody_transactions (type='settlement')
     → UPDATE clearing_settlements SET status='settled'
```

### 7.7 Clearing (Prize Pending → Case Creation → Sent → Received)

```
[Prize Pending]
  1. settle-challenge EF → INSERT coin_ledger (reason='challenge_prize_pending', delta > 0)

[Case Creation] (via clearing-cron, daily 02:00 UTC)
  2. clearing-cron EF:
     a. Create/find clearing_weeks (ISO week, Monday-Sunday)
     b. Find unmatched coin_ledger entries (anti-join vs clearing_case_items)
     c. Determine (from_group, to_group) via challenge_participants.group_id
     d. Group by (from_group, to_group) → INSERT clearing_cases (status='OPEN', deadline 7 days)
     e. INSERT clearing_case_items for each entry
     f. INSERT clearing_case_events (CREATED)

[Confirm Sent]
  3. Portal /clearing → clearing-confirm-sent EF
     → UPDATE clearing_cases SET status='SENT_CONFIRMED'
     → INSERT clearing_case_events (SENT_CONFIRMED)

[Confirm Received]
  4. Portal /clearing → clearing-confirm-received EF
     → UPDATE clearing_cases SET status='RECEIVED_CONFIRMED'
     → custody settlement via settle_clearing RPC
     → INSERT clearing_case_events (RECEIVED_CONFIRMED)

[Expiry]
  5. clearing-cron → WHERE deadline_at < now AND status IN ('OPEN','SENT_CONFIRMED')
     → UPDATE clearing_cases SET status='EXPIRED'

[Dispute]
  6. clearing-open-dispute EF → UPDATE clearing_cases SET status='DISPUTED'
```

### 7.8 Wallet Operations

```
[Credit — Challenge Win]
  settle-challenge EF → INSERT coin_ledger (reason='challenge_*_won')
                      → RPC fn_increment_wallets_batch → UPDATE wallets SET balance_coins += delta

[Credit — Badge Reward]
  evaluate-badges EF → INSERT coin_ledger (reason='badge_reward')
                     → RPC increment_wallet_balance → UPDATE wallets SET balance_coins += delta

[Credit — Session Completed]
  calculate-progression EF → RewardSessionCoins → INSERT coin_ledger (reason='session_completed')
                                                 → UPDATE wallets

[Debit — Challenge Entry Fee]
  challenge-create/join EF → INSERT coin_ledger (delta=-fee, reason='challenge_entry_fee')
                           → UPDATE wallets SET balance_coins -= fee

[Debit — Token Burn (QR)]
  token-consume-intent EF (type=BURN_FROM_ATHLETE) → INSERT coin_ledger (delta=-amount)
                                                    → UPDATE wallets SET balance_coins -= amount

[Reconciliation]
  reconcile-wallets-cron EF → RPC reconcile_all_wallets()
    → Compare wallets.balance_coins vs SUM(coin_ledger.delta_coins) per user
    → Auto-correct drift → INSERT coin_ledger (reason='admin_correction')
```

### 7.9 Token Intents (Create → Consume via QR)

```
[Create Intent — Staff]
  1. StaffGenerateQrScreen → token-create-intent EF
     → Verify staff role (admin_master/coach/assistant)
     → Check daily token limit (check_daily_token_usage RPC)
     → Check inventory capacity (coaching_token_inventory.available_tokens)
     → INSERT token_intents (status='OPEN', nonce, expires_at)
     → Generate QR containing nonce

[Consume Intent — Athlete]
  2. StaffScanQrScreen / AthleteCheckinQrScreen → token-consume-intent EF
     → Lookup token_intents by nonce WHERE status='OPEN' AND expires_at > now
     → Switch by type:
       - ISSUE_TO_ATHLETE:
           INSERT coin_ledger (delta=+amount)
           UPDATE wallets SET balance_coins += amount
           UPDATE coaching_token_inventory SET available_tokens -= amount, issued_tokens += amount
       - BURN_FROM_ATHLETE:
           INSERT coin_ledger (delta=-amount)
           UPDATE wallets SET balance_coins -= amount
           UPDATE coaching_token_inventory SET redeemed_tokens += amount
       - CHAMP_BADGE_ACTIVATE:
           UPDATE championship_participants SET has_badge = true
           UPDATE coaching_badge_inventory SET available_badges -= 1
     → UPDATE token_intents SET status='CONSUMED', consumed_by, consumed_at
```

### 7.10 Strava Data Pipeline

```
[Webhook Reception]
  1. Strava POST → strava-webhook EF
     → INSERT strava_event_queue (owner_id, object_id, aspect_type, status='pending')
     → Return 200 fast (queue-based)

[Queue Processing]
  2. processStravaEvent():
     a. Find strava_connections by strava_athlete_id
     b. Check duplicate: sessions WHERE strava_activity_id = ?
     c. Refresh token if expired → POST https://www.strava.com/oauth/token
     d. Fetch activity: GET https://www.strava.com/api/v3/activities/{id}
     e. Filter: only Run/TrailRun/VirtualRun
     f. Fetch streams: GET .../activities/{id}/streams?keys=latlng,time,heartrate,velocity_smooth,altitude,cadence

[Anti-Cheat]
  3. Integrity checks:
     - TOO_SHORT_DISTANCE (< 1km)
     - TOO_SHORT_DURATION (< 60s)
     - SPEED_IMPOSSIBLE (pace < 2:30/km)
     - IMPLAUSIBLE_PACE (< 3:00 or > 20:00/km)
     - TOO_FEW_POINTS (< 10 GPS points)
     - GPS_JUMP (> 500m in < 30s)
     - TELEPORT (> 2km in < 60s)
     - BACKGROUND_GPS_GAP (> 3 gaps of > 60s)
     - NO_MOTION_PATTERN (velocity CV < 0.03)
     - VEHICLE_SUSPECTED (zero cadence at high speed > 50%)

[Store & Link]
  4. Upload GPS to Supabase Storage: session-points/{user_id}/{session_id}.json
  5. INSERT sessions (source='strava', is_verified = !hasCritical)
  6. linkSessionToChallenges() → UPDATE challenge_participants SET progress_value
  7. Trigger side effects:
     → RPC eval_athlete_verification
     → RPC recalculate_profile_progress
     → RPC evaluate_badges_retroactive
  8. detectAndLinkPark() → UPSERT park_activities
```

### 7.11 Leaderboard Computation

```
[Trigger] — called by client or cron
  compute-leaderboard EF (scope: global | assessoria | championship | batch_assessoria)

[Global]
  → RPC compute_leaderboard_global(period, period_key, start_ms, end_ms)
  → Aggregates sessions (verified, within period) by user
  → UPSERT leaderboard_snapshots

[Assessoria]
  → RPC compute_leaderboard_assessoria(coaching_group_id, period, ...)
  → Joins coaching_members × sessions (verified, within period)
  → UPSERT leaderboard_snapshots

[Championship]
  → RPC compute_leaderboard_championship(championship_id, ...)
  → Joins championship_participants × sessions
  → UPSERT leaderboard_snapshots

[Batch Assessoria] — processes ALL coaching groups
  → Iterates all coaching_groups with cursor + deadline (50s)
  → Calls compute_leaderboard_assessoria per group
  → Returns partial results with next_cursor if deadline hit
```

### 7.12 KPI Daily Computation

```
[Source] — Materialized views / aggregate queries
  → v_kpi_dashboard (sessions, profiles, coaching_members aggregates)
  → v_kpi_retention (activity-based retention metrics)
  → v_weekly_progress (per-user weekly distance aggregation)

[Consumers]
  → StaffDashboardScreen (Flutter)
  → Dashboard page (Portal)
  → StaffRetentionDashboardScreen
  → StaffWeeklyReportScreen
```

### 7.13 Badge Evaluation

```
[Trigger] — after session sync
  1. RunSummaryScreen → evaluate-badges EF (POST { user_id, session_id })

[Evaluation]
  2. Parallel fetch:
     - sessions (this session)
     - profile_progress (lifetime stats)
     - badge_awards (already awarded)
     - badges (full catalog)
     - challenge_results (wins, completions)
     - championship_participants (completions)
     - v_weekly_progress (weekly distance)
     - sessions (best pace)

  3. For each badge NOT already awarded:
     → evaluateCriteria(criteria_type, criteria_json, context):
       - single_session_distance, lifetime_distance, session_count
       - pace_below, personal_record_pace
       - single_session_duration, lifetime_duration
       - daily_streak, weekly_distance
       - challenges_completed, challenge_won, championship_completed
       - session_before_hour, session_after_hour

  4. Awards:
     → INSERT badge_awards
     → INSERT xp_transactions (source='badge')
     → INSERT coin_ledger (reason='badge_reward')
     → RPC increment_profile_progress
     → RPC increment_wallet_balance

  5. Notification:
     → notify-rules EF (rule='badge_earned') → send-push → FCM
```

### 7.14 Notification Pipeline

```
[Rule Evaluation] — notify-rules EF (service_key only)
  Rules:
    1. challenge_received → notify user of challenge invite
    2. streak_at_risk → notify users with expiring streaks
    3. championship_starting → remind participants
    4. friend_request_received → notify of friend invite
    5. friend_request_accepted → notify inviter
    6. challenge_settled → notify participants of result
    7. challenge_expiring → remind of approaching deadline
    8. inactivity_nudge → nudge inactive users (5+ days)
    9. badge_earned → notify of new badge
   10. league_rank_change → notify of rank change
   11. join_request_approved → notify athlete

[Dedup]
  → notification_log table with 12-hour dedup window
  → Key: (user_id, rule, context_hash)

[Delivery]
  → notify-rules → send-push EF → device_tokens lookup → FCM HTTP v1 API
  → Concurrent: 10 parallel sends, 500 per batch
  → Stale token cleanup: delete NOT_FOUND/UNREGISTERED tokens

[Client Reception]
  → PushNotificationService (Flutter) → Firebase.initializeApp
  → PushNavigationHandler → deep link navigation
```

### 7.15 Profile Progression / Leveling

```
[Trigger] — after verified session
  1. RunSummaryScreen → calculate-progression EF (POST { session_id })

[XP Calculation]
  2. Base: 20 XP (if distance >= 200m)
     Distance bonus: floor(distKm * 10), cap 500
     Duration bonus: floor(durMin / 5) * 2, cap 120
     HR bonus: 10 if avgBpm present
     Daily cap: 1000 XP from sessions
     Daily session count cap: 10 sessions

[Streak Update]
  3. Check last_streak_day_ms:
     - Same day: no change
     - Yesterday: increment daily_streak_count
     - Older: reset to 1

[Persistence]
  4. RPC fn_mark_progression_applied (idempotency)
  5. INSERT xp_transactions
  6. RPC increment_profile_progress (total_xp, distance, moving_ms)
  7. UPDATE weekly_goals progress

[Level Calculation]
  8. Client-side: total_xp → level lookup (logarithmic scale)
```

### 7.16 Athlete Verification / Anti-Cheat

```
[Server-Side Verification] — verify-session EF
  1. Receive { session_id, user_id, route, total_distance_m, start_time_ms, end_time_ms }
  2. Run integrity checks on GPS route:
     - SPEED_IMPOSSIBLE, GPS_JUMP, TELEPORT
     - VEHICLE_SUSPECTED, NO_MOTION_PATTERN
     - BACKGROUND_GPS_GAP, TIME_SKEW
     - TOO_FEW_POINTS, TOO_SHORT_DURATION, TOO_SHORT_DISTANCE
     - IMPLAUSIBLE_PACE, IMPLAUSIBLE_HR_LOW, IMPLAUSIBLE_HR_HIGH
  3. Server verdict OVERWRITES client-side flags
  4. UPDATE sessions SET is_verified, integrity_flags

[Athlete Verification Status] — eval-athlete-verification EF
  1. Count verified sessions, flagged sessions, total distance, consistency
  2. Compute trust_score (0-100)
  3. Checklist: min_sessions, min_distance, low_flag_rate, gps_consistency
  4. Status: UNVERIFIED → PENDING → VERIFIED
  5. Monetization gate: stake > 0 requires VERIFIED status

[Periodic Re-evaluation] — eval-verification-cron EF
  → Re-evaluates all athletes periodically
  → Can downgrade status if new flagged sessions detected
```

---

## 8. Failure Impact Matrix

### Single Point of Failure Analysis

| Component | If Down | Blast Radius | Recovery |
|-----------|---------|-------------|----------|
| **Supabase PostgreSQL** | Everything fails | Total | Restore from backup |
| **Supabase Auth** | No login, no API calls | Total | Wait for Supabase recovery |
| **Supabase PostgREST** | No DB queries from any client | Total | Wait for Supabase recovery |
| **Supabase Edge Runtime** | All 57 EFs down | Severe — challenges, billing, notifications, verification | Wait for Deno Deploy recovery |
| **Supabase Storage** | GPS data lost, avatar uploads fail | Moderate | Wait for S3 recovery |
| **Stripe API** | Cannot purchase credits (Stripe gateway) | High for Stripe users | Switch to MercadoPago |
| **MercadoPago API** | Cannot purchase credits (MP gateway) | High for MP users | Switch to Stripe |
| **Strava API** | Activities not imported | Moderate — manual runs still work | Wait for Strava recovery |
| **FCM** | No push notifications | Low — app still works | Wait for Google recovery |
| **TrainingPeaks API** | Workout sync fails | Minimal — feature-flagged | Wait for TP recovery |
| **Sentry** | Error reporting blind | Zero user impact | Wait for Sentry recovery |
| **Firebase** | Push registration fails | Low — existing tokens work | Wait for Firebase recovery |

### Edge Function Dependency Chains

```
lifecycle-cron ──▶ settle-challenge ──▶ fn_increment_wallets_batch ──▶ wallets
       │                   │
       │                   └──▶ notify-rules ──▶ send-push ──▶ FCM
       │
       ├──▶ league-snapshot
       │
       └──▶ notify-rules ──▶ send-push ──▶ FCM

clearing-cron ──▶ aggregate_clearing_window RPC ──▶ settle_clearing RPC ──▶ custody_accounts
       │
       └──▶ clearing_cases, clearing_case_items

auto-topup-cron ──▶ auto-topup-check ──▶ create-checkout-session ──▶ Stripe API
                                        OR create-checkout-mercadopago ──▶ MP API

strava-webhook ──▶ strava_event_queue ──▶ processStravaEvent:
       │
       ├──▶ Strava API (token refresh, activity fetch, streams fetch)
       ├──▶ eval_athlete_verification RPC
       ├──▶ recalculate_profile_progress RPC
       ├──▶ evaluate_badges_retroactive RPC
       └──▶ linkSessionToChallenges → challenge_participants UPDATE
```

---

## 9. Cascading Failure Chains

### Chain 1: Billing Cascade
```
Stripe/MP down
  → webhook-payments/webhook-mercadopago fails
    → billing_purchases stuck in 'pending'
      → fn_fulfill_purchase never called
        → coaching_token_inventory not credited
          → token-create-intent returns INSUFFICIENT_INVENTORY
            → Staff cannot issue tokens via QR
              → Athletes cannot receive OmniCoins
                → Challenge entry fees cannot be paid
                  → New challenges cannot be created
```

### Chain 2: Lifecycle Cron Cascade
```
lifecycle-cron EF down
  → Championships never transition (open → active → completed)
  → Active challenges never settle (stays 'active' forever)
    → coin_ledger entries for prizes never created
      → Wallets never credited
        → Clearing cases never generated (no pending prizes)
          → Inter-group compensation halts
  → League snapshots never taken
  → Challenge expiring notifications never sent
  → Inactivity nudges never sent
```

### Chain 3: Strava Import Cascade
```
Strava API down
  → strava-webhook enqueues but processStravaEvent fails
    → Sessions not imported
      → Challenge progress not updated
        → Leaderboards stale
          → Verification status not re-evaluated
            → Badge evaluation not triggered
              → XP/coins from badges not awarded
```

### Chain 4: Push Notification Cascade
```
FCM down
  → send-push EF fails (all sends return 'failed')
    → notify-rules EF succeeds but no deliveries
      → Challenge invites not notified
      → Challenge results not notified
      → Streak-at-risk not alerted
      → Badge unlocks not notified
      → Inactivity nudges not delivered
        → User engagement drops
          → Retention metrics decline
```

### Chain 5: Database Connection Cascade
```
Supabase PostgreSQL connection limit hit
  → PostgREST returns 503
    → All Flutter app queries fail
    → All Portal pages error
    → All Edge Functions return 500
      → Webhooks fail (Stripe/MP retry, but with delays)
      → Cron jobs fail
      → Real-time subscriptions drop
        → Total platform outage
```

### Chain 6: Auth Cascade
```
Supabase Auth down
  → requireUser() in all 40+ EFs throws AuthError
    → No EF can process requests
      → Flutter app: auth.getUser() fails → stuck on AuthGate
      → Portal: middleware redirects all to /login
        → But login also fails → complete lockout
```

---

## Appendix A: Environment Variables Required

### Supabase Edge Functions
| Variable | Used By | Critical |
|----------|---------|----------|
| `SUPABASE_URL` | All EFs | **YES** |
| `SUPABASE_SERVICE_ROLE_KEY` / `SERVICE_ROLE_KEY` | All EFs | **YES** |
| `SUPABASE_ANON_KEY` | auth.ts (user-scoped client) | **YES** |
| `STRIPE_SECRET_KEY` | create-checkout-session, webhook-payments, process-refund | **YES** |
| `STRIPE_WEBHOOK_SECRET` | webhook-payments | **YES** |
| `MERCADOPAGO_ACCESS_TOKEN` | create-checkout-mercadopago, webhook-mercadopago | **YES** |
| `MERCADOPAGO_WEBHOOK_SECRET` | webhook-mercadopago | **YES** |
| `STRAVA_CLIENT_ID` | strava-webhook, strava-register-webhook | **YES** |
| `STRAVA_CLIENT_SECRET` | strava-webhook, strava-register-webhook | **YES** |
| `STRAVA_VERIFY_TOKEN` | strava-webhook | **YES** |
| `FCM_PROJECT_ID` | send-push | **YES** |
| `FCM_SERVICE_ACCOUNT` | send-push (base64) | **YES** |
| `TRAININGPEAKS_CLIENT_ID` | trainingpeaks-oauth, trainingpeaks-sync | No (feature-flagged) |
| `TRAININGPEAKS_CLIENT_SECRET` | trainingpeaks-oauth, trainingpeaks-sync | No |
| `PORTAL_URL` | create-checkout-mercadopago (back_urls) | **YES** |
| `CORS_ALLOWED_ORIGINS` | cors.ts (all EFs) | No (has defaults) |

### Flutter App
| Variable | Used By | Critical |
|----------|---------|----------|
| `SUPABASE_URL` (dart-define) | Supabase.initialize | **YES** |
| `SUPABASE_ANON_KEY` (dart-define) | Supabase.initialize | **YES** |
| `SENTRY_DSN` (dart-define) | SentryFlutter.init | No |
| `STRAVA_CLIENT_ID` (dart-define) | StravaAuthRepositoryImpl | No |
| `STRAVA_CLIENT_SECRET` (dart-define) | StravaAuthRepositoryImpl | No |

### Portal (Next.js)
| Variable | Used By | Critical |
|----------|---------|----------|
| `NEXT_PUBLIC_SUPABASE_URL` | All clients | **YES** |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | server.ts, client.ts | **YES** |
| `SUPABASE_SERVICE_ROLE_KEY` | admin.ts, service.ts | **YES** |
| `NEXT_PUBLIC_ENV` | Environment indicator | No |

---

## Appendix B: pg_cron Schedule

| Job | Schedule | Edge Function | Purpose |
|-----|----------|--------------|---------|
| lifecycle-cron | Every 5 minutes | `lifecycle-cron` | Championship transitions, challenge settlement, pending expiry, league snapshot, notifications |
| clearing-cron | Daily 02:00 UTC | `clearing-cron` | Case creation, custody settlement, case expiry |
| auto-topup-cron | Hourly | `auto-topup-cron` | Auto top-up for groups with enabled settings |
| reconcile-wallets-cron | Daily 04:00 UTC | `reconcile-wallets-cron` | Wallet balance vs ledger reconciliation |
| eval-verification-cron | Periodic | `eval-verification-cron` | Re-evaluate all athlete verification statuses |

---

## Appendix C: Idempotency Guards

| Flow | Layer | Mechanism |
|------|-------|-----------|
| Billing (Stripe) | L1 | `billing_events.stripe_event_id` UNIQUE partial index |
| Billing (Stripe) | L2 | Conditional UPDATE `WHERE status = 'pending'` |
| Billing (Stripe) | L3 | `fn_fulfill_purchase` checks `status = 'paid'` with FOR UPDATE lock |
| Billing (MercadoPago) | L1 | `billing_events` dedup via `mp_payment_id` in metadata |
| Billing (MercadoPago) | L2 | Same conditional UPDATE pattern |
| Billing (MercadoPago) | L3 | Same `fn_fulfill_purchase` lock |
| Challenge Settlement | Guard | Atomic claim: `UPDATE challenges SET status='completing' WHERE status IN ('active','completing')` |
| Challenge Settlement | Guard | Double-write check: existing `challenge_results` → skip |
| Challenge Results | Upsert | `ON CONFLICT (challenge_id, user_id)` |
| Badge Awards | Unique | `(user_id, badge_id)` UNIQUE constraint |
| Strava Events | Dedup | `(owner_id, object_id, aspect_type)` UNIQUE index on `strava_event_queue` |
| Strava Sessions | Dedup | Check `sessions WHERE strava_activity_id = ?` before insert |
| Progression | Guard | `fn_mark_progression_applied` prevents double XP |
| Clearing Items | Dedup | UNIQUE index on `clearing_case_items` |
| Wallet Reconciliation | Atomic | `reconcile_all_wallets()` compares balance vs SUM(ledger) |
| Notifications | Dedup | `notification_log` with 12-hour window |
