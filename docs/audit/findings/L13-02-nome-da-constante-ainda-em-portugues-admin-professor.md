---
id: L13-02
audit_ref: "13.2"
lens: 13
title: "Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES)"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "middleware", "naming"]
files:
  - portal/src/lib/route-policy.ts
  - portal/src/middleware.ts
  - portal/src/app/api/verification/evaluate/route.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy.test.ts
linked_issues: []
linked_prs:
  - "commit:810d4d9"
owner: portal
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido junto com L13-01:

    - Constante `ADMIN_PROFESSOR_ROUTES` renomeada para
      `ADMIN_COACH_ROUTES` em `portal/src/lib/route-policy.ts`,
      alinhada com a migration
      `20260304050000_fix_coaching_role_mismatch.sql`.
    - Comentário stale em
      `portal/src/app/api/verification/evaluate/route.ts:14`
      atualizado para `coach` (o código já usa o valor novo desde a
      migration; só o comentário estava desatualizado).
    - Adicionado type-guard `isStaffRole()` exportado de
      `route-policy.ts` que rejeita explicitamente o valor legado
      `professor`. O middleware usa esse guard antes de gravar o
      cookie `portal_role`, convertendo qualquer regressão de migração
      em 403 hard em vez de elevação silenciosa de privilégio.
    - Strings PT-BR voltadas ao usuário ("professores e assistentes"
      em `no-access/page.tsx` e `settings/page.tsx`) foram mantidas
      intencionalmente — são UX language, não dívida técnica.

  Commit `810d4d9`.
---
# [L13-02] Nome da constante ainda em português (ADMIN_PROFESSOR_ROUTES)
> **Lente:** 13 — Middleware · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Linha 23 ainda usa `PROFESSOR`, apesar da migration `20260304050000_fix_coaching_role_mismatch.sql` renomear role `professor → coach`. É inconsistência que revela que a migração não foi propagada ao código TypeScript.
## Risco / Impacto

— Dev novo vai procurar `ADMIN_COACH_ROUTES`, não encontra, implementa errado. Sintoma de **debt semântico** generalizado (verificar outros lugares).

## Correção proposta

— Rename + grep do repo inteiro:

```bash
rg -l "professor|assessoria|assistente" portal/src omni_runner/lib supabase
```

Mapear legacy Portuguese → English consistently.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.2).