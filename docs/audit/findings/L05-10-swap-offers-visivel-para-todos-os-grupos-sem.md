---
id: L05-10
audit_ref: "5.10"
lens: 5
title: "Swap offers: visível para todos os grupos, sem filtro de contraparte"
severity: medium
status: fixed
wave: 2
discovered_at: 2026-04-17
fixed_at: 2026-04-21
closed_at: 2026-04-21
tags: ["migration", "rls", "marketplace", "fixed"]
files:
  - supabase/migrations/20260421800000_l05_10_swap_orders_visibility.sql
  - tools/audit/check-k2-sql-fixes.ts
correction_type: code
test_required: true
tests:
  - supabase/migrations/20260421800000_l05_10_swap_orders_visibility.sql
linked_issues: []
linked_prs:
  - aa816fb
  - 8c62f60
owner: platform
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: null
deferred_to_wave: null
note: |
  K2 batch — swap_orders gains visibility ('public' | 'private' | 'whitelist')
  + whitelist_group_ids uuid[]. Default 'public' preserves legacy behavior;
  sellers concerned about competitor pricing can opt into 'private' (only
  matched buyer sees) or 'whitelist' (only listed groups see). New RLS
  read policy filters accordingly. Companion CHECK ensures whitelist_group_ids
  is empty unless visibility='whitelist'.
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