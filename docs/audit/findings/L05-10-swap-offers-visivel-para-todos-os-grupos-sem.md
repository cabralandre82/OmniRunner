---
id: L05-10
audit_ref: "5.10"
lens: 5
title: "Swap offers: visível para todos os grupos, sem filtro de contraparte"
severity: medium
status: fix-pending
wave: 2
discovered_at: 2026-04-17
tags: ["migration"]
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
# [L05-10] Swap offers: visível para todos os grupos, sem filtro de contraparte
> **Lente:** 5 — CPO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `getOpenSwapOffers(groupId)` retorna ofertas de todos os grupos (inclusive inativos, bloqueados ou com score de risco baixo). Potencialmente vaza preços entre concorrentes diretos.
## Correção proposta

— Adicionar `swap_orders.visibility text DEFAULT 'public' CHECK (visibility IN ('public','private','whitelist'))` e `whitelist_group_ids uuid[]`. UI: seller escolhe quem enxerga.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[5.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 5 — CPO, item 5.10).