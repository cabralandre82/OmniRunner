# RLS Roles Proof — coaching_members.role

> Auditoria completa de roles, schema drift encontrado, e correção aplicada.

---

## 1. BUG encontrado: Schema Drift (CORRIGIDO)

### Problema original

A constraint `coaching_members_role_check` no baseline (`20260221095517`) permitia apenas:

```sql
CHECK (role IN ('coach', 'assistant', 'athlete'))
```

Porém, todas as migrations posteriores e o app/portal inseriam valores diferentes: `admin_master`, `professor`, `assistente`, `atleta`. A constraint foi provavelmente alterada manualmente em produção, criando schema drift.

### Correção aplicada

**Migration:** `20260303300000_fix_coaching_roles.sql`

Taxonomia canônica (inglês, ASCII, sem acentos):

| # | Role | Tipo | Descrição |
|---|---|---|---|
| 1 | `admin_master` | staff | Dono da assessoria (1 por grupo) |
| 2 | `coach` | staff | Treinador/professor |
| 3 | `assistant` | staff | Assistente de suporte |
| 4 | `athlete` | non-staff | Atleta (entra via invite ou join request) |

**Backfill aplicado:**

| Valor antigo | Valor canônico | Lógica |
|---|---|---|
| `coach` (legacy) | `admin_master` | Apenas para `user_id = coaching_groups.coach_user_id` (dono verificado) |
| `professor` | `coach` | Renomeado |
| `assistente` | `assistant` | Renomeado |
| `atleta` | `athlete` | Renomeado |

**Constraint final:**
```sql
CHECK (role IN ('admin_master', 'coach', 'assistant', 'athlete'))
```

---

## 2. Definição canônica por camada

### 2.1 Banco de dados (Postgres)

- **Constraint:** `coaching_members_role_check` com 4 valores
- **Default:** `'athlete'`
- **coaching_join_requests:** `requested_role CHECK IN ('athlete', 'coach')`

### 2.2 App Flutter (Dart)

**Arquivo:** `omni_runner/lib/core/constants/coaching_roles.dart`

```dart
const String kRoleAdminMaster = 'admin_master';
const String kRoleCoach = 'coach';
const String kRoleAssistant = 'assistant';
const String kRoleAthlete = 'athlete';
```

**Enum:** `omni_runner/lib/domain/entities/coaching_member_entity.dart`

```dart
enum CoachingRole { adminMaster, assistant, athlete, coach }
```

`coachingRoleFromString` aceita valores legacy (`professor`, `assistente`, `atleta`) para compatibilidade, com log de warning para valores desconhecidos.

### 2.3 Portal Next.js

**Arquivo:** `portal/src/lib/roles.ts`

```typescript
export const ROLE = {
  ADMIN_MASTER: "admin_master",
  COACH: "coach",
  ASSISTANT: "assistant",
  ATHLETE: "athlete",
} as const;
```

### 2.4 Edge Functions (Supabase)

Todas as 13 edge functions que fazem role checks usam os valores canônicos.

---

## 3. RLS — conferência completa

### 3.1 RLS do STEP05 (snapshots)

| Policy | Valores usados | Correto? |
|---|---|---|
| `kpis_daily_staff_read` | `admin_master`, `coach`, `assistant` | OK |
| `athlete_kpis_staff_read` | `admin_master`, `coach`, `assistant` | OK |
| `athlete_kpis_own_read` | `auth.uid() = user_id` | OK |
| `alerts_staff_read` | `admin_master`, `coach`, `assistant` | OK |
| `alerts_staff_update` | `admin_master`, `coach`, `assistant` | OK |
| Platform admin policies | `profiles.platform_role = 'admin'` | OK |

### 3.2 RLS existente (migrations anteriores — atualizadas)

| Policy | Valores usados | Correto? |
|---|---|---|
| `baselines_read` | `admin_master`, `coach`, `assistant` | OK |
| `coach_reads_insights` | `admin_master`, `coach`, `assistant` | OK |
| `coach_updates_insights` | `admin_master`, `coach`, `assistant` | OK |
| `coaching_invites_read` | `admin_master`, `coach`, `assistant` | OK |
| `trends_read` | `admin_master`, `coach`, `assistant` | OK |
| custody/clearing/swap | `admin_master`, `coach` | OK |
| `join_requests_select_staff` | `admin_master`, `coach`, `assistant` | OK |
| `join_requests_update_staff` | `admin_master`, `coach` | OK |
| championship_templates (3 policies) | `admin_master`, `coach` | OK |
| `staff_group_member_ids()` | `admin_master`, `coach`, `assistant` | OK |

### 3.3 RLS helper function

`staff_group_member_ids()` — retorna user_ids de membros staff do grupo. Atualizada na migration `20260303300000` para usar valores canônicos.

---

## 4. `profiles.platform_role` (admin da plataforma)

**Separado de `coaching_members.role`.**

```sql
CHECK (platform_role IS NULL OR platform_role IN ('admin'))
```

Usado apenas nas policies de acesso total (`platform_admin_read`). NÃO confundir com roles de coaching.

---

## 5. Segurança: backfill defensivo

A migration `20260303300000` inclui:

- **Tabela de auditoria** (`_role_migration_audit`): registra anomalias (coach rows que NÃO são group owners)
- **Stop condition**: aborta automaticamente se anomalias > threshold (default 10)
- **JOIN-based backfill**: `coach→admin_master` APENAS para `user_id = coaching_groups.coach_user_id`
- **Sem escalação de privilégio**: non-owner `coach` rows ficam como `coach` (trainer)
