---
id: L23-07
audit_ref: "23.7"
lens: 23
title: "Análise coletiva (grupo) limitada"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["personas", "coach"]
files:
  - supabase/migrations/20260421380000_l23_07_group_analytics_overview.sql
  - portal/src/app/api/platform/analytics/group-overview/route.ts
  - tools/audit/check-group-analytics.ts
  - docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/audit/check-group-analytics.ts
linked_issues: []
linked_prs:
  - local:fdda9e9
owner: unassigned
runbook: docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-07] Análise coletiva (grupo) limitada
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `coaching_kpis_daily` tem total. Coach quer:

- Distribuição de volume semanal (gráfico de cauda)
- Atletas correndo mais do que recomendado
- Atletas não correndo (attrition risk)
- Progresso coletivo vs mês anterior
## Correção proposta

— Views materializadas + `/platform/analytics/group-overview`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.7).
- `2026-04-21` — Fixed via commit `fdda9e9`. On-demand SECURITY DEFINER RPC
  `fn_group_analytics_overview(group_id, window_days)` returns jsonb with
  volume_distribution/overtraining/attrition_risk/collective_progress;
  caller must be coach/assistant; window_days clamped to [7,180]; auth-gated
  route `/api/platform/analytics/group-overview`; 23-check CI guard
  (`audit:group-analytics`) + runtime shape guard
  `fn_group_analytics_assert_shape()`; runbook
  `docs/runbooks/GROUP_ANALYTICS_RUNBOOK.md`.