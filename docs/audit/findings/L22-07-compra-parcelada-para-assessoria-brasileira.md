---
id: L22-07
audit_ref: "22.7"
lens: 22
title: "Compra parcelada para assessoria brasileira"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["migration", "personas", "athlete-amateur"]
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
# [L22-07] Compra parcelada para assessoria brasileira
> **Lente:** 22 — Atleta Amador · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Asaas suporta boleto/PIX parcelado. Stripe apenas cartão. Realidade BR: 60% prefere pagar parcelado/PIX.
## Correção proposta

— Gateway preference: default Asaas para BR; Stripe para internacional. Checkout mostra opções "PIX R$ 120/mês" vs "Cartão 10× R$ 12,50". Já tem módulo billing — confirmar integração ativa.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[22.7]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 22 — Atleta Amador, item 22.7).