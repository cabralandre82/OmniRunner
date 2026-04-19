---
id: L12-02
audit_ref: "12.2"
lens: 12
title: "Thundering herd em 02:00–04:00 UTC"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "portal", "cron", "ux"]
files: ["supabase/migrations/20260419100001_l12_cron_redistribute_thundering_herd.sql"]
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
  Corrigido em 2026-04-19. Migration `20260419100001_l12_cron_redistribute_thundering_herd.sql`
  faz unschedule + reschedule de 4 jobs para quebrar o cluster 03:00–04:00 UTC:

  - `eval-verification-cron`         : `0 3 * * *`   → `15 3 * * *`   (+15 min)
  - `archive-old-sessions`           : `0 3 * * 0`   → `45 3 * * 0`   (+45 min)
  - `archive-old-ledger`             : `0 4 * * 0`   → `15 5 * * 0`   (+1h15)
  - `coin_ledger_ensure_partition_monthly` : `0 3 1 * *` → `30 5 1 * *` (+2h30, off-cluster)

  Combinado com `reconcile-wallets-daily` (L12-01) em `30 4 * * *`, o novo schedule
  garante ≥15 min de espaçamento mínimo entre quaisquer dois jobs, e ≥30 min entre
  qualquer par no domingo 03:00 UTC (horário sintomático em produção). HTTP body
  preservado bit-for-bit das migrations originais; apenas o cron expression mudou.

  Validação local: `SELECT jobname, schedule FROM cron.job ORDER BY schedule, jobname`
  produz a tabela esperada (12 rows, ver runbook §2.1). Re-execução da migration é
  idempotente (cada bloco unschedule é wrapped em BEGIN/EXCEPTION).

  Runbook: `docs/runbooks/CRON_HEALTH_RUNBOOK.md` §3.5 (regressão da redistribuição).
---
# [L12-02] Thundering herd em 02:00–04:00 UTC
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— 5 jobs agendados entre 02:00 e 04:00 UTC:

| Job | Schedule |
|---|---|
| clearing-cron | 0 2 * * * |
| eval-verification-cron | 0 3 * * * |
| archive-old-sessions | 0 3 * * 0 (dom) |
| archive-old-ledger | 0 4 * * 0 (dom) |
| onboarding-nudge-daily | 0 10 * * * |
| (proposto) reconcile-wallets | 30 4 * * * |

Domingo 03:00 UTC: verification + archive-sessions batem juntos. Archive-sessions provavelmente escaneia tabela `sessions` inteira com `VACUUM`/`DELETE` massivo.
## Risco / Impacto

— DB CPU saturado, queries do portal travadas; atleta domingo cedo sincronizando corrida fica pendente 10 min.

## Correção proposta

— Redistribuir:

```sql
SELECT cron.unschedule('clearing-cron');
SELECT cron.schedule('clearing-cron','0 2 * * *', …);  -- OK
SELECT cron.unschedule('eval-verification-cron');
SELECT cron.schedule('eval-verification-cron','15 3 * * *', …);
SELECT cron.unschedule('archive-old-sessions');
SELECT cron.schedule('archive-old-sessions','45 3 * * 0', …);
SELECT cron.unschedule('archive-old-ledger');
SELECT cron.schedule('archive-old-ledger','15 5 * * 0', …);
```

Mínimo 15 min de espaçamento.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.2).