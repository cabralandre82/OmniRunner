# CHANGELOG — OS Assessoria (PASSO 05 + BLOCO 0–6)

## [0.92.0] — 2026-03-20

### Added
- InfoTooltip component for contextual explanations on all financial pages
- Glossary page (/glossary) with 17 proprietary term definitions
- Lightweight /api/liveness health check endpoint
- Table archival system: sessions_archive + coin_ledger_archive with weekly pg_cron jobs
- Feature flag gating for park segments and league screens
- Help Center expanded with 8 new articles (23 total) in 2 new categories
- Onboarding expanded from 6 to 10 steps (custody, clearing, distributions, help)
- PRODUCTION_READINESS.md deployment/rollback/monitoring guide
- CDN caching headers for static assets (immutable) and images (stale-while-revalidate)
- Framer Motion micro-animations: PageTransition, StaggerList, FadeIn, SlideUp, ScaleIn
- Circuit breaker pattern for Strava API calls in strava-webhook Edge Function
- Portal deploy automation (Vercel) in CI pipeline
- ARIA attributes across 8 core portal components
- i18n locale switching (PT-BR/EN) with Accept-Language detection and cookie persistence
- Locale switcher component in sidebar

### Fixed
- Migration 20260320000000: corrected column names (start_time_ms instead of started_at)
- Drift database: fixed clientDefault type mismatch (List<String> vs String)
- League screen: removed const from widget tree containing runtime method calls
- Athlete championships screen: fixed extra closing parenthesis syntax error
- Staff championship manage screen: added missing StaffGenerateQrScreen import

### Changed
- Isar → Drift migration: added ignore directives for legacy Isar schemas pending full removal

---

## PASSO 05 — Hardening & Schema Fix (Base)

### Added
- `compute_coaching_kpis_daily` rewritten as set-based (zero loops)
- `compute_coaching_athlete_kpis_daily` rewritten as set-based
- SECURITY DEFINER hardening: `search_path`, `REVOKE`/`GRANT` for all functions
- UNIQUE constraints on `coaching_kpis_daily`, `coaching_athlete_kpis_daily`, `coaching_alerts`
- `ON CONFLICT DO NOTHING` for idempotent compute
- `tools/verify_metrics_snapshots.ts` — full E2E test suite (RLS, idempotency, performance)
- Centralized role constants: `coaching_roles.dart` (App), `roles.ts` (Portal)
- `docs/STEP05_ROLLOUT.md` — production runbook

### Fixed
- **Schema drift**: `coaching_members.role` CHECK constraint mismatch (PT-BR vs English)
- Role backfill migration with pre-flight audit + stop condition + audit table
- `coachingRoleFromString` silent fallback → AppLogger.warn for unknown roles

### Changed
- Canonical roles: `admin_master`, `coach`, `assistant`, `athlete` (ASCII only)
- 15 RLS policies + 6 SECURITY DEFINER functions recreated with canonical roles

---

## BLOCO 0 — Pre-Analysis (Anti-Hallucination)

### Added
- `docs/ATLAS_OS_MASTER.md` — complete map of existing screens, tables, QR infra, patterns, reuse list

---

## BLOCO 1 — OS-01: Agenda de Treinos + Presença via QR

### Added (DB)
- Table `coaching_training_sessions` (schedule, status, location)
- Table `coaching_training_attendance` (QR check-in, idempotent via UNIQUE)
- 8 RLS policies (staff CRUD, all-members read, athlete self-attendance)
- `fn_mark_attendance` RPC (idempotent, ON CONFLICT DO NOTHING)
- `fn_issue_checkin_token` RPC (signed QR payload with TTL)

### Added (App)
- Staff: training list, create/edit, detail with attendance, QR scanner
- Athlete: my trainings, QR generator, my attendance
- Domain: entities, repositories, use cases, 3 BLoCs

### Added (Portal)
- `/attendance` — attendance report with filters + CSV export
- `/api/export/attendance` — CSV endpoint

### Added (Docs)
- `OS01_SCHEMA_RLS.md`, `OS01_QR_CHECKIN_SPEC.md`, `OS01_APP_FLOWS.md`, `OS01_PORTAL_REPORTS.md`

---

## BLOCO 2 — OS-02: CRM do Atleta

### Added (DB)
- Tables: `coaching_tags`, `coaching_athlete_tags`, `coaching_athlete_notes`, `coaching_member_status`
- 18 RLS policies (staff CRUD, athlete cannot read notes, athlete can read own status)
- `fn_upsert_member_status` RPC (idempotent)

### Added (App)
- Staff: CRM list (filters: tags, status, risk, attendance), athlete profile (tabs)
- Athlete: my status, my evolution
- Domain: entities, repositories, use cases, 2 BLoCs

### Added (Portal)
- `/crm` — CRM table with filters + CSV export
- `/crm/at-risk` — at-risk athletes panel
- `/crm/[userId]` — athlete detail
- API routes: `/api/crm/tags`, `/api/crm/notes`, `/api/export/crm`

### Added (Docs)
- `OS02_CRM_SPEC.md`, `OS02_APP_FLOWS.md`, `OS02_PORTAL.md`

---

## BLOCO 3 — OS-03: Comunicação (Mural + Leitura)

### Added (DB)
- Tables: `coaching_announcements`, `coaching_announcement_reads`
- 9 RLS policies (all-members read, staff CRUD, user marks own read)
- `fn_mark_announcement_read` RPC (idempotent, UNIQUE PK)
- `fn_announcement_read_stats` RPC (staff-only aggregation)

### Added (App)
- Announcement feed (all users), detail, create/edit (staff)
- Auto-mark read on open + manual button fallback
- Domain: entities, repositories, use cases, 2 BLoCs

### Added (Portal)
- `/announcements` — panel with read rate %, create/edit/pin
- API routes: `/api/announcements`, `/api/export/announcements`

### Added (Docs)
- `OS03_ANNOUNCEMENTS_SPEC.md`, `OS03_APP_FLOWS.md`, `OS03_PORTAL.md`

---

## BLOCO 4 — OS-04: Portal Profissional

### Added (Portal)
- `/engagement` upgraded: period filters, score trends, inactive athletes
- `/attendance-analytics` — attendance rates, low-attendance sessions
- `/risk` — high/medium risk athletes with resolve/dismiss
- `/communications` — announcement stats dashboard
- `/exports` — central CSV export hub
- API routes: `/api/export/engagement`, `/api/export/alerts`

### Added (DB)
- 11 performance indexes (group_id + dates on all major tables)

### Added (Docs)
- `OS04_PORTAL_REPORTS.md`, `OS04_EXPORTS.md`

---

## BLOCO 5 — OS-05: KPI + Attendance Integration

### Added (DB)
- Columns: `attendance_sessions_7d`, `attendance_checkins_7d`, `attendance_rate_7d` on `coaching_kpis_daily`
- Alert type: `missed_trainings_14d` (0 attendance in 14d + active group sessions)
- Severity: `critical` if also high engagement risk, else `warning`

### Changed
- `compute_coaching_kpis_daily` — LEFT JOIN LATERAL on training sessions/attendance
- `compute_coaching_alerts_daily` — new alert block with ON CONFLICT DO NOTHING

### Updated
- `tools/verify_metrics_snapshots.ts` — seeds training data, validates attendance KPIs + new alert

### Added (Docs)
- `OS05_KPIS_ALERTS_INTEGRATION.md`

---

## BLOCO 6 — OS-06: QA Total + Release

### Added (Docs)
- `OS06_IMPLEMENTATION_DIFF.md` — full file inventory (~110+ new, ~6 modified)
- `OS06_TEST_MATRIX.md` — complete test matrix (DB/App/Portal/Jobs)
- `OS06_RELEASE_RUNBOOK.md` — production deploy order + rollback (gradual + nuclear)
- `OS06_CHANGELOG.md` — this file

### Updated
- `docs/STEP05_ROLLOUT.md` — Phase 12 (OS-06 QA + Release)

---

## Summary Statistics

| Metric | Count |
|--------|-------|
| SQL Migrations | 7 |
| New DB Tables | 8 |
| RLS Policies | 50+ |
| RPCs / Functions | 7 |
| App Entities | 6 |
| App Screens | 14 |
| App BLoCs | 7 |
| Portal Pages | 16+ |
| Portal API Routes | 9 |
| Performance Indexes | 11 |
| Documentation Files | 17+ |
