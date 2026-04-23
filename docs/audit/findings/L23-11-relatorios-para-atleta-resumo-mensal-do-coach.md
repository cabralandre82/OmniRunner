---
id: L23-11
audit_ref: "23.11"
lens: 23
title: "Relatórios para atleta (resumo mensal do coach)"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["mobile", "personas", "coach"]
files:
  - supabase/migrations/20260421390000_l23_11_athlete_monthly_report.sql
  - portal/src/app/api/coaching/athlete-monthly-report/route.ts
  - tools/audit/check-athlete-monthly-report.ts
  - docs/runbooks/ATHLETE_MONTHLY_REPORT_RUNBOOK.md
  - package.json
correction_type: config
test_required: true
tests:
  - tools/audit/check-athlete-monthly-report.ts
linked_issues: []
linked_prs:
  - local:bda6bec
owner: unassigned
runbook: docs/runbooks/ATHLETE_MONTHLY_REPORT_RUNBOOK.md
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L23-11] Relatórios para atleta (resumo mensal do coach)
> **Lente:** 23 — Treinador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach gasta 1h/mês por atleta escrevendo resumo no Google Docs → envia PDF pelo WhatsApp. Produto não automatiza.
## Correção proposta

— `/api/coaching/athlete-monthly-report?user_id&month` gera PDF: volume, evolução pace, pontos fortes, áreas de melhoria, palavra do coach (campo texto editável). Coach revisa + aprova + envia.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.11).
- `2026-04-21` — **Fixed (commit `bda6bec`).** Entrega do pipeline de dados em 5 camadas: (a) tabela `coaching_monthly_notes` com unique `(group_id, user_id, month_start)` + CHECK de month_trunc + 3× CHECKs de comprimento (2 KB cada) + RLS habilitado (todos reads/writes via RPC SECURITY DEFINER); (b) RPC `fn_athlete_monthly_report(p_group_id, p_user_id, p_month_start)` STABLE SECURITY DEFINER com dupla porta de acesso (caller é coach/assistant do grupo E atleta é membro do grupo — previne leak cross-group via spoof de group_id), retorna `jsonb {month_start, generated_at_ms, metrics{volume_km, sessions_count, longest_run_km, avg_pace_sec_km, avg_bpm, days_active, pace_trend_sec_km}, coach_notes}` com `pace_trend_sec_km = second_half_avg − first_half_avg` (negativo = mais rápido na segunda metade) e métricas NULL-safe quando não há amostra; (c) RPC `fn_upsert_monthly_note(...)` VOLATILE SECURITY DEFINER com mesma porta que seta `approved_at = now()` apenas quando os 3 campos livres estão todos preenchidos (signal explícito "pronto para enviar"); (d) route `/api/coaching/athlete-monthly-report` (GET + PUT) com auth gate via `supabase.auth.getUser()`, validação UUID + month YYYY-MM/YYYY-MM-DD, bound de 2048 chars por campo, e **colapsa** `UNAUTHORIZED` + `ATHLETE_NOT_IN_GROUP` em HTTP 401 para não leakar mapa de membership; (e) `fn_athlete_monthly_report_assert_shape()` + self-test DO block como runtime guard com `L23-11 DRIFT:<reason>` markers + CI guard estático `check-athlete-monthly-report.ts` (34 checks) + runbook `ATHLETE_MONTHLY_REPORT_RUNBOOK.md`. **Escopo deliberadamente excluído**: rendering de PDF (follow-up L23-11-pdf que vai consumir o jsonb verbatim sem re-query), CSV export, analytics de quantos relatórios foram marcados `approved_at`, UI de preview coach-side, rate-limit do upsert.
