---
id: L19-01
audit_ref: "19.1"
lens: 19
title: "coin_ledger não é particionada — tabela crescendo sem controle"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "integration", "mobile", "migration", "cron", "performance"]
files:
  - supabase/migrations/20260218000000_full_schema.sql
correction_type: migration
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
# [L19-01] coin_ledger não é particionada — tabela crescendo sem controle
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep "PARTITION" supabase/migrations/*.sql` retorna matches apenas em `strava-time-index-and-partitioning.sql:20-25` que cria **tabela de arquivo** (não partição). O ledger principal:

```274:274:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_ledger_user ON public.coin_ledger(user_id, created_at_ms DESC);
```

é tabela monolítica. Em 2 anos de crescimento com 100k usuários ativos × 50 tx/mês = 120M rows. Reconciliação full scan = horas.
## Risco / Impacto

— Performance degrada; VACUUM bloqueia; backup demora.

## Correção proposta

— Migrar para `PARTITION BY RANGE (created_at_ms)`, partições mensais:

```sql
-- Requires downtime or blue/green table swap
CREATE TABLE coin_ledger_new (LIKE coin_ledger INCLUDING ALL)
  PARTITION BY RANGE (created_at_ms);

-- Create partitions for past 24 months + future 6 months
-- Move data in batches, swap names.
```

Após partition: archive cron move partições antigas para `coin_ledger_archive` via `ATTACH/DETACH` (instantâneo) ao invés de DELETE (lento + bloat).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.1).