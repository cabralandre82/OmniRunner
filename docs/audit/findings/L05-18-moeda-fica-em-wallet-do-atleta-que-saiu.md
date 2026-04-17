---
id: L05-18
audit_ref: "5.18"
lens: 5
title: "Moeda fica em wallet do atleta que saiu do grupo"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "migration"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: null
---
# [L05-18] Moeda fica em wallet do atleta que saiu do grupo
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Quando atleta deixa o grupo (`DELETE FROM coaching_members`), `wallets.balance_coins` permanece. Atleta queima a moeda após saída → clearing com grupo-ex-emissor complica.
## Correção proposta

— Migration:

```sql
CREATE OR REPLACE FUNCTION fn_handle_athlete_leaves(p_user_id uuid, p_group_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_coins_from_group int;
BEGIN
  SELECT COALESCE(SUM(delta_coins), 0) INTO v_coins_from_group
  FROM coin_ledger WHERE user_id = p_user_id AND issuer_group_id = p_group_id AND delta_coins > 0;
  -- Option A: burn at group's expense (credit group with release)
  -- Option B: mark wallet-group link, redirect future burns to old group
  -- Choose A per business rules.
  -- Implementation omitted; needs product decision.
END;$$;
```

Precisa de decisão de produto antes de implementar.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.18]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.18).