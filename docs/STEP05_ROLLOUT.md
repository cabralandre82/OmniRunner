# STEP 05 — Rollout Runbook (KPIs/Engajamento pré-agregado)

## Pre-requisites

- [ ] Supabase CLI installed and linked (`supabase link`)
- [ ] Direct database connection string available (for migrations)
- [ ] Portal deployed behind feature flag or maintenance page
- [ ] App binary NOT deployed yet (deploy AFTER DB migration)

---

## Phase 1: Database Migrations (maintenance window)

Execute in order. Each migration is idempotent — safe to re-run.

### 1.0 PRE-FLIGHT: Audit existing roles (MANDATORY before migration)

```sql
-- Step 1: See current distribution
SELECT role, count(*) FROM coaching_members GROUP BY role ORDER BY 2 DESC;

-- Step 2: Verify all 'coach' rows are actual group owners
SELECT cm.group_id, cm.user_id, cm.role, cg.coach_user_id,
       (cm.user_id = cg.coach_user_id) AS is_owner
FROM coaching_members cm
JOIN coaching_groups cg ON cg.id = cm.group_id
WHERE cm.role = 'coach';
```

**Expected:** ALL rows should have `is_owner = true`. If any show `false`, those are anomalies.

**Stop condition:** The migration will **auto-abort** (`RAISE EXCEPTION`) if anomalies exceed the threshold (default: 10). If you see more, investigate the `_role_migration_audit` table, then raise `v_max_anomalies` in the migration once confirmed safe. Non-owner `coach` rows are kept as `coach` (new trainer role) — no privilege escalation.

### 1.1 Role canonicalization

```bash
supabase db push --include 20260303300000_fix_coaching_roles.sql
```

**What it does:**
- **Pre-flight audit** (DO block): warns if any `coach` rows are NOT group owners
- **Safe backfill**: `coach→admin_master` ONLY for verified group owners (`user_id = coaching_groups.coach_user_id`). Non-owner `coach` rows stay as `coach` (become trainers — no privilege escalation)
- Then: `professor→coach`, `assistente→assistant`, `atleta→athlete`
- Updates CHECK constraint to canonical set: `admin_master, coach, assistant, athlete`
- Backfills `coaching_join_requests.requested_role`
- Recreates all RLS policies with new role values
- Recreates all role-dependent functions (`staff_group_member_ids`, `fn_create_assessoria`, `fn_request_join`, `fn_approve_join_request`, `fn_reject_join_request`, `fn_remove_member`)

**Verify:**
```sql
-- No rows with old values should remain
SELECT role, count(*) FROM coaching_members GROUP BY role ORDER BY role;
-- Expected: admin_master, coach, assistant, athlete only

SELECT requested_role, count(*) FROM coaching_join_requests GROUP BY requested_role;
-- Expected: athlete, coach only

-- Confirm no accidental privilege escalation
SELECT cm.user_id, cm.group_id, cm.role
FROM coaching_members cm
WHERE cm.role = 'admin_master'
  AND NOT EXISTS (
    SELECT 1 FROM coaching_groups cg
    WHERE cg.id = cm.group_id AND cg.coach_user_id = cm.user_id
  );
-- Expected: 0 rows (every admin_master is a verified group owner)

-- Review anomalies (if any were found)
SELECT * FROM _role_migration_audit ORDER BY created_at;
-- Expected: 0 rows, or a small number with resolution = 'kept_as_coach_trainer'
```

**Post-migration cleanup** (after rollout is stable):
```sql
DROP TABLE IF EXISTS public._role_migration_audit;
```

### 1.2 Alert dedup constraints

```bash
supabase db push --include 20260303300001_alert_dedup_constraints.sql
```

**What it does:**
- Ensures UNIQUE constraints exist on `coaching_kpis_daily`, `coaching_athlete_kpis_daily`, `coaching_alerts`
- Safety net for idempotent compute functions

**Verify:**
```sql
SELECT conname FROM pg_constraint WHERE conname LIKE 'uq_%';
-- Expected: uq_kpis_group_day, uq_athlete_kpis_group_user_day, uq_alert_dedup
```

### 1.3 Apply SECURITY_HARDENING.sql

```bash
psql $DATABASE_URL -f docs/SECURITY_HARDENING.sql
```

**What it does:**
- Sets `search_path = public, pg_temp` on all SECURITY DEFINER functions
- Revokes execution from `anon`/`PUBLIC`
- Grants execution only to `service_role` (internal) or `authenticated` (user-facing RPCs)

**Verify:**
```sql
SELECT proname, prosecdef, proconfig
FROM pg_proc
WHERE prosecdef = true AND pronamespace = 'public'::regnamespace
ORDER BY proname;
-- All should show search_path=public, pg_temp in proconfig
```

### 1.4 Apply PATCH_SET_BASED.sql

```bash
psql $DATABASE_URL -f docs/PATCH_SET_BASED.sql
```

**What it does:**
- Replaces loop-based compute functions with set-based versions
- `compute_coaching_kpis_daily(date)` — one INSERT per group per day
- `compute_coaching_athlete_kpis_daily(date, uuid)` — one INSERT per athlete
- `compute_coaching_alerts_daily(date)` — idempotent alert generation

---

## Phase 2: First Compute (D-1)

Run the compute for yesterday to populate snapshots:

```sql
SELECT compute_coaching_kpis_daily(CURRENT_DATE - 1);
SELECT compute_coaching_athlete_kpis_daily(CURRENT_DATE - 1, NULL); -- NULL = all groups
SELECT compute_coaching_alerts_daily(CURRENT_DATE - 1);
```

**Verify:**
```sql
SELECT count(*) FROM coaching_kpis_daily WHERE day = CURRENT_DATE - 1;
SELECT count(*) FROM coaching_athlete_kpis_daily WHERE day = CURRENT_DATE - 1;
SELECT count(*) FROM coaching_alerts WHERE day = CURRENT_DATE - 1;
```

All counts should be > 0 for an active assessoria.

---

## Phase 3: Validate Dashboards

### 3.1 Portal

1. Log in as `admin_master` of a test group
2. Navigate to `/dashboard` — engagement KPIs should render
3. Navigate to `/engagement` — athlete cards should show metrics
4. Navigate to `/athletes` — athlete list should load
5. Navigate to `/verification` — verification queue should load
6. Navigate to `/custody` — custody accounts accessible
7. Navigate to `/clearing` — clearing events accessible

### 3.2 App

1. Log in as athlete — confirm assessoria visible, sessions work
2. Log in as coach — confirm dashboard, member management works
3. Log in as admin_master — confirm full access
4. Test join request flow (submit → approve)

---

## Phase 4: Run E2E Verification

```bash
cd tools
SUPABASE_URL=https://your-project.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=your-key \
SUPABASE_ANON_KEY=your-anon-key \
npx tsx verify_metrics_snapshots.ts
```

**Expected output:**
- All correctness checks PASS
- Idempotency checks PASS (re-run produces same values, no duplicate alerts)
- RLS checks PASS (coach can't see other group's data, athlete can't see group KPIs)
- Performance: each compute < 5s for test dataset

---

## Phase 5: Deploy App + Portal + Edge Functions

### 5.1 Deploy Edge Functions

```bash
supabase functions deploy --all
```

### 5.2 Deploy Portal

Standard deployment pipeline. The portal now uses canonical roles (`admin_master`, `coach`, `assistant`, `athlete`).

**Important:** After deploy, existing portal sessions with stale `portal_role` cookies will auto-refresh on next middleware check. The middleware now queries with `["admin_master", "coach", "assistant"]`.

### 5.3 Deploy App

Release new app binary. The Dart `coachingRoleFromString` handles both legacy and canonical values, so no ordering dependency.

---

## Phase 6: Enable Daily Cron

Set up the cron job to run compute at 02:00 UTC daily (processes D-1):

```sql
SELECT cron.schedule(
  'daily-coaching-kpis',
  '0 2 * * *',
  $$
    SELECT compute_coaching_kpis_daily(CURRENT_DATE - 1);
    SELECT compute_coaching_athlete_kpis_daily(CURRENT_DATE - 1, NULL);
    SELECT compute_coaching_alerts_daily(CURRENT_DATE - 1);
  $$
);
```

---

## Rollback Plan

### If migrations fail

1. The role backfill migration is wrapped in `BEGIN/COMMIT`. If any step fails, the entire transaction rolls back — no partial state.
2. The dedup constraints migration uses `IF NOT EXISTS` — safe to skip.
3. SECURITY_HARDENING changes are additive (search_path, grants) — no destructive changes.

### If dashboards break after deploy

1. Check `portal_role` cookie value in browser — should be one of `admin_master`, `coach`, `assistant`
2. Clear cookies and re-login
3. Check Supabase logs for RLS "permission denied" errors

### If compute functions fail

1. Check Supabase logs for the specific error
2. The old loop-based functions can be restored by re-running the previous migration version
3. Snapshot tables can be truncated safely — they're rebuilt by compute

### Nuclear rollback (worst case)

```sql
-- Restore old role values
UPDATE coaching_members SET role = 'professor' WHERE role = 'coach';
UPDATE coaching_members SET role = 'assistente' WHERE role = 'assistant';
UPDATE coaching_members SET role = 'atleta' WHERE role = 'athlete';

ALTER TABLE coaching_members DROP CONSTRAINT coaching_members_role_check;
ALTER TABLE coaching_members ADD CONSTRAINT coaching_members_role_check
  CHECK (role IN ('admin_master', 'professor', 'assistente', 'atleta', 'coach', 'assistant', 'athlete'));
```

Then redeploy old portal/app/edge functions.

---

## Files Changed Summary

| Deliverable | File | Purpose |
|---|---|---|
| Migration 1 | `supabase/migrations/20260303300000_fix_coaching_roles.sql` | Role backfill + constraint + RLS + functions |
| Migration 2 | `supabase/migrations/20260303300001_alert_dedup_constraints.sql` | UNIQUE constraints for idempotent snapshots |
| Constants (Dart) | `lib/core/constants/coaching_roles.dart` | Single source of truth for app |
| Constants (Portal) | `portal/src/lib/roles.ts` | Single source of truth for portal |
| Entity | `lib/domain/entities/coaching_member_entity.dart` | Canonical enum + fromString/toString |
| PATCH_SET_BASED | `docs/PATCH_SET_BASED.sql` | Set-based compute functions |
| SECURITY_HARDENING | `docs/SECURITY_HARDENING.sql` | Hardened SECURITY DEFINER functions |
| Verify script | `tools/verify_metrics_snapshots.ts` | E2E test with RLS + idempotency + perf |
| Screens (Dart) | 11 screen/bloc files | Updated role references |
| Tests (Dart) | 7 test files | Updated role references |
| Portal src | 18 source files | Updated role values in queries |
| Portal tests | 13 test files | Updated role values |
| Edge Functions | 13 function files | Updated role values in queries |

---

## Phase 7 — OS-01 Rollout (Training Sessions + Attendance)

### 7.1 Apply OS-01 Migration

```bash
supabase db push
# or apply directly:
# psql $DATABASE_URL -f supabase/migrations/20260303400000_training_sessions_attendance.sql
```

Verify:
```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_training_sessions', 'coaching_training_attendance');
-- expect 2 rows

SELECT polname FROM pg_policies
WHERE tablename IN ('coaching_training_sessions', 'coaching_training_attendance');
-- expect 8 policies

SELECT proname FROM pg_proc
WHERE proname IN ('fn_mark_attendance', 'fn_issue_checkin_token');
-- expect 2 rows
```

### 7.2 Smoke Test RPCs

```sql
-- As service_role, verify functions exist and return expected error for missing auth:
SELECT fn_mark_attendance(gen_random_uuid(), gen_random_uuid(), null);
-- expect: {"ok": false, "status": "forbidden", "message": "NOT_AUTHENTICATED"}
```

### 7.3 Deploy App + Portal

1. Deploy Flutter app with new screens (staff agenda, create, detail, scan + athlete list, QR, attendance)
2. Deploy Portal with attendance report pages + CSV export API
3. Verify sidebar shows "Presença" for staff roles

### 7.4 E2E Validation

Run the full OS-01 done criteria:
1. Staff creates training session
2. Athlete sees session in "Meus Treinos"
3. Athlete generates QR (fn_issue_checkin_token)
4. Staff scans QR → attendance registered (fn_mark_attendance)
5. Athlete sees attendance in "Minha Presença"
6. Portal: staff sees attendance report, exports CSV

### 7.5 Rollback (if needed)

```sql
-- Drop tables (cascades policies + indexes)
DROP TABLE IF EXISTS public.coaching_training_attendance CASCADE;
DROP TABLE IF EXISTS public.coaching_training_sessions CASCADE;

-- Drop RPCs
DROP FUNCTION IF EXISTS public.fn_mark_attendance(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.fn_issue_checkin_token(uuid, int);
```

---

## Phase 8 — OS-02 Rollout (CRM: Tags, Notas, Status)

### 8.1 Apply OS-02 Migration

```bash
supabase db push
# or:
# psql $DATABASE_URL -f supabase/migrations/20260303500000_crm_tags_notes_status.sql
```

Verify:
```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_tags', 'coaching_athlete_tags', 'coaching_athlete_notes', 'coaching_member_status');
-- expect 4 rows

SELECT polname FROM pg_policies
WHERE tablename IN ('coaching_tags', 'coaching_athlete_tags', 'coaching_athlete_notes', 'coaching_member_status');
-- expect 18 policies

SELECT proname FROM pg_proc WHERE proname = 'fn_upsert_member_status';
-- expect 1 row
```

### 8.2 RLS Smoke Test

```sql
-- Verify athlete CANNOT read notes (critical security check):
-- Set role to an athlete user and attempt SELECT on coaching_athlete_notes
-- Should return 0 rows even if data exists
```

### 8.3 Deploy App + Portal

1. Deploy Flutter app with CRM screens (StaffCrmList, StaffAthleteProfile, AthleteMyStatus, AthleteMyEvolution)
2. Deploy Portal with CRM pages (/crm, /crm/at-risk, /crm/[userId]) + export API
3. Verify sidebar shows "CRM Atletas" for staff roles

### 8.4 E2E Validation

1. Staff creates tags, assigns to athletes
2. Staff adds notes to athlete profile
3. Staff changes athlete status
4. Staff filters CRM list by tag and status
5. Portal: CRM table displays, CSV exports correctly
6. Portal: at-risk panel shows athletes with active alerts
7. Athlete sees own status (read-only)
8. Athlete CANNOT see internal notes (RLS enforced)

### 8.5 Rollback

```sql
DROP TABLE IF EXISTS public.coaching_athlete_notes CASCADE;
DROP TABLE IF EXISTS public.coaching_athlete_tags CASCADE;
DROP TABLE IF EXISTS public.coaching_tags CASCADE;
DROP TABLE IF EXISTS public.coaching_member_status CASCADE;
DROP FUNCTION IF EXISTS public.fn_upsert_member_status(uuid, uuid, text);
```

---

## Phase 9 — OS-03 Rollout (Mural de Avisos + Confirmação de Leitura)

### 9.1 Apply OS-03 Migration

```bash
supabase db push
# or:
# psql $DATABASE_URL -f supabase/migrations/20260303600000_announcements.sql
```

Verify:
```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_announcements', 'coaching_announcement_reads');
-- expect 2 rows

SELECT polname FROM pg_policies
WHERE tablename IN ('coaching_announcements', 'coaching_announcement_reads');
-- expect 9 policies

SELECT proname FROM pg_proc
WHERE proname IN ('fn_mark_announcement_read', 'fn_announcement_read_stats');
-- expect 2 rows
```

### 9.2 RLS Smoke Test

```sql
-- Verify: user can only mark OWN read (reads_self_insert enforces user_id = auth.uid())
-- Verify: athlete cannot insert/update/delete announcements
-- Verify: staff can see all reads for their group's announcements
```

### 9.3 Deploy App + Portal

1. Deploy Flutter with announcement screens (Feed, Detail, Create)
2. Deploy Portal with announcements panel + detail + export
3. Verify sidebar shows "Mural" for staff

### 9.4 E2E Validation

1. Staff creates announcement (pinned and unpinned)
2. Athlete opens feed → sees announcement → auto-marked as read
3. Athlete uses fallback "Confirmar leitura" button
4. Staff sees read rate on detail screen
5. Portal: announcements table with read rates, CSV export
6. UNIQUE constraint: marking read twice → no duplicate (idempotent)

### 9.5 Rollback

```sql
DROP TABLE IF EXISTS public.coaching_announcement_reads CASCADE;
DROP TABLE IF EXISTS public.coaching_announcements CASCADE;
DROP FUNCTION IF EXISTS public.fn_mark_announcement_read(uuid);
DROP FUNCTION IF EXISTS public.fn_announcement_read_stats(uuid);
```

---

## Phase 10 — OS-04 Rollout (Portal Profissional: Relatórios + Exports)

### 10.1 Apply Performance Indexes

```bash
psql $DATABASE_URL -f supabase/migrations/20260303700000_portal_performance_indexes.sql
```

Verify indexes exist:
```sql
SELECT indexname FROM pg_indexes
WHERE tablename IN ('sessions', 'coaching_kpis_daily', 'coaching_athlete_kpis_daily',
  'coaching_alerts', 'coaching_training_attendance', 'coaching_announcement_reads',
  'coaching_member_status')
ORDER BY indexname;
```

### 10.2 Deploy Portal

New/upgraded pages:
- `/engagement` — upgraded with score trends + period filter + inactive list
- `/attendance-analytics` — attendance rates, low-attendance sessions
- `/risk` — active alerts, resolve/dismiss actions
- `/communications` — announcement stats dashboard
- `/exports` — central CSV export hub

New API routes:
- `/api/export/engagement` — KPI snapshots CSV
- `/api/export/alerts` — alerts CSV

### 10.3 E2E Validation

1. Engagement: verify DAU/WAU/MAU, score trend chart, period filter works
2. Attendance analytics: verify rates, low-attendance table populates correctly
3. Risk: verify alerts display, resolve button works
4. Communications: verify read rates calculate correctly
5. Exports: download CSV from each module, verify data accuracy
6. Auth: verify athlete cannot access any staff page (sidebar filtering + server-side check)

### 10.4 Performance Check

- All list pages paginate (no full-table scans)
- Queries use group_id + date indexes
- No N+1 patterns in server components

### 10.5 Rollback

```sql
-- Only indexes were added to DB; safe to drop if causing issues:
DROP INDEX IF EXISTS idx_sessions_user_start;
DROP INDEX IF EXISTS idx_kpis_daily_group_day;
DROP INDEX IF EXISTS idx_athlete_kpis_daily_group_day;
DROP INDEX IF EXISTS idx_athlete_kpis_daily_group_user_day;
DROP INDEX IF EXISTS idx_alerts_group_resolved;
DROP INDEX IF EXISTS idx_alerts_group_user;
DROP INDEX IF EXISTS idx_attendance_group_checked;
DROP INDEX IF EXISTS idx_attendance_session_status;
DROP INDEX IF EXISTS idx_announcement_reads_ann_user;
DROP INDEX IF EXISTS idx_member_status_group_status;
-- Portal rollback: redeploy previous version
```

---

## Phase 11 — OS-05 Rollout (KPI + Attendance Integration)

### 11.1 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260303800000_kpi_attendance_integration.sql
```

Verify:
```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'coaching_kpis_daily'
  AND column_name IN ('attendance_sessions_7d', 'attendance_checkins_7d', 'attendance_rate_7d');
-- expect 3 rows
```

### 11.2 Run Compute for D-1

```sql
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
SELECT compute_coaching_alerts_daily(current_date - 1);
```

### 11.3 Validate

```sql
SELECT group_id, attendance_sessions_7d, attendance_checkins_7d, attendance_rate_7d
FROM coaching_kpis_daily WHERE day = current_date - 1 LIMIT 10;

SELECT count(*) FROM coaching_alerts
WHERE day = current_date - 1 AND alert_type = 'missed_trainings_14d';
```

### 11.4 Run Verify Script

```bash
npx tsx tools/verify_metrics_snapshots.ts
```

### 11.5 Rollback

```sql
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_sessions_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_checkins_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_rate_7d;
-- Re-apply original compute functions from docs/PATCH_SET_BASED.sql
```

---

## Phase 12 — OS-06 QA Total + Release

### 12.1 Run Full Test Suite

```bash
# App unit tests
cd omni_runner && flutter test

# Portal tests
cd portal && npm test

# Portal E2E
cd portal && npx playwright test

# Metrics verify script
npx tsx tools/verify_metrics_snapshots.ts
```

### 12.2 Production Deploy Order

1. **Migrations** (Fase 1 do `OS06_RELEASE_RUNBOOK.md`)
2. **Edge Functions** (se houver)
3. **Portal** (build + deploy)
4. **App** (build + deploy)
5. **Ativar Cron** (compute D-1)

### 12.3 Full E2E Validation

Run each OS "DONE" criteria end-to-end per `OS06_RELEASE_RUNBOOK.md` Fase 6.

### 12.4 Rollback

See `docs/OS06_RELEASE_RUNBOOK.md` — Rollback section (gradual or nuclear).

---

## Phase 13 — BLOCO A: Workout Builder

### 13.1 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260304100000_workout_builder.sql
```

### 13.2 Verify

```sql
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_workout_templates','coaching_workout_blocks','coaching_workout_assignments');
-- expect: 3
```

### 13.3 Rollback

```sql
DROP TABLE IF EXISTS public.coaching_workout_assignments CASCADE;
DROP TABLE IF EXISTS public.coaching_workout_blocks CASCADE;
DROP TABLE IF EXISTS public.coaching_workout_templates CASCADE;
DROP FUNCTION IF EXISTS public.fn_assign_workout(uuid, uuid, date, text);
```

---

## Phase 14 — BLOCO C: Integração Esportivo ↔ Financeiro

### 14.1 Pre-requisites

- Phase 13 (BLOCO A) applied — `coaching_workout_templates`, `coaching_workout_assignments`, `fn_assign_workout` exist
- BLOCO B (Financial Engine) applied — `coaching_plans` (with `max_workouts_per_week`), `coaching_subscriptions` (with `status`) exist

### 14.2 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260304300000_workout_financial_integration.sql
```

**What it does:**
- Replaces `fn_assign_workout` with a subscription-aware version
- Checks `coaching_subscriptions.status` before allowing assignment:
  - `late` → blocked (`SUBSCRIPTION_LATE`)
  - `cancelled` / `paused` → blocked (`SUBSCRIPTION_INACTIVE`)
  - `active` → checks weekly limit from `coaching_plans.max_workouts_per_week`
  - No subscription row → allowed (group may not use financial module)
- Enforces `max_workouts_per_week` cap per ISO week when plan defines it

### 14.3 Verify

```sql
-- Confirm function was replaced (check source for 'SUBSCRIPTION_LATE')
SELECT prosrc LIKE '%SUBSCRIPTION_LATE%' AS has_sub_check
FROM pg_proc WHERE proname = 'fn_assign_workout';
-- expect: true

-- Confirm grants
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_name = 'fn_assign_workout';
-- expect: authenticated (EXECUTE), service_role (EXECUTE)
```

### 14.4 Smoke Test

```sql
-- Test 1: Assign workout for athlete with active subscription (should succeed)
-- Test 2: Assign workout for athlete with status='late' → expect SUBSCRIPTION_LATE
-- Test 3: Assign workout for athlete with status='cancelled' → expect SUBSCRIPTION_INACTIVE
-- Test 4: Assign workouts up to max_workouts_per_week, then one more → expect WEEKLY_LIMIT_REACHED
-- Test 5: Assign workout for athlete with no subscription row → expect ASSIGNED (success)
```

### 14.5 Rollback

Re-apply the original `fn_assign_workout` from BLOCO A:

```bash
psql $DATABASE_URL -f supabase/migrations/20260304100000_workout_builder.sql
```

This restores the function without subscription checks. The signature is identical, so `CREATE OR REPLACE` cleanly overwrites.

---

## Phase 15 — BLOCO D: Wearables (Device Links + Workout Executions)

### 15.1 Pre-requisites

- Phase 13 (BLOCO A) applied — `coaching_workout_assignments`, `coaching_workout_templates`, `coaching_workout_blocks` exist
- App and Portal ready to deploy with new screens

### 15.2 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260304400000_wearables.sql
```

**What it does:**
- Creates `coaching_device_links` table (athlete ↔ wearable provider link)
- Creates `coaching_workout_executions` table (execution results)
- Partial unique index for dedup on provider activity imports
- RLS: athletes manage own links/executions; staff read-only for their group
- `fn_generate_workout_payload(uuid)` — builds structured JSON for wearable export
- `fn_import_execution(...)` — imports execution, dedup on provider_activity_id, auto-completes assignment

### 15.3 Verify

```sql
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('coaching_device_links', 'coaching_workout_executions');
-- expect: 2

SELECT polname FROM pg_policies
WHERE tablename IN ('coaching_device_links', 'coaching_workout_executions');
-- expect: 5 policies

SELECT proname FROM pg_proc
WHERE proname IN ('fn_generate_workout_payload', 'fn_import_execution');
-- expect: 2 rows
```

### 15.4 Smoke Test

```sql
-- Test fn_generate_workout_payload with a valid assignment_id
-- expect: {ok: true, data: {assignment_id, template_name, scheduled_date, blocks: [...]}}

-- Test fn_import_execution with manual source
-- expect: {ok: true, code: 'IMPORTED', data: {execution_id: ...}}

-- Test duplicate import (same provider_activity_id)
-- expect: {ok: true, code: 'DUPLICATE', message: ...}
```

### 15.5 Deploy App + Portal

1. Deploy Flutter app with new screens (`AthleteDeviceLinkScreen`, `AthleteLogExecutionScreen`)
2. Deploy Portal with executions page (`/executions`)
3. Verify sidebar shows "Execuções" for staff roles

### 15.6 E2E Validation

1. Athlete links a device (e.g., Garmin) → appears in list
2. Athlete unlinks device → removed from list
3. Staff sees athlete's device links (read-only)
4. Athlete logs manual execution (with/without assignment)
5. Assignment auto-completes when execution is linked
6. Staff sees executions in portal table with filters
7. Duplicate import (same provider_activity_id) returns DUPLICATE, no new row

### 15.7 Rollback

```sql
DROP TABLE IF EXISTS public.coaching_workout_executions CASCADE;
DROP TABLE IF EXISTS public.coaching_device_links CASCADE;
DROP FUNCTION IF EXISTS public.fn_generate_workout_payload(uuid);
DROP FUNCTION IF EXISTS public.fn_import_execution(uuid, int, int, int, int, int, int, text, text);
```

---

## Phase 16 — BLOCO E: Analytics Avançado

### 16.1 Pre-requisites

- Phase 13 (BLOCO A) applied — `coaching_workout_assignments` exists
- BLOCO B (Financial Engine) applied — `coaching_financial_ledger`, `coaching_subscriptions`, `coaching_plans` exist
- Phase 15 (BLOCO D) applied — `coaching_workout_executions` exists (with `actual_duration_seconds`, `avg_pace_seconds_per_km`)
- Phase 11 (OS-05) applied — `coaching_kpis_daily` has attendance columns, compute functions exist

### 16.2 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260304500000_analytics_advanced.sql
```

**What it does:**
- Adds 6 new columns to `coaching_kpis_daily`: `adherence_percent_7d`, `workout_load_week`, `performance_trend`, `revenue_month`, `active_subscriptions`, `late_subscriptions`
- Replaces `compute_coaching_kpis_daily` with extended version (all existing logic preserved + new LATERAL joins)
- Replaces `compute_coaching_alerts_daily` adding `financial_late` alert type

### 16.3 Verify

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'coaching_kpis_daily'
  AND column_name IN ('adherence_percent_7d', 'workout_load_week', 'performance_trend',
                       'revenue_month', 'active_subscriptions', 'late_subscriptions');
-- expect: 6 rows
```

### 16.4 Run Compute for D-1

```sql
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
SELECT compute_coaching_alerts_daily(current_date - 1);
```

### 16.5 Validate

```sql
SELECT group_id, adherence_percent_7d, workout_load_week, performance_trend,
       revenue_month, active_subscriptions, late_subscriptions
FROM coaching_kpis_daily WHERE day = current_date - 1 LIMIT 10;

SELECT count(*) FROM coaching_alerts
WHERE day = current_date - 1 AND alert_type = 'financial_late';
```

### 16.6 Rollback

```sql
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS adherence_percent_7d;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS workout_load_week;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS performance_trend;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS revenue_month;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS active_subscriptions;
ALTER TABLE public.coaching_kpis_daily DROP COLUMN IF EXISTS late_subscriptions;
-- Re-apply previous compute functions:
psql $DATABASE_URL -f supabase/migrations/20260303800000_kpi_attendance_integration.sql
```

---

## Phase 17: TrainingPeaks Integration

### 17.1 Pre-requisites

- [ ] `TRAININGPEAKS_CLIENT_ID` and `TRAININGPEAKS_CLIENT_SECRET` set in Supabase Edge Function secrets
- [ ] `TRAININGPEAKS_REDIRECT_URI` set (e.g., `https://<SUPABASE_URL>/functions/v1/trainingpeaks-oauth?action=callback`)

### 17.2 Apply Migration

```bash
psql $DATABASE_URL -f supabase/migrations/20260304800000_trainingpeaks_integration.sql
```

**What it does:**
- Adds `trainingpeaks` to `coaching_device_links.provider` and `coaching_workout_executions.source` CHECK constraints
- Creates `coaching_tp_sync` table for tracking sync state
- Creates RPCs: `fn_push_to_trainingpeaks`, `fn_tp_sync_status` (both SECURITY DEFINER, hardened)

### 17.3 Deploy Edge Functions

```bash
supabase functions deploy trainingpeaks-oauth
supabase functions deploy trainingpeaks-sync
```

### 17.4 Set Secrets

```bash
supabase secrets set TRAININGPEAKS_CLIENT_ID=<your_client_id>
supabase secrets set TRAININGPEAKS_CLIENT_SECRET=<your_client_secret>
supabase secrets set TRAININGPEAKS_REDIRECT_URI=<your_redirect_uri>
```

### 17.5 Verify

```sql
-- Check provider constraint updated
SELECT conname, consrc FROM pg_constraint
WHERE conname = 'coaching_device_links_provider_check';

-- Check sync table exists
SELECT count(*) FROM information_schema.tables
WHERE table_name = 'coaching_tp_sync';

-- Check RPCs exist
SELECT proname FROM pg_proc WHERE proname IN ('fn_push_to_trainingpeaks', 'fn_tp_sync_status');
```

### 17.6 Rollback

```sql
DROP TABLE IF EXISTS public.coaching_tp_sync CASCADE;
DROP FUNCTION IF EXISTS public.fn_push_to_trainingpeaks(uuid);
DROP FUNCTION IF EXISTS public.fn_tp_sync_status(uuid);
-- Revert provider CHECKs to previous values if needed
```

---

## Phase 18: Vercel Portal Deployment

### 18.1 Pre-requisites

- [ ] Vercel project configured with root directory: `portal/`
- [ ] Environment variables set in Vercel dashboard:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `SENTRY_ORG`, `SENTRY_PROJECT`, `SENTRY_AUTH_TOKEN` (optional)

### 18.2 Deploy

Push to `master` triggers automatic deployment. Verify at Vercel dashboard.

### 18.3 Post-Deploy Checks

- [ ] `/api/health` returns `{ "status": "ok" }`
- [ ] Login flow works
- [ ] Dashboard loads with data
- [ ] TrainingPeaks page accessible for staff
- [ ] CSV exports work
- [ ] No console errors

### 18.4 Rollback

Redeploy previous commit from Vercel dashboard:
```bash
# Or via CLI:
vercel rollback
```

---

## Full Migration Order (Production)

| # | Migration | What |
|---|-----------|------|
| 1 | `20260303300000_fix_coaching_roles.sql` | Canonical roles + backfill |
| 2 | `20260303300001_alert_dedup_constraints.sql` | Alert dedup |
| 3 | `20260303400000_training_sessions_attendance.sql` | OS-01 Training |
| 4 | `20260303500000_crm_tags_notes_status.sql` | OS-02 CRM |
| 5 | `20260303600000_announcements.sql` | OS-03 Announcements |
| 6 | `20260303700000_portal_performance_indexes.sql` | OS-04 Indexes |
| 7 | `20260303800000_kpi_attendance_integration.sql` | OS-05 KPI |
| 8 | `20260303900000_security_definer_hardening_remaining.sql` | Security |
| 9 | `20260304100000_workout_builder.sql` | BLOCO A |
| 10 | `20260304200000_financial_engine.sql` | BLOCO B |
| 11 | `20260304300000_workout_financial_integration.sql` | BLOCO C |
| 12 | `20260304400000_wearables.sql` | BLOCO D |
| 13 | `20260304500000_analytics_advanced.sql` | BLOCO E |
| 14 | `20260304600000_security_hardening_legacy_rpcs.sql` | Legacy RPCs |
| 15 | `20260304700000_optimistic_locking.sql` | Locking |
| 16 | `20260304800000_trainingpeaks_integration.sql` | TrainingPeaks |

### One-liner (apply all)

```bash
for f in supabase/migrations/202603*.sql supabase/migrations/202604*.sql; do
  echo "=== Applying: $f ==="
  psql $DATABASE_URL -f "$f" || { echo "FAILED: $f"; exit 1; }
done
```
