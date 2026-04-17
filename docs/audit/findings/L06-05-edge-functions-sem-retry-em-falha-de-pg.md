---
id: L06-05
audit_ref: "6.5"
lens: 6
title: "Edge Functions sem retry em falha de pg_net"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "security-headers", "mobile", "edge-function", "migration", "cron"]
files:
  - supabase/migrations/20260221000001_auto_topup_cron.sql
correction_type: migration
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
# [L06-05] Edge Functions sem retry em falha de pg_net
> **Lente:** 6 — COO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
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
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 6 — COO, item 6.5).