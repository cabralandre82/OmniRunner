---
id: L19-03
audit_ref: "19.3"
lens: 19
title: "Indexes redundantes em sessions"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["portal", "migration", "performance", "reliability"]
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
# [L19-03] Indexes redundantes em sessions
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
—

```79:81:supabase/migrations/20260218000000_full_schema.sql
CREATE INDEX idx_sessions_user ON public.sessions(user_id, start_time_ms DESC);
CREATE INDEX idx_sessions_status ON public.sessions(user_id, status);
CREATE INDEX idx_sessions_verified ON public.sessions(user_id) WHERE is_verified = true;
```

Adicionado depois em `20260303700000_portal_performance_indexes.sql:7`:

```sql
CREATE INDEX idx_sessions_user_start
  ON public.sessions (user_id, start_time_ms DESC);
```
## Correção proposta

— Auditar todos índices duplicados:

```sql
SELECT tablename, array_agg(indexname) AS dups
FROM (
  SELECT tablename, indexname,
         pg_get_indexdef(indexrelid) AS def
  FROM pg_indexes i JOIN pg_stat_user_indexes s ON i.indexname = s.indexrelname
  WHERE schemaname = 'public'
) x
GROUP BY tablename, regexp_replace(def, 'idx_\w+', 'idx_')
HAVING COUNT(*) > 1;
```

Dropar duplicados. Regra de code review: novo index deve ser justificado por query real em `pg_stat_statements`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.3).