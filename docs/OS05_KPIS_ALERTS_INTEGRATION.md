# OS-05 — Integração KPIs/Alerts com OS-01/02/03

## Objetivo

Acoplar os dados de presença (OS-01) e CRM (OS-02) aos snapshots e alertas do PASSO 05, sem criar outro motor de compute.

## Migration

`supabase/migrations/20260303800000_kpi_attendance_integration.sql`

## 1. Novas Colunas em `coaching_kpis_daily`

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `attendance_sessions_7d` | `integer` | Treinos (não cancelados) nos últimos 7 dias |
| `attendance_checkins_7d` | `integer` | Check-ins de presença nos últimos 7 dias |
| `attendance_rate_7d` | `numeric(5,2)` | `checkins / (sessions * total_athletes) * 100` |

A rate é `NULL` quando não há treinos ou atletas (divisão por zero evitada).

## 2. Compute: `compute_coaching_kpis_daily` (atualizado)

A função set-based agora inclui um `LEFT JOIN LATERAL` extra que consulta `coaching_training_sessions` + `coaching_training_attendance` para o window de 7 dias:

```sql
LEFT JOIN LATERAL (
  SELECT
    count(DISTINCT ts.id) AS training_sessions_7d,
    count(DISTINCT ta.id) AS checkins_7d
  FROM coaching_training_sessions ts
  LEFT JOIN coaching_training_attendance ta ON ta.session_id = ts.id
  WHERE ts.group_id = g.id
    AND ts.starts_at >= v_7d_start_ts
    AND ts.starts_at < v_day_start_ts + interval '1 day'
    AND ts.status != 'cancelled'
) att ON true
```

- **Set-based**: zero loops, single INSERT...SELECT across all groups
- **Idempotente**: `ON CONFLICT (group_id, day) DO UPDATE SET`
- **D-1**: compute sempre para "ontem", dia fechado

## 3. Novo Alerta: `missed_trainings_14d`

Adicionado ao `compute_coaching_alerts_daily`:

| Campo | Valor |
|-------|-------|
| `alert_type` | `missed_trainings_14d` |
| `severity` | `critical` se `risk_level = 'high'`, senão `warning` |
| **Condição** | Atleta com 0 presenças em 14 dias E grupo teve >= 2 treinos no período |

### Lógica

```sql
FROM coaching_members cm
JOIN LATERAL (
  SELECT count(*) AS session_count
  FROM coaching_training_sessions ts
  WHERE ts.group_id = cm.group_id
    AND ts.starts_at >= v_14d_start_ts AND ts.status != 'cancelled'
) gs ON gs.session_count >= 2
LEFT JOIN LATERAL (
  SELECT count(*) AS att_count
  FROM coaching_training_attendance ta
  JOIN coaching_training_sessions ts ON ts.id = ta.session_id
  WHERE ta.athlete_user_id = cm.user_id AND ta.group_id = cm.group_id
    AND ts.starts_at >= v_14d_start_ts
) att ON true
WHERE cm.role = 'athlete' AND coalesce(att.att_count, 0) = 0
ON CONFLICT DO NOTHING
```

- **Combina com score**: se o atleta já tem `risk_level = 'high'`, severity é `critical`
- **Idempotente**: `ON CONFLICT (group_id, user_id, day, alert_type) DO NOTHING`

## 4. Verify Script Atualizado

`tools/verify_metrics_snapshots.ts` (v2) agora inclui:

### Seed data adicional
- 3 training sessions (ontem, D-2, D-5) no Group A
- 2 attendance records para Athlete A1 (2/3 treinos)
- 0 attendance para Athlete A2 (missed all)
- 1 assistant member para testar total_coaches

### Novos assertions

| Assertion | Valor esperado |
|-----------|---------------|
| `attendance_sessions_7d` (Group A) | 3 |
| `attendance_checkins_7d` (Group A) | 2 |
| `attendance_rate_7d` (Group A) | ≈ 33.33% (2 / (3 * 2)) |
| `attendance_sessions_7d` (Group B) | 0 |
| `attendance_rate_7d` (Group B) | null |
| `missed_trainings_14d` alert (Athlete A2) | 1 |
| `missed_trainings_14d` alert (Athlete A1) | 0 (attended) |
| Idempotency: attendance fields unchanged | exact match |
| Idempotency: missed alert count = 1 after re-run | no duplicates |

### Execução

```bash
npx tsx tools/verify_metrics_snapshots.ts
```

## 5. Regras Fase 0

- **Tenant**: todas as queries filtram por `group_id`
- **Roles canônicos**: `admin_master`, `coach`, `assistant`, `athlete`
- **UNIQUE + ON CONFLICT**: attendance com `UNIQUE(session_id, athlete_user_id)`, alerts com `UNIQUE(group_id, user_id, day, alert_type)`
- **D-1**: compute prefere dia fechado (ontem)
- **Set-based**: zero loops, single INSERT...SELECT

## 6. Impacto nos Dashboards

### Portal `/engagement` (OS-04)
- Agora pode exibir `attendance_rate_7d` como KPI card
- Trend chart pode plotar attendance_rate ao longo dos dias

### Portal `/risk` (OS-04)
- `missed_trainings_14d` aparece automaticamente na lista de alertas
- Combina com `athlete_high_risk` para visão unificada de risco

### Portal `/attendance-analytics` (OS-04)
- Pode usar `attendance_sessions_7d` e `attendance_checkins_7d` do snapshot como cache
- Fallback: query direta nas tabelas de training

## 7. Rollback

```sql
-- Remove new columns (safe, doesn't affect existing data)
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_sessions_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_checkins_7d;
ALTER TABLE coaching_kpis_daily DROP COLUMN IF EXISTS attendance_rate_7d;

-- Restore original compute functions from PATCH_SET_BASED.sql
-- (re-run docs/PATCH_SET_BASED.sql to revert function definitions)
```
