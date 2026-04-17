---
id: L02-02
audit_ref: "2.2"
lens: 2
title: "execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "migration", "cron", "testing"]
files:
  - supabase/migrations/20260228160001_burn_plan_atomic.sql
correction_type: migration
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
# [L02-02] execute_burn_atomic — Exceções engolidas em custody_release_committed e settle_clearing
> **Lente:** 2 — CTO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** BACKEND (Supabase RPC)
**Personas impactadas:** Plataforma, Assessoria
## Achado
`supabase/migrations/20260228160001_burn_plan_atomic.sql:159-163, 182-186`:
  ```sql
  BEGIN
    PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
  EXCEPTION WHEN OTHERS THEN
    NULL; -- Custody not yet active for this club
  END;
  -- ...
  BEGIN
    PERFORM public.settle_clearing(v_settlement_id);
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  ```
  Silenciar `WHEN OTHERS` inclui `deadlock_detected`, `connection_exception`, constraint violations, check_custody_invariants, OUT OF MEMORY, etc. O atleta é creditado pelo burn, o coin_ledger é atualizado, mas o `total_committed` do clube emissor permanece inflado → **invariante R_i vs M_i quebrada**.
## Risco / Impacto

Violação direta da invariante central do modelo de custódia. `check_custody_invariants` eventualmente detecta e bloqueia operações futuras (linhas 302-321), mas o atleta já consumiu suas coins e a assessoria emissora fica com passivo "fantasma" (R elevado).

## Correção proposta

Capturar exceções específicas apenas (connection / undefined_function) para compatibilidade com clubes sem custody:
  ```sql
  BEGIN
    PERFORM public.custody_release_committed(v_issuer, v_issuer_balance);
  EXCEPTION
    WHEN undefined_function THEN NULL;  -- RPC não existe (legacy)
    WHEN OTHERS THEN RAISE;             -- re-raise para abortar a transação
  END;
  ```
  - Para settle_clearing: remover o bloco EXCEPTION — deixar falhar. Se settlement falha, a transação toda rollback (burn não processado). Alternativa: inserir `clearing_settlements` com status `'pending_retry'` e cron faz retries.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.2]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.2).