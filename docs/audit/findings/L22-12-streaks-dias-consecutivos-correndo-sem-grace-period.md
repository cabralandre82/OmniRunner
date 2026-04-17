---
id: L22-12
audit_ref: "22.12"
lens: 22
title: "Streaks (dias consecutivos correndo) sem grace period"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["personas", "athlete-amateur"]
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
# [L22-12] Streaks (dias consecutivos correndo) sem grace period
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Auditoria não encontrou tabela `streaks`. Se existir, provavelmente quebra com "rest day" (ruim para atleta responsável).
## Correção proposta

— Streak = "dias com atividade (correr OU outro treino)". Grace de 1 dia/semana (pausa opcional). Streak shield: 1 por mês para compensar viagem.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.12).