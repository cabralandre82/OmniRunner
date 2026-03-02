# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
