---
id: L21-12
audit_ref: "21.12"
lens: 21
title: "Sem \"team dashboard\" para staff técnica"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["personas", "athlete-pro"]
files:
  - supabase/migrations/20260421630000_l21_12_staff_team_dashboard.sql
  - tools/audit/check-staff-team-dashboard.ts
correction_type: code
test_required: true
tests:
  - tools/audit/check-staff-team-dashboard.ts
linked_issues: []
linked_prs:
  - "local:4bcadf6"
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in 4bcadf6 (J30). Expanded `coaching_members.role`
  CHECK to include `physio`, `nutritionist`, `psychologist`
  without breaking any existing CHECK-bound RLS policy
  (`pg_constraint` introspection drops the existing CHECK
  by name, re-adds the expanded one). `public.role_permissions`
  is the canonical `(role, permission)` matrix — permission
  shape CHECK is `^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$` so
  callers only query well-formed `namespace.action` strings.
  Seeded with the canonical policy (admin_master = everything;
  coach = training + health read + health notes;
  nutritionist = nutrition read/write;
  psychologist = mental read/write;
  physio = health notes write; athlete = read own).
  `fn_is_staff_role` (IMMUTABLE PARALLEL SAFE) abstracts the
  staff membership list so new specialist roles don't need
  every caller rewritten. `fn_role_has_permission` (STABLE
  PARALLEL SAFE, NULL-safe) reads role_permissions and
  returns `COALESCE(granted, FALSE)`. `public.athlete_staff_access`
  is the athlete-controlled, per-(athlete, staff, permission)
  grant (composite PK, `revoked_at >= granted_at` CHECK,
  partial staff index on live rows, athlete-own write RLS +
  staff read of own rows + platform_admin read). Lets an
  athlete open nutrition to ONE nutritionist without
  blanket-enabling every nutritionist in the group.
  `fn_my_role_in_group_ext` returns `{role, is_staff,
  permissions}` jsonb so the portal/mobile render
  role-specific dashboards without N queries. Invariants
  locked by `npm run audit:staff-team-dashboard`.
---
# [L21-12] Sem "team dashboard" para staff técnica
> **Lente:** 21 — Atleta Pro · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach individual vê atleta. Elite tem **equipe**: técnico + fisiologista + fisioterapeuta + nutricionista + psicólogo. Sem roles múltiplos.
## Correção proposta

— `coaching_members.role` ampliar para `['admin_master','coach','assistant','physio','nutritionist','psychologist','athlete']` com permissões granulares em `role_permissions`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[21.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 21 — Atleta Pro, item 21.12).