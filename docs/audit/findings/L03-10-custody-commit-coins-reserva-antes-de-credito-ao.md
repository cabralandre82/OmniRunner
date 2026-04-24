---
id: L03-10
audit_ref: "3.10"
lens: 3
title: "custody_commit_coins — Reserva ANTES de crédito ao atleta"
severity: medium
status: duplicate
wave: 2
discovered_at: 2026-04-17
closed_at: 2026-04-21
tags: ["finance", "atomicity", "portal"]
files: []
correction_type: process
test_required: false
tests: []
linked_issues: []
linked_prs: []
owner: finance
runbook: null
effort_points: 2
blocked_by: []
duplicate_of: L02-01
deferred_to_wave: null
note: |
  Fechado como **duplicate de L02-01** (`distribute_coins_atomic`).
  A janela "reserva → decrement → increment" foi colapsada numa
  única transação SQL pelo trabalho de Onda 0 (L02-01 +
  cross-ref L01-03), eliminando a temporal-inconsistency-window
  apontada aqui. A invariante R = M é checada por
  `check_custody_invariants` (L03-08) em real-time via
  `/api/platform/invariants/wallets` (L08-07).
---
# [L03-10] custody_commit_coins — Reserva ANTES de crédito ao atleta
> **Lente:** 3 — CFO · **Severidade:** 🟡 Medium · **Onda:** 2 · **Status:** fix-pending
**Camada:** BACKEND + PORTAL
**Personas impactadas:** —
## Achado
O flow atual é: `custody_commit_coins` (reserva R) → `decrement_token_inventory` (decremento de inventário do grupo) → `increment_wallet_balance` (atleta recebe). Se qualquer etapa após (1) falhar, `R_i` fica elevado sem coin correspondente. A invariante R=M é quebrada temporariamente.
## Risco / Impacto

Janela de inconsistência entre etapas (não-atomic — ver [2.1]).

## Correção proposta

Ver [2.1] e [1.3] — migrar para `distribute_coins_atomic` em SQL.

## Referência narrativa
Contexto completo e motivação detalhada em [`docs/audit/parts/`](../parts/) — buscar pelo anchor `[3.10]`.
## Histórico
- `2026-04-17` — Descoberto na auditoria inicial (Lente 3 — CFO, item 3.10).