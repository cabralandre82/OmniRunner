---
id: L12-03
audit_ref: "12.3"
lens: 12
title: "*/5 * * * * crons sem lock — overlap risk"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["cron", "performance"]
files: []
correction_type: code
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
# [L12-03] */5 * * * * crons sem lock — overlap risk
> **Lente:** 12 — Cron/Scheduler · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `lifecycle-cron`, `expire-matchmaking-queue`, `process-scheduled-workout-releases` rodam a cada 5 min. Se execução n dura 6 min, execução n+1 começa enquanto n ainda processa mesmos registros → double processing.
## Correção proposta

— Advisory lock:

```sql
CREATE OR REPLACE FUNCTION fn_process_scheduled_releases_safe()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtext('process_scheduled_releases')) THEN
    RAISE NOTICE 'Previous run still in progress; skipping';
    RETURN;
  END IF;
  PERFORM fn_process_scheduled_releases();
END;$$;
```

Chamar a versão `_safe` no cron.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[12.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 12 — Cron/Scheduler, item 12.3).