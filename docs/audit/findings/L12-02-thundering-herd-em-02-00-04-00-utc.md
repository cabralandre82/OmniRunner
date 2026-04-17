---
id: L12-02
audit_ref: "12.2"
lens: 12
title: "Thundering herd em 02:00–04:00 UTC"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "portal", "cron", "ux"]
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