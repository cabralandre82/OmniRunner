---
id: L19-02
audit_ref: "19.2"
lens: 19
title: "DELETE em archive cron gera table bloat massivo"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "integration", "migration", "performance"]
files:
  - supabase/migrations/20260320000000_strava_time_index_and_partitioning.sql
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