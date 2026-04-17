---
id: L03-07
audit_ref: "3.7"
lens: 3
title: "Cupom 100% / pedido de $0.00"
severity: na
status: fix-pending
wave: 3
discovered_at: 2026-04-17
tags: ["portal", "edge-function", "migration", "ux"]
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
# [L03-07] Cupom 100% / pedido de $0.00
> **Lente:** 3 — CFO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** fix-pending
**Camada:** PORTAL
**Personas impactadas:** Atleta, Plataforma
## Achado
_(sem descrição detalhada — ver relatório original em `docs/audit/parts/`)_
## Correção proposta

Auditar `create-checkout-session` e `create-checkout-mercadopago` Edge Functions. Confirmar que rejeitam `price_cents = 0`.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.7).