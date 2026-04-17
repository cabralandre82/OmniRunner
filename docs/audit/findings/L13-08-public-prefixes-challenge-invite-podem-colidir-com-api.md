---
id: L13-08
audit_ref: "13.8"
lens: 13
title: "PUBLIC_PREFIXES /challenge/, /invite/ podem colidir com /api/challenge/"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L13-08] PUBLIC_PREFIXES /challenge/, /invite/ podem colidir com /api/challenge/
> **Lente:** 13 — Middleware · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `pathname.startsWith("/challenge/")` também retorna `true` para `/challenge/123/admin-only-action`? Se existir, admin action vira pública.
## Correção proposta

— Regex explícito `^/challenge/[a-z0-9-]+$` ou `/challenge` SOMENTE GET.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[13.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 13 — Middleware, item 13.8).