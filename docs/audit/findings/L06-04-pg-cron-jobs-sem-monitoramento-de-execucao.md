---
id: L06-04
audit_ref: "6.4"
lens: 6
title: "pg_cron jobs sem monitoramento de execução"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "migration", "cron", "reliability"]
files: []
correction_type: process
test_required: true
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L06-04] pg_cron jobs sem monitoramento de execução
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `grep "cron.schedule" supabase/migrations/*.sql` lista: `auto_topup_cron`, `lifecycle_cron`, `clearing_cron`, `verification_cron`, `swap_expire`, `reconcile-wallets-cron`. Não há tabela `cron_job_runs` registrando sucesso/falha. `cron.job_run_details` existe em pg_cron mas:

- Nenhum alerta quando job falha por > 2 ciclos seguidos
- Nenhum dashboard mostrando última execução de cada job
## Risco / Impacto

— `reconcile-wallets-cron` para; ninguém nota; drift acumula 3 meses → auditoria revela US$ 50k faltantes.

## Correção proposta

—

```sql
CREATE OR REPLACE FUNCTION public.fn_check_cron_health()
RETURNS TABLE(jobname text, last_success timestamptz, minutes_since_success numeric, status text)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT
    j.jobname,
    MAX(r.end_time) FILTER (WHERE r.status='succeeded') AS last_success,
    EXTRACT(EPOCH FROM (now() - MAX(r.end_time) FILTER (WHERE r.status='succeeded')))/60,
    CASE
      WHEN MAX(r.end_time) FILTER (WHERE r.status='succeeded') < now() - interval '2 hours' THEN 'STALE'
      WHEN BOOL_OR(r.status='failed' AND r.end_time > now() - interval '1 hour') THEN 'FAILING'
      ELSE 'OK'
    END
  FROM cron.job j
  LEFT JOIN cron.job_run_details r ON r.jobid = j.jobid
  GROUP BY j.jobname;
$$;
```

Incluir em `/api/internal/health-detailed` (ver [6.2]).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.4]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.4).