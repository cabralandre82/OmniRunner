---
id: L03-11
audit_ref: "3.11"
lens: 3
title: "Pedido de R$ 0 via cupom 100% (duplica 3.7)"
severity: na
status: duplicate
wave: 3
discovered_at: 2026-04-17
reaudited_at: 2026-04-24
tags: ["finance"]
files: []
correction_type: code
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: unassigned
runbook: null
effort_points: 0
blocked_by: []
duplicate_of: L03-07
deferred_to_wave: null
note: "Re-auditoria 2026-04-24: o próprio título declara duplicidade de 3.7. Consolidado."
---
# [L03-11] Pedido de R$ 0 via cupom 100% (duplica 3.7)
> **Lente:** 3 — CFO · **Severidade:** ⚪ N/A · **Onda:** 3 · **Status:** 🔗 duplicate
**Camada:** —
**Personas impactadas:** —

## Achado original
Achado explicitamente marcado como duplicata de `[3.7]` no relatório inicial.

## Re-auditoria 2026-04-24

Consolidado em [L03-07](./L03-07-cupom-100-pedido-de-0-00.md). Ver análise completa lá:
- Sistema de cupom não existe no codebase.
- CHECK `price_cents > 0` em `billing_products`, `billing_purchases`, `athlete_subscriptions`.
- Stripe API rejeita `unit_amount: 0` em modo `payment`.

## Referência narrativa
Contexto completo em [`docs/audit/parts/02-cto-cfo.md`](../parts/02-cto-cfo.md) — anchor `[3.11]`.

## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.11).
- `2026-04-24` — Re-auditoria consolidou como duplicate de L03-07.
