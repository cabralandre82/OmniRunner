# Changelog

All notable changes to the Omni Runner project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-03-05

### Added
- **Portal template CRUD**: full create/edit/delete flow for workout templates directly from the portal
  - `/workouts/new` page with structured block builder (type, duration, distance, pace range, HR zone/range, RPE, repeat count, notes)
  - `/workouts/[id]/edit` page to edit existing templates and their blocks
  - Edit/Delete buttons on template detail page (`/workouts/[id]`)
  - "+ Novo Template" button on templates listing page (`/workouts`)
  - Reusable `TemplateBuilder` client component with block reordering (move up/down) and inline removal
  - Delete confirmation UI with two-step flow
  - API route `POST /api/workouts/templates` (create + update with blocks)
  - API route `DELETE /api/workouts/templates` (delete template + blocks)

## [1.2.0] - 2026-03-05

### Added
- **Structured workout model v2**: pace range (min/max), HR range (bpm), repeat blocks, rest blocks, open duration support in `coaching_workout_blocks`
- **`.FIT` file generation**: Edge Function `generate-fit-workout` produces binary `.FIT` workout files (protocol 2.0, CRC-16 validated) for direct-to-watch delivery
- **"Enviar para relógio" button**: Athletes with FIT-compatible watches (Garmin, COROS, Suunto) can share `.FIT` files via native share sheet
- **Athlete-centric workout assignment page** (`/workouts/assign`): lists all athletes with watch compatibility badges, bulk assignment (select N athletes + template + date), inline watch type editing
- **Watch type tracking**: `watch_type` column on `coaching_members` with auto-detection from `coaching_device_links` via `v_athlete_watch_type` view; `fn_set_athlete_watch_type` RPC for coach override
- **Assignment → auto-attendance bridge**: `trg_assignment_to_training` trigger auto-creates `coaching_training_sessions` with distance/pace from workout blocks when assignments are created
- Portal workout template detail page (`/workouts/[id]`) with structured block visualization
- Portal templates list now shows total distance and links to detail view
- API routes: `POST /api/workouts/assign` (bulk), `POST /api/workouts/watch-type`
- FIT validation tools (`tools/test_fit_generation.js`, `tools/validate_fit.js`)
- 46 new tests: WorkoutBlockEntity v2 fields, WorkoutBlockType enum (rest/repeat), labels, repo mapper, watch type resolution, FIT compatibility
- RLS policies for athlete read access to workout blocks and templates

### Changed
- `WorkoutBlockEntity`: replaced single `targetPaceSecondsPerKm` with `targetPaceMinSecPerKm`/`targetPaceMaxSecPerKm` range; added `targetHrMin`/`targetHrMax`, `repeatCount`, `notes`
- Workout builder UI: expanded bottom sheet with pace range, HR range, repeat count, notes, rest/repeat block types
- Portal sidebar: "Treinos" renamed to "Templates", added "Atribuir Treinos" entry
- Conditional "Enviar para relógio": hidden for Apple Watch/Polar users, shows guidance text instead

## [1.1.0] - 2026-03-04

### Added
- **Auto-attendance system** replacing QR-based check-in for training sessions
  - Staff assigns workouts with distance target and optional pace range
  - System automatically evaluates athlete's next 2 runs against training parameters
  - Distance match (±15%) + pace match → Concluído; ran but no match → Parcial; no runs → Ausente
  - DB triggers on `sessions` (run sync) and `coaching_training_sessions` (new training) for real-time evaluation
  - Manual override via bottom sheet for staff to adjust status
- Workout parameter fields in training creation form (distance km, pace min/max)
- Color-coded attendance status badges (Concluído/Parcial/Ausente) in detail screens
- Attendance status display for athletes in training list bottom sheet
- Portal attendance pages updated: workout params display, status breakdown, analytics
- Unit tests for auto-attendance entities, enums, and workout params (38 tests)
- `fn_evaluate_athlete_training` DB function for workout matching logic
- `trg_session_auto_attendance` and `trg_training_close_prev` DB triggers
- `fn_search_users` DB function for user search in Flutter app
- `platform_fee_config` table with default fee configuration
- Logout button ("Sair") in portal platform admin header
- `ProfileDataService` registration in DI container

### Changed
- **Labels clarified**: "Presença" → "Treinos Prescritos" / "Cumprimento dos Treinos" across all screens and portal to distinguish workout compliance from assessoria attendance
- Portal sidebar: "Presença" → "Treinos Prescritos", "Análise Presença" → "Análise de Treinos"
- CRM labels: "Presenças" → "Treinos", attendance counts → "treinos concluídos"
- Global SafeArea fix via `MaterialApp.builder` to handle Android navigation bar overlap
- Standardized role names from Portuguese to English (`atleta`→`athlete`, `professor`→`coach`, `assistente`→`assistant`) via migration + app/portal filters
- Replaced ~40 silent `catch (_) {}` blocks with proper logging via `AppLogger`
- Premium dark mode design system applied to all 88 Flutter screens and portal pages
- Dark mode readability fixes: theme-aware colors for Strava banners, challenge cards, matchmaking, badge cards
- AppBar backgrounds: removed all `inversePrimary` overrides across 24+ screens for proper dark mode contrast
- "Progresso" hub: removed competition sub-tabs and OmniCoins section for cleaner layout
- "Primeiros passos" card made collapsible; runner quiz only shown after first steps complete
- Strava connection status now refreshes when dashboard tab becomes visible
- Map route fallback: uses `strava_activity_id` direct lookup then date-window matching in `strava_activity_history`
- Edge functions: removed `issuer_group_id` from all `coin_ledger` INSERTs (6 functions)
- Edge function `delete-account`: fixed `profiles.role` → `profiles.user_role`
- Edge function `create-portal-session`: removed non-existent `profiles.email` column
- Portal queries: added try-catch for non-existent feature tables (custody, swap, league)
- Portal role filter: `.eq("role", "athlete")` → `.in("role", ["athlete", "atleta"])` across 16+ files
- Corrected `sessions.distance_meters` → `total_distance_m` in profile screen
- Corrected `coin_ledger.issuer_group_id` removal from wallet remote source
- Corrected `coaching_members.joined_via` → `group_id` lookup in invite QR screen
- Fixed 5 broken DB functions (`fn_delete_user_data`, `fn_compute_kpis_batch`, `fn_compute_skill_bracket`, `fn_increment_wallets_batch`, `fn_sum_coin_ledger_by_group`)
- Fixed `staff-alerts` API route: `settlements` → `clearing_cases`, `created_at_ms` → `created_at`

### Fixed
- Black screen on app startup due to uncaught async initialization errors
- Strava disconnection loop in challenges list and auth repository
- "Algo deu errado" errors on verification card (duplicate DI registration)
- "Algo deu errado" on challenge/matchmaking buttons (missing general catch in BLoC)
- "Recurso não encontrado" on assign workout (improved error messages)
- Assessoria/athlete link mismatch (role name inconsistency in DB vs app filters)
- Invisible green box on "Hoje" screen (white text on green background)
- Typo "corredore" → "corredor" in active runners count
- Profile "Salvar" button not working (missing `ProfileDataService` DI registration)
- Invisible red error button on profile screen (adjusted error card styling)
- Empty fees page in platform admin (missing `platform_fee_config` table)
- Login failure "sem conexão" after disk cleanup (missing `--dart-define-from-file` in build)
- Sentry errors: `workout_delivery_items` table not found, `VerificationBloc` not registered, `ProfileDataService` not registered

### Removed
- QR code scanning screen for staff (`StaffTrainingScanScreen` no longer used for attendance)
- QR code generation for athletes (`AthleteCheckinQrScreen` navigation removed from training list)
- Deleted 129MB `app-prod-release.apk` from repository

## [1.0.13] - 2026-02-27

### Added
- Platform approval flow for assessorias (pending/approved/rejected/suspended)
- Join request approval required setting per assessoria
- Friends activity feed

### Fixed
- RLS recursion in coaching_members and group_members
- Championship templates RLS policies
- `fn_request_join` email column reference

## [1.0.0] - 2026-02-12

### Added
- Initial release with full feature set
- Flutter mobile app (Android/iOS) with Clean Architecture
- Next.js B2B portal for assessorias
- Supabase backend with RLS, Edge Functions, and pg_cron
- Strava integration as sole data source
- Gamification: challenges, OmniCoins, XP, badges, missions
- Coaching: assessorias, member management, join requests
- Championships between assessorias
- Parks detection and leaderboards
- Athlete verification system
- Push notifications via FCM
- BLE heart rate monitor support
- Health export (HealthKit / Health Connect)
- File export (GPX, TCX, FIT)
- Portal: dashboard, credits, billing, athletes, verification, engagement, settings
- Portal: platform admin (assessorias, financeiro, reembolsos, produtos, support)
