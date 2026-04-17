---
id: L22-03
audit_ref: "22.3"
lens: 22
title: "Plano semanal pessoal ausente para solo runner"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["edge-function", "migration", "reliability", "personas", "athlete-amateur"]
files: []
correction_type: code
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
# [L22-03] Plano semanal pessoal ausente para solo runner
> **Lente:** 22 — Atleta Amador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Se amador não tem coach (não faz parte de assessoria paga), sem plano. "Training plan module" (migration 20260407000000, 1500+ linhas) presume coach-driven.
## Risco / Impacto

— 80% dos amadores brasileiros treinam **sem coach**. Produto os exclui.

## Correção proposta

— Plano auto-gerado via Edge Function `generate-fit-workout` (já existe!) + GPT-based "Omni AI Coach" tier freemium:

- Objetivo: "correr 5K sem parar", "melhorar 10K", "meia-maratona em 8 semanas"
- Ajusta semanal baseado em compliance
- Free tier: 1 plano ativo por vez; premium ilimitado

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.3).