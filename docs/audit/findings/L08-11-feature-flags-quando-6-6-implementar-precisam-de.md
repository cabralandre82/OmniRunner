---
id: L08-11
audit_ref: "8.11"
lens: 8
title: "Feature flags (quando [6.6] implementar) precisam de metrics"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: []
files: []
correction_type: code
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
# [L08-11] Feature flags (quando [6.6] implementar) precisam de metrics
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Implementação proposta sem auditar quem mudou e quando.
## Correção proposta

— Trigger em `feature_flags` gravando `audit_logs(action='feature_flag.toggled', …)`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.11).