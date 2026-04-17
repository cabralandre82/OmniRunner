---
id: L23-14
audit_ref: "23.14"
lens: 23
title: "\"Corrida de teste\" (time trial) agendada"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["testing", "personas", "coach"]
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
# [L23-14] "Corrida de teste" (time trial) agendada
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Protocolo de teste (3k, 5k, 30min tempo trial) calcula limiar. Sem agendamento/tracking específico.
## Correção proposta

— Workout type `time_trial` com tratamento especial: resultado atualiza automaticamente `athlete_zones` ([21.5]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.14).