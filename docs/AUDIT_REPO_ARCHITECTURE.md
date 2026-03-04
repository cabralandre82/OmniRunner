# Audit: Repository Architecture

> Generated: 2026-03-04 | Read-only analysis of the monorepo at `/home/usuario/project-running`

---

## 1. Monorepo Overview

| Module | Path | Stack | Purpose |
|--------|------|-------|---------|
| **omni_runner** | `omni_runner/` | Flutter (Dart 3.8+) | Mobile app (iOS + Android) |
| **portal** | `portal/` | Next.js 14 (React 18, TypeScript) | Coach/Admin web dashboard |
| **supabase** | `supabase/` | Postgres + Deno Edge Functions | Backend: DB, auth, RPCs, crons |
| **watch** | `watch/` | Swift (Apple Watch) + Kotlin (Wear OS) | Wearable companion apps |
| **contracts** | `contracts/` | Markdown | API contracts (analytics, sync payload) |
| **scripts** | `scripts/` | Bash | CI helpers (bump_version, test_verification_gate) |
| **.github** | `.github/` | YAML | CI/CD workflows, issue templates, Dependabot |

---

## 2. Quantitative Summary

| Metric | Count |
|--------|-------|
| Flutter screens (`presentation/screens/*.dart`) | **100** |
| Flutter source files (`omni_runner/lib/**/*.dart`) | **619** |
| Portal pages (`page.tsx`) | **55** |
| Portal source files (`portal/src/**/*.ts{x}`) | **273** |
| Supabase Edge Functions (directories) | **57** (+ `_shared/`) |
| Supabase Migrations (`.sql` files) | **92** |
| Database tables (`CREATE TABLE`) | **~95** |
| Database RPC functions (`CREATE OR REPLACE FUNCTION`) | **~90** |
| Database views | **2** (`v_user_progression`, `v_weekly_progress`) |
| Wear OS Kotlin files | **17** |
| Apple Watch Swift stubs | Scaffolded (`.gitkeep` placeholders) |
| CI/CD workflows | **4** (flutter, portal, supabase, release) |

---

## 3. Flutter App — `omni_runner/`

### 3.1 Architecture Pattern

Clean Architecture with 4 layers:

```
lib/
├── core/           # Cross-cutting: auth, analytics, config, push, sync, theme, logging
├── data/           # Implementations: datasources, mappers, models (Isar + proto), repositories_impl
├── domain/         # Contracts: entities (65+), repositories (49 interfaces), usecases, services, failures
├── features/       # Self-contained feature modules (parks, strava, health_export, watch_bridge, wearables_ble)
├── l10n/           # Internationalization (pt-BR, en)
└── presentation/   # UI: blocs (34 BLoC dirs), screens (100), widgets (31), map
```

### 3.2 State Management

- **flutter_bloc** (BLoC pattern) — 34 BLoC modules under `presentation/blocs/`
- **get_it** — Service locator for dependency injection
- **Isar** — Local offline database (with `isar_flutter_libs` override via `third_party/`)

### 3.3 Core Layer Breakdown

| Sub-module | Role |
|------------|------|
| `core/analytics` | Event tracking + Sentry |
| `core/auth` | `AuthRepository`, `UserIdentityProvider`, anonymous mode |
| `core/config` | Environment/build config |
| `core/constants` | App-wide constants |
| `core/deep_links` | `app_links` based deep link handling |
| `core/errors` | Error types |
| `core/logging` | `AppLogger` abstraction |
| `core/push` | Firebase Messaging + `push_navigation_handler.dart` |
| `core/sync` | Offline-first sync engine |
| `core/theme` | `DesignTokens`, light/dark theme |
| `core/tips` | Contextual first-use tip system |
| `core/utils` | Shared utilities |

### 3.4 Data Layer

| Component | Files |
|-----------|-------|
| Datasources | 15 (geolocator, health, BLE, Isar DB, auth remote/mock, sync) |
| Mappers | Entity ↔ model mappers |
| Models | Isar schemas + protobuf models |
| Repository impls | Concrete implementations of domain interfaces |

### 3.5 Domain Layer

**Entities (65+):** `profile`, `session`, `challenge`, `coaching_group`, `coaching_member`, `badge`, `wallet`, `ledger_entry`, `workout_template`, `workout_assignment`, `workout_execution`, `training_session`, `training_attendance`, `mission`, `leaderboard`, `league`, `race_event`, `friendship`, `announcement`, `token_intent`, `athlete_verification`, `device_link`, and many more.

**Repository interfaces (49):** Every external data dependency has a contract (`i_*.dart`).

**Use case folders:**
| Folder | Domain |
|--------|--------|
| `announcements` | Mural / bulletin board |
| `coaching` | Assessoria management |
| `crm` | Athlete relationship management |
| `financial` | Plans, subscriptions, ledger |
| `gamification` | Badges, challenges, XP |
| `progression` | Level, streak, weekly goals |
| `social` | Friends, feed |
| `training` | Sessions, attendance |
| `wearable` | Device link, workout delivery |
| `workout` | Builder, assignments, templates |

### 3.6 Feature Modules

Self-contained features with own data/domain/presentation:

| Feature | Description |
|---------|-------------|
| `parks` | Park detection, leaderboard ("Rei do Parque"), segments |
| `strava` | OAuth, webhook sync, activity history import |
| `health_export` | Apple Health / Google Fit integration |
| `integrations_export` | TrainingPeaks and generic export |
| `watch_bridge` | Communication bridge to Apple Watch / Wear OS |
| `wearables_ble` | BLE heart rate sensor pairing |

### 3.7 Presentation Layer — 100 Screens

**Athlete screens:** `athlete_dashboard`, `today` (live run), `history`, `challenges_list`, `challenge_details`, `challenge_create`, `challenge_join`, `challenge_result`, `matchmaking`, `wallet`, `badges`, `leaderboards`, `league`, `missions`, `progression`, `personal_evolution`, `running_dna`, `wrapped`, `streaks_leaderboard`, `progress_hub`, `athlete_championships`, `athlete_verification`, `athlete_workout_day`, `athlete_training_list`, `athlete_log_execution`, `athlete_delivery`, `athlete_device_link`, `athlete_checkin_qr`, `athlete_my_evolution`, `athlete_my_status`, `athlete_evolution`, `athlete_attendance`, `athlete_championship_ranking`, `map`, `run_details`, `run_summary`, `run_replay`, `recovery`, `assessoria_feed`, `join_assessoria`, `my_assessoria`, `friends`, `friend_profile`, `friends_activity_feed`, `invite_friends`, `invite_qr`, `profile`, `settings`, `support`, `support_ticket`, `diagnostics`, `how_it_works`, `welcome`, `onboarding_role`, `onboarding_tour`

**Staff screens:** `staff_dashboard`, `staff_training_create`, `staff_training_detail`, `staff_training_list`, `staff_training_scan`, `staff_workout_builder`, `staff_workout_templates`, `staff_workout_assign`, `staff_qr_hub`, `staff_generate_qr`, `staff_scan_qr`, `staff_credits`, `staff_performance`, `staff_retention_dashboard`, `staff_weekly_report`, `staff_disputes`, `staff_join_requests`, `staff_crm_list`, `staff_athlete_profile`, `staff_championship_manage`, `staff_championship_templates`, `staff_championship_invites`, `staff_challenge_invites`, `staff_setup`, `coach_insights`, `coaching_groups`, `coaching_group_details`

**Shared screens:** `home` (tab shell), `more` (menu hub), `auth_gate`, `login`, `events`, `event_details`, `race_event_details`, `groups`, `group_details`, `group_members`, `group_events`, `group_evolution`, `group_rankings`, `partner_assessorias`

### 3.8 Key Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `supabase_flutter` | ^2.12.0 | Backend client |
| `flutter_bloc` | ^8.1.6 | State management |
| `isar` / `isar_flutter_libs` | ^3.1.0 | Offline local DB |
| `geolocator` | ^11.0.0 | GPS tracking |
| `maplibre_gl` | ^0.25.0 | Map rendering |
| `flutter_foreground_task` | ^8.0.0 | Background run tracking |
| `flutter_blue_plus` | ^2.1.1 | BLE heart rate sensors |
| `health` | ^13.3.1 | Apple Health / Google Fit |
| `firebase_core` / `firebase_messaging` | ^3.12/^15.2 | Push notifications |
| `google_sign_in` / `sign_in_with_apple` | ^6.2/^6.1 | Social auth |
| `sentry_flutter` | ^9.13.0 | Error monitoring |
| `fl_chart` | ^1.1.1 | Charts and graphs |
| `qr_flutter` / `mobile_scanner` | ^4.1/^7.2 | QR code generation + scanning |
| `cached_network_image` | ^3.4.1 | Image caching |
| `flutter_tts` | ^4.0.2 | Audio coach during runs |
| `share_plus` | ^12.0.1 | Social sharing |
| `flutter_web_auth_2` | ^5.0.1 | OAuth flows (Strava, TrainingPeaks) |
| `google_fonts` | ^8.0.2 | Typography |

---

## 4. Portal — `portal/`

### 4.1 Stack

- **Next.js 14** (App Router with route groups)
- **React 18** + **TypeScript 5**
- **Tailwind CSS 3.4**
- **Supabase SSR** (`@supabase/ssr` ^0.8)
- **next-intl** (i18n)
- **Zod 4** (schema validation)
- **Sonner** (toast notifications)
- **Sentry** (`@sentry/nextjs`)

### 4.2 Directory Structure

```
portal/src/
├── app/
│   ├── (portal)/        # Route group: authenticated coach/admin pages (35 routes)
│   ├── platform/        # Route group: platform-admin-only pages (12 routes)
│   ├── api/             # API route handlers (30+ endpoints)
│   ├── login/           # Auth page
│   ├── no-access/       # Access denied page
│   ├── challenge/[id]/  # Public challenge view
│   ├── invite/[code]/   # Invite code landing
│   └── select-group/    # Multi-group selection
├── components/
│   ├── sidebar.tsx      # Main navigation (NAV_ITEMS + PLATFORM_ITEMS)
│   └── ui/              # Shared UI components
├── lib/
│   ├── supabase/        # Client: admin.ts, client.ts, middleware.ts, server.ts, service.ts
│   ├── actions.ts       # Server actions
│   ├── analytics.ts     # Analytics helpers
│   ├── audit.ts         # Audit log utilities
│   ├── clearing.ts      # Clearing/settlement logic
│   ├── csrf.ts          # CSRF protection
│   ├── custody.ts       # Custody/wallet ops
│   ├── export.ts        # CSV/data export
│   ├── feature-flags.ts # Feature flag system
│   ├── format.ts        # Formatters
│   ├── logger.ts        # Structured logging
│   ├── metrics.ts       # Performance metrics
│   ├── rate-limit.ts    # Rate limiting
│   ├── roles.ts         # RBAC helpers
│   ├── schemas.ts       # Zod schemas
│   ├── swap.ts          # Token swap logic
│   └── webhook.ts       # Webhook verification
├── i18n/                # Internationalization config
├── styles/              # Global styles
└── test/                # Unit tests (vitest)
```

### 4.3 Portal Pages (55 page.tsx files)

**Coach/Admin (`(portal)/`):** dashboard, athletes, attendance, attendance-analytics, announcements (CRUD), audit, badges, billing (+success/cancelled), clearing, communications, credits, crm (+at-risk, +[userId] detail), custody, delivery, distributions, engagement, executions, exports, financial (+plans, +subscriptions), fx, risk, settings, swap, trainingpeaks, verification, workouts (+analytics, +assignments)

**Platform Admin (`platform/`):** assessorias, conquistas, feature-flags, fees, financeiro, invariants, liga, produtos, reembolsos, support (+[id] detail)

**Public:** login, no-access, challenge/[id], invite/[code], select-group

### 4.4 API Routes (30+)

`announcements`, `auth/callback`, `auto-topup`, `billing-portal`, `branding`, `checkout`, `clearing`, `crm` (+notes, +tags), `custody` (+webhook, +withdraw), `debug-auth`, `distribute-coins`, `export` (alerts, announcements, athletes, attendance, crm, engagement, financial), `gateway-preference`, `health`, `platform/*` (assessorias, feature-flags, fees, invariants, liga, products, refunds, support), `swap`, `team` (+invite, +remove), `verification` (+evaluate)

### 4.5 Role-Based Access

| Role | Sidebar Items | Scope |
|------|---------------|-------|
| `admin_master` | All 25 items | Full assessoria control |
| `coach` | 22 items (no Custódia, Swap, FX) | Coaching + moderate financial |
| `assistant` | 12 items | Athletes, attendance, CRM, announcements, executions |
| `platform_admin` | Separate section | Global platform ops |

---

## 5. Supabase Backend — `supabase/`

### 5.1 Database Schema

**92 migrations** spanning 2026-02-18 through 2026-03-05.

**~95 tables** organized by domain:

| Domain | Tables |
|--------|--------|
| **Core** | `profiles`, `sessions`, `sessions_archive` |
| **Gamification** | `seasons`, `badges`, `badge_awards`, `profile_progress`, `xp_transactions`, `season_progress`, `weekly_goals`, `missions`, `mission_progress` |
| **Economy** | `wallets`, `coin_ledger`, `coaching_token_inventory`, `token_intents` |
| **Challenges** | `challenges`, `challenge_participants`, `challenge_results`, `challenge_run_bindings`, `challenge_queue`, `challenge_team_invites` |
| **Championships** | `championship_templates`, `championships`, `championship_invites`, `championship_participants`, `championship_badges` |
| **Leaderboards** | `leaderboards`, `leaderboard_entries` |
| **Leagues** | `league_seasons`, `league_enrollments`, `league_snapshots` |
| **Coaching** | `coaching_groups`, `coaching_members`, `coaching_invites`, `coaching_rankings`, `coaching_ranking_entries`, `coaching_announcements`, `coaching_announcement_reads`, `coaching_tags`, `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_member_status`, `coaching_training_sessions`, `coaching_training_attendance`, `coaching_badge_inventory`, `coaching_device_links`, `coaching_workout_executions`, `coaching_tp_sync` |
| **Workouts** | `coaching_workout_templates`, `coaching_workout_blocks`, `coaching_workout_assignments` |
| **Delivery** | `workout_delivery_batches`, `workout_delivery_items`, `workout_delivery_events` |
| **Financial** | `coaching_plans`, `coaching_subscriptions`, `coaching_financial_ledger` |
| **Billing** | `billing_customers`, `billing_products`, `billing_purchases`, `billing_events`, `billing_limits`, `billing_auto_topup_settings`, `billing_refund_requests`, `institution_credit_purchases` |
| **Clearing** | `clearing_weeks`, `clearing_cases`, `clearing_case_items`, `clearing_case_events` |
| **Social** | `friendships`, `groups`, `group_members`, `group_goals`, `assessoria_feed`, `assessoria_partnerships` |
| **Events/Races** | `events`, `event_participations`, `race_events`, `race_participations`, `race_results` |
| **Verification** | `athlete_verification` |
| **Analytics** | `analytics_submissions`, `athlete_baselines`, `athlete_trends`, `coach_insights` |
| **Integrations** | `strava_connections`, `strava_activity_history` |
| **Parks** | `parks`, `park_activities`, `park_segments`, `park_leaderboard` |
| **Personalization** | `running_dna`, `user_wrapped` |
| **Infrastructure** | `api_rate_limits`, `notification_log`, `product_events`, `device_tokens`, `portal_audit_log`, `portal_branding` |

**2 Views:** `v_user_progression`, `v_weekly_progress`

**~90 RPC functions** (see AUDIT_FEATURE_MAP.md for mapping).

### 5.2 Edge Functions (57)

| Category | Functions |
|----------|-----------|
| **Challenges** | `challenge-create`, `challenge-get`, `challenge-join`, `challenge-list-mine`, `challenge-invite-group`, `challenge-accept-group-invite`, `settle-challenge` |
| **Championships** | `champ-create`, `champ-list`, `champ-open`, `champ-enroll`, `champ-invite`, `champ-accept-invite`, `champ-cancel`, `champ-participant-list`, `champ-update-progress`, `champ-lifecycle`, `champ-activate-badge` |
| **Matchmaking** | `matchmake` |
| **Gamification** | `evaluate-badges`, `calculate-progression`, `compute-leaderboard`, `league-list`, `league-snapshot`, `generate-running-dna`, `generate-wrapped` |
| **Financial** | `create-checkout-session`, `create-checkout-mercadopago`, `create-portal-session`, `webhook-payments`, `webhook-mercadopago`, `auto-topup-check`, `auto-topup-cron`, `list-purchases`, `process-refund` |
| **Tokens** | `token-create-intent`, `token-consume-intent` |
| **Clearing** | `clearing-cron`, `clearing-confirm-sent`, `clearing-confirm-received`, `clearing-open-dispute` |
| **Verification** | `eval-athlete-verification`, `eval-verification-cron`, `verify-session` |
| **Integrations** | `strava-webhook`, `strava-register-webhook`, `trainingpeaks-oauth`, `trainingpeaks-sync` |
| **Social** | `complete-social-profile`, `validate-social-login` |
| **Notifications** | `send-push`, `notify-rules` |
| **Analytics** | `submit-analytics` |
| **Admin** | `set-user-role`, `delete-account`, `lifecycle-cron`, `reconcile-wallets-cron` |

### 5.3 Cron Jobs

| Function | Schedule |
|----------|----------|
| `auto-topup-cron` | Auto-replenish token inventory |
| `lifecycle-cron` | Challenge/championship lifecycle state transitions |
| `clearing-cron` | Weekly clearing/settlement processing |
| `eval-verification-cron` | Periodic re-evaluation of athlete verification status |
| `reconcile-wallets-cron` | Wallet balance reconciliation |
| `league-snapshot` | Periodic league ranking snapshots |

---

## 6. Watch Apps — `watch/`

### 6.1 Wear OS (Kotlin — Active)

```
watch/wear_os/app/src/main/kotlin/com/omnirunner/watch/
├── MainActivity.kt
├── OmniRunnerWatchApp.kt
├── service/
│   ├── WearWorkoutManager.kt      # Workout tracking engine
│   └── WorkoutService.kt          # Foreground workout service
├── data/sync/
│   ├── DataLayerManager.kt        # Phone ↔ watch data sync
│   ├── OfflineSessionStore.kt     # Offline session persistence
│   └── WearListenerService.kt     # Data layer listener
├── domain/
│   ├── models/                    # HeartRateSample, HrZone, LocationSample
│   └── usecases/Haversine.kt     # Distance calculation
└── ui/
    ├── screens/                   # StartScreen, WorkoutScreen, SummaryScreen
    ├── components/HrZoneIndicator.kt
    └── theme/Theme.kt
```

### 6.2 Apple Watch (Swift — Scaffolded)

Directory structure exists with `.gitkeep` placeholders under `Sources/` (App, Managers, Models, Utils, Views). Not yet implemented.

---

## 7. CI/CD — `.github/`

| Workflow | Trigger | Actions |
|----------|---------|---------|
| `flutter.yml` | Push to omni_runner/ | Analyze, test, build APK/IPA |
| `portal.yml` | Push to portal/ | Lint, test (vitest), build (Next.js) |
| `supabase.yml` | Push to supabase/ | Validate migrations, deploy functions |
| `release.yml` | Tag push | Coordinated release across modules |

Additional config: `dependabot.yml` (auto-update deps), `secret_scanning.yml`, issue/PR templates.

---

## 8. Shared Infrastructure

| Component | Location | Purpose |
|-----------|----------|---------|
| API Contracts | `contracts/` | `analytics_api.md`, `sync_payload.md` |
| ADRs | `docs/adr/` | Architecture Decision Records |
| Scripts | `scripts/` | `bump_version.sh`, `test_verification_gate.sh` |
| Portal scripts | `portal/scripts/` | `qa-full.sh`, `qa-no-money.sh` |
| Flutter scripts | `omni_runner/scripts/` | Build/test helpers |
| Tools | `tools/` | Miscellaneous tooling |

---

## 9. Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENTS                                   │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │  omni_runner  │  │    portal     │  │   watch (Wear/Apple)   │ │
│  │  Flutter App  │  │  Next.js 14   │  │   Kotlin / Swift       │ │
│  │  100 screens  │  │  55 pages     │  │   3 screens            │ │
│  │  34 BLoCs     │  │  30+ API rts  │  │   DataLayer sync       │ │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬─────────────┘ │
│         │                  │                      │               │
└─────────┼──────────────────┼──────────────────────┼───────────────┘
          │                  │                      │
          ▼                  ▼                      ▼
┌─────────────────────────────────────────────────────────────────┐
│                     SUPABASE PLATFORM                            │
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │  Auth (GoTrue)    │  │  57 Edge Funcs   │  │  Realtime      │ │
│  │  Google/Apple SSO │  │  Deno runtime    │  │  Subscriptions │ │
│  │  Anonymous mode   │  │  + 6 cron jobs   │  │                │ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                    PostgreSQL                                 ││
│  │  ~95 tables │ ~90 RPC functions │ 2 views │ 92 migrations    ││
│  │  Row-Level Security (RLS) on all user-facing tables          ││
│  └──────────────────────────────────────────────────────────────┘│
│                                                                  │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │  Storage          │  │  pg_cron          │  │  pg_net        │ │
│  │  Avatars, media   │  │  Scheduled tasks  │  │  HTTP calls    │ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────────────┘
          │                  │
          ▼                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                   EXTERNAL SERVICES                              │
│                                                                  │
│  Stripe │ MercadoPago │ Strava │ TrainingPeaks │ Firebase (FCM) │
│  Sentry │ Vercel (portal hosting)                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 10. Key Architectural Decisions

1. **Offline-first mobile:** Isar local DB + sync engine ensures runs are never lost, even without connectivity.
2. **BLoC pattern everywhere:** All Flutter state is managed via BLoC, with 34 specialized BLoC modules.
3. **Edge functions over direct DB access:** Complex operations (challenges, championships, clearing) go through Edge Functions for atomicity and authorization.
4. **Dual payment gateway:** Stripe (international) + MercadoPago (Brazil) with gateway preference per group.
5. **Role-based everything:** Three levels — app roles (athlete vs staff), portal roles (admin_master, coach, assistant), platform role (platform_admin). Enforced at DB (RLS), API, and UI levels.
6. **Feature flags:** Runtime feature toggles via `feature-flags` system for gradual rollout.
7. **Verification system:** Athletes must meet minimum criteria (run count, distance, Strava link) before high-stakes features (challenges with entry fees).
8. **Token economy:** OmniCoins with wallet, ledger, clearing, disputes — full financial infrastructure within the platform.
