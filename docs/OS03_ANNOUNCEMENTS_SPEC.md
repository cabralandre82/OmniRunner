# OS-03 — Mural de Avisos: Especificação Técnica

---

## Migration

- **Arquivo:** `supabase/migrations/20260303600000_announcements.sql`

---

## Tables

### coaching_announcements

| Coluna       | Tipo        | Constraints                                                                 |
|-------------|-------------|-----------------------------------------------------------------------------|
| id          | uuid        | PRIMARY KEY, DEFAULT gen_random_uuid()                                      |
| group_id    | uuid        | NOT NULL, REFERENCES coaching_groups(id) ON DELETE CASCADE                  |
| created_by  | uuid        | NOT NULL, REFERENCES auth.users(id)                                        |
| title       | text        | NOT NULL, CHECK (length(trim(title)) >= 2 AND length(trim(title)) <= 200)   |
| body        | text        | NOT NULL, CHECK (length(trim(body)) >= 1)                                   |
| pinned      | boolean     | NOT NULL DEFAULT false                                                      |
| created_at  | timestamptz | NOT NULL DEFAULT now()                                                      |
| updated_at  | timestamptz | NOT NULL DEFAULT now()                                                      |

### coaching_announcement_reads

| Coluna        | Tipo        | Constraints                                              |
|---------------|-------------|----------------------------------------------------------|
| announcement_id | uuid      | NOT NULL, REFERENCES coaching_announcements(id) ON DELETE CASCADE |
| user_id       | uuid        | NOT NULL, REFERENCES auth.users(id)                      |
| read_at       | timestamptz | NOT NULL DEFAULT now()                                  |
| **PRIMARY KEY** | (announcement_id, user_id) | UNIQUE (composite)                        |

---

## Indexes

| Nome                         | Tabela                      | Colunas                                                |
|-----------------------------|-----------------------------|--------------------------------------------------------|
| idx_announcements_group_time | coaching_announcements      | (group_id, created_at DESC)                            |
| idx_announcements_group_pinned | coaching_announcements   | (group_id, pinned DESC, created_at DESC)               |
| idx_announcement_reads_announcement | coaching_announcement_reads | (announcement_id)                     |

---

## RLS Policy Matrix

### coaching_announcements

| Policy                      | Operação | Condição                                                             |
|----------------------------|----------|----------------------------------------------------------------------|
| announcements_member_read  | SELECT   | Membro do grupo (via coaching_members)                               |
| announcements_staff_insert | INSERT   | admin_master ou coach (via coaching_members)                          |
| announcements_staff_update | UPDATE   | admin_master ou coach (via coaching_members)                          |
| announcements_staff_delete | DELETE   | admin_master ou coach (via coaching_members)                          |
| announcements_platform_admin_read | SELECT | platform_role = 'admin' (profiles)                     |

### coaching_announcement_reads

| Policy                | Operação | Condição                                                                 |
|-----------------------|----------|--------------------------------------------------------------------------|
| reads_self_insert     | INSERT   | user_id = auth.uid() e usuário é membro do grupo do anúncio               |
| reads_self_select     | SELECT   | user_id = auth.uid()                                                     |
| reads_staff_select    | SELECT   | Staff (admin_master, coach, assistant) pode ver reads dos avisos do grupo |
| reads_platform_admin_read | SELECT | platform_role = 'admin' (profiles)                                   |

**Total:** 9 políticas de grupo + 2 platform admin.

---

## RPCs

### fn_mark_announcement_read(uuid)

- **Parâmetro:** `p_announcement_id` (uuid)
- **Retorno:** `jsonb` — `{ ok: true }` ou `{ ok: false, error: string }`
- **Erros:** NOT_AUTHENTICATED, ANNOUNCEMENT_NOT_FOUND, NOT_IN_GROUP
- **Comportamento:** Marca o aviso como lido pelo usuário autenticado. Idempotente (ON CONFLICT DO NOTHING).
- **Segurança:** Usuário só pode marcar leitura própria; validação de membership no grupo.

### fn_announcement_read_stats(uuid)

- **Parâmetro:** `p_announcement_id` (uuid)
- **Retorno:** `jsonb` — `{ ok: true, total_members, read_count, read_rate }` ou `{ ok: false, error }`
- **Erros:** NOT_AUTHENTICATED, ANNOUNCEMENT_NOT_FOUND, NOT_STAFF
- **Comportamento:** Retorna contagem de membros, leituras e taxa de leitura.
- **Segurança:** Apenas staff (admin_master, coach, assistant) pode ver estatísticas agregadas.

---

## Security Summary

- **Leitura:** Usuário só pode marcar a própria leitura (validado contra group membership).
- **Estatísticas:** Staff pode ver estatísticas agregadas de leitura por aviso.
