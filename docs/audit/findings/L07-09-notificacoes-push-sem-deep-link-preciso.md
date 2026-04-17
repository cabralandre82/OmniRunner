---
id: L07-09
audit_ref: "7.9"
lens: 7
title: "Notificações push: sem deep link preciso"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["mobile"]
files:
  - omni_runner/lib/core/push/push_navigation_handler.dart
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
# [L07-09] Notificações push: sem deep link preciso
> **Lente:** 7 — CXO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `omni_runner/lib/core/push/push_navigation_handler.dart` abre a tela home ou última tela. Notificação "Você tem novo workout delivery" não abre direto o item.
## Correção proposta

— Payload push incluir `data: { route: "/workout-delivery/123" }` e handler navegar com `context.go(route)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[7.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 7 — CXO, item 7.9).