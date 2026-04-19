---
id: L12-01
audit_ref: "12.1"
lens: 12
title: "reconcile-wallets-cron existe mas NÃO está agendado"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "security-headers", "mobile", "edge-function", "migration", "cron"]
files: ["supabase/migrations/20260419100002_l12_reconcile_wallets_schedule.sql", "supabase/functions/reconcile-wallets-cron/index.ts"]
correction_type: process
test_required: true
tests: ["tools/test_cron_health.ts"]
linked_issues: []
linked_prs:
  - be1c9e4
owner: platform
runbook: docs/runbooks/CRON_HEALTH_RUNBOOK.md
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Corrigido em 2026-04-19. Migration `20260419100002_l12_reconcile_wallets_schedule.sql`
  registra `cron.schedule('reconcile-wallets-daily', '30 4 * * *', ...)` que dispara
  a Edge Function `reconcile-wallets-cron` via `extensions.http(...)` com bearer
  service-role. Horário (04:30 UTC diário) escolhido para não colidir com a janela
  redistribuída em L12-02 (clearing 02:00, eval-verification 03:15, archive-old-sessions
  03:45-Sun, archive-old-ledger 05:15-Sun, partition-monthly 05:30-day-1).

  A migration também faz seed de `public.cron_run_state` (introduzida em L12-03) com
  `last_status='never_run'` para o job, dando visibilidade imediata em queries de
  inventário ops. A EF não chama `fn_cron_mark_started/completed` ainda — follow-up
  rastreável: instrumentar `reconcile-wallets-cron/index.ts` e os demais EFs para
  reportar lifecycle. Não é blocker porque o job é diário e idempotente (drift
  correction converge para o mesmo resultado em N execuções).

  Validação: `SELECT * FROM cron.job WHERE jobname='reconcile-wallets-daily'` retorna
  1 row pós-migration (verificado local). Tests em `tools/test_cron_health.ts`
  garantem o seed de `cron_run_state`. Runbook: `docs/runbooks/CRON_HEALTH_RUNBOOK.md`
  §2.1 (inventário) e §3.4 (drift residual / disparo manual).
---
# [L12-01] reconcile-wallets-cron existe mas NÃO está agendado
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep -rn "cron.schedule" supabase/migrations/*.sql` lista 10 jobs (`auto-topup-hourly`, `lifecycle-cron`, `clearing-cron`, `eval-verification-cron`, `expire-matchmaking-queue`, `onboarding-nudge-daily`, `archive-old-sessions`, `archive-old-ledger`, `process-scheduled-workout-releases`, `aml-structuring-detect` proposto). **Reconcile-wallets-cron NÃO aparece**. A função `reconcile_all_wallets()` existe (`20260227500000_wallet_reconcile_and_session_retention.sql:109`) e o Edge Function `reconcile-wallets-cron/` existe — mas nenhuma migration `SELECT cron.schedule('reconcile-wallets', ...)`.
## Risco / Impacto

— **Reconciliação nunca roda automaticamente**. Drift entre `wallets.balance_coins` e `SUM(coin_ledger.delta_coins)` acumula indefinidamente. O único mecanismo defensivo citado em runbooks é inexistente em produção.

## Correção proposta

— Nova migration:

```sql
SELECT cron.schedule(
  'reconcile-wallets-daily',
  '30 4 * * *',  -- 04:30 UTC, after archive jobs
  $$
  SELECT extensions.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/reconcile-wallets-cron',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  )$$
);
```

## Teste de regressão

— `SELECT * FROM cron.job WHERE jobname = 'reconcile-wallets-daily'` deve existir em prod.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.1).