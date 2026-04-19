---
id: L12-03
audit_ref: "12.3"
lens: 12
title: "*/5 * * * * crons sem lock — overlap risk"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["cron", "performance"]
files: ["supabase/migrations/20260419100000_l12_cron_overlap_protection.sql"]
correction_type: code
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
  Corrigido em 2026-04-19. Migration `20260419100000_l12_cron_overlap_protection.sql`
  introduz três defesas complementares contra overlap nos jobs `*/5`:

  1. **`public.cron_run_state`** — tabela single-row-per-job com `started_at`,
     `finished_at`, `last_status` (`never_run|running|completed|failed|skipped|timeout`),
     `run_count`, `skip_count`, `last_error`, `last_meta`. Service-role only (RLS
     enabled, no policies). Doubles como surface de observabilidade para ops.

  2. **`fn_cron_should_run` + `fn_cron_mark_started/completed/failed`** —
     state-machine helpers SECURITY DEFINER. `should_run` retorna `false` se
     `started_at > now() - max_runtime_seconds` AND `last_status='running'`,
     bumpando `skip_count`. Se a janela passou, marca `timeout` e libera nova
     execução (recovery automático de orphans).

  3. **Wrappers `fn_*_safe`** — combinam `pg_try_advisory_xact_lock` (mutex
     hard dentro do Postgres, auto-released no fim da transaction) com a
     state-machine acima. Aplicados aos três jobs `*/5`:
     - `fn_expire_queue_entries_safe()`           ← `expire-matchmaking-queue`
     - `fn_process_scheduled_releases_safe()`     ← `process-scheduled-workout-releases`
     - `fn_invoke_lifecycle_cron_safe()`          ← `lifecycle-cron` (HTTP fire)

     A migration faz unschedule+reschedule defensivos para apontar cada cron
     job para o wrapper.

  Para o `lifecycle-cron` (HTTP-fired via `extensions.http`), o advisory lock
  só protege a fase de fire (não a execução do EF). Follow-up: enhancement do
  EF para chamar `fn_cron_mark_started/completed` no entry/exit, fechando o
  loop de observabilidade. Não é blocker porque o EF já é idempotente
  (state-guarded transitions).

  Tests: `tools/test_cron_health.ts` cobre 16 cenários — schema, CHECK
  constraints, helpers state-machine, skip-on-recent / allow-after-timeout,
  wrappers full lifecycle. Todos passam contra Supabase local pós-migration.

  Runbook: `docs/runbooks/CRON_HEALTH_RUNBOOK.md` §2.2 (estado de execução),
  §2.3 (identificar travamento), §3.2 (job travado / skip_count crescendo).
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