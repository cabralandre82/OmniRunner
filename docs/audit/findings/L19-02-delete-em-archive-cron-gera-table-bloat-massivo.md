---
id: L19-02
audit_ref: "19.2"
lens: 19
title: "DELETE em archive cron gera table bloat massivo"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "integration", "migration", "performance"]
files:
  - supabase/migrations/20260320000000_strava_time_index_and_partitioning.sql
  - supabase/migrations/20260419110000_l19_archive_via_partition_detach.sql
correction_type: migration
test_required: true
tests:
  - tools/test_l19_dba_health.ts
linked_issues: []
linked_prs:
  - 0893093
owner: platform-data-eng
runbook: docs/runbooks/DBA_BLOAT_AND_INDEX_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Resolvido em 2026-04-19 via migration `20260419110000_l19_archive_via_partition_detach.sql`.

  Implementação:
  - `fn_archive_old_ledger` reescrito para iterar partições mensais de
    `coin_ledger` (criadas em L19-01) e fazer
    `ALTER TABLE ... DETACH PARTITION` →
    `INSERT INTO coin_ledger_archive` →
    `DROP TABLE`. Zero dead tuples na tabela viva, zero VACUUM pressure.
    `lock_timeout=5s`; partições com lock contention são puladas e
    retentadas no próximo ciclo semanal.
  - `fn_archive_old_sessions` reescrito para chunked DELETE (BATCH=250,
    MAX_BATCHES=200, `lock_timeout=2s`, `FOR UPDATE SKIP LOCKED`).
    Sessions ainda não é particionada — eliminação total de bloat
    requer mirror do trabalho L19-01 (partition por `start_time_ms`),
    rastreado como follow-up Wave 2. Por ora o bloat é mitigado por
    tuning agressivo de autovacuum em `sessions`
    (`autovacuum_vacuum_scale_factor=0.05`, `fillfactor=90`).
  - Pre-flight `ALTER TABLE sessions_archive ADD COLUMN IF NOT EXISTS
    total_elevation_m` corrige bug latente introduzido em
    `20260322000000_p0_critical_fixes.sql` (coluna adicionada em
    `sessions` mas não propagada para `sessions_archive` — o archive
    teria explodido em prod no primeiro ciclo com dados elegíveis).

  Cobertura de teste (`tools/test_l19_dba_health.ts`): chamada das
  duas funções idempotente, retorno int, e regression guard de
  schema drift entre `sessions` e `sessions_archive` (via
  `pg_table_columns()` helper).

  Runbook operacional: `docs/runbooks/DBA_BLOAT_AND_INDEX_RUNBOOK.md`.
---
# [L19-02] DELETE em archive cron gera table bloat massivo
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/migrations/20260320000000_strava_time_index_and_partitioning.sql:66` arquiva via `DELETE FROM coin_ledger WHERE …`. Cada delete marca tuples como dead; VACUUM não roda automaticamente em intervalo curto; tabela fica inchada.
## Risco / Impacto

— Até 50% de espaço desperdiçado; queries varrem pages com dead tuples; performance linearmente pior.

## Correção proposta

— Após partitioning ([19.1]), arquivar = `ALTER TABLE coin_ledger DETACH PARTITION ledger_202501`, rename, move. **Zero bloat**.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.2).