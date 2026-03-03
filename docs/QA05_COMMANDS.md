# QA-05 — Comandos de Teste (Exatos)

## 1. DB — RLS + Constraints + Idempotência

### Requisitos
- PostgreSQL CLI (`psql`) com acesso ao banco
- Variável `$DATABASE_URL` configurada
- Supabase CLI para testes locais: `supabase start`

### Aplicar migrations (local)
```bash
supabase db push
# OU manualmente:
for f in supabase/migrations/202603033*.sql; do
  psql $DATABASE_URL -f "$f"
done
```

### RLS tests (via psql com roles)
```bash
# Criar test harness (requer service_role)
psql $DATABASE_URL <<'SQL'
-- Setup: criar users/groups de teste
-- (já coberto pelo verify_metrics_snapshots.ts)

-- Test R06 (CRITICAL): Atleta não lê notas
SET LOCAL role TO authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"ATHLETE_A_UUID","role":"authenticated"}';
SELECT count(*) AS athlete_notes_count FROM coaching_athlete_notes;
-- MUST be 0

-- Test R01: Coach A não lê Grupo B
SET LOCAL request.jwt.claims TO '{"sub":"COACH_A_UUID","role":"authenticated"}';
SELECT count(*) AS cross_group FROM coaching_training_sessions
WHERE group_id = 'GROUP_B_UUID';
-- MUST be 0

RESET role;
RESET request.jwt.claims;
SQL
```

### Constraint tests
```bash
psql $DATABASE_URL <<'SQL'
-- C01: Duplicate attendance
INSERT INTO coaching_training_attendance
  (group_id, session_id, athlete_user_id, checked_by)
VALUES ('g','s','a','c')
ON CONFLICT (session_id, athlete_user_id) DO NOTHING;
-- Should: do nothing (no error)

-- C04: Duplicate alert
INSERT INTO coaching_alerts
  (group_id, user_id, day, alert_type, title, message, severity)
VALUES ('g','u','2026-03-03','test','t','m','info')
ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING;
-- Should: do nothing
SQL
```

### Idempotency (3x)
```bash
psql $DATABASE_URL <<'SQL'
\timing on

SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_athlete_kpis_daily(current_date - 1);
SELECT compute_coaching_alerts_daily(current_date - 1);

-- Save baseline
CREATE TEMP TABLE _qa_baseline AS
  SELECT group_id, total_athletes, attendance_sessions_7d, attendance_rate_7d
  FROM coaching_kpis_daily WHERE day = current_date - 1;

-- Run 2 + 3
SELECT compute_coaching_kpis_daily(current_date - 1);
SELECT compute_coaching_kpis_daily(current_date - 1);

-- Check drift
SELECT 'DRIFT DETECTED' AS status, b.group_id
FROM _qa_baseline b
JOIN coaching_kpis_daily c ON c.group_id = b.group_id AND c.day = current_date - 1
WHERE b.total_athletes != c.total_athletes
   OR b.attendance_sessions_7d != c.attendance_sessions_7d
   OR b.attendance_rate_7d IS DISTINCT FROM c.attendance_rate_7d;
-- Expected: 0 rows

-- Check alert duplication
SELECT 'DUPLICATE ALERT' AS status, alert_type, group_id, user_id, count(*)
FROM coaching_alerts WHERE day = current_date - 1
GROUP BY 1,2,3,4 HAVING count(*) > 1;
-- Expected: 0 rows

DROP TABLE _qa_baseline;
SQL
```

---

## 2. Verify Script (E2E Métricas)

```bash
# Requisitos: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY no env
export SUPABASE_URL="http://localhost:54321"
export SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"

# Run
npx tsx tools/verify_metrics_snapshots.ts

# Expected output:
# ✅ KPIs computed
# ✅ Attendance metrics correct
# ✅ MISSED_TRAININGS_14D alert generated
# ✅ Idempotency verified
# ✅ RLS isolation verified
# ✅ Performance < 5s
```

---

## 3. App Flutter

### Unit tests
```bash
cd omni_runner

# All tests
flutter test

# Specific OS tests
flutter test test/domain/usecases/training/
flutter test test/domain/usecases/crm/
flutter test test/domain/usecases/announcements/
flutter test test/presentation/blocs/
```

### Integration tests (requires supabase local)
```bash
supabase start
flutter test integration_test/
```

### Code coverage
```bash
flutter test --coverage
lcov --summary coverage/lcov.info
# Target: > 70% on new files
```

---

## 4. Portal Next.js

### Unit / Integration
```bash
cd portal

# Install deps (if needed)
npm install

# Run all tests
npm test

# Run specific test files
npx vitest run src/components/sidebar.test.tsx
npx vitest run src/app/api/export/
```

### Playwright E2E
```bash
cd portal

# Install playwright browsers (first time)
npx playwright install

# Run all E2E
npx playwright test

# Run specific test
npx playwright test tests/attendance.spec.ts
npx playwright test tests/auth-guard.spec.ts

# With UI (debug)
npx playwright test --ui

# Generate report
npx playwright show-report
```

### Type check
```bash
cd portal && npx tsc --noEmit
```

### Lint
```bash
cd portal && npx eslint src/ --ext .ts,.tsx
```

---

## 5. Full QA Pipeline (all-in-one)

```bash
#!/bin/bash
set -e

echo "=== 1. DB Migrations ==="
supabase db push

echo "=== 2. Verify Script ==="
npx tsx tools/verify_metrics_snapshots.ts

echo "=== 3. Flutter Tests ==="
cd omni_runner && flutter test && cd ..

echo "=== 4. Portal Tests ==="
cd portal && npm test && cd ..

echo "=== 5. Portal Type Check ==="
cd portal && npx tsc --noEmit && cd ..

echo "=== 6. Portal E2E ==="
cd portal && npx playwright test && cd ..

echo "=== ALL PASSED ==="
```

Save as `scripts/qa_full.sh` and run:
```bash
chmod +x scripts/qa_full.sh
./scripts/qa_full.sh
```
