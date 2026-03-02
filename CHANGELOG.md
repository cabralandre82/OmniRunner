# Changelog

All notable changes to the Omni Runner project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Replaced ~40 silent `catch (_) {}` blocks with proper logging via `AppLogger`
- Removed dead code and TODO comments from `service_locator.dart`
- Updated `pubspec.yaml` description from template text to proper project description
- Added `*.apk`, `*.aab`, `*.ipa` to `.gitignore`

### Removed
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
