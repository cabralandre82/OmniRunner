---
id: L18-08
audit_ref: "18.8"
lens: 18
title: "Edge Functions vs Route Handlers — responsabilidade duplicada"
severity: high
status: fix-pending
wave: 1
discovered_at: 2026-04-17
tags: ["finance", "mobile", "portal", "edge-function"]
files:
  - portal/src/app/api/distribute-coins/route.ts
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
# [L18-08] Edge Functions vs Route Handlers — responsabilidade duplicada
> **Lente:** 18 — Principal Eng · **Severidade:** 🟠 High · **Onda:** 1 · **Status:** fix-pending
**Camada:** —
**Personas impactadas:** —
## Achado
— `distribute-coins` tem versão em `portal/src/app/api/distribute-coins/route.ts` E existe função `fn_increment_wallets_batch` chamada por Edge Functions. Dois caminhos que fazem coisas parecidas, mantidos separadamente.
## Risco / Impacto

— Mudança de regra de negócio em um path esquece o outro. Divergência.

## Correção proposta

— **Canonical path**: tudo financeiro flui por RPC Postgres. Route Handler e Edge Function ambos apenas validam + chamam RPC. Business logic 100% no banco (SECURITY DEFINER funcs).

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[18.8]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 18 — Principal Eng, item 18.8).