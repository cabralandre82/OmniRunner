---
id: L02-07
audit_ref: "2.7"
lens: 2
title: "execute_swap — Buyer funding não é lockado corretamente"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "migration", "ux", "reliability"]
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
# [L02-07] execute_swap — Buyer funding não é lockado corretamente
> **Lente:** 2 — CTO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND
**Personas impactadas:** —
## Achado
`20260228170000:229-246`: o seller tem `v_seller_avail < v_amount` verificado, mas o **buyer recebe `v_net` sem checar se o buyer tem USD para pagar**. No modelo atual, buyer recebe a credit `D_buyer += net` *sem* débito correspondente — o swap é uma **cessão de crédito de custódia**, não uma transferência monetária bilateral. Se essa é a intenção de produto (liquidez interclub), OK. Se é uma venda (buyer paga cash fora-do-sistema e recebe backing), **faltam validações**: comprovante externo, aprovação dupla, idempotência por order_id.
## Risco / Impacto

Dependente de regra de negócio. Admin_master do buyer pode aceitar ofertas sem ter USD reais, "inflando" a custódia do clube.

## Correção proposta

Documentar o modelo em ADR. Se é cessão de crédito: adicionar `swap_external_payment_ref` obrigatório no aceite. Se é matching ativo: atrelar ao fluxo Stripe/MP com checkout.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[2.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 2 — CTO, item 2.7).