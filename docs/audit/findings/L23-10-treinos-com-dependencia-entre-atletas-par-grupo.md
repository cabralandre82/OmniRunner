---
id: L23-10
audit_ref: "23.10"
lens: 23
title: "Treinos com dependência entre atletas (par/grupo)"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["cron", "personas", "coach"]
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
# [L23-10] Treinos com dependência entre atletas (par/grupo)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— "João e Maria correm juntos amanhã, 10 km ritmo base". Hoje são dois workouts separados.
## Correção proposta

— `paired_workouts` tipo com sincronização: se um não confirmar, o outro é avisado.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.10).