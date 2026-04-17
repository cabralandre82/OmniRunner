---
id: L12-01
audit_ref: "12.1"
lens: 12
title: "reconcile-wallets-cron existe mas NÃO está agendado"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "mobile", "edge-function", "migration", "cron"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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