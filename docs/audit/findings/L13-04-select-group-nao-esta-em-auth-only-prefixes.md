---
id: L13-04
audit_ref: "13.4"
lens: 13
title: "/select-group não está em AUTH_ONLY_PREFIXES nem PUBLIC → comportamento indefinido"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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