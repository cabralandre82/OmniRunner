---
id: L01-11
audit_ref: "1.11"
lens: 1
title: "POST /api/workouts/assign, /api/workouts/templates — Autorização cross-athlete"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["mobile", "portal", "migration", "reliability"]
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
# [L01-11] POST /api/workouts/assign, /api/workouts/templates — Autorização cross-athlete
> **Lente:** 1 — CISO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Atleta, Coach
## Achado
Arquivos existem (`ls portal/src/app/api/workouts/assign`), mas conteúdo não foi inspecionado nesta parte. Marcar para reauditoria específica. Padrão esperado: validar que o `athlete_user_id` do body pertence à assessoria do caller (`coaching_members` join com `group_id` do cookie + role `athlete`).
## Correção proposta

Auditar separadamente. Checklist para cada mutação: (a) `requireUser`; (b) `group_id` do cookie; (c) `athlete_user_id` ∈ `coaching_members(group_id, role='athlete')`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[1.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 1 — CISO, item 1.11).