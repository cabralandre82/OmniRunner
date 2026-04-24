---
id: L22-12
audit_ref: "22.12"
lens: 22
title: "Streaks (dias consecutivos correndo) sem grace period"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["personas", "athlete-amateur"]
files:
  - docs/product/ATHLETE_AMATEUR_BASELINE.md

correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: product
runbook: docs/product/ATHLETE_AMATEUR_BASELINE.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Coberto em `docs/product/ATHLETE_AMATEUR_BASELINE.md`. Tabela
  `user_streaks` + `streak_events` com 1 grace-day/semana e
  1 shield/mês auto-creditado (max 4). Cron 02:00 local TZ.
  Manual freeze até 30 dias para lesão/viagem. Streak conta
  qualquer atividade movimentada (não só corrida). Wave 4
  fase G.
---
# [L22-12] Streaks (dias consecutivos correndo) sem grace period
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fixed
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