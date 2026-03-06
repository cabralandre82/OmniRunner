# OS-01 — Schema & RLS: Treinos Prescritos + Cumprimento

> **Atualizado:** 2026-03-04 — DECISAO 134 (auto-attendance)

Migrations:
- `20260303400000_training_sessions_attendance.sql` (tabelas base)
- `20260313000000_auto_attendance.sql` (workout params, auto-avaliação)

---

## Table Schemas

### coaching_training_sessions

| Column           | Type            | Constraints                                           |
|------------------|-----------------|-------------------------------------------------------|
| id               | uuid            | PRIMARY KEY, DEFAULT gen_random_uuid()                |
| group_id         | uuid            | NOT NULL, REFERENCES coaching_groups(id) ON DELETE CASCADE |
| created_by       | uuid            | NOT NULL, REFERENCES auth.users(id)                   |
| title            | text            | NOT NULL, CHECK(length(trim(title)) BETWEEN 2 AND 120) |
| description      | text            | —                                                     |
| starts_at        | timestamptz     | NOT NULL                                              |
| ends_at          | timestamptz     | CHECK(NULL OR ends_at > starts_at)                    |
| location_name    | text            | —                                                     |
| location_lat     | double precision| —                                                     |
| location_lng     | double precision| —                                                     |
| status           | text            | NOT NULL, DEFAULT 'scheduled', CHECK IN (scheduled, cancelled, done) |
| **distance_target_m**  | double precision | — *(distância alvo em metros)*              |
| **pace_min_sec_km**    | double precision | — *(pace mínimo em seg/km)*                 |
| **pace_max_sec_km**    | double precision | — *(pace máximo em seg/km)*                 |
| created_at       | timestamptz     | NOT NULL, DEFAULT now()                               |
| updated_at       | timestamptz     | NOT NULL, DEFAULT now()                               |

### coaching_training_attendance

| Column           | Type            | Constraints                                           |
|------------------|-----------------|-------------------------------------------------------|
| id               | uuid            | PRIMARY KEY, DEFAULT gen_random_uuid()                |
| group_id         | uuid            | NOT NULL, REFERENCES coaching_groups(id) ON DELETE CASCADE |
| session_id       | uuid            | NOT NULL, REFERENCES coaching_training_sessions(id) ON DELETE CASCADE |
| athlete_user_id  | uuid            | NOT NULL, REFERENCES auth.users(id)                   |
| checked_by       | uuid            | **NULLABLE**, REFERENCES auth.users(id) *(NULL para auto)* |
| checked_at       | timestamptz     | NOT NULL, DEFAULT now()                               |
| status           | text            | NOT NULL, DEFAULT 'present', CHECK IN (**present, late, excused, absent, completed, partial**) |
| method           | text            | NOT NULL, DEFAULT 'qr', CHECK IN (**qr, manual, auto**) |
| **matched_run_id** | uuid          | — *(ID da corrida que bateu com o treino)*            |
| —                | —               | UNIQUE (session_id, athlete_user_id)                  |

---

## Indexes

| Index Name                              | Table                       | Columns                                      |
|-----------------------------------------|-----------------------------|----------------------------------------------|
| idx_training_sessions_group_starts      | coaching_training_sessions  | (group_id, starts_at DESC)                   |
| idx_training_sessions_group_status_starts | coaching_training_sessions | (group_id, status, starts_at DESC)           |
| idx_attendance_group_session            | coaching_training_attendance | (group_id, session_id)                      |
| idx_attendance_group_athlete_time       | coaching_training_attendance | (group_id, athlete_user_id, checked_at DESC) |

---

## RLS Policy Matrix

| Policy                                | Table      | Action | Who                                   |
|---------------------------------------|------------|--------|---------------------------------------|
| training_sessions_member_read         | sessions   | SELECT | any group member                      |
| training_sessions_staff_insert        | sessions   | INSERT | admin_master, coach                   |
| training_sessions_staff_update        | sessions   | UPDATE | admin_master, coach                   |
| attendance_staff_read                 | attendance | SELECT | admin_master, coach, assistant        |
| attendance_own_read                   | attendance | SELECT | athlete (self only)                   |
| attendance_staff_insert               | attendance | INSERT | admin_master, coach, assistant        |
| **attendance_system_insert**          | attendance | INSERT | **all (for triggers/service_role)**   |
| **attendance_system_update**          | attendance | UPDATE | **all (for triggers/service_role)**   |
| training_sessions_platform_admin_read | sessions   | SELECT | platform admin                        |
| attendance_platform_admin_read        | attendance | SELECT | platform admin                        |

---

## Functions

| Function                        | Signature                              | Purpose                                        |
|---------------------------------|----------------------------------------|------------------------------------------------|
| fn_mark_attendance              | `(uuid, uuid, text)`                   | Mark attendance (legacy QR, idempotent)        |
| fn_issue_checkin_token          | `(uuid, int)`                          | Generate QR nonce (legacy)                     |
| **fn_evaluate_athlete_training** | `(uuid, uuid, bigint)`                | Avaliar treino: compara 2 próximas corridas    |

### fn_evaluate_athlete_training

- **p_training_id** — ID do treino prescrito
- **p_athlete_user_id** — ID do atleta
- **p_deadline_ms** — Timestamp em ms do próximo treino (opcional)
- **Retorna:** `'completed'`, `'partial'`, ou `NULL` (sem corridas)
- **SECURITY DEFINER**, `search_path = public, pg_temp`
- Faz UPSERT em `coaching_training_attendance` com `ON CONFLICT DO UPDATE WHERE method = 'auto'`

---

## Triggers

| Trigger                       | Table    | Event               | Condition                        | Function                          |
|-------------------------------|----------|----------------------|----------------------------------|-----------------------------------|
| trg_session_auto_attendance   | sessions | AFTER INSERT/UPDATE  | `NEW.status = 3`                | trg_session_evaluate_attendance() |
| trg_training_close_prev       | coaching_training_sessions | AFTER INSERT | `NEW.distance_target_m IS NOT NULL` | trg_training_close_previous() |

---

## UNIQUE Constraints & ON CONFLICT

- **uq_attendance_session_athlete** on `(session_id, athlete_user_id)` enforces one record per athlete per session.
- `fn_evaluate_athlete_training` uses `INSERT ... ON CONFLICT DO UPDATE SET status, method, matched_run_id WHERE method = 'auto'` — never overwrites manual overrides.
- `trg_training_close_prev` uses `INSERT ... ON CONFLICT DO NOTHING` for absent marking.
