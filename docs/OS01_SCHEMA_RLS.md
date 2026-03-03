# OS-01 — Schema & RLS: Treinos + Presença

Migration file: `supabase/migrations/20260303400000_training_sessions_attendance.sql`

---

## Table Schemas

### coaching_training_sessions

| Column         | Type            | Constraints                                           |
|----------------|-----------------|-------------------------------------------------------|
| id             | uuid            | PRIMARY KEY, DEFAULT gen_random_uuid()                |
| group_id       | uuid            | NOT NULL, REFERENCES coaching_groups(id) ON DELETE CASCADE |
| created_by     | uuid            | NOT NULL, REFERENCES auth.users(id)                   |
| title          | text            | NOT NULL, CHECK(length(trim(title)) BETWEEN 2 AND 120) |
| description    | text            | —                                                     |
| starts_at      | timestamptz     | NOT NULL                                              |
| ends_at        | timestamptz     | CHECK(NULL OR ends_at > starts_at)                    |
| location_name  | text            | —                                                     |
| location_lat   | double precision| —                                                     |
| location_lng   | double precision| —                                                     |
| status         | text            | NOT NULL, DEFAULT 'scheduled', CHECK IN (scheduled, cancelled, done) |
| created_at     | timestamptz     | NOT NULL, DEFAULT now()                               |
| updated_at     | timestamptz     | NOT NULL, DEFAULT now()                               |

### coaching_training_attendance

| Column         | Type            | Constraints                                           |
|----------------|-----------------|-------------------------------------------------------|
| id             | uuid            | PRIMARY KEY, DEFAULT gen_random_uuid()                |
| group_id       | uuid            | NOT NULL, REFERENCES coaching_groups(id) ON DELETE CASCADE |
| session_id     | uuid            | NOT NULL, REFERENCES coaching_training_sessions(id) ON DELETE CASCADE |
| athlete_user_id| uuid            | NOT NULL, REFERENCES auth.users(id)                   |
| checked_by     | uuid            | NOT NULL, REFERENCES auth.users(id)                   |
| checked_at     | timestamptz     | NOT NULL, DEFAULT now()                               |
| status         | text            | NOT NULL, DEFAULT 'present', CHECK IN (present, late, excused, absent) |
| method         | text            | NOT NULL, DEFAULT 'qr', CHECK IN (qr, manual)          |
| —              | —               | UNIQUE (session_id, athlete_user_id)                  |

---

## Indexes

| Index Name                         | Table                    | Columns                                      |
|------------------------------------|--------------------------|----------------------------------------------|
| idx_training_sessions_group_starts | coaching_training_sessions | (group_id, starts_at DESC)                  |
| idx_training_sessions_group_status_starts | coaching_training_sessions | (group_id, status, starts_at DESC)   |
| idx_attendance_group_session       | coaching_training_attendance | (group_id, session_id)                   |
| idx_attendance_group_athlete_time  | coaching_training_attendance | (group_id, athlete_user_id, checked_at DESC) |

---

## RLS Policy Matrix

| Policy                                | Table     | Action | Who                                   |
|--------------------------------------|-----------|--------|--------------------------------------|
| training_sessions_member_read         | sessions  | SELECT | any group member                      |
| training_sessions_staff_insert        | sessions  | INSERT | admin_master, coach                   |
| training_sessions_staff_update        | sessions  | UPDATE | admin_master, coach                   |
| attendance_staff_read                 | attendance| SELECT | admin_master, coach, assistant        |
| attendance_own_read                   | attendance| SELECT | athlete (self only)                   |
| attendance_staff_insert               | attendance| INSERT | admin_master, coach, assistant        |
| training_sessions_platform_admin_read | sessions  | SELECT | platform admin                        |
| attendance_platform_admin_read        | attendance| SELECT | platform admin                        |

---

## RPC Signatures

| Function                    | Signature                         | Purpose                                        |
|----------------------------|-----------------------------------|------------------------------------------------|
| fn_mark_attendance         | `(uuid, uuid, text)`              | Mark attendance for session/athlete (nonce optional) |
| fn_issue_checkin_token     | `(uuid, int)`                     | Generate nonce + expires_at for QR (TTL in seconds)  |

---

## UNIQUE Constraints & ON CONFLICT

- **uq_attendance_session_athlete** on `(session_id, athlete_user_id)` enforces one attendance record per athlete per session.
- `fn_mark_attendance` uses `INSERT ... ON CONFLICT (session_id, athlete_user_id) DO NOTHING`.
- On conflict: no insert; RPC returns `{ok: true, status: 'already_present'}`.
- On insert: RPC returns `{ok: true, status: 'inserted', attendance_id: uuid}`.
