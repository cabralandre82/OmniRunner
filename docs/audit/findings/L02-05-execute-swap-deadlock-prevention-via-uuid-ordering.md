---
id: L02-05
audit_ref: "2.5"
lens: 2
title: "execute_swap — Deadlock prevention via UUID ordering"
severity: safe
status: fixed
wave: 3
discovered_at: 2026-04-17
tags: []
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
# [L02-05] execute_swap — Deadlock prevention via UUID ordering
> **Lente:** 2 — CTO · **Severidade:** 🟢 Safe · **Onda:** 3 · **Status:** fixed
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260228170000:231-241` ordena os locks FOR UPDATE por UUID (`v_seller < p_buyer_group_id`). Previne deadlocks clássicos de circular-wait. Bom design.
## Correção proposta

N/A.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.5).