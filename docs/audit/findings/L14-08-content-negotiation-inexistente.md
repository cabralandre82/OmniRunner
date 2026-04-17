---
id: L14-08
audit_ref: "14.8"
lens: 14
title: "Content negotiation inexistente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["security-headers", "mobile"]
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
# [L14-08] Content negotiation inexistente
> **Lente:** 14 — Contracts · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Todos endpoints hardcoded `application/json`. Export CSV precisa de endpoint separado `/api/export/...` vs `/api/... (Accept: text/csv)`.
## Correção proposta

— Single endpoint, negocia via `Accept` header. OpenAPI doc descreve.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[14.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 14 — Contracts, item 14.8).