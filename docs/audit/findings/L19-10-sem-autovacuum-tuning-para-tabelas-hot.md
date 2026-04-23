---
id: L19-10
audit_ref: "19.10"
lens: 19
title: "Sem autovacuum tuning para tabelas hot"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-23
fixed_at: 2026-04-23
closed_at: 2026-04-23
tags: ["dba", "performance", "sql", "migration"]
files:
  - supabase/migrations/20260421750000_l19_10_autovacuum_hot_tables.sql
  - tools/audit/check-autovacuum-hot-tables.ts
correction_type: schema
test_required: true
tests:
  - tools/audit/check-autovacuum-hot-tables.ts
linked_issues: []
linked_prs: []
owner: platform
runbook: docs/runbooks/CONNECTION_POOLING.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Migration aditiva 20260421750000 aplica
  `autovacuum_vacuum_scale_factor=0.05` /
  `autovacuum_analyze_scale_factor=0.02` /
  `autovacuum_vacuum_cost_delay=10` /
  `autovacuum_vacuum_cost_limit=1000` em 6 tabelas hot:
  `coin_ledger`, `sessions`, `product_events`, `audit_logs`,
  `workout_delivery_items`, `workout_delivery_events`. Idempotente
  (skip quando tabela não existe no env). Self-test verifica que
  ≥1 tabela recebeu o setting. CI guard
  `audit:autovacuum-hot-tables` (16 asserts).
---
# [L19-10] Sem autovacuum tuning para tabelas hot
> **Lente:** 19 — DBA · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** ✅ fixed

## Correção aplicada
Migration aditiva configura autovacuum agressivo (5% threshold em
vez de 20% default) nas 6 tabelas hot identificadas. CI guard
`audit:autovacuum-hot-tables` (16 asserts).

## Histórico
- `2026-04-23` — Fixed via migration + CI guard.
