---
id: L18-01
audit_ref: "18.1"
lens: 18
title: "Duas fontes da verdade para balance de wallet (wallets.balance_coins vs SUM(coin_ledger))"
severity: critical
status: fixed
wave: 1
discovered_at: 2026-04-17
fixed_at: 2026-04-19
tags: ["finance", "atomicity", "mobile", "performance", "reliability"]
files:
  - "supabase/migrations/20260419130000_l18_wallet_mutation_guard.sql"
correction_type: code
test_required: true
tests:
  - "tools/test_l18_wallet_guard.ts"
linked_issues: []
linked_prs:
  - "dee5791"
owner: principal-eng
runbook: "docs/runbooks/WALLET_MUTATION_GUARD_RUNBOOK.md"
effort_points: 5
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  Arquitetura "guard + gateway" implementada em
  `supabase/migrations/20260419130000_l18_wallet_mutation_guard.sql`.

  • Trigger `trg_wallet_mutation_guard_{insert,update}` em `public.wallets`
    bloqueia qualquer INSERT/UPDATE de balance_coins / pending_coins /
    lifetime_* a menos que a transação tenha definido o GUC de sessão
    `app.wallet_mutation_authorized = 'yes'` (LOCAL, rolled back em commit).
    Bypass tentado direto via REST/SQL retorna `P0007` com mensagem clara.

  • Toda RPC mutadora existente foi re-criada com o `set_config(...,true)`
    como primeira instrução: `increment_wallet_balance`,
    `increment_wallet_pending`, `release_pending_to_balance`,
    `debit_wallet_checked`, `fn_increment_wallets_batch`, `reconcile_wallet`,
    `reconcile_all_wallets`, `execute_burn_atomic`, `fn_switch_assessoria`.
    Surface de comportamento inalterado; tests existentes (1078 portal +
    36 L19 DBA + 22 L18-02 idem + 16 cron-health) continuam verdes.

  • Novo gateway `fn_mutate_wallet(user_id, delta_coins, reason, ref_id,
    issuer_group_id) RETURNS TABLE(ledger_id, new_balance)` é o caminho
    preferencial para código novo: insere ledger row, aplica delta no
    wallet (com lifetime_* derivado do sinal), tudo em uma transação
    atômica atrás do guard. Validações: INVALID_USER_ID, INVALID_DELTA,
    MISSING_REASON (P0001) + check_violation se debit > balance.

  • Coverage: 21 testes em `tools/test_l18_wallet_guard.ts` cobrindo:
    direct UPDATE blocked (3 colunas), INSERT de signup permitido (zero
    counters), todos os 8 RPCs autorizados, gateway happy-path/edge-cases,
    paridade `SUM(ledger) == balance` após N operações.

  • Observação: o `note` column foi removido pela migração L19-01
    (partitioning); o gateway codifica context em `ref_id` (text). Reason
    de reconciliação usa `admin_adjustment` (no allowlist atual).

  • Runbook: `docs/runbooks/WALLET_MUTATION_GUARD_RUNBOOK.md`.
---
# [L18-01] Duas fontes da verdade para balance de wallet (wallets.balance_coins vs SUM(coin_ledger))
> **Lente:** 18 — Principal Eng · **Severidade:** 🔴 Critical · **Onda:** 1 · **Status:** fixed
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