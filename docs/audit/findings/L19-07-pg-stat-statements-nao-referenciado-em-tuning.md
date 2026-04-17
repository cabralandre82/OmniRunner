---
id: L19-07
audit_ref: "19.7"
lens: 19
title: "pg_stat_statements não referenciado em tuning"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile"]
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
# [L19-07] pg_stat_statements não referenciado em tuning
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Sem evidência de análise de top-N slow queries. Operações financeiras podem ter queries subótimas silenciosamente.
## Correção proposta

— `CREATE EXTENSION pg_stat_statements` + runbook `DBA_QUERY_TUNING.md` com:

```sql
SELECT query, calls, total_exec_time, mean_exec_time, stddev_exec_time
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY total_exec_time DESC LIMIT 20;
```

Revisão mensal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.7).