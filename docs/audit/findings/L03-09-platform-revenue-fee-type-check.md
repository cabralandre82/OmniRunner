---
id: L03-09
audit_ref: "3.9"
lens: 3
title: "platform_revenue.fee_type CHECK"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "webhook", "mobile", "migration", "performance", "reliability"]
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
# [L03-09] platform_revenue.fee_type CHECK
> **Lente:** 3 — CFO · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260228170000:11`: CHECK `('clearing', 'swap', 'fx_spread', 'maintenance')` — **não inclui `'billing_split'` nem `'provider_fee'`**. `platform_revenue` insere `fee_type='clearing'`, `'swap'`, `'fx_spread'`. Maintenance é inserido por `asaas-webhook/index.ts:216+` (não totalmente lido). Se `billing_split` for inserido, CHECK rejeita — perda silenciosa.
## Risco / Impacto

Insert falha, erro engolido (várias rotas têm `try/catch`), receita não registrada.

## Correção proposta

Alinhar CHECK de `platform_revenue.fee_type` com `platform_fee_config.fee_type`:
```sql
ALTER TABLE platform_revenue DROP CONSTRAINT platform_revenue_fee_type_check;
ALTER TABLE platform_revenue ADD CONSTRAINT platform_revenue_fee_type_check
  CHECK (fee_type IN ('clearing','swap','maintenance','billing_split','fx_spread','provider_fee'));
```

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.9]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.9).