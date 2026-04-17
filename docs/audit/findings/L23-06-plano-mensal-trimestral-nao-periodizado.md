---
id: L23-06
audit_ref: "23.6"
lens: 23
title: "Plano mensal/trimestral não periodizado"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["personas", "coach"]
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
# [L23-06] Plano mensal/trimestral não periodizado
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Módulo `training-plan` (1500 linhas) presumivelmente lida com plans. Auditoria rápida não confirma **periodização** (base → build → peak → taper).
## Correção proposta

— Template wizard: "Meia-maratona em 12 semanas" gera periodização automática ajustada ao atleta. Coach edita blocks (não workouts individuais) — escala.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.6).