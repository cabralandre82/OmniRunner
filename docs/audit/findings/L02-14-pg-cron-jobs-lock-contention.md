---
id: L02-14
audit_ref: "2.14"
lens: 2
title: "pg_cron jobs — Lock contention"
severity: na
status: duplicate
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["finance", "migration", "cron"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: L12-03
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: item umbrella da lente CTO apontando para análise detalhada em L12. Todos os 12 findings L12 já estão fixed. Consolidado como duplicate de L12-03 (crons sem lock — o achado mais específico)."
---
# [L02-14] pg_cron jobs — Lock contention
> **Lente:** 2 — CTO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔗 duplicate
**Camada:** BACKEND
**Personas impactadas:** Todos

## Achado original
Migration `20260221000008_clearing_cron.sql` existe. Análise detalhada em [12.x].

## Re-auditoria 2026-04-24

Este achado é um **apontador umbrella** da lente CTO (L02) para análise detalhada feita na lente Cron/Scheduler (L12). Todos os itens L12 relevantes à lock contention já estão `fixed`:

| Finding | Tema | Status |
|---|---|---|
| [L12-02](./L12-02-thundering-herd-em-02-00-04-00-utc.md) | Thundering herd em 02:00–04:00 UTC — jitter + staggered schedule | ✅ fixed |
| [L12-03](./L12-03-5-crons-sem-lock-overlap-risk.md) | `*/5 * * * *` crons sem lock — overlap risk (advisory lock) | ✅ fixed |
| [L12-06](./L12-06-archive-old-sessions-roda-como-funcao-pesada-sem.md) | archive-old-sessions — batching + DELETE bloat mitigation | ✅ fixed |
| [L12-10](./L12-10-jobs-pg-cron-executam-como-superuser-padrao.md) | Jobs pg_cron executam como superuser — role isolation | ✅ fixed |
| [L12-11](./L12-11-cron-schedule-em-migration-duplicada-corre-risco.md) | cron.schedule duplicada risco de re-run | ✅ fixed |

Marcado como `duplicate_of: L12-03` (o mais específico e que endereça diretamente "lock contention").

## Referência narrativa
Contexto completo em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.14]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.14).
- `2026-04-24` — Re-auditoria consolidou como duplicate de L12-03 (todos os findings L12 de lock/cron já fixed).
