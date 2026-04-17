---
id: L08-03
audit_ref: "8.3"
lens: 8
title: "Sem índice de analytics time-series em sessions"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["migration", "performance"]
files:
  - supabase/migrations/20260218000000_full_schema.sql
correction_type: migration
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
# [L08-03] Sem índice de analytics time-series em sessions
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/migrations/20260218000000_full_schema.sql:79-81` indexa por `user_id, start_time_ms DESC`. Mas queries do tipo "todas sessões da última hora em todos os grupos" (para dashboards realtime CDO) fazem seq scan.
## Correção proposta

—

```sql
CREATE INDEX idx_sessions_start_time_brin
  ON public.sessions USING BRIN (start_time_ms);
-- BRIN é ideal para time-series, 99% menos espaço que B-tree
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.3).