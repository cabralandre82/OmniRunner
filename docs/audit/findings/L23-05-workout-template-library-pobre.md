---
id: L23-05
audit_ref: "23.5"
lens: 23
title: "Workout template library pobre"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "migration", "personas", "coach"]
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
# [L23-05] Workout template library pobre
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `staff_workout_templates_screen.dart` existe. Coach de assessoria nova começa do zero. Sem biblioteca pré-populada (fartlek clássicos, treino limiar, tempo run, etc).
## Correção proposta

— `workout_templates_library` seeded em migration com 50+ treinos canônicos (Daniels, Pfitzinger, Hudson). Coach clona e customiza.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.5).