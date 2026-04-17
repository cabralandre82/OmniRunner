---
id: L19-05
audit_ref: "19.5"
lens: 19
title: "Falta FOR UPDATE NOWAIT em funções de lock crítico"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "atomicity"]
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
# [L19-05] Falta FOR UPDATE NOWAIT em funções de lock crítico
> **Lente:** 19 — DBA · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `execute_burn_atomic` faz `SELECT … FOR UPDATE` — se outra transação bloquear, espera indefinidamente (até `statement_timeout` se configurado). Em cenário de contenção alta, filas de requests se acumulam.
## Correção proposta

—

```sql
-- Explicit timeout per lock
SELECT balance_coins INTO v_wallet_balance
FROM public.wallets
WHERE user_id = p_user_id
FOR UPDATE NOWAIT;
-- If lock not obtained → raises 55P03 lock_not_available
EXCEPTION WHEN lock_not_available THEN
  RAISE EXCEPTION 'Wallet busy, retry' USING ERRCODE = 'W001';
```

Client retries with backoff ou return 429 imediato.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[19.5]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 19 — DBA, item 19.5).