---
id: L23-13
audit_ref: "23.13"
lens: 23
title: "Feedback do atleta (RPE, dor, humor) não requerido"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "personas", "coach"]
files: []
correction_type: code
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
# [L23-13] Feedback do atleta (RPE, dor, humor) não requerido
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `athlete_workout_feedback_screen.dart` existe. Obrigatoriedade variável — coach não pode "forçar" preenchimento (que guia o próximo treino).
## Correção proposta

— Workflow: workout não fica "100% completo" até RPE + humor preenchidos. Badge de bronze por 30 dias de feedback consecutivo.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.13]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.13).