---
id: L08-05
audit_ref: "8.5"
lens: 8
title: "Views de progressão sem filtro de atletas inativos"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["analytics", "views"]
files:
  - supabase/migrations/20260421310000_l08_05_inactive_athletes_filter.sql
  - tools/test_l08_05_inactive_athletes_filter.ts
  - docs/runbooks/INACTIVE_ATHLETES_VIEWS_RUNBOOK.md
correction_type: code
test_required: true
tests:
  - tools/test_l08_05_inactive_athletes_filter.ts
linked_issues: []
linked_prs:
  - bed5d0c
owner: platform-data
runbook: docs/runbooks/INACTIVE_ATHLETES_VIEWS_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L08-05] Views de progressão sem filtro de atletas inativos
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** ✅ fixed
**Camada:** DB / Analytics
**Personas impactadas:** staff (leaderboard interno), coaching, analytics

## Achado
— `v_user_progression`, `v_weekly_progress` (em 20260221000030). Atletas que pararam há 1 ano continuam sendo agregados no ranking de "atleta mais evoluído", distorcendo baselines.

## Correção aplicada (2026-04-21)
Expansão forward-compatible em vez de `WHERE` destrutivo:
- `v_user_progression` ganha 2 colunas no final (backward-compat):
  - `last_session_at timestamptz` — última sessão verificada (NULL se não houver).
  - `is_active_90d boolean` — TRUE se >= 1 sessão verificada nos últimos 90d.
- `v_user_progression_active_90d` (novo) — fonte canônica para rankings/baselines.
- `v_weekly_progress_active_90d` (novo) — mirror de `v_weekly_progress` filtrado a 90d.
- Helper `fn_is_athlete_active_90d(uuid)` STABLE SECURITY DEFINER, granted a
  `authenticated` + `service_role`, revoked from `anon`.
- Todas as 3 views são `security_invoker = on` (RLS per-query enforced).

Nenhum consumidor atual (`notify-rules`, `streaks_leaderboard_screen`,
`staff_weekly_report_screen`) quebra — eles continuam legítimos (ex.: staff
report mostra atleta cold-start). A migração de cada call-site para
`_active_90d` é um follow-up de UX documentado no runbook.

Runbook: [`INACTIVE_ATHLETES_VIEWS_RUNBOOK.md`](../../runbooks/INACTIVE_ATHLETES_VIEWS_RUNBOOK.md)

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.5).
- `2026-04-21` — Corrigido (commit `bed5d0c`): expansão de colunas + 2 views `_active_90d` + helper + runbook.