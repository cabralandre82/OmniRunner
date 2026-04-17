---
id: L19-10
audit_ref: "19.10"
lens: 19
title: "Sem autovacuum tuning para tabelas hot"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "migration", "observability"]
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
# [L19-10] Sem autovacuum tuning para tabelas hot
> **Lente:** 19 — DBA · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `sessions`, `coin_ledger`, `product_events` crescem rápido. Autovacuum default pode não acompanhar.
## Correção proposta

—

```sql
ALTER TABLE coin_ledger SET (
  autovacuum_vacuum_scale_factor = 0.05,  -- default 0.2
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_vacuum_cost_delay = 10
);
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.10).