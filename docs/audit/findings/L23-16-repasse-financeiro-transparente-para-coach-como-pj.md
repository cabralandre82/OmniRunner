---
id: L23-16
audit_ref: "23.16"
lens: 23
title: "Repasse financeiro transparente para coach como PJ"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["finance", "personas", "coach"]
files: []
correction_type: code
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
# [L23-16] Repasse financeiro transparente para coach como PJ
> **Lente:** 23 — Treinador · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— Coach quer ver: "no mês recebi R$ X bruto; descontadas taxas (Y%), líquido R$ Z; posso sacar quando?". Dashboard financeiro simples.
## Correção proposta

— `/platform/billing/earnings` com breakdown mensal + previsão de saque.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[23.16]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 23 — Treinador, item 23.16).