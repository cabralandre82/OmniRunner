---
id: L03-03
audit_ref: "3.3"
lens: 3
title: "execute_withdrawal — total_deposited_usd -= amount_usd não contabiliza fee do provider"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "portal", "migration", "reliability"]
files:
  - portal/src/lib/custody.ts
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
# [L03-03] execute_withdrawal — total_deposited_usd -= amount_usd não contabiliza fee do provider
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** Assessoria, Plataforma
## Achado
`createWithdrawal` (`portal/src/lib/custody.ts:324-370`) calcula `localAmount = convertFromUsdWithSpread(amountUsd - providerFee, fxRate, spreadPct)` — o `providerFeeUsd` reduz o USD antes de converter para local.
  - `execute_withdrawal` (migration 20260228170000:120-123) faz `total_deposited_usd -= v_amount` onde `v_amount = amount_usd = input gross`.
## Risco / Impacto

Buraco contábil: USD some da custódia mas não aparece nem como revenue nem como saque. Invariante contábil quebra no balanço total. CFO não consegue explicar.

## Correção proposta

Inserir em `platform_revenue` também o `provider_fee_usd` (category `'provider_fee'` ou similar) — mesmo que a plataforma só passe esse dinheiro adiante, precisa ser registrado:
```sql
IF v_provider_fee > 0 THEN
  INSERT INTO platform_revenue (fee_type, amount_usd, source_ref_id, group_id, description)
  VALUES ('provider_fee', v_provider_fee, p_withdrawal_id::text, v_group_id, 'Gateway fee on withdrawal');
END IF;
```
Expandir CHECK de `fee_type` para incluir `'provider_fee'`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.3]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.3).