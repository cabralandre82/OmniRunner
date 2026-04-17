---
id: L19-06
audit_ref: "19.6"
lens: 19
title: "JSONB em audit_logs.metadata sem índice GIN"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["performance"]
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
# [L19-06] JSONB em audit_logs.metadata sem índice GIN
> **Lente:** 19 — DBA · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Queries "todos eventos do request_id X" fazem seq scan.
## Correção proposta

—

```sql
CREATE INDEX CONCURRENTLY idx_audit_logs_metadata_gin
  ON public.audit_logs USING GIN (metadata jsonb_path_ops);

-- query patterns:
-- WHERE metadata @> '{"request_id": "..."}'
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.6]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.6).