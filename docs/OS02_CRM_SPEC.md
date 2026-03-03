# OS-02 — CRM do Atleta: Especificação Técnica

---

## Migration

`supabase/migrations/20260303500000_crm_tags_notes_status.sql`

---

## Table Schemas

| Table | Columns | Constraints |
|-------|---------|-------------|
| `coaching_tags` | id, group_id, name, color, created_at | UNIQUE(group_id, name) |
| `coaching_athlete_tags` | id, group_id, athlete_user_id, tag_id, created_at | UNIQUE(group_id, athlete_user_id, tag_id) |
| `coaching_athlete_notes` | id, group_id, athlete_user_id, created_by, note, created_at | — |
| `coaching_member_status` | group_id, user_id, status, updated_at, updated_by | PK(group_id, user_id) |

### Details

- **coaching_tags**: `name` CHECK(length 1–60), `color` optional hex `#RRGGBB`
- **coaching_athlete_tags**: FK to `coaching_tags`, `auth.users`
- **coaching_athlete_notes**: `note` CHECK(trim length ≥ 1)
- **coaching_member_status**: `status` IN (`active`, `paused`, `injured`, `inactive`, `trial`)

---

## Indexes

| Name | Table | Columns |
|------|-------|---------|
| idx_tags_group | coaching_tags | (group_id) |
| idx_athlete_tags_group_athlete | coaching_athlete_tags | (group_id, athlete_user_id) |
| idx_athlete_tags_tag | coaching_athlete_tags | (tag_id) |
| idx_athlete_notes_group_athlete_time | coaching_athlete_notes | (group_id, athlete_user_id, created_at DESC) |
| idx_member_status_group | coaching_member_status | (group_id, status) |

---

## RLS Policy Matrix

| Table | Policy | Action | Who |
|-------|--------|--------|-----|
| coaching_tags | tags_staff_read | SELECT | admin_master, coach, assistant |
| coaching_tags | tags_staff_insert | INSERT | admin_master, coach |
| coaching_tags | tags_staff_update | UPDATE | admin_master, coach |
| coaching_tags | tags_staff_delete | DELETE | admin_master, coach |
| coaching_athlete_tags | athlete_tags_staff_read | SELECT | staff |
| coaching_athlete_tags | athlete_tags_staff_insert | INSERT | staff |
| coaching_athlete_tags | athlete_tags_staff_delete | DELETE | staff |
| coaching_athlete_notes | notes_staff_read | SELECT | staff |
| coaching_athlete_notes | notes_staff_insert | INSERT | staff |
| coaching_athlete_notes | notes_staff_delete | DELETE | admin_master, coach |
| coaching_member_status | status_staff_read | SELECT | staff |
| coaching_member_status | status_self_read | SELECT | self (athlete) |
| coaching_member_status | status_staff_upsert | INSERT | admin_master, coach |
| coaching_member_status | status_staff_update | UPDATE | admin_master, coach |

Plus **platform_admin read-all** (`*_platform_admin_read`) for all four tables: `profiles.platform_role = 'admin'`.

---

## Key Security Point

**Athletes CANNOT read `coaching_athlete_notes`** — no SELECT policy for athletes. Notes are staff-only.

---

## RPC

```sql
fn_upsert_member_status(p_group_id uuid, p_user_id uuid, p_status text) RETURNS jsonb
```

- Idempotent: `ON CONFLICT (group_id, user_id) DO UPDATE`
- SECURITY DEFINER, validates caller is admin_master/coach and target is group member
- Returns `{ok: true, status}` or `{ok: false, error}`

---

## UNIQUE Constraints and ON CONFLICT

| Table | Constraint | ON CONFLICT Behavior |
|-------|------------|----------------------|
| coaching_tags | uq_tag_group_name (group_id, name) | Insert fails on duplicate name |
| coaching_athlete_tags | uq_athlete_tag (group_id, athlete_user_id, tag_id) | Insert fails on duplicate assignment |
| coaching_member_status | PK (group_id, user_id) | `fn_upsert_member_status` uses DO UPDATE |
