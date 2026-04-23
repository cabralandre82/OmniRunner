---
id: L06-05
audit_ref: "6.5"
lens: 6
title: "Edge Functions sem retry em falha de pg_net"
severity: high
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-21
tags: ["finance", "security-headers", "mobile", "edge-function", "migration", "cron"]
files:
  - "supabase/migrations/20260421230000_l06_05_edge_retry_wrapper.sql"
  - "tools/test_l06_05_edge_retry_wrapper.ts"
  - "docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md"
correction_type: migration
test_required: true
tests:
  - "tools/test_l06_05_edge_retry_wrapper.ts"
  - "supabase/migrations/20260421230000_l06_05_edge_retry_wrapper.sql"
linked_issues: []
linked_prs:
  - "86a3e03"
owner: coo
runbook: "docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md"
effort_points: 3
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L06-05] Edge Functions sem retry em falha de pg_net
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fixed
**Camada:** —
**Personas impactadas:** —
## Achado
— `supabase/migrations/20260221000001_auto_topup_cron.sql:56` usa `pg_net` para chamar Edge Function. Se falhar (timeout, 503), **não há retry automático**; o cron espera o próximo ciclo (1 hora).
## Risco / Impacto

— Auto-topup perde a janela; cliente fica sem moeda; frustração. Pior, `lifecycle-cron` adiar não é crítico, mas `reconcile-wallets-cron` adiar **é**.

## Correção proposta

— Wrapper SQL com retry:

```sql
CREATE OR REPLACE FUNCTION public.fn_invoke_edge_with_retry(
  p_url text, p_body jsonb, p_max_attempts int DEFAULT 3
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_attempt int := 0; v_status int;
BEGIN
  LOOP
    v_attempt := v_attempt + 1;
    SELECT status_code INTO v_status FROM net.http_post(
      url := p_url, body := p_body,
      headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.service_key'))
    );
    EXIT WHEN v_status = 200 OR v_attempt >= p_max_attempts;
    PERFORM pg_sleep(v_attempt * 5);
  END LOOP;
  IF v_status <> 200 THEN
    INSERT INTO cron_failures (job, url, final_status, attempted_at) VALUES (...);
  END IF;
END;$$;
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[6.5]`.

## Correção implementada (2026-04-21, commit `86a3e03`)

Implementação em **6 camadas** (detalhes no runbook
`docs/runbooks/EDGE_RETRY_WRAPPER_RUNBOOK.md`):

1. **`public.cron_edge_retry_attempts`** — append-only audit table,
   uma linha por tentativa HTTP (sucesso E falha). RLS forçado,
   service_role only. Índices forenses `(job_name, started_at DESC)`
   e `(started_at DESC) WHERE http_status IS NULL OR http_status >= 400`
   cobrem as duas queries operacionais principais.
2. **`public.fn_invoke_edge_with_retry(job, endpoint, body,
   max_attempts=3, backoff_base_seconds=5, success_statuses=[2xx])`**
   — SECURITY DEFINER, `lock_timeout=2s`, `search_path` locked.
   Usa `extensions.http` (síncrono — `pg_net.http_post` é async e
   não satisfaz retry). Backoff linear capped em 120s. Records
   EVERY attempt. Em falha final chama `fn_record_cron_health_alert`
   (severity=critical, cooldown=60min) via L06-04 sink. Retorna
   jsonb `{ok, status, attempts, endpoint, last_error?, alert_id?}`.
3. **`public.fn_invoke_edge_fire_and_forget(job, endpoint, body)`**
   — fast path via `pg_net.http_post` para callers que gerenciam
   retry na própria EF. Grava linha única com `meta.mode='async'`.
4. **Reescrita dos 2 wrappers existentes** (`fn_invoke_auto_topup_cron`,
   `fn_invoke_lifecycle_cron_safe`) + **4 novos wrappers**
   (`fn_invoke_clearing_cron_safe`, `fn_invoke_verification_cron_safe`,
   `fn_invoke_onboarding_nudge_safe`, `fn_invoke_reconcile_wallets_safe`)
   — cada um combina advisory-lock + `cron_run_state` lifecycle +
   retry wrapper. Reschedule via `cron.unschedule` + `cron.schedule`
   dentro de DO-block (idempotente em re-apply).
5. **Tolerância a sandbox**: quando `http` extension ausente
   (`CREATE EXTENSION http` não instalado em local) → grava linha
   `meta.mode='skipped'` + retorna `{skipped:true,
   reason:'http_extension_missing'}`. Migration aplica cleanly sem
   pg_cron/http instalados (`IF EXISTS (... cron_run_state ...)`
   guards em DO-blocks).
6. **Self-test DO-block** + **18 integration cases**
   (`tools/test_l06_05_edge_retry_wrapper.ts`) via
   `docker exec psql`: schema/DDL (tabela + 2 índices + RLS + 8
   funções), argument validation (4 casos 22023), runtime behaviour
   (config ausente, http ausente).

**Impacto operacional**: downtime curto da Edge Function agora é
absorvido dentro do mesmo cron window (3 attempts × 5s/10s linear =
~15s extra worst-case) ao invés de propagar para a próxima janela.
Para `reconcile-wallets-daily` isso reduz a janela de drift invisível
de 24h → 0 no happy path de falhas transientes.

**Backwards compat**: additive only — 1 nova tabela, 3 novas funções
base, 4 novos wrappers por-job, 2 wrappers existentes reescritos
(`fn_invoke_auto_topup_cron` e `fn_invoke_lifecycle_cron_safe`) com
assinatura preservada. Zero breaking change.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.5).
- `2026-04-21` — Fix implementado (commit `86a3e03`).
