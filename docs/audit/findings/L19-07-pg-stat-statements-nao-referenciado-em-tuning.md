---
id: L19-07
audit_ref: "19.7"
lens: 19
title: "pg_stat_statements não referenciado em tuning"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "dba"]
files:
  - supabase/migrations/20260421450000_l19_07_pg_stat_statements.sql
  - docs/runbooks/DBA_QUERY_TUNING.md
  - tools/audit/check-pg-stat-statements.ts
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs:
  - local:9fc786f
owner: platform-dba
runbook: docs/runbooks/DBA_QUERY_TUNING.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Migration installs `pg_stat_statements`, exposes a
  service-role-only view `public.v_pg_stat_statements_top`
  (security_invoker, mean ≥ 100 ms, ORDER BY total_exec_time
  DESC) and two SECURITY DEFINER wrappers
  (`fn_pg_stat_statements_top`, `fn_pg_stat_statements_reset`).
  Raw stats are never exposed to anon/authenticated because query
  text can leak literals/PII/service keys. The DBA_QUERY_TUNING
  runbook declares first-Tuesday monthly reviews with a watch/
  breach classification (100 ms / 400 ms thresholds), a P1
  breach playbook with `CREATE INDEX CONCURRENTLY` preference
  and "never rollback finance migrations to fix latency", and a
  reset policy gated behind the review log. 33 invariants
  enforced via `npm run audit:pg-stat-statements`.
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