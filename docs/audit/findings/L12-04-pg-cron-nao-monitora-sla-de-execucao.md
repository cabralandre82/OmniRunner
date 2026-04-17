---
id: L12-04
audit_ref: "12.4"
lens: 12
title: "pg_cron não monitora SLA de execução"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "cron"]
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
# [L12-04] pg_cron não monitora SLA de execução
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `cron.job_run_details` existe mas nenhum dashboard. Se `clearing-cron` falhar 5 dias seguidos, ninguém nota.
## Correção proposta

— Ver [6.4]: `fn_check_cron_health()` + alerta Slack se `minutes_since_success > 2 * schedule_interval_minutes`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.4).