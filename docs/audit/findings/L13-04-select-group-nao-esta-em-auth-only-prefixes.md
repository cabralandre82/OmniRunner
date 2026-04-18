---
id: L13-04
audit_ref: "13.4"
lens: 13
title: "/select-group não está em AUTH_ONLY_PREFIXES nem PUBLIC → comportamento indefinido"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fix_ready_at: 2026-04-17
fixed_at: 2026-04-17
tags: ["portal", "middleware"]
files:
  - portal/src/lib/route-policy.ts
  - portal/src/middleware.ts
correction_type: code
test_required: true
tests:
  - portal/src/lib/route-policy.test.ts
linked_issues: []
linked_prs:
  - "6908546"
owner: platform
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Fixed in commit 6908546. /select-group is now an explicit member of
  the new `AUTH_NO_GROUP_ROUTES` set in `route-policy.ts` and gets a
  dedicated branch in `middleware.ts` that only requires an
  authenticated user — never a portal_group cookie. The previous
  implicit "fall through and bail at line 139" behaviour is gone, so
  any future change to the multi-membership branch can no longer break
  the group-selection page.

  4 unit tests cover the new helper (`isAuthNoGroupRoute` matches only
  `/select-group`, rejects `/select-group/`, sub-paths, and unrelated
  routes; the constant is asserted to contain `/select-group`).
---
# [L13-04] /select-group não está em AUTH_ONLY_PREFIXES nem PUBLIC → comportamento indefinido
> **Lente:** 13 — Middleware · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Lógica de multi-membership (linhas 138-144) redireciona para `/select-group` sem cookie. Na próxima request, middleware vê user autenticado, cookie ausente, e re-entra no branch `!groupId || !role` → `memberships.length > 1` → **redireciona de novo para `/select-group`**. Só retorna `supabaseResponse` se `pathname === "/select-group"` (linha 139).

Isso **funciona**, mas é frágil: se `/select-group` page fizer um `fetch("/api/...")` sem cookie, a API recebe request com `portal_group_id` ausente. API pode retornar 400 ou assumir comportamento inesperado.
## Correção proposta

— Adicionar `/select-group` em `PUBLIC_ROUTES` (exige auth user mas não exige group) e documentar contrato.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.4).