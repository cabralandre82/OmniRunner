---
id: L02-14
audit_ref: "2.14"
lens: 2
title: "pg_cron jobs — Lock contention"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["finance", "migration", "cron"]
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
# [L02-14] pg_cron jobs — Lock contention
> **Lente:** 2 — CTO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Todos
## Achado
Migration `20260221000008_clearing_cron.sql` existe. Análise detalhada em [12.x].
## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.14]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.14).