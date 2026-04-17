---
id: L12-12
audit_ref: "12.12"
lens: 12
title: "Timezone do cron = UTC ok, mas horário DST?"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["cron"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L12-12] Timezone do cron = UTC ok, mas horário DST?
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Brasil aboliu DST em 2019; não é problema. EUA sim — se expandir, crons em horário UTC fixos mudam relação com horário comercial US.
## Correção proposta

— Documentar decisão: "crons sempre UTC; UI local time opcional".

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.12]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.12).