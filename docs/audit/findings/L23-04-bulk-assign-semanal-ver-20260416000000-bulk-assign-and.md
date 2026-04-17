---
id: L23-04
audit_ref: "23.4"
lens: 23
title: "Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates.sql) sem rollback"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["migration", "personas", "coach"]
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
# [L23-04] Bulk assign semanal (ver 20260416000000_bulk_assign_and_week_templates.sql) sem rollback
> **Lente:** 23 — Treinador · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Migration sugere existência de bulk assign. Se coach atribui errado para 300 atletas, não há "desfazer tudo" atômico.
## Correção proposta

— `bulk_assignments` com `batch_id`; botão "Desfazer último lote" (TTL 1h). Soft-delete em `workout_delivery_items` com flag `undone_by_batch`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.4).