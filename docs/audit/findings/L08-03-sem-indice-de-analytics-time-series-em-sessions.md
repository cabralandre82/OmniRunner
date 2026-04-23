---
id: L08-03
audit_ref: "8.3"
lens: 8
title: "Sem índice de analytics time-series em sessions"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["migration", "performance"]
files:
  - supabase/migrations/20260218000000_full_schema.sql
  - supabase/migrations/20260421330000_l08_03_sessions_time_series_index.sql
  - tools/audit/check-sessions-time-series-index.ts
  - tools/test_l08_03_sessions_time_series_index.ts
  - package.json
  - docs/runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md
correction_type: migration
test_required: true
tests:
  - tools/test_l08_03_sessions_time_series_index.ts
linked_issues: []
linked_prs:
  - b68e71d
owner: platform-data
runbook: docs/runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L08-03] Sem índice de analytics time-series em sessions
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB
**Personas impactadas:** staff (portal dashboards), anti-cheat sweep
## Achado
— `supabase/migrations/20260218000000_full_schema.sql:79-81` indexa por `user_id, start_time_ms DESC`. Mas queries do tipo "todas sessões da última hora em todos os grupos" (para dashboards realtime CDO) fazem seq scan.
## Correção proposta

—

```sql
CREATE INDEX idx_sessions_start_time_brin
  ON public.sessions USING BRIN (start_time_ms);
-- BRIN é ideal para time-series, 99% menos espaço que B-tree
```

## Correção aplicada (2026-04-21)
Migration `20260421330000_l08_03_sessions_time_series_index.sql`:
- `idx_sessions_start_time_brin USING BRIN (start_time_ms) WITH
  (pages_per_range=32)` — ~8 KiB/1M rows, canonical para range scans em
  dashboards realtime.
- `idx_sessions_status_start_time ON (status, start_time_ms DESC) WHERE
  status >= 3` — btree parcial para "last N finalizadas globally"; a
  predicate assume o invariante L08-04.
- `fn_sessions_has_time_series_indexes()` STABLE SECURITY DEFINER +
  `fn_sessions_assert_time_series_indexes()` raise P0010.
- CI `npm run audit:sessions-time-series-index`.
- 15 integration tests (DDL + privileges + detector/assert + planner).
- Runbook [`SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md`](../../runbooks/SESSIONS_TIME_SERIES_INDEX_RUNBOOK.md)
  documenta `CREATE INDEX CONCURRENTLY` out-of-band para tabelas > 5M
  rows (o `CREATE INDEX` não-concurrent da migration é unsafe em prod
  peak hours).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.3).
- `2026-04-21` — Corrigido (commit `b68e71d`): BRIN + partial btree + detector + assert + CI + runbook.