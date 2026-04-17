---
id: L08-05
audit_ref: "8.5"
lens: 8
title: "Views de progressão sem filtro de atletas inativos"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: []
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
# [L08-05] Views de progressão sem filtro de atletas inativos
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `v_user_progression`, `v_weekly_progress` (em 20260221000030). Atletas que pararam há 1 ano continuam sendo agregados no ranking de "atleta mais evoluído", distorcendo baselines.
## Correção proposta

— Adicionar `WHERE last_session_at > now() - interval '90 days'` nas views (ou material view com refresh semanal).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.5).