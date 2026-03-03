# OS-06 — Matriz de Testes Final

## 1. DB / RLS Isolation

### 1.1 Script automático: `tools/verify_metrics_snapshots.ts`

```bash
# Requer: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
# Opcional: SUPABASE_ANON_KEY (habilita testes RLS com tokens reais)
npx tsx tools/verify_metrics_snapshots.ts
```

**Cobertura:**
- [x] KPI group-level correctness (DAU/WAU/MAU/sessions/distance)
- [x] KPI athlete-level correctness (score/risk/streak)
- [x] Attendance integration (attendance_sessions_7d, checkins_7d, rate_7d)
- [x] MISSED_TRAININGS_14D alert generation
- [x] Idempotency (3x run — values unchanged, no alert duplication)
- [x] RLS: Coach A reads Group A, NOT Group B
- [x] RLS: Athlete reads ONLY own athlete_kpis
- [x] RLS: Coach B reads Group B, NOT Group A
- [x] Performance: each compute < 5s for small dataset

### 1.2 Manual SQL RLS checks (run against staging)

```sql
-- ═══ OS-01: Training sessions ═══
-- Athlete cannot INSERT training sessions
SET ROLE authenticated;
-- (as athlete user)
INSERT INTO coaching_training_sessions (group_id, created_by, title, starts_at)
VALUES ('group-id', 'athlete-id', 'Should Fail', now());
-- Expected: ERROR (RLS violation)

-- Staff of Group A cannot read Group B sessions
-- (as staff of Group A)
SELECT * FROM coaching_training_sessions WHERE group_id = 'group-b-id';
-- Expected: 0 rows

-- ═══ OS-02: CRM Notes ═══
-- Athlete CANNOT read coaching_athlete_notes
-- (as athlete user)
SELECT * FROM coaching_athlete_notes WHERE group_id = 'any-group';
-- Expected: 0 rows (no SELECT policy for athletes)

-- ═══ OS-03: Announcement Reads ═══
-- User cannot mark read for another user
INSERT INTO coaching_announcement_reads (announcement_id, user_id)
VALUES ('ann-id', 'other-user-id');
-- Expected: ERROR (user_id = auth.uid() check)
```

### 1.3 Constraint tests

```sql
-- UNIQUE: duplicate attendance
INSERT INTO coaching_training_attendance (group_id, session_id, athlete_user_id, checked_by)
VALUES ('g', 's', 'a', 'c');
INSERT INTO coaching_training_attendance (group_id, session_id, athlete_user_id, checked_by)
VALUES ('g', 's', 'a', 'c');
-- Expected: second INSERT fails (uq_attendance_session_athlete)

-- UNIQUE: duplicate tag
INSERT INTO coaching_tags (group_id, name) VALUES ('g', 'VIP');
INSERT INTO coaching_tags (group_id, name) VALUES ('g', 'VIP');
-- Expected: second INSERT fails (uq_tag_group_name)

-- UNIQUE: duplicate announcement read
INSERT INTO coaching_announcement_reads (announcement_id, user_id) VALUES ('a', 'u');
INSERT INTO coaching_announcement_reads (announcement_id, user_id) VALUES ('a', 'u');
-- Expected: second INSERT fails (PK violation)

-- UNIQUE: duplicate alert
INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
VALUES ('g', 'u', '2026-03-03', 'test', 't', 'm', 'info');
INSERT INTO coaching_alerts (group_id, user_id, day, alert_type, title, message, severity)
VALUES ('g', 'u', '2026-03-03', 'test', 't', 'm', 'info');
-- Expected: second INSERT → DO NOTHING (no error if using ON CONFLICT)
```

### 1.4 Migration idempotence

```bash
# Run each migration twice — should succeed without errors
psql $DATABASE_URL -f supabase/migrations/20260303400000_training_sessions_attendance.sql
psql $DATABASE_URL -f supabase/migrations/20260303400000_training_sessions_attendance.sql
# Expected: no errors (IF NOT EXISTS, CREATE OR REPLACE)
```

---

## 2. App Flutter

### 2.1 Unit tests (usecases + blocs)

```bash
cd omni_runner && flutter test
```

**Checklist mínimo para novos testes:**

| Test | File | Assertions |
|------|------|------------|
| CreateTrainingSession | `test/domain/usecases/training/create_training_session_test.dart` | title validation, endsAt > startsAt, calls repo |
| ListTrainingSessions | `test/domain/usecases/training/list_training_sessions_test.dart` | passes params to repo, returns list |
| MarkAttendance | `test/domain/usecases/training/mark_attendance_test.dart` | delegates to repo, returns result types |
| ManageTags | `test/domain/usecases/crm/manage_tags_test.dart` | name validation, CRUD delegation |
| ManageNotes | `test/domain/usecases/crm/manage_notes_test.dart` | empty note validation |
| TrainingListBloc | `test/presentation/blocs/training_list_bloc_test.dart` | Initial → Loading → Loaded, refresh |
| CheckinBloc | `test/presentation/blocs/checkin_bloc_test.dart` | Generate → QrReady, Consume → Success |
| CrmListBloc | `test/presentation/blocs/crm_list_bloc_test.dart` | Load → Loaded with filters |
| AnnouncementFeedBloc | `test/presentation/blocs/announcement_feed_bloc_test.dart` | Load → Loaded, MarkRead updates locally |

### 2.2 Integration smoke test (against supabase dev)

```bash
# Start local supabase
supabase start

# Run integration tests
flutter test integration_test/
```

**E2E flow OS-01 (smoke):**
1. Staff creates training session → verify in DB
2. Athlete generates QR (fn_issue_checkin_token) → verify payload
3. Staff scans QR → fn_mark_attendance → verify attendance row
4. Re-scan same QR → verify "already_present" (idempotent)
5. Athlete sees own attendance
6. Cancel session → verify status = 'cancelled'

---

## 3. Portal

### 3.1 Existing test suite

```bash
cd portal && npm test
```

### 3.2 Playwright E2E (new tests needed)

```bash
cd portal && npx playwright test
```

**Checklist:**

| Test | Page | Assertions |
|------|------|------------|
| Login + sidebar | all | Staff sees all nav items; athlete gets no-access |
| Attendance report | `/attendance` | Table renders, filter by date works, rows clickable |
| Attendance analytics | `/attendance-analytics` | KPI cards render, period filter works |
| CRM table | `/crm` | Table renders, tag filter works, status filter works |
| CRM export | `/crm` → export | CSV downloads with correct headers |
| At-risk panel | `/crm/at-risk` | Cards render for athletes with alerts |
| Announcements | `/announcements` | Table with read rates, create inline |
| Announcement detail | `/announcements/[id]` | Read stats visible, read list |
| Risk page | `/risk` | Alerts display, resolve button works |
| Exports hub | `/exports` | All 5 export cards render, download links work |
| Communications | `/communications` | KPI cards, table, pagination |
| Auth guard | all staff pages | Athlete role → redirect to no-access |

### 3.3 Export CSV validation

```bash
# Download and validate each CSV
curl -H "Cookie: portal_group_id=...; ..." \
  "http://localhost:3000/api/export/attendance?from=2026-03-01&to=2026-03-03" \
  -o attendance.csv

# Verify: UTF-8 BOM, correct columns, data rows
head -3 attendance.csv
```

---

## 4. Compute Jobs

### 4.1 D-1 compute

```sql
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
SELECT compute_coaching_alerts_daily(current_date - 1);
```

### 4.2 Idempotency (3x)

```sql
-- Run 1
SELECT compute_coaching_kpis_daily(current_date - 1);
-- Capture values
SELECT attendance_sessions_7d, attendance_rate_7d FROM coaching_kpis_daily
WHERE day = current_date - 1 LIMIT 1;

-- Run 2 & 3
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_kpis_daily(current_date - 1);

-- Verify identical
SELECT attendance_sessions_7d, attendance_rate_7d FROM coaching_kpis_daily
WHERE day = current_date - 1 LIMIT 1;
-- Expected: same values

-- Verify alert uniqueness
SELECT count(*), count(DISTINCT (group_id, user_id, alert_type))
FROM coaching_alerts WHERE day = current_date - 1;
-- Expected: both counts equal
```

---

## 5. Resumo de Cobertura

| Camada | Tipo | Cobertura |
|--------|------|-----------|
| DB | RLS isolation | Coach A ≠ Coach B, Athlete ≠ Staff, Athlete ≠ notes |
| DB | UNIQUE constraints | attendance, tags, reads, alerts |
| DB | Migration idempotence | re-run safe |
| App | Unit tests | usecases + blocs |
| App | Integration | E2E OS-01 flow |
| Portal | Unit/integration | npm test |
| Portal | E2E | Playwright: pages + filters + export + auth |
| Jobs | D-1 compute | correctness + attendance metrics |
| Jobs | Idempotency | 3x run, no drift, no duplicates |
