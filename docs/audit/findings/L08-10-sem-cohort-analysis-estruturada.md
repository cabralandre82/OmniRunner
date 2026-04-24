---
id: L08-10
audit_ref: "8.10"
lens: 8
title: "Sem cohort analysis estruturada"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
tags: []
files:
  - docs/analytics/COHORT_RETENTION.md
correction_type: spec
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: data+product
runbook: docs/analytics/COHORT_RETENTION.md
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Spec ratified in docs/analytics/COHORT_RETENTION.md:
  analytics.mv_cohort_retention (signup cohorts D1/D7/D30/
  D60/D90/D180 by role) refreshed weekly Sunday 04:00 UTC,
  fed by audit_logs (event_domain in app/workout/assessoria/
  marketplace), exposed via fn_cohort_retention RPC
  (platform_admins only). Sibling mv_paying_cohort_retention
  on first paid event. Implementation lands in 4 follow-up
  migrations tracked separately.
---
# [L08-10] Sem cohort analysis estruturada
> **Lente:** 8 — CDO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Grep não encontrou tabela `cohort_snapshots` nem views de coorte. Análise de retenção D1/D7/D30 feita ad-hoc.
## Correção proposta

— Materialized view `mv_cohort_retention` refresh semanal.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.10).