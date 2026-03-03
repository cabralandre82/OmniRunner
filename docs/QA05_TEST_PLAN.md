# QA-05 — Test Plan Completo

## 1. Banco de Dados (RLS / Constraints / Idempotência)

### 1.1 RLS Isolation — Testes com JWT Real

| # | Test | Persona JWT | Query | Expected | Prioridade |
|---|------|-------------|-------|----------|------------|
| R01 | Coach A não lê treinos do Grupo B | Coach A | `SELECT * FROM coaching_training_sessions WHERE group_id = 'B'` | 0 rows | P0 |
| R02 | Coach B não lê treinos do Grupo A | Coach B | `SELECT * FROM coaching_training_sessions WHERE group_id = 'A'` | 0 rows | P0 |
| R03 | Atleta A vê treinos do Grupo A | Athlete A (Grupo A) | `SELECT * FROM coaching_training_sessions WHERE group_id = 'A'` | N rows | P0 |
| R04 | Atleta A NÃO vê attendance de outro atleta | Athlete A | `SELECT * FROM coaching_training_attendance WHERE athlete_user_id != auth.uid()` | 0 rows | P0 |
| R05 | Atleta A vê SUA attendance | Athlete A | `SELECT * FROM coaching_training_attendance WHERE athlete_user_id = auth.uid()` | N rows | P0 |
| R06 | Atleta NÃO lê `coaching_athlete_notes` | Athlete A | `SELECT * FROM coaching_athlete_notes` | 0 rows | **P0 CRITICAL** |
| R07 | Atleta lê seu próprio status | Athlete A | `SELECT * FROM coaching_member_status WHERE user_id = auth.uid()` | 0-1 row | P1 |
| R08 | Atleta NÃO lê status de outro | Athlete A | `SELECT * FROM coaching_member_status WHERE user_id != auth.uid()` | 0 rows | P1 |
| R09 | Atleta lê avisos do grupo | Athlete A | `SELECT * FROM coaching_announcements WHERE group_id = 'A'` | N rows | P0 |
| R10 | Atleta marca read apenas para si | Athlete A | `INSERT INTO coaching_announcement_reads (announcement_id, user_id) VALUES (X, OTHER_USER)` | ERROR (RLS) | P0 |
| R11 | Staff do Grupo A CRUD tags | Coach A | `INSERT/SELECT/DELETE coaching_tags WHERE group_id = 'A'` | Success | P0 |
| R12 | Coach A não CRUD tags do Grupo B | Coach A | `INSERT INTO coaching_tags (group_id, name) VALUES ('B', 'test')` | ERROR (RLS) | P0 |
| R13 | Atleta não insere training session | Athlete A | `INSERT INTO coaching_training_sessions (...)` | ERROR (RLS) | P0 |
| R14 | Assistant não deleta announcements | Assistant A | `DELETE FROM coaching_announcements WHERE id = X` | ERROR ou 0 rows (RLS) | P1 |

### 1.2 Constraints (UNIQUE)

| # | Constraint | Test | Expected |
|---|-----------|------|----------|
| C01 | `uq_attendance_session_athlete` | Inserir presença 2x para mesmo atleta/sessão | 2nd: CONFLICT (DO NOTHING via RPC) |
| C02 | `uq_tag_group_name` | Inserir tag duplicada (mesmo nome, mesmo grupo) | 2nd: ERROR unique violation |
| C03 | `coaching_announcement_reads PK` | Inserir read 2x para mesmo user/announcement | 2nd: CONFLICT (DO NOTHING via RPC) |
| C04 | `uq_alerts_dedup` | Inserir alerta duplicado (group, user, day, type) | 2nd: CONFLICT (DO NOTHING) |
| C05 | `uq_kpis_daily_group` | Inserir KPI duplicado (group_id, day) | 2nd: UPDATE via ON CONFLICT |
| C06 | `uq_athlete_kpis_daily` | Inserir athlete KPI duplicado | 2nd: UPDATE via ON CONFLICT |

### 1.3 Idempotência (compute 3x)

```sql
-- Run 1
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
SELECT compute_coaching_alerts_daily(current_date - 1);

-- Capture baseline
CREATE TEMP TABLE _baseline AS
  SELECT * FROM coaching_kpis_daily WHERE day = current_date - 1;

-- Run 2 + 3
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_kpis_daily(current_date - 1);

-- Assert no drift
SELECT b.group_id,
  b.total_athletes = c.total_athletes AS athletes_match,
  b.attendance_sessions_7d = c.attendance_sessions_7d AS att_sessions_match,
  b.attendance_rate_7d IS NOT DISTINCT FROM c.attendance_rate_7d AS att_rate_match
FROM _baseline b
JOIN coaching_kpis_daily c ON c.group_id = b.group_id AND c.day = b.day;
-- ALL columns must be true

-- Assert no alert duplication
SELECT alert_type, group_id, user_id, count(*)
FROM coaching_alerts WHERE day = current_date - 1
GROUP BY 1,2,3 HAVING count(*) > 1;
-- Expected: 0 rows
```

---

## 2. App Flutter

### 2.1 Unit Tests (UseCases + Mappers)

| # | Test File | Tests | Prioridade |
|---|-----------|-------|------------|
| U01 | `test/domain/usecases/training/create_training_session_test.dart` | Valida title required, ends>=starts, delegates to repo | P0 |
| U02 | `test/domain/usecases/training/list_training_sessions_test.dart` | Passa group_id + pagination, retorna lista | P0 |
| U03 | `test/domain/usecases/training/mark_attendance_test.dart` | Delega para repo, retorna inserted/already_present/forbidden | P0 |
| U04 | `test/domain/usecases/training/cancel_training_session_test.dart` | Atualiza status='cancelled' | P1 |
| U05 | `test/domain/usecases/crm/manage_tags_test.dart` | CRUD tags, validação nome vazio | P1 |
| U06 | `test/domain/usecases/crm/manage_notes_test.dart` | Add note, validação texto vazio | P1 |
| U07 | `test/domain/usecases/announcements/create_announcement_test.dart` | Título required, delega para repo | P1 |
| U08 | `test/domain/usecases/announcements/mark_announcement_read_test.dart` | Delega para repo, idempotente | P1 |

### 2.2 BLoC Tests

| # | Test File | States Tested | Prioridade |
|---|-----------|---------------|------------|
| B01 | `test/presentation/blocs/training_list_bloc_test.dart` | Initial → Loading → Loaded, Refresh, Error | P0 |
| B02 | `test/presentation/blocs/training_detail_bloc_test.dart` | Load → Loaded, MarkAttendance → Updated | P0 |
| B03 | `test/presentation/blocs/checkin_bloc_test.dart` | Generate → QrReady, Expire, Error | P0 |
| B04 | `test/presentation/blocs/crm_list_bloc_test.dart` | Load → Loaded, Filter → Filtered, Error | P1 |
| B05 | `test/presentation/blocs/athlete_profile_bloc_test.dart` | Load tabs, AddNote → Updated, Error | P1 |
| B06 | `test/presentation/blocs/announcement_feed_bloc_test.dart` | Load → Loaded, MarkRead → Updated | P1 |
| B07 | `test/presentation/blocs/announcement_detail_bloc_test.dart` | Load → Loaded, Delete → Popped | P1 |

### 2.3 Integration / Smoke Tests

| # | Fluxo | Passos | Ambiente |
|---|-------|--------|----------|
| S01 | OS-01 completo | Login staff → criar treino → atleta gerar QR → staff scan → presença registrada → atleta vê presença | Supabase dev (local) |
| S02 | OS-02 completo | Staff cria tag → atribui a atleta → adiciona nota → filtra por tag → nota visível | Supabase dev |
| S03 | OS-03 completo | Staff cria aviso → atleta abre → leitura marcada → staff vê taxa | Supabase dev |

---

## 3. Portal Next.js

### 3.1 Unit / Integration (npm test)

```bash
cd portal && npm test
```

Testes existentes cobrem:
- Sidebar rendering + role-based items
- API routes (clearing, branding, gateway, distribute-coins, export/athletes, team)
- Schema validation

### 3.2 Playwright E2E

| # | Test | Page | Assertions | Prioridade |
|---|------|------|------------|------------|
| P01 | Staff login + sidebar | `/dashboard` | Sidebar mostra 9+ items | P0 |
| P02 | Attendance report | `/attendance` | Tabela carrega, filtro por data funciona | P0 |
| P03 | Attendance export CSV | `/api/export/attendance` | CSV download, headers corretos | P0 |
| P04 | CRM table | `/crm` | Tabela carrega, filtro por tag funciona | P0 |
| P05 | CRM export | `/api/export/crm` | CSV download | P1 |
| P06 | Announcements | `/announcements` | Lista com read rates | P1 |
| P07 | Risk page | `/risk` | Alertas carregam ou empty state | P1 |
| P08 | Exports hub | `/exports` | 5 cards render, links funcionam | P1 |
| P09 | Engagement upgraded | `/engagement` | Trends chart, period filter, inactive list | P1 |
| P10 | Auth guard: athlete | all staff pages | Redirect `/no-access` | **P0** |
| P11 | Communications | `/communications` | KPI cards, table | P2 |
| P12 | Attendance analytics | `/attendance-analytics` | Chart, low-attendance list | P2 |

---

## 4. Jobs / Cron

### 4.1 verify_metrics_snapshots.ts

```bash
npx tsx tools/verify_metrics_snapshots.ts
```

**Cobertura:**
- Seeds: training sessions + attendance + users
- Compute: group KPIs + athlete KPIs + alerts
- Assert: attendance_sessions_7d, checkins_7d, rate_7d
- Assert: MISSED_TRAININGS_14D alert
- Assert: idempotency (3x run, values stable)
- Assert: RLS (coach A only sees group A)
- Assert: performance < 5s

### 4.2 Timing Benchmark

```sql
\timing on
SELECT compute_coaching_kpis_daily(current_date - 1);
-- Expect: < 5s for < 100 groups
-- Expect: < 30s for 1000 groups
-- Expect: < 300s for 10000 groups (target scale)
```

---

## Cobertura Resumo

| Camada | Tipo | Tests | Prioridade |
|--------|------|-------|------------|
| DB | RLS isolation (14 tests) | R01-R14 | P0 |
| DB | UNIQUE constraints (6 tests) | C01-C06 | P0 |
| DB | Idempotência (3x compute) | 1 scenario | P0 |
| App | Unit usecases (8 tests) | U01-U08 | P0-P1 |
| App | BLoC tests (7 blocs) | B01-B07 | P0-P1 |
| App | Smoke integration (3 flows) | S01-S03 | P0 |
| Portal | Unit/integration | npm test | P0 |
| Portal | Playwright E2E (12 tests) | P01-P12 | P0-P2 |
| Jobs | verify script | 1 comprehensive | P0 |
| Jobs | Timing | 1 benchmark | P1 |
| **TOTAL** | | **52+ tests** | |
