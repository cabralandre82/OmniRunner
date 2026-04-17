---
id: L18-01
audit_ref: "18.1"
lens: 18
title: "Duas fontes da verdade para balance de wallet (wallets.balance_coins vs SUM(coin_ledger))"
severity: critical
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "mobile", "performance", "reliability"]
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
# [L18-01] Duas fontes da verdade para balance de wallet (wallets.balance_coins vs SUM(coin_ledger))
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— O ledger é append-only e canônico; `wallets.balance_coins` é cache mutável. `execute_burn_atomic`, `fn_increment_wallets_batch`, e outros atualizam `wallets` diretamente. `reconcile_all_wallets` corrige drift — mas a existência de drift é o sintoma de arquitetura frágil.
## Risco / Impacto

— Qualquer RPC nova esquecer de atualizar `wallets` = drift silencioso até próximo reconcile (que [12.1] revelou não estar agendado).

## Correção proposta

— Três opções arquiteturais:

1. **Calcular balance sempre** do ledger (view materializada incremental):

```sql
CREATE MATERIALIZED VIEW mv_wallet_balance AS
SELECT user_id, SUM(delta_coins) AS balance_coins,
       MAX(created_at_ms) AS last_ms
FROM coin_ledger GROUP BY user_id;

CREATE UNIQUE INDEX ON mv_wallet_balance(user_id);

-- Incremental refresh not supported natively; use triggers
```

2. **Single gateway function**: toda mutação de wallet passa por `fn_mutate_wallet(user_id, delta, reason, ref_id)` que insere em ledger **e** atualiza wallet atomicamente. Proibir `UPDATE wallets SET balance_coins = ...` via trigger guard:

```sql
CREATE OR REPLACE FUNCTION fn_forbid_direct_wallet_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('app.allow_wallet_mutation', true) != 'yes' THEN
    RAISE EXCEPTION 'Direct wallet mutation forbidden. Use fn_mutate_wallet.';
  END IF;
  RETURN NEW;
END;$$;
CREATE TRIGGER trg_wallet_gate BEFORE UPDATE ON wallets
  FOR EACH ROW EXECUTE FUNCTION fn_forbid_direct_wallet_update();
```

A RPC autorizada faz `SET LOCAL app.allow_wallet_mutation = 'yes'` dentro da transação.

3. **Event sourcing puro**: remove `wallets.balance_coins` completamente. Calcular on-the-fly com index `WHERE user_id = X`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.1).