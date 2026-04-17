---
id: L12-11
audit_ref: "12.11"
lens: 12
title: "cron.schedule em migration duplicada corre risco"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "mobile", "migration", "cron", "reliability"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
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