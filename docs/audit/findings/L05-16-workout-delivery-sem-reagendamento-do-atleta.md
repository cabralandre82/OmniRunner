---
id: L05-16
audit_ref: "5.16"
lens: 5
title: "Workout delivery: sem reagendamento do atleta"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["ux"]
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
# [L05-16] Workout delivery: sem reagendamento do atleta
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `workout_delivery_items` permite coach marcar "treino de hoje". Atleta machuca tornozelo, precisa mover para amanhã. Não há endpoint/UI.
## Correção proposta

— Campo `athlete_requested_date date` + fluxo de aceite do coach (notificação push).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.16).