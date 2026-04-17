---
id: L23-01
audit_ref: "23.1"
lens: 23
title: "Workout delivery em massa sem preview por atleta"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["mobile", "reliability", "personas", "coach"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-01] Workout delivery em massa sem preview por atleta
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `staff_workout_assign_screen.dart` assign workout a atletas. Sem preview individual: "para João, 400 m × 8 (Z4) soa correto? ele reporta dor no tornozelo há 3 dias".
## Risco / Impacto

— Coach de 200 atletas atribui pacote genérico → atleta lesiona → reputação do coach quebra.

## Correção proposta

— Antes de publicar, UI mostra matriz `atleta × alerta`:

- 🟡 João — reportou dor há 3 dias (soft warning)
- 🔴 Maria — TSS acumulado 450 nos últimos 7 dias (overtraining)
- 🟢 Pedro — OK
- ⚪ Ana — sem dados recentes (sem base para opinar)

Coach confirma com 1 clique; ajusta individuais com 2 cliques.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.1).