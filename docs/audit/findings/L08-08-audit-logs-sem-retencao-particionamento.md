---
id: L08-08
audit_ref: "8.8"
lens: 8
title: "audit_logs sem retenção / particionamento"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["lgpd", "migration", "cron", "reliability"]
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
# [L08-08] audit_logs sem retenção / particionamento
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Tabela cresce indefinidamente. Sem particionamento por mês.
## Risco / Impacto

— Após 2 anos: 100M+ rows, queries de compliance levam minutos, backups inchados.

## Correção proposta

—

```sql
-- Partition by month
CREATE TABLE audit_logs_new (...) PARTITION BY RANGE (created_at);
-- Migrate data; create 24 monthly partitions ahead.
-- pg_cron: drop partitions older than 2 years (LGPD justifica retenção por auditoria fiscal; 5 anos para dados fiscais).
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.8).