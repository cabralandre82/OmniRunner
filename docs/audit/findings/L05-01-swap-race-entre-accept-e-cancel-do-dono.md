---
id: L05-01
audit_ref: "5.1"
lens: 5
title: "Swap: race entre accept e cancel do dono da oferta"
severity: critical
status: fix-pending
wave: 0
discovered_at: 2026-04-17
tags: ["finance", "atomicity", "mobile", "portal", "migration", "testing"]
files:
  - portal/src/app/api/swap/route.ts
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
note: "Override manual Onda 1 → Onda 0: heurística de triage não capturou 'fundos transferidos em oferta cancelada' como perda financeira direta, mas trata-se de double-spend por race em operação financeira ativa. Ver TRIAGE.md seção 'Overrides manuais'."
---
# [L05-01] Swap: race entre accept e cancel do dono da oferta
> **Lente:** 5 — CPO · **Severidade:** 🔴 Critical · **Onda:** 0 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `portal/src/app/api/swap/route.ts:117` chama `acceptSwapOffer` e `cancelSwapOffer` sem verificação cruzada. Se Grupo A cria oferta, Grupo B clica em "aceitar" e — no mesmo instante — o Grupo A clica em "cancelar", ambas chamadas tocam `UPDATE swap_orders SET status='…' WHERE id = x`. Quem chegar primeiro "vence", mas não há `FOR UPDATE` ou `status = 'open'` predicate na última vista da migration.
## Risco / Impacto

— Oferta marcada "canceled" mas `execute_swap` já movimentou custódia → fundos transferidos numa oferta "cancelada".

## Correção proposta

— RPCs garantirem:

```sql
CREATE OR REPLACE FUNCTION public.cancel_swap_order(p_order_id uuid, p_group_id uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM swap_orders
    WHERE id = p_order_id AND seller_group_id = p_group_id
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Not your order'; END IF;
  IF v_status <> 'open' THEN RAISE EXCEPTION 'Not open' USING ERRCODE='CS001'; END IF;
  UPDATE swap_orders SET status='canceled', canceled_at=now() WHERE id = p_order_id;
END;$$;
```

E em `execute_swap`: primeiro `SELECT … WHERE status='open' FOR UPDATE` — já existe? Sim (PARTE 2, [2.4]), mas o `cancel` não usa `FOR UPDATE`.

## Teste de regressão

— Teste de concorrência: 2 transactions iniciam, uma faz accept outra cancel → apenas uma sucesso, outra erro `CS001`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.1]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.1).