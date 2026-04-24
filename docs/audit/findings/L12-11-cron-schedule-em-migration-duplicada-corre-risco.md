---
id: L12-11
audit_ref: "12.11"
lens: 12
title: "cron.schedule em migration duplicada corre risco"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["finance", "mobile", "migration", "cron", "reliability", "fixed", "baseline-ratchet"]
files:
  - tools/audit/check-cron-idempotency.ts
  - tools/audit/baselines/cron-idempotency-baseline.txt
correction_type: code
test_required: true
tests:
  - "npm run audit:cron-idempotency"
linked_issues: []
linked_prs: []
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — baseline-ratchet CI guard:
  tools/audit/check-cron-idempotency.ts scans every supabase/migrations/*.sql
  for `cron.schedule(...)` calls and asserts each one is preceded by an
  idempotency guard: either `IF NOT EXISTS (SELECT 1 FROM cron.job ...)` or
  `BEGIN PERFORM cron.unschedule(...) EXCEPTION WHEN OTHERS THEN NULL; END;`.
  Existing legacy violations (9 entries) grandfathered via baseline file;
  any NEW migration introducing an unguarded cron.schedule fails CI.
  All migrations after 2026-04-19 already use the safe pattern
  (see e.g. 20260421840000_l03_15_expire_stale_deposits.sql).
---
# [L12-11] cron.schedule em migration duplicada corre risco
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Se migration roda 2× (rollback + reapply), `cron.schedule` retorna erro "jobname duplicate". Algumas migrations não usam `IF NOT EXISTS`.
## Correção proposta

— Padrão:

```sql
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'clearing-cron') THEN
    PERFORM cron.schedule('clearing-cron', '0 2 * * *', $job$...$job$);
  END IF;
END $$;
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.11]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.11).