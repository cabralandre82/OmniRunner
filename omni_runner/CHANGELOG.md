# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2026-03-05

### Added
- Structured workout blocks v2: pace range (min/max), HR range (bpm), repeat count, notes, block types `rest` and `repeat`
- `.FIT` file export: "Enviar para relógio" button on athlete workout screen, generates `.FIT` via Edge Function and opens native share sheet
- FIT compatibility check: queries `coaching_members.watch_type` and `coaching_device_links.provider` to show/hide send-to-watch button
- `WorkoutBlockEntity` helpers: `isOpen`, `hasPaceRange`, `hasHrRange`, `totalDistanceMeters`
- `workoutBlockTypeLabel()` function for Portuguese block type labels
- 46 new unit tests covering block entity, enum round-trips, labels, repo mapper, watch type resolution

### Changed
- `WorkoutBlockEntity`: `targetPaceSecondsPerKm` → `targetPaceMinSecPerKm`/`targetPaceMaxSecPerKm` range
- Workout builder bottom sheet: pace range fields (mín/máx), HR range (bpm), repeat count, notes, all block types
- Block tile: shows pace range, HR range, repeat count, "livre" for open duration
- Athlete workout screen: guidance text for non-FIT-compatible watches instead of send button
- Repo mapper: backward-compatible with legacy `target_pace_seconds_per_km` column

## [0.11.0] - 2026-03-04

### Added
- Auto-attendance: workout params (distance, pace) in training creation form
- Auto-attendance: status badges (Concluído/Parcial/Ausente) on training detail
- Auto-attendance: athlete training list shows workout parameters and evaluation status
- Manual override bottom sheet for staff to change attendance status
- `attendanceStatusLabel()` helper for Portuguese status labels
- `CheckinMethod.auto` enum value for system-evaluated attendance
- `AttendanceStatus.completed` and `AttendanceStatus.partial` enum values
- `matchedRunId` field on `TrainingAttendanceEntity`
- Workout params (`distanceTargetM`, `paceMinSecKm`, `paceMaxSecKm`) on `TrainingSessionEntity`
- `ProfileDataService` DI registration
- `fn_search_users` RPC support
- Unit tests for auto-attendance entities, enums, labels (17 tests)
- Unit tests for `CreateTrainingSession` with workout params (3 tests)

### Changed
- Labels: "Presença" → "Treinos Prescritos" / "Cumprimento dos Treinos" across all screens
- Tab "Presença" → "Treinos" in staff athlete profile
- "Minha Presença" → "Meus Treinos Prescritos" for athletes
- Global SafeArea via `MaterialApp.builder` (fixes Android nav bar overlap)
- Removed `backgroundColor: inversePrimary` from AppBars across 24+ screens (dark mode fix)
- Dark mode: theme-aware colors for Strava banners, challenge cards, matchmaking, badges
- "Progresso" hub: removed competition sub-tabs and OmniCoins
- "Primeiros passos" made collapsible; runner quiz conditional
- Strava status refreshes on dashboard tab visibility change
- Map polyline fallback: `strava_activity_id` direct lookup + date-window matching
- Fixed `sessions.distance_meters` → `total_distance_m`
- Fixed `coin_ledger.issuer_group_id` removal
- Fixed `coaching_members.joined_via` → `group_id` in invite QR
- `checkedBy` on `TrainingAttendanceEntity` now nullable (auto-evaluated rows have no checker)

### Fixed
- Black screen on startup (uncaught async init errors)
- Strava disconnect loop
- "Algo deu errado" on verification card (duplicate DI)
- "Algo deu errado" on challenge/matchmaking (missing catch)
- Invisible green box on "Hoje" screen
- Typo "corredore" → "corredor"
- Profile "Salvar" not working
- Login "sem conexão" (missing env vars in build)
- Sentry: `workout_delivery_items` not found, `VerificationBloc` not registered

### Removed
- QR code navigation from athlete training list (replaced by auto-attendance)
- QR scan button and FAB from staff training detail screen

## [0.10.0] - 2026-02-28

### Added
- Widget tests for EmptyState, ErrorState, CachedAvatar, ShimmerLoading, StaggeredList, InvalidatedRunCard, DisputeStatusCard, SuccessOverlay (56 tests)
- Screen tests for BadgesScreen with fake BLoC (7 tests)
- Unit tests for ThemeNotifier, AppLogger, FeatureFlagService (18 tests)
- WCAG AA contrast ratio validation tests for AppTheme (light + dark)
- ADRs for architecture, portal, feature flags, i18n, observability, testing strategy

### Changed
- Updated README with i18n, observability, security, and feature flags sections

## [0.9.0] - 2026-02-28

### Added
- Gamification engine: challenges (1v1 and group), OmniCoins wallet, ledger, staked challenges
- Progression system: XP, levels, daily/weekly missions, badge catalog with retroactive evaluation
- Coaching (assessoria): groups, invites, member management, switch assessoria flow
- Social: friend invites, accept/block, groups, virtual running events with rankings
- Coach insights: athlete trends, baselines, inactivity warnings, overtraining detection
- Session integrity: speed, teleport, and vehicle detection
- Wearables: BLE heart rate, Apple Watch bridge, Health Connect / HealthKit export
- Strava integration: OAuth, upload, auto-sync
- Audio coach with configurable alerts
- Ghost runner mode (race against previous sessions)
- Portal web (Next.js): dashboard, athletes, credits, billing, settings, verification, platform admin
- 110 Flutter unit tests covering all domain use cases and services
- 40 Portal tests covering API routes, UI components, and lib utilities

### Changed
- Domain architecture refactored to Clean Architecture with dependency inversion
- All use cases follow single `call()` method pattern (O4 convention)
- OmniCoins acquisition restricted to assessoria distribution only (sessions no longer award coins)

## [0.1.0] - 2025-12-01

### Added
- Initial app scaffold: run tracking with GPS, pace calculation, distance accumulation
- Session persistence with Isar local database
- Basic map display and route recording
- Location permissions and auto-pause detection
