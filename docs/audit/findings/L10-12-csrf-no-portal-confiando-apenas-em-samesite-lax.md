---
id: L10-12
audit_ref: "10.12"
lens: 10
title: "CSRF no portal confiando apenas em SameSite=Lax"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "portal", "migration"]
files: []
correction_type: code
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
# [L10-12] CSRF no portal confiando apenas em SameSite=Lax
> **Lente:** 10 — CSO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Cookies `portal_group_id`, `portal_role` com `sameSite: "lax"`. Ataques com navegação top-level (GET) não são bloqueados.
## Correção proposta

— Todas as mutações via POST/PUT/DELETE + verificação de token CSRF anti-forgery (double-submit cookie pattern) nos `api/*` que alteram estado financeiro.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[10.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 10 — CSO, item 10.12).