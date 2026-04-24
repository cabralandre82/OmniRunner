---
id: L12-12
audit_ref: "12.12"
lens: 12
title: "Timezone do cron = UTC ok, mas horário DST?"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["cron", "timezone", "docs", "fixed"]
files:
  - docs/runbooks/CRON_TIMEZONE_POLICY.md
correction_type: docs
test_required: false
tests: []
linked_issues: []
linked_prs:
  - 99ac6c7
  - 69db409
owner: platform
runbook: docs/runbooks/CRON_TIMEZONE_POLICY.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K4 batch — codified the policy that pg_cron schedules are ALWAYS
  in UTC. Calendar-aware cutoffs (e.g. "settle today's clearing")
  resolve `now()` against `America/Sao_Paulo` inside the helper
  function the cron invokes, never inside the schedule string.
  DST is irrelevant for Brazil today; the runbook documents the
  US/EU expansion checklist (per-tenant `business_timezone`
  column, helper invocation, NO change to the cron schedule).
  Cross-references `fn_clearing_cutoff_utc` (L12-08) and
  `fn_should_send_nudge_now` (L12-07) as canonical examples.
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