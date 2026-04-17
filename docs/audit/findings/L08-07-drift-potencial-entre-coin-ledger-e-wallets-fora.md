---
id: L08-07
audit_ref: "8.7"
lens: 8
title: "Drift potencial entre coin_ledger e wallets fora do horário do cron"
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
# [L08-07] Drift potencial entre coin_ledger e wallets fora do horário do cron
> **Lente:** 8 — CDO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `reconcile-wallets-cron` roda 1x/dia. Entre reconciliações, drift pode crescer invisível.
## Correção proposta

— Acrescentar check em `check_custody_invariants()`:

```sql
-- ... existing checks, plus:
UNION ALL
SELECT 'wallet_vs_ledger' AS invariant, w.user_id::text,
       jsonb_build_object('wallet', w.balance_coins, 'ledger', COALESCE(sum_delta, 0))
FROM wallets w
LEFT JOIN (
  SELECT user_id, SUM(delta_coins) AS sum_delta FROM coin_ledger GROUP BY user_id
) l ON w.user_id = l.user_id
WHERE w.balance_coins <> COALESCE(l.sum_delta, 0);
```

Health-check captura drift em tempo real (não só 1x/dia).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[8.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 8 — CDO, item 8.7).